import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/ids.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  CategoryKind kind = CategoryKind.expense;

  Future<void> _edit(
    FinanceController fc, {
    FinCategory? category,
    String? parentId,
  }) async {
    final c = await showModalBottomSheet<FinCategory>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategorySheet(
        fc: fc,
        kind: kind,
        category: category,
        parentId: parentId,
      ),
    );
    if (c != null && mounted) {
      await runAction(
        context,
        () => fc.saveCategory(c),
        success: 'Categoria salva',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final roots =
        fc.data.categories
            .where((c) => c.kind == kind && c.parentId == null)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    Widget tile(FinCategory c, {bool sub = false}) => ListTile(
      contentPadding: EdgeInsets.only(left: sub ? 56 : 16, right: 4),
      leading: CircleAvatar(
        radius: sub ? 14 : 18,
        backgroundColor: Color(c.color).withValues(alpha: 0.12),
        child: Icon(
          categoryIcon(c.icon),
          color: Color(c.color),
          size: sub ? 16 : 20,
        ),
      ),
      title: Text(c.name),
      onTap: () => _edit(fc, category: c),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'sub') _edit(fc, parentId: c.id);
          if (v == 'delete') {
            final ok = await confirmDialog(
              context,
              title: 'Excluir “${c.name}”?',
              message: c.parentId == null
                  ? 'Subcategorias passam a ser categorias principais e os lançamentos ficam sem categoria.'
                  : 'Os lançamentos passam para a categoria principal.',
              confirm: 'Excluir',
              destructive: true,
            );
            if (ok && context.mounted) {
              await runAction(
                context,
                () => fc.deleteCategory(c),
                success: 'Categoria excluída',
              );
            }
          }
        },
        itemBuilder: (_) => [
          if (!sub)
            const PopupMenuItem(
              value: 'sub',
              child: Text('Adicionar subcategoria'),
            ),
          const PopupMenuItem(value: 'delete', child: Text('Excluir')),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-cat',
        onPressed: () => _edit(fc),
        icon: const Icon(Icons.add),
        label: const Text('Nova categoria'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<CategoryKind>(
              segments: const [
                ButtonSegment(
                  value: CategoryKind.expense,
                  label: Text('Despesas'),
                ),
                ButtonSegment(
                  value: CategoryKind.income,
                  label: Text('Receitas'),
                ),
              ],
              selected: {kind},
              onSelectionChanged: (s) => setState(() => kind = s.first),
            ),
          ),
          Expanded(
            child: roots.isEmpty
                ? const EmptyState(
                    icon: Icons.category_outlined,
                    title: 'Nenhuma categoria',
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      for (final r in roots) ...[
                        tile(r),
                        for (final s
                            in fc.data.categories
                                .where((c) => c.parentId == r.id)
                                .toList()
                              ..sort((a, b) => a.name.compareTo(b.name)))
                          tile(s, sub: true),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  final FinanceController fc;
  final CategoryKind kind;
  final FinCategory? category;
  final String? parentId;
  const _CategorySheet({
    required this.fc,
    required this.kind,
    this.category,
    this.parentId,
  });
  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final name = TextEditingController(text: widget.category?.name ?? '');
  late String icon = widget.category?.icon ?? 'other';
  late int color =
      widget.category?.color ??
      widget.fc.data.categoryById[widget.parentId]?.color ??
      palette.first;
  late String? parentId = widget.category?.parentId ?? widget.parentId;

  @override
  Widget build(BuildContext context) {
    final kind = widget.category?.kind ?? widget.kind;
    final parents = widget.fc.data.categories
        .where(
          (c) =>
              c.kind == kind &&
              c.parentId == null &&
              c.id != widget.category?.id,
        )
        .toList();
    final hasChildren =
        widget.category != null &&
        widget.fc.data.categories.any((c) => c.parentId == widget.category!.id);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.category == null ? 'Nova categoria' : 'Editar categoria',
              style: context.text.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            if (!hasChildren)
              DropdownButtonFormField<String?>(
                initialValue: parentId,
                decoration: const InputDecoration(
                  labelText: 'Categoria principal',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Nenhuma (principal)'),
                  ),
                  for (final p in parents)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => parentId = v),
              ),
            const SizedBox(height: 16),
            Text('Ícone', style: context.text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in categoryIcons.entries)
                  ChoiceChip(
                    label: Icon(e.value, size: 18),
                    selected: icon == e.key,
                    onSelected: (_) => setState(() => icon = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Cor', style: context.text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in palette)
                  GestureDetector(
                    onTap: () => setState(() => color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: color == c
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                final base =
                    widget.category ??
                    FinCategory(id: newId('cat_'), name: '', kind: kind);
                Navigator.pop(
                  context,
                  base.copyWith(
                    name: name.text.trim(),
                    icon: icon,
                    color: color,
                    parentId: parentId,
                  ),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
