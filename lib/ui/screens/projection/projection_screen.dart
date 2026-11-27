import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../domain/models/scenario.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/filters_panel.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/plan_upsell.dart';
import '../../widgets/remembered_filters.dart';
import '../../widgets/tx_grid.dart';
import '../transactions/transaction_form_screen.dart';
import 'drilldown_screen.dart';
import 'month_adjust_screen.dart';
import 'month_closing_ui.dart';
import 'projection_filters_screen.dart';

/// Projeção Financeira Mensal: matriz com meses nas colunas e indicadores
/// nas linhas, primeira coluna fixa e rolagem horizontal.
class ProjectionScreen extends StatefulWidget {
  const ProjectionScreen({super.key});

  /// Meses que o plano Grátis mostra, a partir do mês atual.
  static const freeMonths = 3;

  /// No plano Grátis, no máximo [freeMonths] meses e nada além do 3º mês a
  /// partir de agora (o passado continua disponível).
  static MonthRange limitRange(MonthRange r, {required bool gratis}) {
    if (!gratis) return r;
    final last = YearMonth.now().add(freeMonths - 1);
    final to = r.to.compareTo(last) > 0 ? last : r.to;
    var from = r.from.compareTo(to) > 0 ? to : r.from;
    final first = to.add(-(freeMonths - 1));
    if (from.compareTo(first) < 0) from = first;
    return from == r.from && to == r.to ? r : MonthRange(from, to);
  }

  @override
  State<ProjectionScreen> createState() => _ProjectionScreenState();
}

