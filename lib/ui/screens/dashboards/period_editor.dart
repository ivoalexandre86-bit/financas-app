import 'package:flutter/material.dart';

import '../../../core/dates.dart';
import '../../../domain/models/dashboard.dart';
import '../../theme.dart';

/// Editor de período reutilizado pelo filtro do painel e pelos gráficos.
class PeriodEditor extends StatelessWidget {
  final PeriodSpec value;
  final YearMonth reference;
  final ValueChanged<PeriodSpec> onChanged;
  const PeriodEditor({
    super.key,
    required this.value,
    required this.reference,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = value.resolve(reference);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<PeriodKind>(
          initialValue: value.kind,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Tipo de período'),
          items: [
            for (final k in PeriodKind.values)
              DropdownMenuItem(value: k, child: Text(k.label)),
          ],
          onChanged: (k) {
            if (k == null) return;
            onChanged(switch (k) {
              PeriodKind.specificMonth => value.copyWith(
                kind: k,
                month: value.month ?? reference,
              ),
              PeriodKind.multipleMonths => value.copyWith(
                kind: k,
                months: value.months.isEmpty
                    ? [reference.add(-1), reference]
                    : value.months,
              ),
              PeriodKind.customRange => value.copyWith(
                kind: k,
                from: value.from ?? reference.firstDay,
                to: value.to ?? reference.lastDay,
              ),
              _ => value.copyWith(kind: k),
            });
          },
        ),
        const SizedBox(height: 12),
        switch (value.kind) {
          PeriodKind.referenceMonth => _hint(
            context,
            'Acompanha o mês selecionado no painel (${reference.longLabel}).',
          ),
          PeriodKind.specificMonth => _MonthStepper(
            label: 'Mês',
            month: value.month ?? reference,
            onChanged: (m) => onChanged(value.copyWith(month: m)),
          ),
          PeriodKind.multipleMonths => _MultiMonths(
            reference: reference,
            selected: value.months.toSet(),
            onChanged: (s) =>
                onChanged(value.copyWith(months: s.toList()..sort())),
          ),
          PeriodKind.relative => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OffsetStepper(
                label: 'De',
                value: value.fromOffset,
                reference: reference,
                onChanged: (v) => onChanged(
                  value.copyWith(
                    fromOffset: v,
                    toOffset: v > value.toOffset ? v : value.toOffset,
                  ),
                ),
              ),
              _OffsetStepper(
                label: 'Até',
                value: value.toOffset,
                reference: reference,
                onChanged: (v) => onChanged(
                  value.copyWith(
                    toOffset: v,
                    fromOffset: v < value.fromOffset ? v : value.fromOffset,
                  ),
                ),
              ),
            ],
          ),
          PeriodKind.year => Row(
            children: [
              Text('Ano', style: context.text.bodyMedium),
              const Spacer(),
              IconButton(
                tooltip: 'Ano anterior',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => onChanged(
                  value.copyWith(year: (value.year ?? reference.year) - 1),
                ),
              ),
              Text(
                value.year == null
                    ? '${reference.year} (do mês de referência)'
                    : '${value.year}',
                style: context.text.titleSmall,
              ),
              IconButton(
                tooltip: 'Próximo ano',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => onChanged(
                  value.copyWith(year: (value.year ?? reference.year) + 1),
                ),
              ),
              if (value.year != null)
                TextButton(
                  onPressed: () => onChanged(value.copyWith(year: null)),
                  child: const Text('Acompanhar'),
                ),
            ],
          ),
          PeriodKind.customRange => OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text(resolved.label),
            onPressed: () async {
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDateRange: DateTimeRange(
                  start: value.from ?? reference.firstDay,
                  end: value.to ?? reference.lastDay,
                ),
              );
              if (r != null) {
                onChanged(
                  value.copyWith(
                    from: Dates.dateOnly(r.start),
                    to: Dates.dateOnly(r.end),
                  ),
                );
              }
            },
          ),
        },
        const SizedBox(height: 4),
        _hint(context, 'Período resultante: ${resolved.label}'),
      ],
    );
  }

  Widget _hint(BuildContext context, String s) => Text(
    s,
    style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
  );
}

class _MonthStepper extends StatelessWidget {
  final String label;
  final YearMonth month;
  final ValueChanged<YearMonth> onChanged;
  const _MonthStepper({
    required this.label,
    required this.month,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label, style: context.text.bodyMedium),
      const Spacer(),
      IconButton(
        tooltip: 'Mês anterior',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => onChanged(month.previous),
      ),
      Text(month.longLabel, style: context.text.titleSmall),
      IconButton(
        tooltip: 'Próximo mês',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => onChanged(month.next),
      ),
    ],
  );
}

class _OffsetStepper extends StatelessWidget {
  final String label;
  final int value;
  final YearMonth reference;
  final ValueChanged<int> onChanged;
  const _OffsetStepper({
    required this.label,
    required this.value,
    required this.reference,
    required this.onChanged,
  });

  String get _desc {
    if (value == 0) return 'mês de referência';
    final n = value.abs();
    final unit = n == 1 ? 'mês' : 'meses';
    return value < 0 ? '$n $unit antes' : '$n $unit depois';
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 36, child: Text(label)),
      IconButton(
        tooltip: 'Diminuir',
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: value <= -36 ? null : () => onChanged(value - 1),
      ),
      Expanded(
        child: Text(
          '$_desc · ${reference.add(value).shortLabel}',
          textAlign: TextAlign.center,
        ),
      ),
      IconButton(
        tooltip: 'Aumentar',
        icon: const Icon(Icons.add_circle_outline),
        onPressed: value >= 36 ? null : () => onChanged(value + 1),
      ),
    ],
  );
}

class _MultiMonths extends StatefulWidget {
  final YearMonth reference;
  final Set<YearMonth> selected;
  final ValueChanged<Set<YearMonth>> onChanged;
  const _MultiMonths({
    required this.reference,
    required this.selected,
    required this.onChanged,
  });
  @override
  State<_MultiMonths> createState() => _MultiMonthsState();
}

class _MultiMonthsState extends State<_MultiMonths> {
  late int year = widget.selected.isEmpty
      ? widget.reference.year
      : widget.selected.last.year;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Ano anterior',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => year--),
            ),
            Text('$year', style: context.text.titleSmall),
            IconButton(
              tooltip: 'Próximo ano',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => year++),
            ),
            const Spacer(),
            Text(
              '${widget.selected.length} selecionado(s)',
              style: context.text.labelSmall,
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var m = 1; m <= 12; m++)
              () {
                final ym = YearMonth(year, m);
                final on = widget.selected.contains(ym);
                return FilterChip(
                  label: Text(ym.shortLabel.split('/').first),
                  selected: on,
                  onSelected: (v) {
                    final s = {...widget.selected};
                    v ? s.add(ym) : s.remove(ym);
                    if (s.isNotEmpty) widget.onChanged(s);
                  },
                );
              }(),
          ],
        ),
      ],
    );
  }
}
