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
import '../../widgets/tx_grid.dart';
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

  static const _rowH = 40.0;
  static const _headerH = 42.0;
  static const _minCellW = 112.0;

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
                Navigator.pop(ctx, Money.tryEval(ctrl.text));
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _ProjectionKpis(result: result),
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
        ],
      ),
    );
  }

  /// Grade no mesmo estilo da de Transações: painel com borda neon,
  /// cabeçalho escuro com sublinhado luminoso, linhas compactas com zebra e
  /// listra colorida por indicador. A coluna de indicadores fica fixa e os
  /// meses se esticam para ocupar a largura (rolando quando não cabem).
  Widget _matrix(
    BuildContext context,
    ProjectionResult result,
    List<ProjectionColumn> cols,
  ) {
    final p = GridPalette.of(context);
    final fin = context.fin;
    final rows = <_MatrixRow>[
      _MatrixRow('Receitas', DrillRow.income, (c) => c.income, fin.income),
      _MatrixRow('Despesas', DrillRow.expenses, (c) => c.expenses, fin.expense),
      _MatrixRow(
        'Resultado',
        DrillRow.net,
        (c) => c.net,
        p.neon,
        strong: true,
        signed: true,
      ),
      if (result.showsTransfers)
        _MatrixRow(
          'Transferências',
          null,
          (c) => c.transfersNet,
          fin.subtle,
          signed: true,
        ),
      _MatrixRow(
        'Saldo acumulado',
        DrillRow.net,
        (c) => c.accumulated,
        p.neon2,
        strong: true,
        signed: true,
        highlight: true,
      ),
    ];
    final headerStyle = context.text.labelSmall?.copyWith(
      color: p.headerText,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridPanel(
        child: LayoutBuilder(
          builder: (context, box) {
            final labelW = box.maxWidth < 640 ? 144.0 : 168.0;
            final cellW = ((box.maxWidth - labelW) / cols.length)
                .clamp(_minCellW, double.infinity)
                .toDouble();

            Widget rowBg(int i, Widget child) => Container(
              height: _rowH,
              decoration: BoxDecoration(
                color: i.isOdd ? p.zebra : null,
                border: Border(bottom: BorderSide(color: p.line, width: 0.6)),
              ),
              child: child,
            );

            // Coluna fixa de indicadores, com a listra colorida de cada linha.
            final labels = Container(
              width: labelW,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: p.line)),
              ),
              child: Column(
                children: [
                  Container(
                    height: _headerH,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 13),
                    child: Text('INDICADOR', style: headerStyle),
                  ),
                  for (final (i, r) in rows.indexed)
                    rowBg(
                      i,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: GridLayout.stripeW,
                            decoration: BoxDecoration(
                              color: r.accent.withValues(alpha: 0.85),
                              boxShadow: [
                                BoxShadow(
                                  color: r.accent.withValues(alpha: 0.55),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: GridCell(
                              child: Text(
                                r.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodyMedium?.copyWith(
                                  fontWeight: r.strong
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );

            Widget monthHeader(ProjectionColumn c) => Container(
              width: cellW,
              height: _headerH,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: c.isCurrent ? p.neon.withValues(alpha: 0.10) : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    c.month.shortLabel.toUpperCase(),
                    style: headerStyle?.copyWith(
                      color: c.isCurrent ? p.neon : null,
                    ),
                  ),
                  if (c.isCurrent || c.isPast)
                    Text(
                      c.isCurrent ? 'atual' : 'realizado',
                      style: context.text.labelSmall?.copyWith(
                        color: p.headerText.withValues(alpha: 0.6),
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            );

            final months = Scrollbar(
              controller: hScroll,
              thumbVisibility: cellW * cols.length > box.maxWidth - labelW,
              child: SingleChildScrollView(
                controller: hScroll,
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [for (final c in cols) monthHeader(c)]),
                    for (final (i, r) in rows.indexed)
                      rowBg(
                        i,
                        Row(
                          children: [
                            for (final c in cols)
                              _cell(context, p, c, r, r.value(c), cellW),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );

            return Stack(
              children: [
                // Faixa escura do cabeçalho com a linha neon, atrás das duas
                // partes (fixa e rolável) para formar um cabeçalho contínuo.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: _headerH,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: p.header),
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                p.neon,
                                p.neon2,
                                p.neon.withValues(alpha: 0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: p.neon.withValues(alpha: 0.6),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labels,
                    Expanded(child: months),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    GridPalette p,
    ProjectionColumn c,
    _MatrixRow r,
    Money v,
    double width,
  ) {
    final negative = r.signed && v.isNegative;
    final color = negative
        ? context.fin.negative
        : r.label == 'Receitas'
        ? context.fin.positive
        : r.label == 'Transferências'
        ? context.fin.subtle
        : null;
    final bg = c.isCurrent
        ? p.neon.withValues(alpha: 0.06)
        : negative
        ? context.fin.negative.withValues(alpha: 0.08)
        : r.highlight
        ? p.valueBg
        : null;
    return SizedBox(
      width: width,
      child: Material(
        color: bg ?? Colors.transparent,
        child: InkWell(
          hoverColor: p.hover,
          splashColor: p.neon.withValues(alpha: 0.10),
          highlightColor: p.neon.withValues(alpha: 0.06),
          onTap: r.drill == null
              ? null
              : () => push(
                  context,
                  DrilldownScreen(
                    month: c.month,
                    row: r.drill!,
                    filter: filter,
                  ),
                ),
          child: GridCell(
            right: true,
            child: Text(
              v.formatPlain(),
              maxLines: 1,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: r.strong ? FontWeight.w700 : FontWeight.w500,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MatrixRow {
  final String label;
  final DrillRow? drill;
  final Money Function(ProjectionColumn) value;
  final Color accent;
  final bool strong;
  final bool signed;
  final bool highlight;
  const _MatrixRow(
    this.label,
    this.drill,
    this.value,
    this.accent, {
    this.strong = false,
    this.signed = false,
    this.highlight = false,
  });
}

/// Indicadores do período projetado, no mesmo formato dos KPIs da tela
/// inicial.
class _ProjectionKpis extends StatelessWidget {
  final ProjectionResult result;
  const _ProjectionKpis({required this.result});

  @override
  Widget build(BuildContext context) {
    final cols = result.columns;
    final n = cols.length;
    final net = result.totalIncome - result.totalExpenses;
    final negMonths = cols.where((c) => c.net.isNegative).length;
    final finalBalance = cols.last.accumulated;
    final lowest = cols
        .map((c) => c.accumulated)
        .reduce((a, b) => a < b ? a : b);
    Money avg(Money total) => Money(total.cents ~/ n);
    final tiles = [
      _ProjectionKpiTile(
        key: const ValueKey('proj-kpi-income'),
        label: 'Receitas do período',
        value: result.totalIncome,
        detail: 'média ${avg(result.totalIncome).format()}/mês',
        icon: Icons.south_west,
        color: context.fin.income,
      ),
      _ProjectionKpiTile(
        key: const ValueKey('proj-kpi-expenses'),
        label: 'Despesas do período',
        value: result.totalExpenses,
        detail: 'média ${avg(result.totalExpenses).format()}/mês',
        icon: Icons.north_east,
        color: context.fin.expense,
      ),
      _ProjectionKpiTile(
        key: const ValueKey('proj-kpi-net'),
        label: 'Resultado',
        value: net,
        colorize: true,
        detail: negMonths == 0
            ? 'Nenhum mês negativo'
            : '$negMonths de $n ${n == 1 ? 'mês' : 'meses'} negativos',
        detailColor: negMonths == 0 ? null : context.fin.negative,
        icon: Icons.balance,
        color: net.isNegative ? context.fin.negative : context.colors.primary,
        highlight: net.isNegative,
      ),
      _ProjectionKpiTile(
        key: const ValueKey('proj-kpi-balance'),
        label: 'Saldo final',
        value: finalBalance,
        colorize: true,
        detail: 'menor saldo ${lowest.format()}',
        detailColor: lowest.isNegative ? context.fin.negative : null,
        icon: Icons.account_balance_wallet_outlined,
        color: finalBalance.isNegative
            ? context.fin.negative
            : context.fin.positive,
        highlight: finalBalance.isNegative,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 640 ? 4 : 2;
        const gap = 8.0;
        final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

class _ProjectionKpiTile extends StatelessWidget {
  final String label;
  final Money value;
  final String detail;
  final Color? detailColor;
  final IconData icon;
  final Color color;
  final bool colorize;
  final bool highlight;
  const _ProjectionKpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    this.detailColor,
    this.colorize = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: highlight ? color.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlight
              ? color.withValues(alpha: 0.5)
              : context.colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelMedium?.copyWith(
                      color: context.fin.subtle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyText(
                value,
                colorize: colorize,
                style: context.text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: detailColor ?? context.fin.subtle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
