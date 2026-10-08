import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/dashboard_engine.dart';
import '../../../domain/models/dashboard.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';

/// Cores para identificar simulações.
const simColors = <int>[
  0xFF1565C0,
  0xFF2E7D32,
  0xFFC62828,
  0xFF6A1B9A,
  0xFFEF6C00,
  0xFF00838F,
  0xFFAD1457,
  0xFF5D4037,
];

String fmtCents(int c) => Money(c).format();

/// "+R$ 10,00" / "−R$ 10,00" / "R$ 0,00".
String fmtDiff(int c) => c == 0
    ? Money.zero.format()
    : '${c > 0 ? '+' : '−'}${Money(c.abs()).format()}';

String fmtPct(double? p) {
  if (p == null) return '—';
  final s = p.abs() >= 10 ? p.toStringAsFixed(0) : p.toStringAsFixed(1);
  return '${p > 0 ? '+' : ''}${s.replaceAll('.', ',')}%';
}

String fmtUpdated(DateTime d) {
  final today = Dates.dateOnly(DateTime.now());
  final day = Dates.dateOnly(d);
  final diff = today.difference(day).inDays;
  final time = DateFormat('HH:mm').format(d);
  if (diff == 0) return 'Hoje, $time';
  if (diff == 1) return 'Ontem, $time';
  return DateFormat('dd/MM/yy').format(d);
}

/// Cor de uma diferença: [goodWhenUp] = aumento é bom (receitas, saldo).
Color diffColor(BuildContext context, int diff, {bool goodWhenUp = true}) {
  if (diff == 0) return context.fin.subtle;
  final good = goodWhenUp ? diff > 0 : diff < 0;
  return good ? context.fin.positive : context.fin.negative;
}

/// Texto de diferença com seta e cor.
class DiffText extends StatelessWidget {
  final int diff;
  final bool goodWhenUp;
  final TextStyle? style;
  const DiffText(this.diff, {super.key, this.goodWhenUp = true, this.style});

  @override
  Widget build(BuildContext context) {
    final color = diffColor(context, diff, goodWhenUp: goodWhenUp);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (diff != 0)
            Icon(
              diff > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 18,
              color: color,
            ),
          Text(
            fmtDiff(diff),
            style: (style ?? context.text.bodySmall)?.copyWith(
              color: color,
              fontWeight: diff == 0 ? null : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nome da categoria raiz (ou "Sem categoria").
String? rootCategoryId(FinanceController fc, String? id) {
  if (id == null) return null;
  final c = fc.data.categories.where((c) => c.id == id).firstOrNull;
  return c?.parentId ?? c?.id;
}

FinCategory? categoryOf(FinanceController fc, String? id) =>
    id == null ? null : fc.data.categories.where((c) => c.id == id).firstOrNull;

String categoryLabel(FinanceController fc, String? id) {
  final c = categoryOf(fc, id);
  if (c == null) return 'Sem categoria';
  final parent = categoryOf(fc, c.parentId);
  return parent == null ? c.name : '${parent.name} › ${c.name}';
}

String fundingLabel(FinanceController fc, String? accountId, String? cardId) {
  if (cardId != null) {
    final c = fc.data.cards.where((c) => c.id == cardId).firstOrNull;
    return c == null ? 'Cartão' : 'Cartão ${c.name}';
  }
  if (accountId != null) {
    return fc.data.accounts.where((a) => a.id == accountId).firstOrNull?.name ??
        'Conta';
  }
  return '—';
}

/// Série de gráfico simples.
ChartSeries simSeries(
  String key,
  String name,
  List<int> values,
  SeriesRole role, {
  int? color,
  int? total,
}) => ChartSeries(
  key: key,
  name: name,
  values: values,
  role: role,
  color: color,
  total: total ?? values.fold(0, (a, v) => a + v),
);

/// Monta um gráfico dos painéis a partir de valores prontos.
ChartDataset simChart({
  required String id,
  required String title,
  required ChartType type,
  required List<String> xKeys,
  required List<String> xLabels,
  required List<ChartSeries> series,
  required String periodLabel,
  DataSource source = DataSource.both,
  bool showTotals = true,
  bool swapAxes = false,
  Dimension xAxis = Dimension.month,
  ChartPalette palette = ChartPalette.auto,
}) => ChartDataset(
  config: ChartConfig(
    id: id,
    title: title,
    type: type,
    source: source,
    xAxis: xAxis,
    showTotals: showTotals,
    swapAxes: swapAxes,
    palette: palette,
    colors: {
      for (final s in series)
        if (s.color != null) ChartConfig.seriesColorKey(s.key): s.color!,
    },
  ),
  xAxis: xAxis,
  xKeys: xKeys,
  xLabels: xLabels,
  xColors: List<int?>.filled(xKeys.length, null),
  series: series,
  comparison: const [],
  period: ResolvedPeriod(const [], label: periodLabel),
  comparisonPeriod: null,
  isMoney: true,
);

/// Cartão com título para os gráficos e tabelas da simulação.
class SimPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const SimPanel({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.text.titleSmall),
          if (subtitle != null)
            Text(
              subtitle!,
              style: context.text.bodySmall?.copyWith(
                color: context.fin.subtle,
              ),
            ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );
}

/// Indicador numérico.
class SimKpi extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final Color? color;
  final IconData icon;
  const SimKpi({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    this.color,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color ?? context.fin.subtle),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: context.text.labelMedium?.copyWith(
                      color: context.fin.subtle,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: context.text.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null)
              Text(
                detail!,
                style: context.text.bodySmall?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Seletor de mês em lista suspensa.
class MonthDropdown extends StatelessWidget {
  final String label;
  final YearMonth value;
  final List<YearMonth> options;
  final ValueChanged<YearMonth> onChanged;
  const MonthDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value.key,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final m in options)
        DropdownMenuItem(value: m.key, child: Text(m.shortLabel)),
    ],
    onChanged: (k) => k == null ? null : onChanged(YearMonth.parse(k)),
  );
}
