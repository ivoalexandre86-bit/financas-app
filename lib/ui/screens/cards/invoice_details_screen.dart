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
import '../../../domain/engine/recurrence.dart';
import '../recurring/recurring_form_screen.dart';
import '../transactions/transaction_form_screen.dart';
import 'card_details_screen.dart';
import 'invoice_purchases.dart';

/// Detalhes de uma fatura: cabeçalho com totais e datas, indicadores, grade
/// de compras (com agrupamento/filtro por categoria) e ações de pagamento. Pagar a fatura
/// quita todas as compras dela.
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

  void _goTo(YearMonth m) => setState(() => month = m);

  Future<void> _pay(
    FinanceController fc,
    Invoice inv, {
    required bool partial,
  }) async {
    final amountCtrl = TextEditingController(
      text: partial ? '' : inv.remaining.formatPlain(),
    );
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  partial
                      ? 'Pagamento parcial · ${inv.title}'
                      : 'Marcar como paga · ${inv.title}',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  partial
                      ? 'Restante: ${inv.remaining.format()}. O valor pago conta no mês do pagamento; o saldo segue para o mês em que for quitado.'
                      : 'Valor: ${inv.remaining.format()}. A fatura e todas as compras dela passam para o mês da data do pagamento.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (partial) ...[
                  MoneyField(
                    controller: amountCtrl,
                    label: 'Valor pago',
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                ],
                AccountDropdown(
                  fc: fc,
                  value: account,
                  label: 'Conta de origem do pagamento',
                  onChanged: (v) => setS(() => account = v),
                ),
                const SizedBox(height: 12),
                DateField(
                  value: date,
                  label: 'Data do pagamento',
                  onChanged: (d) => setS(() => date = d ?? date),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    if (key.currentState!.validate() && account != null) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  child: Text(
                    partial
                        ? 'Registrar pagamento parcial'
                        : 'Confirmar pagamento',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final amount = partial ? Money.tryEval(amountCtrl.text)! : inv.remaining;
    await runAction(
      context,
      () => fc.payInvoice(inv, amount, date: date, accountId: account!),
      success: amount >= inv.remaining
          ? 'Fatura paga'
          : 'Pagamento parcial registrado',
    );
  }

  void _addPurchase(Invoice inv, DateTime today, {bool recurring = false}) {
    // Data sugerida dentro do período de compras desta fatura.
    final start = BillingCycle.cycleStart(inv.card, inv.month);
    final last = BillingCycle.lastPurchaseDay(inv.card, inv.month);
    final date = today.isBefore(start)
        ? start
        : today.isAfter(last)
        ? last
        : today;
    push(
      context,
      TransactionFormScreen(
        initialType: TransactionType.expense,
        initialCardId: inv.card.id,
        initialDate: date,
        initialRecurring: recurring,
      ),
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

    final rules =
        fc.data.recurringRules
            .where((r) => r.cardId == card.id && !r.isEndedBy(e.today))
            .toList()
          ..sort((a, b) => a.description.compareTo(b.description));
    final canPay =
        inv.remaining.isPositive && inv.status != InvoiceStatus.future;

    return Scaffold(
      appBar: AppBar(
        title: Text('Fatura ${card.name}'),
        actions: [
          IconButton(
            tooltip: 'Adicionar recorrência (assinatura) no cartão',
            icon: const Icon(Icons.autorenew),
            onPressed: () => _addPurchase(inv, e.today, recurring: true),
          ),
          IconButton(
            tooltip: 'Adicionar compra a esta fatura',
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: () => _addPurchase(inv, e.today),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('invoice-prev'),
                tooltip: 'Fatura anterior',
                onPressed: () => _goTo(month.previous),
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: Text(
                  'Referência ${month.longLabel}',
                  style: context.text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const ValueKey('invoice-next'),
                tooltip: 'Próxima fatura',
                onPressed: () => _goTo(month.next),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Color(card.color)
                            .withValues(alpha: 0.14),
                        child: Icon(
                          Icons.credit_card,
                          color: Color(card.color),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(card.name, style: context.text.labelLarge),
                            MoneyText(
                              inv.isCredit ? -inv.total : inv.total,
                              style: context.text.headlineMedium,
                              color: inv.isCredit ? context.fin.positive : null,
                            ),
                          ],
                        ),
                      ),
                      Pill(
                        inv.isCredit ? 'Saldo credor' : inv.status.label,
                        color: inv.isCredit
                            ? context.fin.positive
                            : invoiceStatusColor(context, inv.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InfoRow.text('Fechamento', Dates.format(inv.closingDate)),
                  InfoRow.text('Vencimento', Dates.format(inv.dueDate)),
                  InfoRow.text(
                    'Compras de',
                    '${Dates.format(BillingCycle.cycleStart(card, inv.month))} a ${Dates.format(BillingCycle.lastPurchaseDay(card, inv.month))}',
                  ),
                  if (inv.paid.isPositive) ...[
                    InfoRow('Pago', MoneyText(inv.paid)),
                    InfoRow(
                      'Restante',
                      MoneyText(
                        inv.remaining,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                  if (!inv.isEmpty)
                    InfoRow.text(
                      'Conta em',
                      [
                        for (final s in inv.slices)
                          '${s.month.longLabel}${s.settled ? '' : ' (previsto)'}',
                      ].join(' + '),
                    ),
                  if (inv.status == InvoiceStatus.future)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Fatura planejada: inclui parcelas já contratadas e recorrências previstas no cartão.',
                        style: context.text.bodySmall?.copyWith(
                          color: context.fin.subtle,
                        ),
                      ),
                    ),
                  if (canPay) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('invoice-pay'),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Marcar como paga'),
                          onPressed: () => _pay(fc, inv, partial: false),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('invoice-pay-partial'),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Pagamento parcial'),
                          onPressed: () => _pay(fc, inv, partial: true),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('invoice-add-purchase'),
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar compra'),
                        onPressed: () => _addPurchase(inv, e.today),
                      ),
                      TextButton.icon(
                        key: const ValueKey('invoice-add-recurring'),
                        icon: const Icon(Icons.autorenew),
                        label: const Text('Adicionar recorrência'),
                        onPressed: () =>
                            _addPurchase(inv, e.today, recurring: true),
                      ),
                    ],
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
          if (inv.transactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: InvoiceKpis(invoice: inv, engine: e),
            ),
          InvoicePurchases(
            key: ValueKey('invoice-purchases-${card.id}-${inv.key}'),
            invoice: inv,
            engine: e,
          ),
          if (rules.isNotEmpty) ...[
            _title(context, 'Recorrências no cartão (${rules.length})'),
            for (final r in rules)
              ListTile(
                key: ValueKey('card-rule-${r.id}'),
                onTap: () => push(context, RecurringFormScreen(rule: r)),
                leading: CircleAvatar(
                  backgroundColor: context.colors.primary.withValues(
                    alpha: 0.12,
                  ),
                  child: Icon(
                    r.isPaused ? Icons.pause : Icons.autorenew,
                    color: context.colors.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  r.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    r.frequency.label,
                    e.categoryLabel(r.categoryId),
                    if (r.isPaused)
                      'pausada'
                    else if (Recurrence.nextOccurrence(r, e.today)
                        case final next?)
                      'próxima ${Dates.format(next)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
                trailing: MoneyText(
                  -r.amount,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _title(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(t, style: context.text.titleMedium),
  );
}
