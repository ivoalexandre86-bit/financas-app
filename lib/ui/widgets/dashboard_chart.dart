import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../domain/engine/dashboard_engine.dart';
import '../../domain/models/dashboard.dart';
import '../theme.dart';

// Cores -----------------------------------------------------------------------

/// Paleta categórica validada para daltonismo (ordem fixa, nunca ciclada).
const _catLight = [
  Color(0xFF2A78D6),
  Color(0xFFEB6834),
  Color(0xFF1BAF7A),
  Color(0xFFEDA100),
  Color(0xFFE87BA4),
  Color(0xFF008300),
  Color(0xFF4A3AA7),
  Color(0xFFE34948),
];
const _catDark = [
  Color(0xFF3987E5),
  Color(0xFFD95926),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF008300),
  Color(0xFF9085E9),
  Color(0xFFE66767),
];
const _ocean = [
  Color(0xFF1C5CAB),
  Color(0xFF1BAF7A),
  Color(0xFF5598E7),
  Color(0xFF0E7490),
  Color(0xFF86B6EF),
  Color(0xFF14B8A6),
  Color(0xFF104281),
  Color(0xFF67E8F9),
];
const _sunset = [
  Color(0xFFEB6834),
  Color(0xFFD55181),
  Color(0xFFEDA100),
  Color(0xFFE34948),
  Color(0xFF9333EA),
  Color(0xFFF59E0B),
  Color(0xFFBE185D),
  Color(0xFFFB923C),
];
const _forest = [
  Color(0xFF15803D),
  Color(0xFF65A30D),
  Color(0xFF0F766E),
  Color(0xFFA16207),
  Color(0xFF4ADE80),
  Color(0xFF166534),
  Color(0xFF84CC16),
  Color(0xFF78716C),
];
const _mono = [
  Color(0xFF184F95),
  Color(0xFF2A78D6),
  Color(0xFF5598E7),
  Color(0xFF86B6EF),
  Color(0xFF104281),
  Color(0xFF3987E5),
  Color(0xFF6DA7EC),
  Color(0xFF9EC5F4),
];

List<Color> paletteColors(BuildContext context, ChartPalette p) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (p) {
    ChartPalette.ocean => _ocean,
    ChartPalette.sunset => _sunset,
    ChartPalette.forest => _forest,
    ChartPalette.mono => _mono,
    _ => dark ? _catDark : _catLight,
  };
}

/// Cor de cada série, seguindo a entidade (receita, despesa, categoria…).
List<Color> seriesColors(BuildContext context, ChartDataset d) {
  final fin = context.fin;
  final pal = paletteColors(context, d.config.palette);
  final auto = d.config.palette == ChartPalette.auto;
  final useCat = d.config.palette == ChartPalette.categories;
  return [
    for (var i = 0; i < d.series.length; i++)
      () {
        final s = d.series[i];
        final custom = d.config.colors[ChartConfig.seriesColorKey(s.key)];
        if (custom != null) return Color(custom);
        if (useCat && s.color != null) return Color(s.color!);
        if (!auto) return pal[i % pal.length];
        if (s.key == 'actual') return context.colors.primary;
        if (s.key == 'planned') {
          return context.colors.primary.withValues(alpha: 0.45);
        }
        if (s.key == 'completed') return fin.positive;
        if (s.key == 'pending') return fin.warning;
        return switch (s.role) {
          SeriesRole.income when d.series.length <= 2 => fin.income,
          SeriesRole.expense when d.series.length <= 2 => fin.expense,
          SeriesRole.net || SeriesRole.balance => context.colors.primary,
          _ => pal[i % pal.length],
        };
      }(),
  ];
}

/// Cor de cada item do eixo X (pizza, rosca, Pareto).
List<Color> xColors(BuildContext context, ChartDataset d) {
  final pal = paletteColors(context, d.config.palette);
  final useCat = d.config.palette == ChartPalette.categories;
  final custom = xOverrides(d);
  return [
    for (var i = 0; i < d.xKeys.length; i++)
      custom[i] ??
          (d.xKeys[i] == DashboardEngine.otherKey
              ? context.fin.subtle
              : (useCat && d.xColors[i] != null)
              ? Color(d.xColors[i]!)
              : pal[i % pal.length]),
  ];
}

/// Cor escolhida pelo usuário para cada coluna/fatia (ou `null`).
List<Color?> xOverrides(ChartDataset d) => [
  for (final k in d.xKeys)
    switch (d.config.colors[ChartConfig.xColorKey(k)]) {
      final int c => Color(c),
      null => null,
    },
];

/// Itens cuja cor o usuário pode escolher, com a cor atual: as colunas ou
/// fatias (gráficos de uma série, pizza, rosca, Pareto, cascata) ou as séries.
List<({String key, String label, Color color})> colorableItems(
  BuildContext context,
  ChartDataset d,
) {
  final t = d.config.type;
  final sc = seriesColors(context, d);
  final singleBar =
      d.series.length <= 1 &&
      (t == ChartType.bar ||
          t == ChartType.comparative ||
          t == ChartType.stackedBar ||
          t == ChartType.pareto);
  if (t.isCircular || t == ChartType.waterfall || singleBar) {
    final xo = xOverrides(d);
    final xc = xColors(context, d);
    final combined = t == ChartType.waterfall
        ? d.combined(
            signed: d.series.length > 1 || d.config.source == DataSource.net,
          )
        : const <int>[];
    return [
      for (var i = 0; i < d.xKeys.length; i++)
        (
          key: ChartConfig.xColorKey(d.xKeys[i]),
          label: d.xLabels[i],
          color:
              xo[i] ??
              (t.isCircular
                  ? xc[i]
                  : t == ChartType.waterfall
                  ? (combined[i] >= 0
                        ? context.fin.positive
                        : context.fin.negative)
                  : (sc.isEmpty ? context.colors.primary : sc.first)),
        ),
    ];
  }
  return [
    for (var i = 0; i < d.series.length; i++)
      (
        key: ChartConfig.seriesColorKey(d.series[i].key),
        label: d.series[i].name,
        color: sc[i],
      ),
  ];
}

