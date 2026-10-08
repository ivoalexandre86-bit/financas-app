import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/dashboard_engine.dart';
import '../../../domain/engine/simulation_engine.dart';
import '../../../domain/models/dashboard.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/dashboard_chart.dart';
import 'sim_common.dart';

enum _Metric {
  income('Receitas', true),
  expenses('Despesas', false),
  net('Superávit / déficit (fluxo de caixa)', true),
  accumulated('Saldo acumulado', true),
  utilization('Utilização do orçamento', false);

  final String label;
  final bool higherIsBetter;
  const _Metric(this.label, this.higherIsBetter);
}

const _officialId = '__official__';

class _Scenario {
  final String id;
  final String name;
  final int color;
  final SimTotals totals;
  final List<YearMonth> months;
  const _Scenario(this.id, this.name, this.color, this.totals, this.months);
}

/// Comparação de dois ou mais cenários (e do orçamento oficial atual), mês a
/// mês e no período.
class ScenarioCompareScreen extends StatefulWidget {
  final List<String> initialIds;
  const ScenarioCompareScreen({super.key, this.initialIds = const []});

  @override
  State<ScenarioCompareScreen> createState() => _ScenarioCompareScreenState();
}

class _ScenarioCompareScreenState extends State<ScenarioCompareScreen> {
  late final Set<String> ids = {
    _officialId,
    ...(widget.initialIds.isNotEmpty
        ? widget.initialIds
        : context
              .read<FinanceController>()
              .simulations
              .where((s) => !s.isArchived)
              .map((s) => s.id)),
  };
  _Metric metric = _Metric.accumulated;

  int? _value(SimMonth? m) {
    if (m == null) return null;
    return switch (metric) {
      _Metric.income => m.income,
      _Metric.expenses => m.expenses,
      _Metric.net => m.net,
      _Metric.accumulated => m.accumulated,
      _Metric.utilization => (m.utilization * 10000).round(),
    };
  }

  int? _total(_Scenario s) => switch (metric) {
    _Metric.income => s.totals.income,
    _Metric.expenses => s.totals.expenses,
    _Metric.net => s.totals.net,
    _Metric.accumulated => s.totals.finalBalance,
    _Metric.utilization =>
      s.totals.income == 0
          ? 0
          : (s.totals.expenses / s.totals.income * 10000).round(),
  };

