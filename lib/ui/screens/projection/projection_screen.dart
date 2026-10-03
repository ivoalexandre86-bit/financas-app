import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import 'drilldown_screen.dart';
import 'projection_filters_screen.dart';

/// Projeção Financeira Mensal: matriz com meses nas colunas e indicadores
/// nas linhas, primeira coluna fixa e rolagem horizontal.
class ProjectionScreen extends StatefulWidget {
  const ProjectionScreen({super.key});
  @override
  State<ProjectionScreen> createState() => _ProjectionScreenState();
}

class _ProjectionScreenState extends State<ProjectionScreen> {
  MonthRange range = MonthRange.starting(YearMonth.now(), 6);
  int? preset = 6; // null = personalizado
  ProjectionFilter filter = ProjectionFilter.none;
  Money? openingOverride;
  final hScroll = ScrollController();

  static const _labelW = 104.0;
  static const _cellW = 98.0;
  static const _rowH = 48.0;

  @override
  void dispose() {
    hScroll.dispose();
    super.dispose();
  }

  void _setPreset(int months) => setState(() {
    preset = months;
    range = MonthRange.starting(range.from, months);
  });

  void _shift(int months) => setState(
    () => range = MonthRange(range.from.add(months), range.to.add(months)),
  );

  Future<void> _customRange() async {
    final r = await showDialog<MonthRange>(
      context: context,
      builder: (_) => _RangeDialog(initial: range),
    );
    if (r != null) {
      setState(() {
        range = r;
        preset = null;
      });
    }
  }