/// Cores oferecidas ao personalizar um gráfico.
const chartSwatches = [
  0xFF2A78D6,
  0xFF1C5CAB,
  0xFF5598E7,
  0xFF0E7490,
  0xFF14B8A6,
  0xFF1BAF7A,
  0xFF15803D,
  0xFF65A30D,
  0xFF84CC16,
  0xFFEDA100,
  0xFFCA8A04,
  0xFFF59E0B,
  0xFFEB6834,
  0xFFEA580C,
  0xFFE34948,
  0xFFDC2626,
  0xFFBE185D,
  0xFFE87BA4,
  0xFFD55181,
  0xFF9333EA,
  0xFF7C3AED,
  0xFF4A3AA7,
  0xFF78716C,
  0xFF64748B,
  0xFF334155,
  0xFF111827,
];

/// Escolha de cor: devolve a cor escolhida, `-1` para voltar à automática
/// ou `null` se cancelar.
Future<int?> pickChartColor(
  BuildContext context, {
  required String title,
  required Color current,
  bool custom = false,
}) => showDialog<int>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
    content: SizedBox(
      width: 320,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in chartSwatches)
            InkWell(
              key: ValueKey('swatch-$c'),
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(ctx, c),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Color(c),
                child: custom && current.toARGB32() == c
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
        ],
      ),
    ),
    actions: [
      if (custom)
        TextButton(
          onPressed: () => Navigator.pop(ctx, -1),
          child: const Text('Cor automática'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancelar'),
      ),
    ],
  ),
);

// Formatação ------------------------------------------------------------------

String formatValue(int v, bool money, {bool compact = false}) {
  if (!money) return '$v';
  if (!compact) return Money(v).format();
  final reais = v / 100;
  final a = reais.abs();
  String n(double x, String suf) =>
      '${(x).toStringAsFixed(x >= 10 ? 0 : 1).replaceAll('.', ',')}$suf';
  final sign = v < 0 ? '-' : '';
  if (a >= 1e6) return '$sign${n(a / 1e6, ' mi')}';
  if (a >= 1e3) return '$sign${n(a / 1e3, ' mil')}';
  return '$sign${a.round()}';
}

String formatPct(double p, {bool signed = false}) {
  final s = p.abs() >= 10 ? p.toStringAsFixed(0) : p.toStringAsFixed(1);
  return '${signed && p > 0 ? '+' : ''}${s.replaceAll('.', ',')}%';
}

// Widget principal ------------------------------------------------------------

/// Desenha um [ChartDataset] no tipo configurado, com legenda, resumo de
/// totais/variações e detalhamento ao tocar.
class DashboardChartView extends StatefulWidget {
  final ChartDataset data;
  final double height;
  final bool showTable;
  const DashboardChartView({
    super.key,
    required this.data,
    required this.height,
    this.showTable = false,
  });

  @override
  State<DashboardChartView> createState() => _DashboardChartViewState();
}

class _DashboardChartViewState extends State<DashboardChartView> {
  int? selected;

  @override
  void didUpdateWidget(covariant DashboardChartView old) {
    super.didUpdateWidget(old);
    if (selected != null &&
        (selected! >= _itemCount ||
            old.data.config.type != widget.data.config.type)) {
      selected = null;
    }
  }

  ChartDataset get d => widget.data;
  ChartType get type => d.config.type;
  int get _itemCount =>
      type == ChartType.waterfall ? d.xKeys.length + 1 : d.xKeys.length;

  @override
  Widget build(BuildContext context) {
    final cfg = d.config;
    if (d.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Summary(data: d),
          SizedBox(
            height: widget.height,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insights_outlined, color: context.fin.subtle),
                  const SizedBox(height: 6),
                  Text(
                    'Sem dados para este período e filtros',
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall?.copyWith(
                      color: context.fin.subtle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (widget.showTable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Summary(data: d),
          ChartTable(data: d),
        ],
      );
    }
    final sColors = seriesColors(context, d);
    final xCols = xColors(context, d);
    final style = _ChartStyle(
      fin: context.fin,
      label: context.text.labelSmall!.copyWith(color: context.fin.subtle),
      ink: context.colors.onSurface,
      surface: context.colors.surfaceContainerLowest,
      primary: context.colors.primary,
    );

    Widget plot;
    if (type.isCircular) {
      plot = LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, widget.height);
          final model = _PieModel(d, xCols, donut: type == ChartType.donut);
          return GestureDetector(
            onTapDown: (t) => setState(
              () => selected = model.hit(size, t.localPosition) ?? selected,
            ),
            child: CustomPaint(
              size: size,
              painter: _PiePainter(model, style, selected, cfg.showPercentages),
            ),
          );
        },
      );
    } else {
      final model = _CartesianModel.build(d, sColors, xOverrides(d), style);
      plot = LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, widget.height);
          void pick(Offset o) {
            final i = model.indexAt(size, o, style);
            if (i != null) setState(() => selected = i);
          }

          return GestureDetector(
            onTapDown: (t) => pick(t.localPosition),
            onHorizontalDragUpdate: model.horizontal
                ? null
                : (t) => pick(t.localPosition),
            child: CustomPaint(
              size: size,
              painter: _CartesianPainter(
                model,
                style,
                selected,
                cfg.showValues,
              ),
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Summary(data: d),
        const SizedBox(height: 8),
        SizedBox(height: widget.height, child: plot),
        if (selected != null)
          _SelectionDetail(data: d, index: selected!, colors: sColors)
        else
          const SizedBox(height: 4),
        if (cfg.showLegend) _Legend(data: d, sColors: sColors, xCols: xCols),
      ],
    );
  }
}

