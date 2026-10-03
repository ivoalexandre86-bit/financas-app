import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/billing_cycle.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../transactions/transaction_form_screen.dart';
import 'installment_details_screen.dart';

/// Quantas parcelas já foram faturadas/vencidas (para "3/12").
int installmentsElapsed(FinanceController fc, List<FinTransaction> parts) {
  final today = fc.today;
  var n = 0;
  for (final t in parts) {
    if (t.status == TransactionStatus.cancelled) continue;
    final card = fc.data.cardById[t.cardId];
    final due = card == null
        ? t.date
        : BillingCycle.closingDate(
            card,
            BillingCycle.invoiceForTransaction(card, t),
          );
    if (!due.isAfter(today)) n++;
  }
  return n;
}

class InstallmentsScreen extends StatelessWidget {
  const InstallmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final groups = [...fc.data.installmentGroups]
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    return Scaffold(
      appBar: AppBar(title: const Text('Parcelamentos')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-inst',
        onPressed: () => push(context, const TransactionFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nova compra'),
      ),
      body: groups.isEmpty
          ? const EmptyState(
              icon: Icons.view_week_outlined,
              title: 'Nenhuma compra parcelada',
              message: 'Ao registrar uma despesa, ative “Compra parcelada” para gerar as parcelas.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final g = groups[i];
                final parts = fc.installmentsOf(g.id);
                final active = parts.where(
                  (t) => t.status != TransactionStatus.cancelled,
                );
                final elapsed = installmentsElapsed(fc, parts);
                final where = g.cardId != null
                    ? fc.data.cardById[g.cardId]?.name
                    : fc.data.accountById[g.accountId]?.name;
                final finished = elapsed >= active.length;
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () =>
                        push(context, InstallmentDetailsScreen(groupId: g.id)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  g.description,
                                  style: context.text.titleMedium,
                                ),
                              ),
                              Text(
                                '${elapsed.clamp(0, g.count)}/${g.count}',
                                style: context.text.titleMedium?.copyWith(
                                  color: context.colors.primary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${where ?? '—'} · compra em ${Dates.format(g.purchaseDate)}',
                            style: context.text.bodySmall?.copyWith(
                              color: context.fin.subtle,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: g.count == 0 ? 0 : elapsed / g.count,
                              minHeight: 6,
                              backgroundColor: context.fin.gridLine,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '${g.count}× ${parts.isEmpty ? '' : parts.last.amount.format()}',
                              ),
                              const Spacer(),
                              if (finished)
                                Pill('Quitado', color: context.fin.positive)
                              else
                                MoneyText(
                                  g.totalAmount,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