  Future<void> _editOpening(Money current) async {
    final ctrl = TextEditingController(text: current.formatPlain());
    final key = GlobalKey<FormState>();
    final r = await showDialog<Object>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saldo inicial da projeção'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Por padrão usamos o saldo real das contas. Informe outro valor para simular cenários.',
              ),
              const SizedBox(height: 12),
              MoneyField(
                controller: ctrl,
                allowZero: true,
                allowNegative: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'reset'),
            child: const Text('Usar saldo real'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(ctx, Money.tryParse(ctrl.text));
              }
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (r == 'reset') setState(() => openingOverride = null);
    if (r is Money) setState(() => openingOverride = r);
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final result = e.projection(
      range,
      filter: filter,
      openingOverride: openingOverride,
    );
    final cols = result.columns;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projeção financeira mensal'),
        actions: [
          IconButton(
            tooltip: 'Filtros',
            icon: Badge(
              isLabelVisible: !filter.isEmpty,
              label: Text('${filter.activeCount}'),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () async {
              final r = await push<ProjectionFilterResult>(
                context,
                ProjectionFiltersScreen(initial: filter, range: range),
              );
              if (r != null) {
                setState(() {
                  filter = r.filter;
                  if (r.range != range) {
                    range = r.range;
                    preset = [3, 6, 12, 24].contains(r.range.length)
                        ? r.range.length
                        : null;
                  }
                });
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Período
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final m in [3, 6, 12, 24])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$m meses'),
                      selected: preset == m,
                      onSelected: (_) => _setPreset(m),
                    ),
                  ),
                ChoiceChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: const Text('Personalizado'),
                  selected: preset == null,
                  onSelected: (_) => _customRange(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Voltar 1 ano',
                  onPressed: () => _shift(-12),
                  icon: const Icon(Icons.keyboard_double_arrow_left),
                ),
                IconButton(
                  tooltip: 'Voltar 1 mês',
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${range.from.shortLabel} – ${range.to.shortLabel}',
                    textAlign: TextAlign.center,
                    style: context.text.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Avançar 1 mês',
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: 'Avançar 1 ano',
                  onPressed: () => _shift(12),
                  icon: const Icon(Icons.keyboard_double_arrow_right),
                ),
              ],
            ),
          ),
          if (range.from != YearMonth.now())
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.today, size: 16),
                label: const Text('Começar no mês atual'),
                onPressed: () => setState(
                  () => range = MonthRange.starting(
                    YearMonth.now(),
                    range.length,
                  ),
                ),
              ),
            ),
          if (!filter.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _ActiveFilters(
                filter: filter,
                fc: fc,
                onClear: () => setState(() => filter = ProjectionFilter.none),
              ),
            ),
          // Saldo inicial
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: openingOverride != null
                              ? 'Saldo inicial (simulado): '
                              : result.openingIsAccountBalance
                              ? 'Saldo inicial (contas): '
                              : 'Acumulado do recorte a partir de ',
                          style: TextStyle(color: context.fin.subtle),
                        ),
                        TextSpan(
                          text: result.openingBalance.format(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _editOpening(result.openingBalance),
                  child: const Text('Alterar'),
                ),
              ],
            ),
          ),
          _matrix(context, result, cols),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Toque em um valor para ver o detalhamento. Compras no cartão contam no mês em que a fatura é paga '
              '(no vencimento, enquanto não for paga); pagamentos de fatura e transferências não contam como despesa.',
              style: context.text.bodySmall?.copyWith(
                color: context.fin.subtle,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SectionCard(
              title: 'Resumo do período',
              child: Column(
                children: [
                  InfoRow('Receitas', MoneyText(result.totalIncome)),
                  InfoRow('Despesas', MoneyText(result.totalExpenses)),
                  InfoRow(
                    'Resultado',
                    MoneyText(
                      result.totalIncome - result.totalExpenses,
                      colorize: true,
                    ),
                  ),
                  InfoRow(
                    'Saldo final',
                    MoneyText(
                      cols.last.accumulated,
                      colorize: true,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  InfoRow.text(
                    'Meses com resultado negativo',
                    '${cols.where((c) => c.net.isNegative).length} de ${cols.length}',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _matrix(
    BuildContext context,
    ProjectionResult result,
    List<ProjectionColumn> cols,
  ) {
    final rows = <(String, DrillRow?, Money Function(ProjectionColumn))>[
      ('Receitas', DrillRow.income, (c) => c.income),
      ('Despesas', DrillRow.expenses, (c) => c.expenses),
      ('Resultado', DrillRow.net, (c) => c.net),
      if (result.showsTransfers)
        ('Transferências', null, (c) => c.transfersNet),
      ('Saldo acumulado', DrillRow.net, (c) => c.accumulated),
    ];
    final border = BorderSide(color: context.colors.outlineVariant);
    final headerStyle = context.text.labelLarge?.copyWith(
      color: context.fin.subtle,
      fontWeight: FontWeight.w600,
    );

    Widget labelCell(String text, {bool header = false, bool strong = false}) =>
        Container(
          height: _rowH,
          width: _labelW,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: context.fin.stickyColumn,
            border: Border(bottom: border, right: border),
          ),
          child: Text(
            text,
            style: header
                ? headerStyle
                : context.text.bodyMedium?.copyWith(
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  ),
          ),
        );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.outlineVariant),
        color: context.colors.surfaceContainerLowest,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coluna fixa de indicadores.
          Column(
            children: [
              labelCell('Indicador', header: true),
              for (final r in rows)
                labelCell(r.$1, strong: r.$1 == 'Saldo acumulado'),
            ],
          ),
          Expanded(
            child: Scrollbar(
              controller: hScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: hScroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in cols)
                      Container(
                        width: _cellW,
                        color: c.isCurrent
                            ? context.colors.primary.withValues(alpha: 0.06)
                            : null,
                        child: Column(
                          children: [
                            Container(
                              height: _rowH,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                border: Border(bottom: border),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    c.month.shortLabel,
                                    style: headerStyle?.copyWith(
                                      color: c.isCurrent
                                          ? context.colors.primary
                                          : null,
                                    ),
                                  ),
                                  if (c.isCurrent || c.isPast)
                                    Text(
                                      c.isCurrent ? 'atual' : 'realizado',
                                      style: context.text.labelSmall?.copyWith(
                                        color: context.fin.subtle,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            for (final r in rows)
                              _cell(
                                context,
                                c,
                                r.$2,
                                r.$3(c),
                                strong:
                                    r.$1 == 'Saldo acumulado' ||
                                    r.$1 == 'Resultado',
                                signed:
                                    r.$1 != 'Receitas' && r.$1 != 'Despesas',
                                border: border,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    ProjectionColumn c,
    DrillRow? row,
    Money v, {
    required bool strong,
    required bool signed,
    required BorderSide border,
  }) {
    final negative = signed && v.isNegative;
    return InkWell(
      onTap: row == null
          ? null
          : () => push(
              context,
              DrilldownScreen(month: c.month, row: row, filter: filter),
            ),
      child: Container(
        height: _rowH,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(bottom: border),
          color: negative ? context.fin.negative.withValues(alpha: 0.08) : null,
        ),
        child: Text(
          v.formatPlain(),
          maxLines: 1,
          style: context.text.bodyMedium?.copyWith(
            fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
            color: negative ? context.fin.negative : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  final ProjectionFilter filter;
  final FinanceController fc;
  final VoidCallback onClear;
  const _ActiveFilters({
    required this.filter,
    required this.fc,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final d = fc.data;
    final labels = [
      ...filter.accountIds.map((id) => d.accountById[id]?.name ?? id),
      ...filter.cardIds.map((id) => d.cardById[id]?.name ?? id),
      ...filter.categoryIds.map((id) => fc.engine.categoryLabel(id)),
      ...filter.projectIds.map((id) => d.projectById[id]?.name ?? id),
      ...filter.types.map((t) => t.label),
      ...filter.sources.map((s) => s.label),
      if (filter.hasCustomStatuses) ...filter.statuses.map((s) => s.label),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final l in labels)
          Chip(label: Text(l), visualDensity: VisualDensity.compact),
        ActionChip(
          avatar: const Icon(Icons.close, size: 16),
          label: const Text('Limpar'),
          onPressed: onClear,
        ),
      ],
    );
  }
}

class _RangeDialog extends StatefulWidget {
  final MonthRange initial;
  const _RangeDialog({required this.initial});
  @override
  State<_RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<_RangeDialog> {
  late YearMonth from = widget.initial.from;
  late YearMonth to = widget.initial.to;

  @override
  Widget build(BuildContext context) {
    final base = YearMonth.now().add(-36);
    final options = [for (var i = 0; i < 36 + 61; i++) base.add(i)];
    DropdownButtonFormField<YearMonth> dd(
      String label,
      YearMonth v,
      ValueChanged<YearMonth> f,
    ) => DropdownButtonFormField<YearMonth>(
      initialValue: options.contains(v) ? v : null,
      decoration: InputDecoration(labelText: label),
      menuMaxHeight: 320,
      items: [
        for (final m in options)
          DropdownMenuItem(value: m, child: Text(m.longLabel)),
      ],
      onChanged: (x) => setState(() => f(x!)),
    );
    final valid = from <= to && from.monthsUntil(to) < 60;
    return AlertDialog(
      title: const Text('Período personalizado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          dd('Mês inicial', from, (m) => from = m),
          const SizedBox(height: 12),
          dd('Mês final', to, (m) => to = m),
          if (!valid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'O período deve ter de 1 a 60 meses.',
                style: TextStyle(color: context.colors.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, MonthRange(from, to))
              : null,
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
