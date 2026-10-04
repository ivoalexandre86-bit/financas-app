import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/ids.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';

/// Ajuste das categorias: renomear, trocar ícone/cor, mover, excluir e
/// adicionar subcategorias.
class CategoriesScreen extends StatefulWidget {
  final CategoryKind initialKind;
  const CategoriesScreen({super.key, this.initialKind = CategoryKind.expense});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late CategoryKind kind = widget.initialKind;
  String query = '';

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

  Future<void> _delete(FinanceController fc, FinCategory c) async {
    final ok = await confirmDialog(
      context,
      title: 'Excluir “${c.name}”?',
      message: c.parentId == null
          ? 'Subcategorias passam a ser categorias principais e os lançamentos ficam sem categoria.'
          : 'Os lançamentos passam para a categoria principal.',
      confirm: 'Excluir',
      destructive: true,
    );
    if (ok && mounted) {
      await runAction(
        context,
        () => fc.deleteCategory(c),
        success: 'Categoria excluída',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final q = query.trim().toLowerCase();
    // Uso de cada categoria (lançamentos + recorrências).
    final uses = <String, int>{};
    for (final t in fc.data.transactions) {
      final id = t.categoryId;
      if (id != null) uses[id] = (uses[id] ?? 0) + 1;
    }
    for (final r in fc.data.recurringRules) {
      final id = r.categoryId;
      if (id != null) uses[id] = (uses[id] ?? 0) + 1;
    }
    int byName(FinCategory a, FinCategory b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    List<FinCategory> subsOf(FinCategory r) =>
        fc.data.categories.where((c) => c.parentId == r.id).toList()
          ..sort(byName);
    bool hit(FinCategory c) => q.isEmpty || c.name.toLowerCase().contains(q);
    final roots =
        fc.data.categories
            .where((c) => c.kind == kind && c.parentId == null)
            .where((r) => hit(r) || subsOf(r).any(hit))
            .toList()
          ..sort(byName);

    String usage(FinCategory c) {
      final n = uses[c.id] ?? 0;
      return n == 0
          ? 'sem lançamentos'
          : '$n ${n == 1 ? 'lançamento' : 'lançamentos'}';
    }

    Widget subTile(FinCategory s) => ListTile(
      key: ValueKey('cat-${s.id}'),
      dense: true,
      contentPadding: const EdgeInsets.only(left: 28, right: 4),
      leading: Icon(categoryIcon(s.icon), size: 18, color: Color(s.color)),
      title: Text(s.name),
      subtitle: Text(usage(s)),
      onTap: () => _edit(fc, category: s),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _edit(fc, category: s),
          ),
          IconButton(
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _delete(fc, s),
          ),
        ],
      ),
    );

    Widget rootCard(FinCategory r) {
      final subs = subsOf(r).where((s) => hit(s) || hit(r)).toList();
      return Card(
        key: ValueKey('cat-${r.id}'),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 4),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(r.color).withValues(alpha: 0.12),
                  child: Icon(
                    categoryIcon(r.icon),
                    color: Color(r.color),
                    size: 20,
                  ),
                ),
                title: Text(
                  r.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${subsOf(r).length} '
                  '${subsOf(r).length == 1 ? 'subcategoria' : 'subcategorias'}'
                  ' · ${usage(r)}',
                ),
                onTap: () => _edit(fc, category: r),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar categoria',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _edit(fc, category: r),
                    ),
                    IconButton(
                      tooltip: 'Excluir categoria',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _delete(fc, r),
                    ),
                  ],
                ),
              ),
              for (final s in subs) subTile(s),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 4),
                  child: TextButton.icon(
                    key: ValueKey('add-sub-${r.id}'),
                    onPressed: () => _edit(fc, parentId: r.id),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Adicionar subcategoria'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-cat',
        onPressed: () => _edit(fc),
        icon: const Icon(Icons.add),
        label: const Text('Nova categoria'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar categoria ou subcategoria',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              Expanded(
                child: roots.isEmpty
                    ? EmptyState(
                        icon: Icons.category_outlined,
                        title: q.isEmpty
                            ? 'Nenhuma categoria'
                            : 'Nenhuma categoria encontrada',
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 96),
                        children: [for (final r in roots) rootCard(r)],
                      ),
              ),
            ],
          ),
        ),
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
              widget.category != null
                  ? 'Editar categoria'
                  : widget.parentId != null
                  ? 'Nova subcategoria'
                  : 'Nova categoria',
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
