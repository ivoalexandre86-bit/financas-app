import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/ids.dart';
import '../../../domain/models/entities.dart';
import '../../../domain/models/planning.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/remembered_filters.dart';
import '../../widgets/sort_grid.dart';
import '../../widgets/tx_grid.dart';
import '../../widgets/view_mode.dart';

/// Regras de categorização: "descrição contém X → categoria Y". Valem ao
/// lançar no app, ao importar planilhas e no Open Finance.
class CategoryRulesScreen extends StatefulWidget {
  const CategoryRulesScreen({super.key});

  @override
  State<CategoryRulesScreen> createState() => _CategoryRulesScreenState();
}

class _CategoryRulesScreenState extends State<CategoryRulesScreen>
    with RememberedFilters {
  ViewMode view = ViewMode.cards;

  @override
  String get filterKey => 'rules';

  @override
  Map<String, Object?> filtersToJson() => {'view': view.name};

  @override
  void restoreFilters(Map<String, Object?> saved, FinanceController fc) =>
      view = FilterJson.enumOrNull(ViewMode.values, saved['view']) ?? view;

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final rules = fc.categoryRules;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Regras de categoria'),
        actions: [
          ViewModeToggle(
            keyPrefix: 'rules',
            mode: view,
            onChanged: (v) => setFilters(() => view = v),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-rule',
        onPressed: () => showRuleDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Nova regra'),
      ),
      body: rules.isEmpty
          ? EmptyState(
              icon: Icons.rule_outlined,
              title: 'Nenhuma regra',
              message:
                  'Crie regras como “iFood → Delivery”. Lançamentos com esse '
                  'texto na descrição já entram na categoria certa, no app, na '
                  'importação de planilhas e no Open Finance.',
              actionLabel: 'Criar regra',
              onAction: () => showRuleDialog(context),
            )
          : view == ViewMode.grid
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [RulesGrid(rules: rules)],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: rules.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = rules[i];
                final cat = fc.data.categoryById[r.categoryId];
                return Card(
                  child: ListTile(
                    onTap: () => showRuleDialog(context, rule: r),
                    leading: Icon(
                      categoryIcon(cat?.icon),
                      color: cat == null ? null : Color(cat.color),
                    ),
                    title: Text('“${r.pattern}”'),
                    subtitle: Text(
                      '→ ${fc.engine.categoryLabel(r.categoryId)}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Excluir regra',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => runAction(
                        context,
                        () => fc.deleteCategoryRule(r),
                        success: 'Regra excluída',
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Regras no padrão de grade de Faturas: ordenável.
class RulesGrid extends StatelessWidget {
  final List<CategoryRule> rules;
  const RulesGrid({super.key, required this.rules});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    FinCategory? cat(CategoryRule r) => fc.data.categoryById[r.categoryId];
    String label(CategoryRule r) => fc.engine.categoryLabel(r.categoryId);
    String kind(CategoryRule r) => cat(r)?.kind.label ?? '—';
    Color color(CategoryRule r) {
      final c = cat(r);
      return c == null ? context.fin.subtle : Color(c.color);
    }

    Widget delete(CategoryRule r) => IconButton(
      key: ValueKey('rules-delete-${r.id}'),
      tooltip: 'Excluir regra',
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      icon: const Icon(Icons.delete_outline),
      onPressed: () => runAction(
        context,
        () => fc.deleteCategoryRule(r),
        success: 'Regra excluída',
      ),
    );

    return SortGrid<CategoryRule>(
      keyPrefix: 'rules',
      rows: rules,
      rowId: (r) => r.id,
      accent: (context, r) => color(r),
      onOpen: (r) => showRuleDialog(context, rule: r),
      initialSort: 'pattern',
      tieBreak: (a, b) => text(a.pattern, b.pattern),
      columns: [
        SortCol(
          id: 'pattern',
          label: 'Contém o texto',
          width: 220,
          minWidth: 140,
          flexible: true,
          fill: true,
          compare: (a, b) => text(a.pattern, b.pattern),
          cell: (context, r) => GridCell(
            child: Text(
              '“${r.pattern}”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SortCol(
          id: 'category',
          label: 'Categoria',
          width: 240,
          minWidth: 140,
          flexible: true,
          compare: (a, b) => text(label(a), label(b)),
          cell: (context, r) => GridCell(
            child: Row(
              children: [
                Icon(categoryIcon(cat(r)?.icon), size: 18, color: color(r)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label(r),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        SortCol(
          id: 'kind',
          label: 'Tipo',
          width: 110,
          compare: (a, b) => text(kind(a), kind(b)),
          cell: (context, r) => GridCell(
            child: NeonStatus(
              label: kind(r),
              color: cat(r)?.kind == CategoryKind.income
                  ? context.fin.positive
                  : cat(r) == null
                  ? context.fin.subtle
                  : context.fin.expense,
            ),
          ),
        ),
        SortCol(
          id: 'delete',
          label: '',
          width: 52,
          cell: (context, r) => Center(child: delete(r)),
        ),
      ],
      compactRow: (context, r) => Row(
        children: [
          Icon(categoryIcon(cat(r)?.icon), size: 20, color: color(r)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '“${r.pattern}”',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '→ ${label(r)} · ${kind(r)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtle,
                ),
              ],
            ),
          ),
          delete(r),
        ],
      ),
      footerLabel: (context, l) => Text(
        '${l.length} ${l.length == 1 ? 'regra' : 'regras'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: gridFooterLabelStyle(context),
      ),
      compactFooter: (context, l) => const SizedBox.shrink(),
    );
  }
}

/// Cria ou edita uma regra; depois oferece aplicá-la aos lançamentos
/// existentes. [pattern] e [categoryId] preenchem uma regra nova.
Future<void> showRuleDialog(
  BuildContext context, {
  CategoryRule? rule,
  String? pattern,
  String? categoryId,
}) async {
  final fc = context.read<FinanceController>();
  final saved = await showDialog<CategoryRule>(
    context: context,
    builder: (_) => _RuleDialog(
      fc: fc,
      rule: rule,
      pattern: pattern,
      categoryId: categoryId,
    ),
  );
  if (saved == null || !context.mounted) return;
  final n = fc.ruleCandidates(saved).length;
  if (n == 0) return;
  final apply = await confirmDialog(
    context,
    title: 'Aplicar aos lançamentos existentes?',
    message:
        '$n ${n == 1 ? 'lançamento tem' : 'lançamentos têm'} “${saved.pattern}” '
        'na descrição e está em outra categoria. Mover para '
        '${fc.engine.categoryLabel(saved.categoryId)}?',
    confirm: 'Aplicar',
  );
  if (!apply || !context.mounted) return;
  await runAction(
    context,
    () => fc.applyCategoryRule(saved),
    success:
        '$n ${n == 1 ? 'lançamento atualizado' : 'lançamentos atualizados'}',
  );
}

class _RuleDialog extends StatefulWidget {
  final FinanceController fc;
  final CategoryRule? rule;
  final String? pattern;
  final String? categoryId;
  const _RuleDialog({
    required this.fc,
    this.rule,
    this.pattern,
    this.categoryId,
  });
  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final text = TextEditingController(
    text: widget.rule?.pattern ?? widget.pattern ?? '',
  );
  late String? categoryId = widget.rule?.categoryId ?? widget.categoryId;
  late CategoryKind kind =
      widget.fc.data.categoryById[categoryId]?.kind ?? CategoryKind.expense;

  @override
  Widget build(BuildContext context) {
    final fc = widget.fc;
    return AlertDialog(
      title: Text(widget.rule == null ? 'Nova regra' : 'Editar regra'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('rule-pattern'),
              controller: text,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Quando a descrição contiver',
                hintText: 'Ex.: ifood, uber, farmácia',
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<CategoryKind>(
              segments: const [
                ButtonSegment(
                  value: CategoryKind.expense,
                  label: Text('Despesa'),
                ),
                ButtonSegment(
                  value: CategoryKind.income,
                  label: Text('Receita'),
                ),
              ],
              selected: {kind},
              onSelectionChanged: (s) => setState(() {
                kind = s.first;
                categoryId = null;
              }),
            ),
            const SizedBox(height: 12),
            CategoryDropdown(
              fc: fc,
              kind: kind,
              value: categoryId,
              onChanged: (v) => setState(() => categoryId = v),
            ),
            const SizedBox(height: 8),
            Text(
              'Não diferencia maiúsculas nem acentos. Se mais de uma regra '
              'servir, vale a de texto mais longo.',
              style: context.text.bodySmall?.copyWith(
                color: context.fin.subtle,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            final r =
                (widget.rule ??
                        CategoryRule(
                          id: newId('rule_'),
                          pattern: '',
                          categoryId: '',
                        ))
                    .copyWith(
                      pattern: text.text.trim(),
                      categoryId: categoryId ?? '',
                    );
            final ok = await runAction(
              context,
              () => fc.saveCategoryRule(r),
              success: 'Regra salva',
            );
            if (ok && context.mounted) Navigator.pop(context, r);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