  String _fmt(int? v) {
    if (v == null) return '—';
    if (metric == _Metric.utilization) {
      return '${(v / 100).toStringAsFixed(0)}%';
    }
    return fmtCents(v);
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final sims = fc.simulations
        .where((s) => !s.isArchived || ids.contains(s.id))
        .toList();
    final chosen = sims.where((s) => ids.contains(s.id)).toList();

    // Período: união dos períodos escolhidos (ou ano atual).
    YearMonth? from, to;
    for (final s in chosen) {
      if (from == null || s.from < from) from = s.from;
      if (to == null || s.to > to) to = s.to;
    }
    final now = YearMonth.now();
    from ??= now;
    to ??= now.add(11);
    final months = YearMonth.range(from, to).toList();

    final scenarios = <_Scenario>[
      if (ids.contains(_officialId))
        _Scenario(
          _officialId,
          'Orçamento oficial (hoje)',
          0xFF616161,
          SimTotals.official(fc.engine, from, to),
          months,
        ),
      for (final s in chosen)
        _Scenario(
          s.id,
          s.name,
          s.color,
          SimTotals.of(s.items, s.months, s.opening),
          s.months,
        ),
    ];

    // Melhor cenário no período pela métrica.
    String? bestId;
    int? bestVal;
    for (final s in scenarios) {
      final v = _total(s);
      if (v == null) continue;
      final better =
          bestVal == null ||
          (metric.higherIsBetter ? v > bestVal : v < bestVal);
      if (better) {
        bestVal = v;
        bestId = s.id;
      }
    }

    final fin = context.fin;
    final head = context.text.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final body = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget cell(Widget c, {bool left = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Align(
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        child: c,
      ),
    );

    final table = Table(
      defaultColumnWidth: const FixedColumnWidth(150),
      columnWidths: const {0: FixedColumnWidth(130)},
      border: TableBorder(horizontalInside: BorderSide(color: fin.gridLine)),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: fin.stickyColumn),
          children: [
            cell(Text('Mês', style: head), left: true),
            for (final s in scenarios)
              cell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 5, backgroundColor: Color(s.color)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        s.name,
                        style: head,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        for (final m in months)
          TableRow(
            children: [
              cell(Text(m.longLabel, style: body), left: true),
              for (final s in scenarios)
                () {
                  final v = s.months.contains(m)
                      ? _value(s.totals.at(m))
                      : null;
                  final neg = v != null && v < 0 && metric != _Metric.expenses;
                  return cell(
                    Text(
                      _fmt(v),
                      style: body?.copyWith(color: neg ? fin.negative : null),
                    ),
                  );
                }(),
            ],
          ),
        TableRow(
          decoration: BoxDecoration(color: context.colors.surfaceContainerHigh),
          children: [
            cell(
              Text(
                metric == _Metric.accumulated ? 'Fim do período' : 'Período',
                style: head,
              ),
              left: true,
            ),
            for (final s in scenarios)
              cell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (s.id == bestId && scenarios.length > 1) ...[
                      Icon(Icons.emoji_events, size: 16, color: fin.positive),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      _fmt(_total(s)),
                      style: body?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );

    final chart = simChart(
      id: 'cmp',
      title: '',
      type: metric == _Metric.accumulated ? ChartType.line : ChartType.bar,
      xKeys: [for (final m in months) m.key],
      xLabels: [for (final m in months) m.shortLabel],
      periodLabel: '${from.shortLabel} – ${to.shortLabel}',
      showTotals: false,
      source: metric == _Metric.accumulated
          ? DataSource.balance
          : DataSource.net,
      series: [
        for (final s in scenarios)
          simSeries(
            s.id,
            s.name,
            [
              for (final m in months)
                s.months.contains(m) ? (_value(s.totals.at(m)) ?? 0) : 0,
            ],
            SeriesRole.other,
            color: s.color,
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Comparar cenários')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Cenários', style: context.text.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Orçamento oficial (hoje)'),
                selected: ids.contains(_officialId),
                onSelected: (v) => setState(
                  () => v ? ids.add(_officialId) : ids.remove(_officialId),
                ),
              ),
              for (final s in sims)
                FilterChip(
                  avatar: CircleAvatar(backgroundColor: Color(s.color)),
                  label: Text('${s.name} (${s.periodLabel})'),
                  selected: ids.contains(s.id),
                  onSelected: (v) =>
                      setState(() => v ? ids.add(s.id) : ids.remove(s.id)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Comparar por', style: context.text.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _Metric.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: metric == m,
                  onSelected: (_) => setState(() => metric = m),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (scenarios.isEmpty)
            Text(
              'Escolha ao menos um cenário.',
              style: context.text.bodyMedium?.copyWith(color: fin.subtle),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final s in scenarios)
                  SimKpi(
                    label: s.name,
                    value: fmtCents(s.totals.net),
                    detail:
                        'saldo final ${fmtCents(s.totals.finalBalance)} · '
                        '${s.totals.deficitMonths} mês(es) no vermelho',
                    icon: s.id == bestId && scenarios.length > 1
                        ? Icons.emoji_events
                        : Icons.circle,
                    color: Color(s.color),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SimPanel(
              title: metric.label,
              subtitle: scenarios.length > 1 && bestId != null
                  ? 'Melhor no período: '
                        '${scenarios.firstWhere((s) => s.id == bestId).name}'
                  : null,
              child: DashboardChartView(height: 240, data: chart),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
