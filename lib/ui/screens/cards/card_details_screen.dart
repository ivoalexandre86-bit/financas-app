import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'cards_screen.dart';
import 'invoice_details_screen.dart';

Color invoiceStatusColor(BuildContext context, InvoiceStatus s) => switch (s) {
  InvoiceStatus.paid => context.fin.positive,
  InvoiceStatus.overdue => context.fin.negative,
  InvoiceStatus.partial || InvoiceStatus.closed => context.fin.warning,
  InvoiceStatus.open => context.colors.primary,
  InvoiceStatus.future => context.fin.subtle,
};

class CardDetailsScreen extends StatelessWidget {
  final String cardId;
  const CardDetailsScreen({super.key, required this.cardId});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final card = fc.data.cardById[cardId];
    if (card == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.credit_card,
          title: 'Cartão removido',
        ),
      );
    }
    final e = fc.engine;
    final invoices = e
        .invoicesForCard(card, until: e.currentMonth.add(12))
        .reversed
        .toList();
    final future = invoices
        .where((i) => i.status == InvoiceStatus.future)
        .toList()
        .reversed
        .toList();
    final current = invoices
        .where((i) => i.status == InvoiceStatus.open)
        .toList();
    final past = invoices
        .where(
          (i) =>
              i.status != InvoiceStatus.future &&
              i.status != InvoiceStatus.open,
        )
        .toList();

    Widget tile(Invoice inv) => ListTile(
      onTap: () => push(
        context,
        InvoiceDetailsScreen(cardId: card.id, month: inv.month),
      ),
      title: Text('Fatura ${inv.month.shortLabel}'),
      subtitle: Text(
        'Fecha ${Dates.format(inv.closingDate)} · vence ${Dates.format(inv.dueDate)}',
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
              color: invoiceStatusColor(context, inv.status),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(card.name),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => push(context, CardFormScreen(card: card)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          CreditCardVisual(card: card, tappable: false),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              children: [
                InfoRow('Limite total', MoneyText(card.limit)),
                InfoRow(
                  'Limite disponível',
                  MoneyText(e.availableLimit(card), colorize: true),
                ),
                InfoRow.text('Fechamento', 'Dia ${card.closingDay}'),
                InfoRow.text('Vencimento', 'Dia ${card.dueDay}'),
                InfoRow.text('Melhor dia de compra', 'Dia ${card.closingDay}'),
                InfoRow.text(
                  'Conta de pagamento',
                  fc.data.accountById[card.paymentAccountId]?.name ?? '—',
                ),
              ],
            ),
          ),
          if (current.isNotEmpty) ...[
            _title(context, 'Fatura atual'),
            Card(child: Column(children: current.map(tile).toList())),
          ],
          if (future.isNotEmpty) ...[
            _title(context, 'Faturas futuras (projetadas)'),
            Card(child: Column(children: future.map(tile).toList())),
          ],
          if (past.isNotEmpty) ...[
            _title(context, 'Faturas anteriores'),
            Card(child: Column(children: past.map(tile).toList())),
          ],
        ],
      ),
    );
  }

  Widget _title(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(t, style: context.text.titleMedium),
  );
}
