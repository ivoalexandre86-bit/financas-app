import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/billing_cycle.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/transaction_tile.dart';
import '../transactions/transaction_details_screen.dart';
import 'card_details_screen.dart';

class InvoiceDetailsScreen extends StatefulWidget {
  final String cardId;
  final YearMonth month;
  const InvoiceDetailsScreen({
    super.key,
    required this.cardId,
    required this.month,
  });
  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  late YearMonth month = widget.month;

  Future<void> _pay(FinanceController fc, Invoice inv) async {
    final amountCtrl = TextEditingController(text: inv.remaining.formatPlain());
    String? account =
        inv.card.paymentAccountId ?? fc.activeAccounts.firstOrNull?.id;
    var date = fc.today;
    final key = GlobalKey<FormState>();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pagar fatura ${inv.month.shortLabel}',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Restante: ${inv.remaining.format()} — o pagamento liquida a fatura e não é contado como nova despesa.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                MoneyField(controller: amountCtrl, label: 'Valor pago'),
                const SizedBox(height: 12),
                AccountDropdown(
                  fc: fc,
                  value: account,
                  label: 'Pagar com a conta',
                  onChanged: (v) => setS(() => account = v),
                ),
                const SizedBox(height: 12),
                DateField(
                  value: date,
                  label: 'Data do pagamento',
                  onChanged: (d) => setS(() => date = d ?? date),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setS(
                        () => amountCtrl.text = inv.remaining.formatPlain(),
                      ),
                      child: const Text('Valor total'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        if (key.currentState!.validate()) {
                          Navigator.pop(ctx, true);
                        }
                      },
                      child: const Text('Registrar pagamento'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final amount = Money.tryParse(amountCtrl.text)!;
    await runAction(
      context,
      () => fc.payInvoice(inv, amount, date: date, accountId: account!),
      success: amount >= inv.remaining
          ? 'Fatura paga'
          : 'Pagamento parcial registrado',
    );
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final card = fc.data.cardById[widget.cardId];
    if (card == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox());
    }
    final e = fc.engine;
    final inv = e.invoice(card, month);
    final installments = inv.transactions
        .where((t) => t.isInstallment)
        .toList();
    final others = inv.transactions.where((t) => !t.isInstallment).toList();

    return Scaffold(
      appBar: AppBar(title: Text('${card.name} · ${month.shortLabel}')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Fatura anterior',
                onPressed: () => setState(() => month = month.previous),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                'Fatura ${month.longLabel}',
                style: context.text.titleMedium,
              ),
              IconButton(
                tooltip: 'Próxima fatura',
                onPressed: () => setState(() => month = month.next),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SectionCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MoneyText(
                          inv.total,
                          style: context.text.headlineMedium,
                        ),
                      ),
                      Pill(
                        inv.status.label,
                        color: invoiceStatusColor(context, inv.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InfoRow('Pago', MoneyText(inv.paid)),
                  InfoRow(
                    'Restante',
                    MoneyText(
                      inv.remaining,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  InfoRow.text('Fechamento', Dates.format(inv.closingDate)),
                  InfoRow.text('Vencimento', Dates.format(inv.dueDate)),
                  InfoRow.text(
                    'Compras de',
                    '${Dates.format(BillingCycle.cycleStart(card, inv.month))} a ${Dates.format(BillingCycle.lastPurchaseDay(card, inv.month))}',
                  ),
                  if (!inv.remaining.isZero &&
                      inv.status != InvoiceStatus.future) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Pagar fatura'),
                      onPressed: () => _pay(fc, inv),
                    ),
                  ],
                  if (inv.status == InvoiceStatus.future)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Fatura projetada: inclui parcelas já contratadas e recorrências previstas no cartão.',
                        style: context.text.bodySmall?.copyWith(
                          color: context.fin.subtle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (inv.payments.isNotEmpty) ...[
            _title(context, 'Pagamentos'),
            for (final p in inv.payments)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(p.amount.format()),
                subtitle: Text(
                  '${Dates.format(p.date)} · ${fc.data.accountById[p.accountId]?.name ?? '—'}',
                ),
                trailing: IconButton(
                  tooltip: 'Desfazer pagamento',
                  icon: const Icon(Icons.undo),
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Desfazer pagamento?',
                      message: 'O valor volta para o saldo da conta e a fatura fica em aberto.',
                      confirm: 'Desfazer',
                    );
                    if (ok && context.mounted) {
                      await runAction(
                        context,
                        () => fc.deleteInvoicePayment(p),
                        success: 'Pagamento removido',
                      );
                    }
                  },
                ),
              ),
          ],
          if (installments.isNotEmpty) ...[
            _title(context, 'Parcelas'),
            for (final t in installments)
              TransactionTile(
                tx: t,
                engine: e,
                onTap: () => push(context, TransactionDetailsScreen(tx: t)),
              ),
          ],
          _title(context, 'Lançamentos'),
          if (others.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhum lançamento nesta fatura.'),
            )
          else
            for (final t in others)
              TransactionTile(
                tx: t,
                engine: e,
                onTap: () => push(context, TransactionDetailsScreen(tx: t)),
              ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(t, style: context.text.titleMedium),
  );
}