class _ChartStyle {
  final FinColors fin;
  final TextStyle label;
  final Color ink;
  final Color surface;
  final Color primary;
  const _ChartStyle({
    required this.fin,
    required this.label,
    required this.ink,
    required this.surface,
    required this.primary,
  });
}

// Resumo (totais e variação) -----------------------------------------------

class _Summary extends StatelessWidget {
  final ChartDataset data;
  const _Summary({required this.data});

  @override
  Widget build(BuildContext context) {
    final cfg = data.config;
    final items = <Widget>[];
    if (cfg.showTotals) {
      final isBalance = cfg.source == DataSource.balance;
      if (data.series.length == 1 || isBalance) {
        final s = data.series.first;
        items.add(
          _Kpi(
            label: isBalance ? 'Fim do período' : 'Total',
            value: formatValue(s.total, data.isMoney),
          ),
        );
      } else {
        for (final s in data.series.take(4)) {
          items.add(
            _Kpi(label: s.name, value: formatValue(s.total, data.isMoney)),
          );
        }
        if (cfg.source == DataSource.both &&
            data.series.every(
              (s) =>
                  s.role == SeriesRole.income || s.role == SeriesRole.expense,
            )) {
          final net = data.series.fold(0, (a, s) => a + s.total * s.sign);
          items.add(
            _Kpi(
              label: 'Resultado',
              value: formatValue(net, data.isMoney),
              color: net < 0 ? context.fin.negative : context.fin.positive,
            ),
          );
        }
      }
    }
    if (cfg.showVariation && data.hasComparison) {
      final cur = data.series.fold(0, (a, s) => a + s.total * s.sign);
      final prev = data.comparison.fold(0, (a, s) => a + s.total * s.sign);
      final v = ChartDataset.variation(cur, prev);
      items.add(
        _Kpi(
          label: 'vs ${data.comparisonPeriod!.label.toLowerCase()}',
          value: v == null ? '—' : formatPct(v, signed: true),
          icon: v == null
              ? null
              : v >= 0
              ? Icons.arrow_upward
              : Icons.arrow_downward,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.period.label,
          style: context.text.labelSmall?.copyWith(color: context.fin.subtle),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 16, runSpacing: 4, children: items),
        ],
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
  const _Kpi({required this.label, required this.value, this.color, this.icon});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: context.text.labelSmall?.copyWith(color: context.fin.subtle),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 14, color: context.fin.subtle),
          Text(
            value,
            style: context.text.titleSmall?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ],
  );
}

// Detalhe da seleção ------------------------------------------------------------

class _SelectionDetail extends StatelessWidget {
  final ChartDataset data;
  final int index;
  final List<Color> colors;
  const _SelectionDetail({
    required this.data,
    required this.index,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = data.config;
    final parts = <String>[];
    String label;
    if (cfg.type == ChartType.waterfall && index == data.xKeys.length) {
      label = 'Total';
      parts.add(
        formatValue(
          data.combined(signed: true).fold(0, (a, b) => a + b),
          data.isMoney,
        ),
      );
    } else if (index < data.xKeys.length) {
      label = data.xLabels[index];
      final circular = cfg.type.isCircular || cfg.type == ChartType.pareto;
      if (circular) {
        final vals = data.combined();
        final total = vals.fold(0, (a, b) => a + math.max(0, b));
        final v = vals[index];
        parts.add(formatValue(v, data.isMoney));
        if (total > 0) parts.add(formatPct(v / total * 100));
        if (cfg.type == ChartType.pareto && total > 0) {
          var acc = 0;
          for (var i = 0; i <= index; i++) {
            acc += vals[i];
          }
          parts.add('acumulado ${formatPct(acc / total * 100)}');
        }
      } else {
        for (var s = 0; s < data.series.length; s++) {
          final ser = data.series[s];
          var txt = data.series.length > 1
              ? '${ser.name} ${formatValue(ser.values[index], data.isMoney)}'
              : formatValue(ser.values[index], data.isMoney);
          if (cfg.showPercentages && ser.total != 0) {
            txt += ' (${formatPct(ser.values[index] / ser.total * 100)})';
          }
          if (cfg.showVariation && index > 0) {
            final v = ChartDataset.variation(
              ser.values[index],
              ser.values[index - 1],
            );
            if (v != null) txt += ' ${formatPct(v, signed: true)} vs anterior';
          }
          if (data.hasComparison) {
            final c = data.comparison[s].values[index];
            txt += ' · antes ${formatValue(c, data.isMoney)}';
          }
          parts.add(txt);
        }
      }
    } else {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: parts.join(' · ')),
          ],
        ),
        style: context.text.labelMedium,
      ),
    );
  }
}

