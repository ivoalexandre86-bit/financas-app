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
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../transactions/transaction_details_screen.dart';
import '../transactions/transaction_form_screen.dart';
import 'card_details_screen.dart';

/// Detalhes de uma fatura: cabeçalho com totais e datas, compras (com
/// agrupamento/filtro por categoria) e ações de pagamento. Pagar a fatura
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
  bool byCategory = false;
  String? categoryFilter; // categoria raiz

  void _goTo(YearMonth m) => setState(() {
    month = m;
    categoryFilter = null;
  });

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
    final amount = partial ? Money.tryParse(amountCtrl.text)! : inv.remaining;
    await runAction(
      context,
      () => fc.payInvoice(inv, amount, date: date, accountId: account!),
      success: amount >= inv.remaining
          ? 'Fatura paga'
          : 'Pagamento parcial registrado',
    );
  }

  void _addPurchase(Invoice inv, DateTime today) {
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

    // Subtotais por categoria raiz.
    final byRoot = <String, List<FinTransaction>>{};
    for (final t in inv.transactions) {
      byRoot.putIfAbsent(e.rootCategoryId(t.categoryId), () => []).add(t);
    }
    Money subtotal(List<FinTransaction> l) => l.map(Invoice.signedOf).sum();
    final roots = byRoot.keys.toList()
      ..sort((a, b) => subtotal(byRoot[b]!).compareTo(subtotal(byRoot[a]!)));
    final visible = categoryFilter == null
        ? inv.transactions
        : (byRoot[categoryFilter] ?? const <FinTransaction>[]);
    final canPay =
        inv.remaining.isPositive && inv.status != InvoiceStatus.future;

    return Scaffold(
      appBar: AppBar(
        title: Text('Fatura ${card.name}'),
        actions: [
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
              Text(
                'Referência ${month.longLabel}',
                style: context.text.titleMedium,
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar compra a esta fatura'),
                      onPressed: () => _addPurchase(inv, e.today),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Compras (${inv.transactions.length})',
                    style: context.text.titleMedium,
                  ),
                ),
                FilterChip(
                  key: const ValueKey('invoice-by-category'),
                  label: const Text('Por categoria'),
                  selected: byCategory,
                  onSelected: (v) => setState(() => byCategory = v),
                ),
              ],
            ),
          ),
          if (roots.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('Todas'),
                      selected: categoryFilter == null,
                      onSelected: (_) => setState(() => categoryFilter = null),
                    ),
                  ),
                  for (final r in roots)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          '${e.categoryLabel(r.isEmpty ? null : r)} · ${subtotal(byRoot[r]!).format()}',
                        ),
                        selected: categoryFilter == r,
                        onSelected: (_) => setState(() => categoryFilter = r),
                      ),
                    ),
                ],
              ),
            ),
          if (inv.transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhuma compra nesta fatura.'),
            )
          else if (byCategory)
            for (final r in roots)
              if (categoryFilter == null || categoryFilter == r) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.categoryLabel(r.isEmpty ? null : r),
                          style: context.text.labelLarge?.copyWith(
                            color: context.fin.subtle,
                          ),
                        ),
                      ),
                      MoneyText(
                        subtotal(byRoot[r]!),
                        style: context.text.labelLarge,
                      ),
                    ],
                  ),
                ),
                for (final t in byRoot[r]!) _PurchaseTile(tx: t, engine: e),
              ] else
                const SizedBox.shrink()
          else
            for (final t in visible) _PurchaseTile(tx: t, engine: e),
        ],
      ),
    );
  }

  Widget _title(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(t, style: context.text.titleMedium),
  );
}

/// Compra dentro da fatura: data, descrição, categoria, parcela e valor.
class _PurchaseTile extends StatelessWidget {
  final FinTransaction tx;
  final FinancialEngine engine;
  const _PurchaseTile({required this.tx, required this.engine});

  @override
  Widget build(BuildContext context) {
    final cat = engine.data.categoryById[tx.categoryId];
    final color = Color(cat?.color ?? context.fin.subtle.toARGB32());
    final credit = tx.type == TransactionType.income;
    final info = [
      Dates.format(tx.date),
      engine.categoryLabel(tx.categoryId),
      if (tx.isInstallment) tx.installmentLabel,
      if (tx.isVirtual) 'prevista',
    ].join(' · ');
    return ListTile(
      onTap: () => push(context, TransactionDetailsScreen(tx: tx)),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(categoryIcon(cat?.icon), color: color, size: 20),
      ),
      title: Text(tx.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        info,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
      ),
      trailing: MoneyText(
        credit ? tx.amount : -tx.amount,
        showPlus: credit,
        color: credit ? context.fin.positive : null,
        style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
