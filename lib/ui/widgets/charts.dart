import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../theme.dart';

class BarPoint {
  final String label;
  final Money income;
  final Money expenses;
  final bool highlight;
  const BarPoint(
    this.label,
    this.income,
    this.expenses, {
    this.highlight = false,
  });
}

/// Barras agrupadas Receitas × Despesas por mês, com legenda e toque para
/// ver valores.
class IncomeExpenseChart extends StatefulWidget {
  final List<BarPoint> points;
  const IncomeExpenseChart({super.key, required this.points});

  @override
  State<IncomeExpenseChart> createState() => _IncomeExpenseChartState();
}

class _IncomeExpenseChartState extends State<IncomeExpenseChart> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    final fin = context.fin;
    final sel = selected == null ? null : widget.points[selected!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Legend(color: fin.income, label: 'Receitas'),
            const SizedBox(width: 16),
            _Legend(color: fin.expense, label: 'Despesas'),
            const Spacer(),
            if (sel != null)
              Text(
                '${sel.label}: ${sel.income.formatCompact()} / ${sel.expenses.formatCompact()}',
                style: context.text.labelMedium,
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: LayoutBuilder(
            builder: (context, c) {
              return GestureDetector(
                onTapDown: (d) {
                  final w = c.maxWidth / widget.points.length;
                  setState(
                    () => selected = (d.localPosition.dx ~/ w).clamp(
                      0,
                      widget.points.length - 1,
                    ),
                  );
                },
                child: CustomPaint(
                  size: Size(c.maxWidth, 150),
                  painter: _BarsPainter(
                    widget.points,
                    fin,
                    context.text.labelSmall!.copyWith(color: fin.subtle),
                    context.colors.surfaceContainerLowest,
                    selected,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: context.text.labelMedium),
    ],
  );
}

class _BarsPainter extends CustomPainter {
  final List<BarPoint> points;
  final FinColors fin;
  final TextStyle labelStyle;
  final Color surface;
  final int? selected;
  _BarsPainter(
    this.points,
    this.fin,
    this.labelStyle,
    this.surface,
    this.selected,
  );

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 18.0;
    final chartH = size.height - labelH;
    final maxV = points.fold<int>(
      1,
      (m, p) => math.max(m, math.max(p.income.cents, p.expenses.cents)),
    );
    final slot = size.width / points.length;
    final barW = math.min(18.0, (slot - 16) / 2);
    final grid = Paint()
      ..color = fin.gridLine
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, chartH), Offset(size.width, chartH), grid);
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final cx = slot * i + slot / 2;
      if (selected == i) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(slot * i + 4, 0, slot - 8, chartH),
            const Radius.circular(8),
          ),
          Paint()..color = fin.gridLine.withValues(alpha: 0.6),
        );
      }
      void bar(double left, int v, Color c) {
        final h = chartH * v / maxV;
        if (h <= 0) return;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left, chartH - h, barW, h),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = c,
        );
      }

      bar(cx - barW - 1, p.income.cents, fin.income);
      bar(cx + 1, p.expenses.cents, fin.expense);
      final tp = TextPainter(
        text: TextSpan(
          text: p.label,
          style: labelStyle.copyWith(
            fontWeight: p.highlight ? FontWeight.w700 : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) =>
      old.points != points || old.selected != selected || old.fin != fin;
}

/// Linha de tendência do saldo acumulado.
class BalanceTrendChart extends StatefulWidget {
  final List<(String, Money)> points;
  final int? currentIndex;
  const BalanceTrendChart({super.key, required this.points, this.currentIndex});
  @override
  State<BalanceTrendChart> createState() => _BalanceTrendChartState();
}

class _BalanceTrendChartState extends State<BalanceTrendChart> {
  int? selected;
  @override
  Widget build(BuildContext context) {
    final fin = context.fin;
    final i = selected ?? widget.points.length - 1;
    final p = widget.points[i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${p.$1}: ${p.$2.format()}',
          style: context.text.labelLarge?.copyWith(
            color: p.$2.isNegative ? fin.negative : null,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: LayoutBuilder(
            builder: (context, c) {
              void pick(Offset o) {
                final n = widget.points.length;
                final step = n <= 1 ? c.maxWidth : c.maxWidth / (n - 1);
                setState(
                  () => selected = (o.dx / step).round().clamp(0, n - 1),
                );
              }

              return GestureDetector(
                onTapDown: (d) => pick(d.localPosition),
                onHorizontalDragUpdate: (d) => pick(d.localPosition),
                child: CustomPaint(
                  size: Size(c.maxWidth, 120),
                  painter: _LinePainter(
                    widget.points,
                    context.colors.primary,
                    fin,
                    context.text.labelSmall!.copyWith(color: fin.subtle),
                    context.colors.surfaceContainerLowest,
                    i,
                    widget.currentIndex,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<(String, Money)> points;
  final Color color;
  final FinColors fin;
  final TextStyle labelStyle;
  final Color surface;
  final int selected;
  final int? currentIndex;
  _LinePainter(
    this.points,
    this.color,
    this.fin,
    this.labelStyle,
    this.surface,
    this.selected,
    this.currentIndex,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const labelH = 18.0;
    const pad = 8.0;
    final h = size.height - labelH - pad;
    var minV = points.map((p) => p.$2.cents).reduce(math.min);
    var maxV = points.map((p) => p.$2.cents).reduce(math.max);
    minV = math.min(minV, 0);
    if (maxV == minV) maxV = minV + 1;
    final n = points.length;
    final dx = n <= 1 ? 0.0 : (size.width - 16) / (n - 1);
    Offset at(int i) => Offset(
      8 + dx * i,
      pad + h - h * (points[i].$2.cents - minV) / (maxV - minV),
    );

    final zeroY = pad + h - h * (0 - minV) / (maxV - minV);
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = fin.gridLine
        ..strokeWidth = 1,
    );

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(at(n - 1).dx, zeroY)
      ..lineTo(at(0).dx, zeroY)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.08));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    final s = at(selected);
    canvas.drawLine(
      Offset(s.dx, pad),
      Offset(s.dx, pad + h),
      Paint()
        ..color = fin.subtle.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(s, 6, Paint()..color = surface);
    canvas.drawCircle(s, 4, Paint()..color = color);

    for (var i = 0; i < n; i++) {
      if (n > 6 && (n - 1 - i) % 2 == 1) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: points[i].$1,
          style: labelStyle.copyWith(
            fontWeight: i == currentIndex ? FontWeight.w700 : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (at(i).dx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - labelH + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.points != points || old.selected != selected || old.color != color;
}