// Legenda --------------------------------------------------------------------

class _Legend extends StatelessWidget {
  final ChartDataset data;
  final List<Color> sColors;
  final List<Color> xCols;
  const _Legend({
    required this.data,
    required this.sColors,
    required this.xCols,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = data.config;
    final entries = <(Color, String, bool)>[];
    if (cfg.type.isCircular) {
      final vals = data.combined();
      final total = vals.fold(0, (a, b) => a + math.max(0, b));
      for (var i = 0; i < data.xKeys.length; i++) {
        final pct = total == 0
            ? ''
            : ' · ${formatPct(math.max(0, vals[i]) / total * 100)}';
        entries.add((xCols[i], '${data.xLabels[i]}$pct', false));
      }
    } else if (cfg.type == ChartType.waterfall) {
      entries
        ..add((context.fin.positive, 'Aumento', false))
        ..add((context.fin.negative, 'Redução', false))
        ..add((context.colors.primary, 'Total', false));
    } else if (cfg.type == ChartType.pareto) {
      entries
        ..add((
          xCols.isEmpty ? context.colors.primary : sColors.first,
          'Itens até 80%',
          false,
        ))
        ..add((context.fin.subtle, 'Acumulado', true));
    } else {
      if (data.series.length > 1 ||
          data.hasComparison ||
          cfg.type == ChartType.trend) {
        for (var i = 0; i < data.series.length; i++) {
          entries.add((sColors[i], data.series[i].name, false));
        }
      }
      if (data.hasComparison) {
        final barLike =
            cfg.type == ChartType.bar || cfg.type == ChartType.comparative;
        entries.add((
          barLike ? sColors.first.withValues(alpha: 0.4) : context.fin.subtle,
          data.comparisonPeriod!.label,
          !barLike,
        ));
      }
      if (cfg.type == ChartType.trend) {
        entries.add((context.fin.subtle, 'Linha de tendência', true));
      }
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final (c, label, dashed) in entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: dashed ? 14 : 10,
                  height: dashed ? 2 : 10,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(dashed ? 1 : 3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(label, style: context.text.labelSmall),
              ],
            ),
        ],
      ),
    );
  }
}

// Tabela (alternativa acessível) ----------------------------------------------

