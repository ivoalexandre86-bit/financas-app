import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../domain/engine/financial_engine.dart';
import '../../domain/models/entities.dart';
import '../screens/cards/card_details_screen.dart';
import '../theme.dart';
import 'common.dart';

/// No celular e no tablet (toque), um toque abre os detalhes; no desktop o
/// clique simples apenas seleciona e o duplo clique abre.
bool get isTouchPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => true,
  _ => false,
};

/// Rótulo de status de uma parte da fatura exibida na lista.
String invoiceSliceStatus(Invoice inv, InvoiceSlice slice) {
  if (inv.isCredit) return 'Saldo credor';
  if (slice.settled) {
    return inv.isSettled
        ? InvoiceStatus.paid.label
        : InvoiceStatus.partial.label;
  }
  return inv.status.label;
}

Color invoiceSliceColor(BuildContext context, Invoice inv, InvoiceSlice s) {
  if (inv.isCredit) return context.fin.positive;
  if (s.settled) {
    return invoiceStatusColor(
      context,
      inv.isSettled ? InvoiceStatus.paid : InvoiceStatus.partial,
    );
  }
  return invoiceStatusColor(context, inv.status);
}

/// Linha consolidada de uma fatura de cartão na lista de transações.
class InvoiceTile extends StatelessWidget {
  final Invoice invoice;

  /// Parte da fatura que cai no mês exibido (a fatura inteira, salvo
  /// pagamento parcial).
  final InvoiceSlice slice;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback? onSelect;
  final bool showDate;

  const InvoiceTile({
    super.key,
    required this.invoice,
    required this.slice,
    required this.onOpen,
    this.onSelect,
    this.selected = false,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final color = Color(inv.card.color);
    final n = inv.transactions.length;
    final partial = slice.amount != inv.total && !inv.isCredit;
    final info = [
      if (showDate) Dates.format(slice.date),
      '$n ${n == 1 ? 'lançamento' : 'lançamentos'}',
      'fecha ${Dates.format(inv.closingDate)}',
      if (slice.settled)
        'paga ${Dates.format(slice.date)}'
      else
        'vence ${Dates.format(inv.dueDate)}',
    ].join(' · ');
    final statusLabel = invoiceSliceStatus(inv, slice);
    final statusColor = invoiceSliceColor(context, inv, slice);
    final touch = isTouchPlatform;

    return InkWell(
      key: ValueKey('invoice-${inv.card.id}-${inv.key}'),
      onTap: touch ? onOpen : onSelect,
      onDoubleTap: touch ? null : onOpen,
      child: ListTile(
        selected: selected,
        selectedTileColor: context.colors.primary.withValues(alpha: 0.08),
        contentPadding: const EdgeInsets.only(left: 16, right: 4),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(Icons.credit_card, color: color, size: 20),
        ),
        title: Text(
          inv.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          partial ? '$info · parte de ${inv.total.format()}' : info,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(
                  -slice.amount,
                  showPlus: slice.amount.isNegative,
                  color: slice.amount.isNegative ? context.fin.positive : null,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Pill(statusLabel, color: statusColor),
              ],
            ),
            IconButton(
              key: ValueKey('invoice-open-${inv.card.id}-${inv.key}'),
              tooltip: 'Abrir fatura',
              icon: const Icon(Icons.chevron_right),
              onPressed: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}
