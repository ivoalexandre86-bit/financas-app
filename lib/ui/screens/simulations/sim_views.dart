import 'package:flutter/material.dart' hide Simulation;

import '../../../core/dates.dart';
import '../../../domain/engine/dashboard_engine.dart';
import '../../../domain/engine/simulation_engine.dart';
import '../../../domain/models/dashboard.dart';
import '../../../domain/models/simulation.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/dashboard_chart.dart';
import 'sim_common.dart';

/// Faixa de indicadores: simulado × base.
class SimSummaryStrip extends StatelessWidget {
  final Simulation sim;
  const SimSummaryStrip({super.key, required this.sim});

  @override
  Widget build(BuildContext context) {
    final months = sim.months;
    final t = SimTotals.of(sim.items, months, sim.opening);
    final b = SimTotals.of(sim.baseItems, months, sim.opening);
    final fin = context.fin;
    Widget kpi(String label, int value, int base, {bool goodUp = true}) =>
        Padding(
          padding: const EdgeInsets.only(right: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: context.text.labelSmall?.copyWith(color: fin.subtle),
              ),
              Text(
                fmtCents(value),
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              DiffText(value - base, goodWhenUp: goodUp),
            ],
          ),
        );
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(
          children: [
            kpi('Receitas', t.income, b.income),
            kpi('Despesas', t.expenses, b.expenses, goodUp: false),
            kpi('Resultado do período', t.net, b.net),
            kpi('Saldo no fim', t.finalBalance, b.finalBalance),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Meses no vermelho',
                  style: context.text.labelSmall?.copyWith(color: fin.subtle),
                ),
                Text(
                  '${t.deficitMonths} de ${months.length}',
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: t.deficitMonths > 0 ? fin.negative : fin.positive,
                  ),
                ),
                Text(
                  'base: ${b.deficitMonths}',
                  style: context.text.bodySmall?.copyWith(color: fin.subtle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Comparação mês a mês: orçamento base × simulação.
class SimCompareView extends StatelessWidget {
  final Simulation sim;
  const SimCompareView({super.key, required this.sim});

  @override
  Widget build(BuildContext context) {
    final months = sim.months;
    final t = SimTotals.of(sim.items, months, sim.opening);
    final b = SimTotals.of(sim.baseItems, months, sim.opening);
    final fin = context.fin;
    final head = context.text.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final body = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    TableRow headRow() => TableRow(
      decoration: BoxDecoration(color: fin.stickyColumn),
      children: [
        for (final h in [
          'Mês',
          'Receita base',
          'Receita simulada',
          'Dif. receita',
          'Despesa base',
          'Despesa simulada',
          'Dif. despesa',
          'Resultado base',
          'Resultado simulado',
          'Dif. resultado',
          'Variação',
          'Acumulado base',
          'Acumulado simulado',
        ])
          _cell(
            Text(h, style: head, textAlign: TextAlign.right),
            left: h == 'Mês',
          ),
      ],
    );
    TableRow dataRow(String label, SimMonthPair p, {bool total = false}) {
      final st = total ? body?.copyWith(fontWeight: FontWeight.w700) : body;
      Widget n(int v, {Color? color}) => _cell(
        Text(
          fmtCents(v),
          style: st?.copyWith(color: color),
          textAlign: TextAlign.right,
        ),
      );
      Widget d(int v, {bool goodUp = true}) =>
          _cell(DiffText(v, goodWhenUp: goodUp, style: st));
      final pct = pctChange(p.base.net, p.sim.net);
      return TableRow(
        decoration: total
            ? BoxDecoration(color: context.colors.surfaceContainerHigh)
            : (p.sim.net < 0
                  ? BoxDecoration(color: fin.negative.withValues(alpha: 0.06))
                  : null),
        children: [
          _cell(
            Text(label, style: st?.copyWith(fontWeight: FontWeight.w600)),
            left: true,
          ),
          n(p.base.income),
          n(p.sim.income),
          d(p.sim.income - p.base.income),
          n(p.base.expenses),
          n(p.sim.expenses),
          d(p.sim.expenses - p.base.expenses, goodUp: false),
          n(p.base.net, color: p.base.net < 0 ? fin.negative : null),
          n(p.sim.net, color: p.sim.net < 0 ? fin.negative : fin.positive),
          d(p.sim.net - p.base.net),
          _cell(
            Text(
              fmtPct(pct),
              style: st?.copyWith(
                color: diffColor(context, p.sim.net - p.base.net),
              ),
              textAlign: TextAlign.right,
            ),
          ),
          n(p.base.accumulated),
          n(
            p.sim.accumulated,
            color: p.sim.accumulated < 0 ? fin.negative : null,
          ),
        ],
      );
    }

    final rows = [
      for (var k = 0; k < months.length; k++)
        dataRow(months[k].longLabel, SimMonthPair(b.months[k], t.months[k])),
      dataRow(
        'Total do período',
        SimMonthPair(
          SimMonth(sim.to, b.income, b.expenses, b.finalBalance),
          SimMonth(sim.to, t.income, t.expenses, t.finalBalance),
        ),
        total: true,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Orçamento base: ${sim.baseName}. Verde = melhora o resultado; '
          'vermelho = piora. Linhas rosadas são meses com déficit na '
          'simulação.',
          style: context.text.bodySmall?.copyWith(color: fin.subtle),
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(132),
              columnWidths: const {0: FixedColumnWidth(150)},
              border: TableBorder(
                horizontalInside: BorderSide(color: fin.gridLine),
              ),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [headRow(), ...rows],
            ),
          ),
        ),
      ],
    );
  }