class ChartTable extends StatelessWidget {
  final ChartDataset data;
  const ChartTable({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final cols = [
      for (final s in data.series) s.name,
      for (final s in data.comparison)
        '${s.name} (${data.comparisonPeriod!.label.toLowerCase()})',
    ];
    final style = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 36,
        columnSpacing: 20,
        columns: [
          DataColumn(
            label: Text(data.xAxis.label, style: context.text.labelMedium),
          ),
          for (final c in cols)
            DataColumn(
              numeric: true,
              label: Text(c, style: context.text.labelMedium),
            ),
        ],
        rows: [
          for (var i = 0; i < data.xKeys.length; i++)
            DataRow(
              cells: [
                DataCell(Text(data.xLabels[i], style: style)),
                for (final s in [...data.series, ...data.comparison])
                  DataCell(
                    Text(formatValue(s.values[i], data.isMoney), style: style),
                  ),
              ],
            ),
          DataRow(
            cells: [
              DataCell(
                Text(
                  'Total',
                  style: style?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final s in [...data.series, ...data.comparison])
                DataCell(
                  Text(
                    formatValue(s.total, data.isMoney),
                    style: style?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Modelo cartesiano -----------------------------------------------------------

class _Bar {
  final int x;
  final int gi; // posição no grupo
  final int gn; // tamanho do grupo
  final int lo;
  final int hi;
  final Color color;
  final bool roundTop;
  final bool roundBottom;
  const _Bar(
    this.x,
    this.gi,
    this.gn,
    this.lo,
    this.hi,
    this.color, {
    this.roundTop = true,
    this.roundBottom = false,
  });
}

class _Line {
  final List<int> values;
  final Color color;
  final bool dashed;
  final bool fill;
  final bool markers;
  const _Line(
    this.values,
    this.color, {
    this.dashed = false,
    this.fill = false,
    this.markers = false,
  });
}

class _Ref {
  final int value;
  final String label;
  const _Ref(this.value, this.label);
}

class _CartesianModel {
  final List<String> xLabels;
  final List<_Bar> bars;
  final List<_Line> lines;
  final List<_Ref> refs;
  final int minY;
  final int maxY;
  final int step;
  final bool money;

  /// Rótulos de variação por ponto (evolução mensal).
  final List<String?> pointNotes;

  /// Eixos invertidos: categorias na vertical, valores na horizontal.
  final bool horizontal;

  _CartesianModel({
    required this.xLabels,
    required this.bars,
    required this.lines,
    required this.refs,
    required this.minY,
    required this.maxY,
    required this.step,
    required this.money,
    this.pointNotes = const [],
    this.horizontal = false,
  });

  static List<int> _running(List<int> v) {
    var acc = 0;
    return [for (final x in v) acc += x];
  }

  static _CartesianModel build(
    ChartDataset d,
    List<Color> sc,
    List<Color?> xo,
    _ChartStyle st,
  ) {
    final type = d.config.type;
    final n = d.xKeys.length;
    final bars = <_Bar>[];
    final lines = <_Line>[];
    final refs = <_Ref>[];
    final labels = [...d.xLabels];
    var notes = <String?>[];
    Color faded(Color c) => c.withValues(alpha: 0.4);
    // Com uma só série, cada coluna pode ter a sua cor.
    Color colorAt(int s, int x) =>
        (d.series.length == 1 ? xo[x] : null) ?? sc[s];

    switch (type) {
      case ChartType.bar:
      case ChartType.comparative:
        final withCmp = d.hasComparison;
        final gn = d.series.length * (withCmp ? 2 : 1);
        for (var s = 0; s < d.series.length; s++) {
          for (var x = 0; x < n; x++) {
            final gi = withCmp ? s * 2 : s;
            if (withCmp) {
              final c = d.comparison[s].values[x];
              bars.add(
                _Bar(
                  x,
                  gi,
                  gn,
                  math.min(0, c),
                  math.max(0, c),
                  faded(colorAt(s, x)),
                ),
              );
            }
            final v = d.series[s].values[x];
            bars.add(
              _Bar(
                x,
                withCmp ? gi + 1 : gi,
                gn,
                math.min(0, v),
                math.max(0, v),
                colorAt(s, x),
              ),
            );
          }
        }
      case ChartType.stackedBar:
        for (var x = 0; x < n; x++) {
          var pos = 0, neg = 0;
          final top = <int>[];
          for (var s = 0; s < d.series.length; s++) {
            if (d.series[s].values[x] > 0) top.add(s);
          }
          for (var s = 0; s < d.series.length; s++) {
            final v = d.series[s].values[x];
            if (v >= 0) {
              bars.add(
                _Bar(
                  x,
                  0,
                  1,
                  pos,
                  pos + v,
                  colorAt(s, x),
                  roundTop: top.isNotEmpty && top.last == s,
                ),
              );
              pos += v;
            } else {
              bars.add(
                _Bar(x, 0, 1, neg + v, neg, colorAt(s, x), roundTop: false),
              );
              neg += v;
            }
          }
        }
        if (d.hasComparison) {
          final totals = [
            for (var x = 0; x < n; x++)
              d.comparison.fold(0, (a, s) => a + s.values[x]),
          ];
          lines.add(_Line(totals, st.fin.subtle, dashed: true, markers: true));
        }
      case ChartType.line:
      case ChartType.area:
      case ChartType.trend:
      case ChartType.cumulative:
      case ChartType.monthlyEvolution:
        final cum = type == ChartType.cumulative;
        for (var s = 0; s < d.series.length; s++) {
          var v = d.series[s].values;
          if (cum) v = _running(v);
          if (d.hasComparison) {
            var c = d.comparison[s].values;
            if (cum) c = _running(c);
            lines.add(_Line(c, faded(sc[s]), dashed: true));
          }
          lines.add(
            _Line(
              v,
              sc[s],
              fill: type == ChartType.area || cum,
              markers:
                  type == ChartType.monthlyEvolution ||
                  type == ChartType.trend ||
                  n <= 2,
            ),
          );
          if (type == ChartType.trend && n >= 2) {
            lines.add(_Line(_regression(v), sc[s], dashed: true));
          }
        }
        if (type == ChartType.monthlyEvolution && d.series.isNotEmpty) {
          final v = d.series.first.values;
          notes = [
            for (var i = 0; i < n; i++)
              i == 0
                  ? null
                  : (() {
                      final p = ChartDataset.variation(v[i], v[i - 1]);
                      return p == null ? null : formatPct(p, signed: true);
                    })(),
          ];
        }
      case ChartType.waterfall:
        final signed = d.series.length > 1 || d.config.source == DataSource.net;
        final deltas = d.combined(signed: signed);
        var run = 0;
        for (var x = 0; x < n; x++) {
          final v = deltas[x];
          final a = run, b = run + v;
          bars.add(
            _Bar(
              x,
              0,
              1,
              math.min(a, b),
              math.max(a, b),
              xo[x] ?? (v >= 0 ? st.fin.positive : st.fin.negative),
              roundTop: true,
              roundBottom: true,
            ),
          );
          run = b;
        }
        bars.add(_Bar(n, 0, 1, math.min(0, run), math.max(0, run), st.primary));
        labels.add('Total');
      case ChartType.pareto:
        final vals = d.combined().map((v) => math.max(0, v)).toList();
        final total = vals.fold(0, (a, b) => a + b);
        final cum = _running(vals);
        final base = sc.isEmpty ? st.primary : sc.first;
        for (var x = 0; x < n; x++) {
          final prevPct = total == 0 ? 0 : (cum[x] - vals[x]) / total;
          final c = xo[x] ?? base;
          bars.add(_Bar(x, 0, 1, 0, vals[x], prevPct < 0.8 ? c : faded(c)));
        }
        lines.add(_Line(cum, st.fin.subtle, markers: true));
        if (total > 0) refs.add(_Ref((total * 0.8).round(), '80%'));
      case ChartType.pie:
      case ChartType.donut:
        break;
    }

    var minY = 0, maxY = 0;
    for (final b in bars) {
      minY = math.min(minY, b.lo);
      maxY = math.max(maxY, b.hi);
    }
    for (final l in lines) {
      for (final v in l.values) {
        minY = math.min(minY, v);
        maxY = math.max(maxY, v);
      }
    }
    if (maxY == minY) maxY = minY + 100;
    final (lo, hi, step) = _nice(minY, maxY);
    return _CartesianModel(
      xLabels: labels,
      bars: bars,
      lines: lines,
      refs: refs,
      minY: lo,
      maxY: hi,
      step: step,
      money: d.isMoney,
      pointNotes: notes,
      horizontal: d.config.horizontal,
    );
  }

  /// Mínimos quadrados: valores da reta de tendência em cada ponto.
  static List<int> _regression(List<int> v) {
    final n = v.length;
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (var i = 0; i < n; i++) {
      sx += i;
      sy += v[i];
      sxx += i * i;
      sxy += i * v[i];
    }
    final den = n * sxx - sx * sx;
    final slope = den == 0 ? 0.0 : (n * sxy - sx * sy) / den;
    final icpt = (sy - slope * sx) / n;
    return [for (var i = 0; i < n; i++) (icpt + slope * i).round()];
  }

  /// Arredonda a escala para valores "redondos".
  static (int, int, int) _nice(int lo, int hi) {
    double step(double range) {
      final raw = range / 4;
      final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
      for (final m in [1, 2, 2.5, 5, 10]) {
        if (raw <= m * mag) return m * mag;
      }
      return 10 * mag;
    }

    final s = step((hi - lo).toDouble());
    final nlo = (lo / s).floor() * s;
    final nhi = (hi / s).ceil() * s;
    return (nlo.round(), nhi.round(), math.max(1, s.round()));
  }

  int get slots => xLabels.length;

  static const leftGutter = 54.0;
  static const bottomGutter = 20.0;
  static const topGutter = 14.0;

  /// Largura dos rótulos das categorias nas barras horizontais.
  static const categoryGutter = 96.0;

  Rect plotRect(Size size) => horizontal
      ? Rect.fromLTRB(
          categoryGutter,
          6,
          size.width - 16,
          size.height - bottomGutter,
        )
      : Rect.fromLTRB(
          leftGutter,
          topGutter,
          size.width - 4,
          size.height - bottomGutter,
        );

  int? indexAt(Size size, Offset o, _ChartStyle st) {
    final r = plotRect(size);
    if (slots == 0) return null;
    if (horizontal) {
      final slot = r.height / slots;
      return ((o.dy - r.top) / slot).floor().clamp(0, slots - 1);
    }
    final slot = r.width / slots;
    return ((o.dx - r.left) / slot).floor().clamp(0, slots - 1);
  }
}

class _CartesianPainter extends CustomPainter {
  final _CartesianModel m;
  final _ChartStyle st;
  final int? selected;
  final bool showValues;
  _CartesianPainter(this.m, this.st, this.selected, this.showValues);

  @override
  void paint(Canvas canvas, Size size) {
    final r = m.plotRect(size);
    final h = m.horizontal;
    // Posição de um valor no eixo de valores (Y, ou X se invertido).
    double vp(int v) {
      final f = (v - m.minY) / (m.maxY - m.minY);
      return h ? r.left + r.width * f : r.bottom - r.height * f;
    }

    final catStart = h ? r.top : r.left;
    final catEnd = h ? r.bottom : r.right;
    final slot = (catEnd - catStart) / math.max(1, m.slots);
    // Centro de uma categoria no eixo de categorias (X, ou Y se invertido).
    double cc(int x) => catStart + slot * x + slot / 2;
    Offset pt(double cat, double val) =>
        h ? Offset(val, cat) : Offset(cat, val);

    // Grade e eixo de valores (recessivos).
    final grid = Paint()
      ..color = st.fin.gridLine
      ..strokeWidth = 1;
    for (var v = m.minY; v <= m.maxY; v += m.step) {
      final p = vp(v);
      canvas.drawLine(pt(catStart, p), pt(catEnd, p), grid);
      if (h) {
        _text(
          canvas,
          formatValue(v, m.money, compact: true),
          Offset(p, r.bottom + 4),
          align: _Align.centerTop,
          maxWidth: 56,
        );
      } else {
        _text(
          canvas,
          formatValue(v, m.money, compact: true),
          Offset(r.left - 6, p),
          align: _Align.rightMiddle,
          maxWidth: _CartesianModel.leftGutter - 8,
        );
      }
    }
    if (m.minY < 0) {
      canvas.drawLine(
        pt(catStart, vp(0)),
        pt(catEnd, vp(0)),
        Paint()
          ..color = st.fin.subtle.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
    }

    if (selected != null && selected! < m.slots) {
      final band = h
          ? Rect.fromLTWH(
              r.left,
              r.top + slot * selected! + 2,
              r.width,
              slot - 4,
            )
          : Rect.fromLTWH(
              r.left + slot * selected! + 2,
              r.top,
              slot - 4,
              r.height,
            );
      canvas.drawRRect(
        RRect.fromRectAndRadius(band, const Radius.circular(6)),
        Paint()..color = st.fin.gridLine.withValues(alpha: 0.6),
      );
    }

    // Barras: 4px de raio na ponta, 2px de espaço entre barras vizinhas.
    for (final b in m.bars) {
      final inner = slot * (m.slots > 16 ? 0.86 : 0.7);
      final bw = math.min(28.0 * b.gn, inner) / b.gn;
      final start = cc(b.x) - bw * b.gn / 2 + bw * b.gi;
      final pHi = vp(b.hi), pLo = vp(b.lo);
      if ((pHi - pLo).abs() < 0.5) continue;
      final rect = h
          ? Rect.fromLTRB(pLo, start + 1, pHi, start + bw - 1)
          : Rect.fromLTRB(start + 1, pHi, start + bw - 1, pLo);
      final rad = Radius.circular(
        math.min(4, (h ? rect.height : rect.width) / 2),
      );
      final positive = b.hi > 0 && b.lo >= 0;
      // Ponta do valor alto (topo, ou direita) e do valor baixo.
      final hiR = (b.roundTop && positive) || b.roundBottom ? rad : Radius.zero;
      final loR = (!positive && b.roundTop) || b.roundBottom
          ? rad
          : Radius.zero;
      canvas.drawRRect(
        h
            ? RRect.fromRectAndCorners(
                rect,
                topRight: hiR,
                bottomRight: hiR,
                topLeft: loR,
                bottomLeft: loR,
              )
            : RRect.fromRectAndCorners(
                rect,
                topLeft: hiR,
                topRight: hiR,
                bottomLeft: loR,
                bottomRight: loR,
              ),
        Paint()..color = b.color,
      );
      // Separador de 2px entre segmentos empilhados.
      if (!b.roundTop && b.gn == 1 && positive) {
        canvas.drawLine(
          h ? Offset(pHi, rect.top) : Offset(rect.left, pHi),
          h ? Offset(pHi, rect.bottom) : Offset(rect.right, pHi),
          Paint()
            ..color = st.surface
            ..strokeWidth = 2,
        );
      }
      if (showValues && (m.bars.length <= 24 || b.x == selected)) {
        final v = positive ? b.hi - b.lo : b.lo - b.hi;
        final txt = formatValue(v, m.money, compact: true);
        if (h) {
          _text(
            canvas,
            txt,
            Offset(positive ? rect.right + 3 : rect.left - 3, rect.center.dy),
            align: positive ? _Align.leftMiddle : _Align.rightMiddle,
            maxWidth: 56,
          );
        } else {
          _text(
            canvas,
            txt,
            Offset(rect.center.dx, positive ? pHi - 2 : pLo + 2),
            align: positive ? _Align.centerBottom : _Align.centerTop,
            maxWidth: math.max(bw + 16, 40),
          );
        }
      }
    }

    // Linhas de 2px; marcadores de 8px com anel da cor da superfície.
    for (final l in m.lines) {
      if (l.values.isEmpty) continue;
      final pts = [
        for (var i = 0; i < l.values.length; i++) pt(cc(i), vp(l.values[i])),
      ];
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      if (l.fill && !h) {
        final base = vp(math.max(m.minY, math.min(0, m.maxY)));
        final fill = Path.from(path)
          ..lineTo(pts.last.dx, base)
          ..lineTo(pts.first.dx, base)
          ..close();
        canvas.drawPath(fill, Paint()..color = l.color.withValues(alpha: 0.14));
      }
      final stroke = Paint()
        ..color = l.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      if (l.dashed) {
        _dash(canvas, pts, stroke);
      } else {
        canvas.drawPath(path, stroke);
      }
      for (var i = 0; i < pts.length; i++) {
        if (!(l.markers || i == selected)) continue;
        canvas.drawCircle(pts[i], 6, Paint()..color = st.surface);
        canvas.drawCircle(pts[i], 4, Paint()..color = l.color);
      }
      if (showValues && !l.dashed && pts.length <= 12) {
        for (var i = 0; i < pts.length; i++) {
          if (pts.length > 6 && i != pts.length - 1 && i != selected) continue;
          _text(
            canvas,
            formatValue(l.values[i], m.money, compact: true),
            h ? pts[i] + const Offset(8, 0) : pts[i] - const Offset(0, 8),
            align: h ? _Align.leftMiddle : _Align.centerBottom,
            maxWidth: 60,
          );
        }
      }
    }

    if (!h) {
      for (var i = 0; i < m.pointNotes.length; i++) {
        final note = m.pointNotes[i];
        if (note == null || m.lines.isEmpty) continue;
        final main = m.lines.firstWhere((l) => !l.dashed);
        _text(
          canvas,
          note,
          Offset(cc(i), vp(main.values[i]) + 10),
          align: _Align.centerTop,
          maxWidth: slot,
        );
      }
    }

    for (final ref in m.refs) {
      final p = vp(ref.value);
      _dash(
        canvas,
        [pt(catStart, p), pt(catEnd, p)],
        Paint()
          ..color = st.fin.negative.withValues(alpha: 0.7)
          ..strokeWidth = 1,
      );
      _text(
        canvas,
        ref.label,
        h ? Offset(p + 3, r.top + 6) : Offset(r.right - 2, p - 2),
        align: h ? _Align.leftMiddle : _Align.rightBottom,
      );
    }

    // Rótulos das categorias (pula alguns quando não cabem).
    final every = h
        ? math.max(1, (m.slots * 16 / r.height).ceil())
        : math.max(1, (m.slots * 46 / r.width).ceil());
    for (var i = 0; i < m.slots; i++) {
      if (i % every != 0 && i != selected) continue;
      if (h) {
        _text(
          canvas,
          m.xLabels[i],
          Offset(r.left - 6, cc(i)),
          align: _Align.rightMiddle,
          maxWidth: _CartesianModel.categoryGutter - 8,
          bold: i == selected,
        );
      } else {
        _text(
          canvas,
          m.xLabels[i],
          Offset(cc(i), r.bottom + 4),
          align: _Align.centerTop,
          maxWidth: slot * every - 2,
          bold: i == selected,
        );
      }
    }
  }

  void _dash(Canvas canvas, List<Offset> pts, Paint p) {
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final len = (b - a).distance;
      if (len == 0) continue;
      final dir = (b - a) / len;
      for (var t = 0.0; t < len; t += 8) {
        canvas.drawLine(a + dir * t, a + dir * math.min(t + 4, len), p);
      }
    }
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    required _Align align,
    double maxWidth = 120,
    bool bold = false,
    Color? color,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: st.label.copyWith(
          fontWeight: bold ? FontWeight.w700 : null,
          color: color ?? (bold ? st.ink : null),
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(8, maxWidth));
    final o = switch (align) {
      _Align.rightMiddle => Offset(at.dx - tp.width, at.dy - tp.height / 2),
      _Align.leftMiddle => Offset(at.dx, at.dy - tp.height / 2),
      _Align.centerTop => Offset(at.dx - tp.width / 2, at.dy),
      _Align.centerBottom => Offset(at.dx - tp.width / 2, at.dy - tp.height),
      _Align.rightBottom => Offset(at.dx - tp.width, at.dy - tp.height),
    };
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _CartesianPainter old) =>
      old.m != m || old.selected != selected || old.showValues != showValues;
}

enum _Align { rightMiddle, leftMiddle, centerTop, centerBottom, rightBottom }

// Pizza / rosca ---------------------------------------------------------------

class _PieModel {
  final List<int> values;
  final List<Color> colors;
  final List<String> labels;
  final bool donut;
  final int total;
  final bool money;

  _PieModel(ChartDataset d, this.colors, {required this.donut})
    : values = d.combined().map((v) => math.max(0, v)).toList(),
      labels = d.xLabels,
      money = d.isMoney,
      total = d.combined().fold(0, (a, b) => a + math.max(0, b));

  (Offset, double) geometry(Size s) {
    final r = math.min(s.width, s.height) / 2 - 8;
    return (Offset(s.width / 2, s.height / 2), r);
  }

  int? hit(Size s, Offset p) {
    final (c, r) = geometry(s);
    final v = p - c;
    if (v.distance > r + 8 || (donut && v.distance < r * 0.58)) return null;
    var ang = math.atan2(v.dy, v.dx) + math.pi / 2;
    if (ang < 0) ang += 2 * math.pi;
    var acc = 0.0;
    for (var i = 0; i < values.length; i++) {
      acc += total == 0 ? 0 : values[i] / total * 2 * math.pi;
      if (ang <= acc) return i;
    }
    return null;
  }
}

class _PiePainter extends CustomPainter {
  final _PieModel m;
  final _ChartStyle st;
  final int? selected;
  final bool showPct;
  _PiePainter(this.m, this.st, this.selected, this.showPct);

  @override
  void paint(Canvas canvas, Size size) {
    if (m.total <= 0) return;
    final (c, r) = m.geometry(size);
    var start = -math.pi / 2;
    for (var i = 0; i < m.values.length; i++) {
      final sweep = m.values[i] / m.total * 2 * math.pi;
      if (sweep <= 0) continue;
      final mid = start + sweep / 2;
      final off = i == selected
          ? Offset(math.cos(mid), math.sin(mid)) * 6
          : Offset.zero;
      final rect = Rect.fromCircle(center: c + off, radius: r);
      canvas.drawArc(rect, start, sweep, true, Paint()..color = m.colors[i]);
      // 2px de separação entre fatias.
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..color = st.surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (showPct && sweep > 0.35) {
        final lr = m.donut ? r * 0.79 : r * 0.62;
        final pos = c + off + Offset(math.cos(mid), math.sin(mid)) * lr;
        final tp = TextPainter(
          text: TextSpan(
            text: formatPct(m.values[i] / m.total * 100),
            style: st.label.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              shadows: const [Shadow(blurRadius: 2, color: Colors.black54)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
      start += sweep;
    }
    if (m.donut) {
      canvas.drawCircle(c, r * 0.58, Paint()..color = st.surface);
      final i = selected;
      final title = i == null ? 'Total' : m.labels[i];
      final value = formatValue(
        i == null ? m.total : m.values[i],
        m.money,
        compact: true,
      );
      final tp1 = TextPainter(
        text: TextSpan(text: title, style: st.label),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r * 1.0);
      final tp2 = TextPainter(
        text: TextSpan(
          text: value,
          style: st.label.copyWith(
            color: st.ink,
            fontSize: (st.label.fontSize ?? 11) + 5,
            fontWeight: FontWeight.w700,
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r * 1.1);
      final h = tp1.height + tp2.height;
      tp1.paint(canvas, c - Offset(tp1.width / 2, h / 2));
      tp2.paint(canvas, c - Offset(tp2.width / 2, h / 2 - tp1.height));
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.m != m || old.selected != selected;
}
