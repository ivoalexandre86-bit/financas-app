import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/recurrence.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import 'recurring_form_screen.dart';

String frequencyLabel(RecurringRule r) {
  if (r.frequency != RecurrenceFrequency.custom) {
    final day = r.dayOfMonth ?? Recurrence.firstOccurrence(r).day;
    return r.frequency == RecurrenceFrequency.weekly
        ? 'Semanal'
        : '${r.frequency.label} · dia $day';
  }
  return 'A cada ${r.interval} ${r.unit.label}';
}

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  bool showEnded = false;

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final today = fc.today;
    final rules =
        fc.data.recurringRules
            .where((r) => showEnded || !r.isEndedBy(today))
            .toList()
          ..sort((a, b) => a.description.compareTo(b.description));
    final income = rules
        .where((r) => r.type == TransactionType.income)
        .toList();
    final expense = rules
        .where((r) => r.type == TransactionType.expense)
        .toList();

    Widget tile(RecurringRule r) {
      final cat = fc.data.categoryById[r.categoryId];
      final next = Recurrence.nextOccurrence(r, today);
      final ended = r.isEndedBy(today);
      final where = r.cardId != null
          ? fc.data.cardById[r.cardId]?.name
          : fc.data.accountById[r.accountId]?.name;
      return ListTile(
        onTap: () => push(context, RecurringFormScreen(rule: r)),
        leading: CircleAvatar(
          backgroundColor: Color(cat?.color ?? 0xFF6B7280)
              .withValues(alpha: 0.12),
          child: Icon(
            categoryIcon(cat?.icon),
            color: Color(cat?.color ?? 0xFF6B7280),
            size: 20,
          ),
        ),
        title: Text(r.description),
        subtitle: Text(
          [
            frequencyLabel(r),
            ?where,
            if (ended)
              'Encerrada'
            else if (r.isPaused)
              'Pausada'
            else if (next != null)
              'Próx. ${Dates.formatShort(next)}',
          ].join(' · '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MoneyText(
              r.amount,
              style: context.text.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: r.type == TransactionType.income
                    ? context.fin.positive
                    : null,
              ),
            ),
            if (r.isPaused || ended)
              Text(
                ended ? 'Encerrada' : 'Pausada',
                style: context.text.labelSmall?.copyWith(
                  color: context.fin.warning,
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorrências'),
        actions: [
          IconButton(
            tooltip: showEnded ? 'Ocultar encerradas' : 'Mostrar encerradas',
            icon: Icon(showEnded ? Icons.history_toggle_off : Icons.history),
            onPressed: () => setState(() => showEnded = !showEnded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-rec',
        onPressed: () => push(context, const RecurringFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nova recorrência'),
      ),
      body: rules.isEmpty
          ? EmptyState(
              icon: Icons.autorenew,
              title: 'Nenhuma recorrência',
              message: 'Cadastre salário, aluguel, assinaturas e contas fixas para projetar meses futuros.',
              actionLabel: 'Nova recorrência',
              onAction: () => push(context, const RecurringFormScreen()),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (income.isNotEmpty) ...[
                  _h(context, 'Receitas recorrentes'),
                  ...income.map(tile),
                ],
                if (expense.isNotEmpty) ...[
                  _h(context, 'Despesas recorrentes'),
                  ...expense.map(tile),
                ],
              ],
            ),
    );
  }

  Widget _h(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(t, style: context.text.titleSmall),
  );
}