  static Widget _cell(Widget child, {bool left = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    child: Align(
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      child: child,
    ),
  );
}

class SimMonthPair {
  final SimMonth base;
  final SimMonth sim;
  const SimMonthPair(this.base, this.sim);
}

/// Painel da simulação: gráficos e destaques que recalculam a cada edição.
class SimDashboardView extends StatelessWidget {
  final FinanceController fc;
  final Simulation sim;
  const SimDashboardView({super.key, required this.fc, required this.sim});

  @override
  Widget build(BuildContext context) {
    final months = sim.months;
    final t = SimTotals.of(sim.items, months, sim.opening);
    final b = SimTotals.of(sim.baseItems, months, sim.opening);
    final keys = [for (final m in months) m.key];
    final labels = [for (final m in months) m.shortLabel];
    final period = sim.periodLabel;
    final fin = context.fin;
    final impacts = SimulationEngine.impacts(sim);
    String? root(String? id) => rootCategoryId(fc, id);

    ChartDataset catDiff(bool income) {
      final base = SimulationEngine.byCategory(
        sim.baseItems,
        months,
        income,
        root,
      );
      final cur = SimulationEngine.byCategory(sim.items, months, income, root);
      final diffs = <String?, int>{
        for (final k in {...base.keys, ...cur.keys})
          k: (cur[k] ?? 0) - (base[k] ?? 0),
      }..removeWhere((_, v) => v == 0);
      final ks = diffs.keys.toList()
        ..sort((a, c) => diffs[c]!.abs().compareTo(diffs[a]!.abs()));
      final top = ks.take(10).toList();
      return simChart(
        id: income ? 'cat-inc' : 'cat-exp',
        title: '',
        type: ChartType.bar,
        xAxis: Dimension.category,
        swapAxes: true,
        showTotals: false,
        xKeys: [for (final k in top) k ?? '_none'],
        xLabels: [for (final k in top) categoryLabel(fc, k)],
        periodLabel: period,
        series: [
          simSeries('diff', 'Diferença', [
            for (final k in top) diffs[k]!,
          ], income ? SeriesRole.income : SeriesRole.expense),
        ],
      );
    }

    final charts = <Widget>[
      SimPanel(
        title: 'Receitas × despesas (simulado)',
        child: DashboardChartView(
          height: 220,
          data: simChart(
            id: 'ie',
            title: '',
            type: ChartType.bar,
            xKeys: keys,
            xLabels: labels,
            periodLabel: period,
            series: [
              simSeries('inc', 'Receitas', [
                for (final m in t.months) m.income,
              ], SeriesRole.income),
              simSeries('exp', 'Despesas', [
                for (final m in t.months) m.expenses,
              ], SeriesRole.expense),
            ],
          ),
        ),
      ),
      SimPanel(
        title: 'Orçamento base × simulado (resultado do mês)',
        child: DashboardChartView(
          height: 220,
          data: simChart(
            id: 'bs',
            title: '',
            type: ChartType.bar,
            xKeys: keys,
            xLabels: labels,
            periodLabel: period,
            source: DataSource.net,
            series: [
              simSeries(
                'base',
                'Base',
                [for (final m in b.months) m.net],
                SeriesRole.other,
                color: 0xFF9E9E9E,
              ),
              simSeries(
                'sim',
                'Simulado',
                [for (final m in t.months) m.net],
                SeriesRole.net,
                color: sim.color,
              ),
            ],
          ),
        ),
      ),
      SimPanel(
        title: 'Resultado mensal (superávit / déficit)',
        child: DashboardChartView(
          height: 200,
          data: simChart(
            id: 'net',
            title: '',
            type: ChartType.bar,
            xKeys: keys,
            xLabels: labels,
            periodLabel: period,
            source: DataSource.net,
            series: [
              simSeries('net', 'Resultado', [
                for (final m in t.months) m.net,
              ], SeriesRole.net),
            ],
          ),
        ),
      ),
      SimPanel(
        title: 'Saldo acumulado',
        subtitle: 'Começa no saldo das contas em ${sim.from.shortLabel}',
        child: DashboardChartView(
          height: 220,
          data: simChart(
            id: 'acc',
            title: '',
            type: ChartType.line,
            xKeys: keys,
            xLabels: labels,
            periodLabel: period,
            source: DataSource.balance,
            series: [
              simSeries(
                'sim',
                'Simulado',
                [for (final m in t.months) m.accumulated],
                SeriesRole.balance,
                color: sim.color,
                total: t.finalBalance,
              ),
              simSeries(
                'base',
                'Base',
                [for (final m in b.months) m.accumulated],
                SeriesRole.other,
                color: 0xFF9E9E9E,
                total: b.finalBalance,
              ),
            ],
          ),
        ),
      ),
      SimPanel(
        title: 'Variação de despesas por categoria',
        subtitle: 'Simulado − base no período',
        child: DashboardChartView(height: 220, data: catDiff(false)),
      ),
      SimPanel(
        title: 'Variação de receitas por categoria',
        subtitle: 'Simulado − base no período',
        child: DashboardChartView(height: 220, data: catDiff(true)),
      ),
      SimPanel(
        title: 'Maiores impactos',
        subtitle: 'Efeito de cada linha no resultado do período',
        child: impacts.isEmpty
            ? Text(
                'Nenhuma alteração em relação ao orçamento base ainda.',
                style: context.text.bodySmall?.copyWith(color: fin.subtle),
              )
            : Column(
                children: [
                  for (final i in impacts.take(8))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        i.base == null
                            ? Icons.add_circle_outline
                            : i.sim == null
                            ? Icons.remove_circle_outline
                            : Icons.edit_outlined,
                        color: diffColor(context, i.effect),
                      ),
                      title: Text(
                        i.item.description,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        i.base == null
                            ? 'Nova ${i.item.isIncome ? 'receita' : 'despesa'}'
                            : i.sim == null
                            ? 'Removida da simulação'
                            : 'Valor alterado',
                      ),
                      trailing: DiffText(i.effect),
                    ),
                ],
              ),
      ),
      SimPanel(
        title: 'Meses com déficit e superávit',
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in t.months)
              Chip(
                visualDensity: VisualDensity.compact,
                backgroundColor: (m.net < 0 ? fin.negative : fin.positive)
                    .withValues(alpha: 0.12),
                side: BorderSide.none,
                label: Text(
                  '${m.month.shortLabel}  ${fmtDiff(m.net)}',
                  style: context.text.labelSmall?.copyWith(
                    color: m.net < 0 ? fin.negative : fin.positive,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];

    final pctNet = pctChange(b.net, t.net);
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1000 ? 2 : 1;
        final w = (c.maxWidth - 32 - (cols - 1) * 12) / cols;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SimKpi(
                  label: 'Receitas',
                  value: fmtCents(t.income),
                  detail: '${fmtDiff(t.income - b.income)} vs base',
                  icon: Icons.trending_up,
                  color: fin.income,
                ),
                SimKpi(
                  label: 'Despesas',
                  value: fmtCents(t.expenses),
                  detail: '${fmtDiff(t.expenses - b.expenses)} vs base',
                  icon: Icons.trending_down,
                  color: fin.expense,
                ),
                SimKpi(
                  label: 'Resultado do período',
                  value: fmtCents(t.net),
                  detail: '${fmtDiff(t.net - b.net)} (${fmtPct(pctNet)})',
                  icon: Icons.balance,
                  color: t.net < 0 ? fin.negative : fin.positive,
                ),
                SimKpi(
                  label: 'Saldo no fim do período',
                  value: fmtCents(t.finalBalance),
                  detail: 'base: ${fmtCents(b.finalBalance)}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                SimKpi(
                  label: 'Utilização do orçamento',
                  value: t.income == 0
                      ? '—'
                      : '${(t.expenses / t.income * 100).toStringAsFixed(0)}%',
                  detail: 'despesas ÷ receitas',
                  icon: Icons.pie_chart_outline,
                ),
                SimKpi(
                  label: 'Meses déficit / superávit',
                  value: '${t.deficitMonths} / ${t.surplusMonths}',
                  detail: 'base: ${b.deficitMonths} / ${b.surplusMonths}',
                  icon: Icons.calendar_month,
                  color: t.deficitMonths > 0 ? fin.negative : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final ch in charts) SizedBox(width: w, child: ch),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Meses de um intervalo (para telas que juntam vários cenários).
List<YearMonth> monthsBetween(YearMonth a, YearMonth b) =>
    YearMonth.range(a, b).toList();
