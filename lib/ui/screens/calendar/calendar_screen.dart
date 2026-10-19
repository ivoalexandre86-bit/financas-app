import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../cards/invoice_details_screen.dart';
import '../transactions/transaction_details_screen.dart';

/// Um lançamento no calendário: transação (fora do cartão) ou fatura.
class CalendarItem {
  final DateTime date;
  final String description;

  /// Valor positivo; [isIncome] diz o sentido.
  final Money amount;
  final bool isIncome;
  final String status;
  final bool overdue;
  final FinTransaction? tx;
  final Invoice? invoice;
  const CalendarItem({
    required this.date,
    required this.description,
    required this.amount,
    required this.isIncome,
    required this.status,
    this.overdue = false,
    this.tx,
    this.invoice,
  });
}

/// Itens do mês por dia, pela data de caixa (regime de caixa, como o resto
/// do app): planejados, recorrências e parcelas incluídos; compras no cartão
/// entram uma única vez, pela fatura.
Map<int, List<CalendarItem>> calendarItems(FinancialEngine e, YearMonth month) {
  final out = <int, List<CalendarItem>>{};
  void add(CalendarItem it) => out.putIfAbsent(it.date.day, () => []).add(it);
  for (final ev in e.monthEvents(ProjectionFilter.none, month)) {
    final t = ev.tx;
    if (t.cardId != null || ev.signed.isZero) continue;
    add(
      CalendarItem(
        date: ev.date,
        description: t.description,
        amount: ev.signed.abs(),
        isIncome: ev.isIncome,
        status: t.status.label,
        overdue: e.isOverdue(t),
        tx: t,
      ),
    );
  }
  for (final (:invoice, :slice) in e.invoiceSlicesIn(month, month)) {
    if (!slice.amount.isPositive) continue;
    add(
      CalendarItem(
        date: slice.date,
        description:
            'Fatura ${invoice.card.name} (${invoice.month.shortLabel})',
        amount: slice.amount,
        isIncome: false,
        status: slice.settled ? 'Paga' : invoice.status.label,
        overdue: !slice.settled && slice.date.isBefore(e.today),
        invoice: invoice,
      ),
    );
  }
  return out;
}

/// Calendário de vencimentos: entradas e saídas de cada dia do mês.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  YearMonth month = YearMonth.now();
  int? selected = Dates.today().day;

  void _setMonth(YearMonth m, DateTime today) => setState(() {
    month = m;
    selected = m.contains(today) ? today.day : null;
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final today = e.today;
    final items = calendarItems(e, month);
    var income = Money.zero, expense = Money.zero;
    for (final l in items.values) {
      for (final it in l) {
        if (it.isIncome) {
          income += it.amount;
        } else {
          expense += it.amount;
        }
      }
    }
    final day = selected;
    final dayItems = day == null ? const <CalendarItem>[] : items[day] ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Calendário')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Center(
            child: MonthSwitcher(
              month: month,
              onChanged: (m) => _setMonth(m, today),
            ),
          ),
          const SizedBox(height: 8),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    _Total('Entradas', income, context.fin.income),
                    _Total('Saídas', expense, context.fin.expense),
                  ],
                ),
                const SizedBox(height: 12),
                _MonthGrid(
                  month: month,
                  today: today,
                  items: items,
                  selected: day,
                  onSelect: (d) => setState(() => selected = d),
                ),
              ],
            ),
          ),
          if (day != null) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: Dates.format(DateTime(month.year, month.month, day)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: dayItems.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Nada previsto neste dia.',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.fin.subtle,
                        ),
                      ),
                    )
                  : Column(
                      children: [for (final it in dayItems) _ItemTile(it)],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final Money value;
  final Color color;
  const _Total(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label: ', style: context.text.bodyMedium),
      MoneyText(
        value,
        color: color,
        style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _MonthGrid extends StatelessWidget {
  final YearMonth month;
  final DateTime today;
  final Map<int, List<CalendarItem>> items;
  final int? selected;
  final ValueChanged<int> onSelect;
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  static const _weekdays = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

  @override
  Widget build(BuildContext context) {
    // Domingo primeiro: DateTime.weekday vai de 1 (seg) a 7 (dom).
    final lead = month.firstDay.weekday % 7;
    final cells = lead + month.days;
    final rows = (cells + 6) ~/ 7;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth / 7;
        final compact = w < 76;
        return Column(
          children: [
            Row(
              children: [
                for (final d in _weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: context.text.labelSmall?.copyWith(
                          color: context.fin.subtle,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var r = 0; r < rows; r++)
              Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final day = r * 7 + col - lead + 1;
                          if (day < 1 || day > month.days) {
                            return SizedBox(height: compact ? 52 : 72);
                          }
                          return _DayCell(
                            key: Key('cal-day-$day'),
                            day: day,
                            items: items[day] ?? const [],
                            compact: compact,
                            isToday: month.contains(today) && today.day == day,
                            selected: selected == day,
                            onTap: () => onSelect(day),
                          );
                        },
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final List<CalendarItem> items;
  final bool compact;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;
  const _DayCell({
    super.key,
    required this.day,
    required this.items,
    required this.compact,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var inc = Money.zero, exp = Money.zero;
    for (final it in items) {
      if (it.isIncome) {
        inc += it.amount;
      } else {
        exp += it.amount;
      }
    }
    final overdue = items.any((it) => it.overdue);
    final small = context.text.labelSmall?.copyWith(
      fontSize: compact ? 9 : 11,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget amount(Money v, Color color) => Text(
      v.formatCompact(),
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: small?.copyWith(color: color),
    );
    Widget dot(Color color) => Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    final border = selected
        ? Border.all(color: context.colors.primary, width: 2)
        : overdue
        ? Border.all(color: context.fin.negative.withValues(alpha: 0.6))
        : Border.all(color: context.fin.gridLine);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: overdue
            ? context.fin.negative.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: compact ? 48 : 68,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            decoration: BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: isToday
                      ? BoxDecoration(
                          color: context.colors.primary,
                          borderRadius: BorderRadius.circular(10),
                        )
                      : null,
                  child: Text(
                    '$day',
                    style: context.text.labelMedium?.copyWith(
                      fontWeight: isToday ? FontWeight.w800 : null,
                      color: isToday ? context.colors.onPrimary : null,
                    ),
                  ),
                ),
                const Spacer(),
                if (compact)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (inc.isPositive) dot(context.fin.income),
                      if (exp.isPositive) dot(context.fin.expense),
                    ],
                  )
                else ...[
                  if (inc.isPositive) amount(inc, context.fin.income),
                  if (exp.isPositive) amount(exp, context.fin.expense),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final CalendarItem it;
  const _ItemTile(this.it);

  @override
  Widget build(BuildContext context) {
    final color = it.isIncome ? context.fin.income : context.fin.expense;
    final status = it.overdue ? 'Vencida' : it.status;
    return ListTile(
      onTap: () {
        if (it.tx != null) {
          push(context, TransactionDetailsScreen(tx: it.tx!));
        } else if (it.invoice != null) {
          push(
            context,
            InvoiceDetailsScreen(
              cardId: it.invoice!.card.id,
              month: it.invoice!.month,
            ),
          );
        }
      },
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
          it.invoice != null
              ? Icons.credit_card
              : it.isIncome
              ? Icons.arrow_downward
              : Icons.arrow_upward,
          color: color,
          size: 20,
        ),
      ),
      title: Text(it.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        status,
        style: it.overdue
            ? TextStyle(
                color: context.fin.negative,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      trailing: MoneyText(
        it.isIncome ? it.amount : -it.amount,
        color: color,
        style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