class _ProjectionScreenState extends State<ProjectionScreen>
    with RememberedFilters {
  MonthRange range = MonthRange.starting(YearMonth.now(), 6);
  int? preset = 6; // null = personalizado
  ProjectionFilter filter = ProjectionFilter.none;
  Money? openingOverride;
  final hScroll = ScrollController();

  static const _rowH = 40.0;
  static const _headerH = 42.0;
  static const _minCellW = 112.0;

  void _upsell() => showPlanUpsell(
    context,
    feature:
        'No plano Grátis a projeção mostra 3 meses a partir do mês atual. '
        'Assine para ver 12 meses à frente.',
  );

  @override
  String get filterKey => 'projection';

  @override
  Map<String, Object?> filtersToJson() => {
    'from': range.from.key,
    'to': range.to.key,
    'preset': preset,
    'accounts': FilterJson.ids(filter.accountIds),
    'cards': FilterJson.ids(filter.cardIds),
    'categories': FilterJson.ids(filter.categoryIds),
    'projects': FilterJson.ids(filter.projectIds),
    'types': FilterJson.enums(filter.types),
    'statuses': FilterJson.enums(filter.statuses),
    'sources': FilterJson.enums(filter.sources),
  };

  @override
  void restoreFilters(Map<String, Object?> j, FinanceController fc) {
    final d = fc.data;
    final from = FilterJson.month(j['from']);
    final to = FilterJson.month(j['to']);
    if (from != null && to != null && from.compareTo(to) <= 0) {
      range = MonthRange(from, to);
      preset = j['preset'] as int?;
    }
    filter = ProjectionFilter(
      accountIds: FilterJson.idSet(j['accounts'], d.accounts.map((a) => a.id)),
      cardIds: FilterJson.idSet(j['cards'], d.cards.map((c) => c.id)),
      categoryIds: FilterJson.idSet(
        j['categories'],
        d.categories.map((c) => c.id),
      ),
      projectIds: FilterJson.idSet(j['projects'], d.projects.map((p) => p.id)),
      types: FilterJson.enumSet(TransactionType.values, j['types']),
      statuses: j['statuses'] is List
          ? FilterJson.enumSet(TransactionStatus.values, j['statuses'])
          : ProjectionFilter.defaultStatuses,
      sources: FilterJson.enumSet(EventSource.values, j['sources']),
    );
  }

  @override
  void dispose() {
    hScroll.dispose();
    super.dispose();
  }

  void _setPreset(int months) {
    if (months > ProjectionScreen.freeMonths &&
        isGratisPlan(context, listen: false)) {
      return _upsell();
    }
    setFilters(() {
      preset = months;
      range = MonthRange.starting(range.from, months);
    });
  }

  void _shift(int months) {
    final gratis = isGratisPlan(context, listen: false);
    final base = ProjectionScreen.limitRange(range, gratis: gratis);
    final next = MonthRange(base.from.add(months), base.to.add(months));
    if (gratis &&
        !identical(ProjectionScreen.limitRange(next, gratis: true), next)) {
      return _upsell();
    }
    setFilters(() => range = next);
  }

  Future<void> _customRange() async {
    final r = await showDialog<MonthRange>(
      context: context,
      builder: (_) => _RangeDialog(initial: range),
    );
    if (r != null) {
      setFilters(() {
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

  /// Escolhe o mês e abre as ações de fechar / ajustar / reabrir.
  Future<void> _pickMonthToAdjust(
    List<YearMonth> months,
    MonthRange shown,
  ) async {
    final fc = context.read<FinanceController>();
    final now = YearMonth.now();
    final m = await showModalBottomSheet<YearMonth>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(
                  'Qual mês você quer fechar ou reabrir?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'Dica: na tabela, tocar no nome do mês abre a mesma opção.',
                ),
              ),
              for (final month in months)
                Builder(
                  builder: (_) {
                    final c = fc.closingOf(month);
                    return ListTile(
                      key: ValueKey('proj-adjust-pick-${month.key}'),
                      leading: Icon(
                        c == null
                            ? Icons.calendar_month_outlined
                            : c.isAdjusted
                            ? Icons.tune
                            : Icons.lock,
                      ),
                      title: Text(month.longLabel),
                      subtitle: Text(
                        c == null
                            ? (month == now ? 'Mês atual · aberto' : 'Aberto')
                            : c.isAdjusted
                            ? 'Ajustado manualmente'
                            : 'Fechado',
                      ),
                      onTap: () => Navigator.pop(ctx, month),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (m != null && mounted) {
      await showMonthClosingActions(context, m, range: shown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final gratis = isGratisPlan(context);
    final shown = ProjectionScreen.limitRange(range, gratis: gratis);
    final shownPreset = identical(shown, range)
        ? preset
        : shown.length == ProjectionScreen.freeMonths
        ? ProjectionScreen.freeMonths
        : null;
    final baseResult = e.projection(
      shown,
      filter: filter,
      openingOverride: openingOverride,
    );
    // Cenário escolhido: soma os fluxos dele só na visão completa.
    final scenario = fc.selectedScenario;
    final scenarioOn = scenario != null && filter.isEmpty;
    final result = scenarioOn
        ? fc.scenarioEngine.apply(baseResult, scenario.pendingFlows)
        : baseResult;
    final cols = result.columns;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projeção financeira mensal'),
        actions: [
          IconButton(
            key: const ValueKey('proj-closings'),
            tooltip: 'Fechamentos e ajustes',
            icon: Badge(
              isLabelVisible: e.data.monthClosings.isNotEmpty,
              label: Text('${e.data.monthClosings.length}'),
              child: const Icon(Icons.lock_clock),
            ),
            onPressed: () => push(context, const MonthClosingsScreen()),
          ),
          FilterButton(
            keyPrefix: 'proj',
            active: filter.activeCount,
            onPressed: () async {
              final r = await showFilterPanel<ProjectionFilterResult>(
                context,
                ProjectionFiltersScreen(initial: filter, range: range),
              );
              if (r != null) {
                setFilters(() {
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
                      selected: shownPreset == m,
                      onSelected: (_) => _setPreset(m),
                    ),
                  ),
                ChoiceChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: const Text('Personalizado'),
                  selected: shownPreset == null,
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
                    '${shown.from.shortLabel} – ${shown.to.shortLabel}',
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
          if (gratis)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: PlanBanner(
                'No plano Grátis a projeção mostra 3 meses. Assine para ver 12.',
              ),
            ),
          if (fc.scenarios.any((x) => !x.archived) || scenario != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: ScenarioBar(
                base: baseResult,
                result: result,
                applies: filter.isEmpty,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _ProjectionKpis(result: result),
          ),
          // Ajuste manual / fechamento do mês, à vista (também abre tocando no
          // nome do mês na tabela).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _NewEntryButton(months: [for (final c in cols) c.month]),
                OutlinedButton.icon(
                  key: const ValueKey('proj-adjust-month'),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Ajustar mês a mês'),
                  onPressed: () =>
                      push(context, MonthAdjustScreen(range: shown)),
                ),
                TextButton.icon(
                  key: const ValueKey('proj-close-month'),
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Fechar ou reabrir mês'),
                  onPressed: () => _pickMonthToAdjust([
                    for (final c in cols) c.month,
                  ], shown),
                ),
                if (e.data.monthClosings.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.lock_clock, size: 18),
                    label: Text('Ver ajustes (${e.data.monthClosings.length})'),
                    onPressed: () => push(context, const MonthClosingsScreen()),
                  ),
              ],
            ),
          ),
          if (shown.from != YearMonth.now())
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.today, size: 16),
                label: const Text('Começar no mês atual'),
                onPressed: () => setFilters(
                  () => range = MonthRange.starting(
                    YearMonth.now(),
                    shown.length,
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
                onClear: () => setFilters(() => filter = ProjectionFilter.none),
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
          if (!filter.isEmpty &&
              cols.any((c) => e.data.closingByMonth.containsKey(c.month)))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Com filtros, os meses fechados mostram o cálculo pelos '
                'lançamentos; o fechamento/ajuste vale para a visão sem filtros.',
                style: context.text.bodySmall?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Toque no mês para fechar, ajustar ou reabrir o resultado. '
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
      // Ajuste manual dos meses fechados, à parte das receitas e despesas.
      if (cols.any((c) => !c.adjustment.isZero))
        _MatrixRow(
          'Ajuste manual',
          null,
          (c) => c.adjustment,
          p.neon2,
          signed: true,
        ),
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

            Widget monthHeader(ProjectionColumn c) {
              final closing = context
                  .read<FinanceController>()
                  .engine
                  .closingFor(filter, c.month);
              final status = closing != null
                  ? (closing.isAdjusted ? 'ajustado' : 'fechado')
                  : c.isCurrent
                  ? 'atual'
                  : c.isPast
                  ? 'realizado'
                  : null;
              return Material(
                color: c.isCurrent
                    ? p.neon.withValues(alpha: 0.10)
                    : Colors.transparent,
                child: InkWell(
                  key: ValueKey('proj-month-${c.month.key}'),
                  onTap: () => showMonthClosingActions(
                    context,
                    c.month,
                    range: MonthRange(cols.first.month, cols.last.month),
                  ),
                  child: Container(
                    width: cellW,
                    height: _headerH,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (closing != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  closing.isAdjusted ? Icons.tune : Icons.lock,
                                  size: 12,
                                  color: p.neon2,
                                ),
                              ),
                            Text(
                              c.month.shortLabel.toUpperCase(),
                              style: headerStyle?.copyWith(
                                color: c.isCurrent ? p.neon : null,
                              ),
                            ),
                          ],
                        ),
                        if (status != null)
                          Text(
                            status,
                            style: context.text.labelSmall?.copyWith(
                              color: closing != null
                                  ? p.neon2
                                  : p.headerText.withValues(alpha: 0.6),
                              fontSize: 9,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }

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

/// Escolha do cenário e o antes e depois do caixa.
class ScenarioBar extends StatelessWidget {
  final ProjectionResult base;
  final ProjectionResult result;

  /// O cenário só vale na visão completa (sem filtros).
  final bool applies;
  const ScenarioBar({
    super.key,
    required this.base,
    required this.result,
    required this.applies,
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final s = fc.selectedScenario;
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final options = [
      for (final x in fc.scenarios)
        if (!x.archived || x.id == s?.id) x,
    ];
    final flows = s == null
        ? const <ScenarioFlow>[]
        : [
            for (final f in s.pendingFlows)
              if (fc.scenarioEngine.monthOf(f) <= base.columns.last.month) f,
          ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String?>(
              key: const ValueKey('proj-scenario'),
              initialValue: s?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Cenário',
                prefixIcon: Icon(Icons.alt_route),
                border: InputBorder.none,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Orçamento base'),
                ),
                for (final x in options)
                  DropdownMenuItem<String?>(value: x.id, child: Text(x.name)),
              ],
              onChanged: fc.selectScenario,
            ),
            if (s != null && !applies)
              Text(
                'Os cenários aparecem só na visão completa. Limpe os filtros '
                'para ver "${s.name}".',
                style: subtle,
              )
            else if (s != null) ...[
              for (final f in flows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${fc.scenarioEngine.monthOf(f).shortLabel} · '
                          '${f.description}'
                          '${f.isEstimate ? ' (estimado)' : ''}',
                          style: context.text.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      MoneyText(
                        f.amount,
                        colorize: true,
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              if (flows.isEmpty)
                Text(
                  'Nenhum fluxo do cenário cai neste período.',
                  style: subtle,
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Acumulado em ${base.columns.last.month.shortLabel}',
                      style: context.text.bodySmall,
                    ),
                  ),
                  Text('base ', style: subtle),
                  MoneyText(
                    base.columns.last.accumulated,
                    key: const ValueKey('proj-scenario-base'),
                    colorize: true,
                    style: context.text.bodySmall,
                  ),
                  Text('  →  cenário ', style: subtle),
                  MoneyText(
                    result.columns.last.accumulated,
                    key: const ValueKey('proj-scenario-result'),
                    colorize: true,
                    style: context.text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                'Simulação: o orçamento base e os meses fechados não mudam.',
                style: subtle,
              ),
            ],
          ],
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
    final net = result.totalNet;
    final adj = result.totalAdjustment;
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
        detail:
            (negMonths == 0
                ? 'Nenhum mês negativo'
                : '$negMonths de $n ${n == 1 ? 'mês' : 'meses'} negativos') +
            (adj.isZero ? '' : ' · ajuste ${adj.format()}'),
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

/// "Lançar": abre o formulário de despesa ou receita sem sair da Projeção.
/// A data sugerida é hoje quando o mês atual está na tela; senão, o dia 1 do
/// primeiro mês mostrado. Ao salvar, a grade se atualiza sozinha.
class _NewEntryButton extends StatelessWidget {
  final List<YearMonth> months;
  const _NewEntryButton({required this.months});

  DateTime _date(DateTime today) {
    final now = YearMonth.of(today);
    if (months.isEmpty || months.contains(now)) return today;
    return months.first.firstDay;
  }

  void _open(BuildContext context, TransactionType type) {
    final today = context.read<FinanceController>().today;
    push(
      context,
      TransactionFormScreen(initialType: type, initialDate: _date(today)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('proj-new-expense'),
          leadingIcon: Icon(Icons.south_east, color: context.fin.negative),
          onPressed: () => _open(context, TransactionType.expense),
          child: const Text('Despesa'),
        ),
        MenuItemButton(
          key: const ValueKey('proj-new-income'),
          leadingIcon: Icon(Icons.north_east, color: context.fin.positive),
          onPressed: () => _open(context, TransactionType.income),
          child: const Text('Receita'),
        ),
      ],
      builder: (context, ctrl, _) => FilledButton.icon(
        key: const ValueKey('proj-new-entry'),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Lançar'),
        onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
      ),
    );
  }
}
