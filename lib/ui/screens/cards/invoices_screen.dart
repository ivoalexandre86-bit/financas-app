import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/billing_cycle.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'card_details_screen.dart';
import 'cards_screen.dart';
import 'invoice_details_screen.dart';

/// Visão consolidada das faturas de todos os cartões.
class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final cards = fc.data.cards.where((c) => c.active).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Faturas')),
      body: cards.isEmpty
          ? EmptyState(
              icon: Icons.receipt_outlined,
              title: 'Nenhum cartão ativo',
              actionLabel: 'Cadastrar cartão',
              onAction: () => push(context, const CardFormScreen()),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final card in cards) ...[
                  Row(
                    children: [
                      Icon(Icons.credit_card, color: Color(card.color)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(card.name, style: context.text.titleMedium),
                      ),
                      TextButton(
                        onPressed: () =>
                            push(context, CardDetailsScreen(cardId: card.id)),
                        child: const Text('Todas'),
                      ),
                    ],
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (final m in [
                          BillingCycle.currentInvoice(card, e.today).previous,
                          BillingCycle.currentInvoice(card, e.today),
                          BillingCycle.currentInvoice(card, e.today).next,
                        ])
                          () {
                            final inv = e.invoice(card, m);
                            return ListTile(
                              onTap: () => push(
                                context,
                                InvoiceDetailsScreen(cardId: card.id, month: m),
                              ),
                              title: Text('Fatura ${m.shortLabel}'),
                              subtitle: Text(
                                'Vence ${Dates.format(inv.dueDate)}',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  MoneyText(
                                    inv.total,
                                    style: context.text.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    inv.status.label,
                                    style: context.text.labelSmall?.copyWith(
                                      color: invoiceStatusColor(
                                        context,
                                        inv.status,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
    );
  }
}
