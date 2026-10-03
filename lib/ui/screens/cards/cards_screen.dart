import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/billing_cycle.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import 'card_details_screen.dart';

class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final cards = [...fc.data.cards]
      ..sort(
        (a, b) => a.active == b.active
            ? a.name.compareTo(b.name)
            : (a.active ? -1 : 1),
      );
    return Scaffold(
      appBar: AppBar(title: const Text('Cartões de crédito')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-card',
        onPressed: () => push(context, const CardFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Novo cartão'),
      ),
      body: cards.isEmpty
          ? EmptyState(
              icon: Icons.credit_card,
              title: 'Nenhum cartão cadastrado',
              message: 'Cadastre seus cartões para controlar faturas, limites e parcelas.',
              actionLabel: 'Novo cartão',
              onAction: () => push(context, const CardFormScreen()),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => CreditCardVisual(card: cards[i]),
            ),
    );
  }
}

/// Representação visual do cartão com limite e fatura atual.
class CreditCardVisual extends StatelessWidget {
  final CreditCard card;
  final bool tappable;
  const CreditCardVisual({super.key, required this.card, this.tappable = true});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final available = e.availableLimit(card);
    final used = card.limit - available;
    final current = e.invoice(card, BillingCycle.currentInvoice(card, e.today));
    final usage = card.limit.cents <= 0
        ? 0.0
        : (used.cents / card.limit.cents).clamp(0.0, 1.0);
    const white = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.75);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: tappable
          ? () => push(context, CardDetailsScreen(cardId: card.id))
          : null,
      child: Opacity(
        opacity: card.active ? 1 : 0.6,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                Color(card.color),
                Color.lerp(Color(card.color), Colors.black, 0.35)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.name,
                      style: context.text.titleMedium?.copyWith(color: white),
                    ),
                  ),
                  Text(
                    card.brand,
                    style: context.text.labelLarge?.copyWith(color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${card.bank.isEmpty ? '' : '${card.bank} · '}•••• ${card.lastFour}'
                '${card.active ? '' : ' · Inativo'}',
                style: context.text.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 18),
              Text(
                'Fatura atual (${current.month.shortLabel})',
                style: context.text.labelMedium?.copyWith(color: muted),
              ),
              MoneyText(
                current.total,
                style: context.text.titleLarge?.copyWith(color: white),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usage,
                  minHeight: 6,
                  color: white,
                  backgroundColor: Colors.white24,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Disponível ${available.format()}',
                      style: context.text.labelMedium?.copyWith(color: white),
                    ),
                  ),
                  Text(
                    'Limite ${card.limit.format()}',
                    style: context.text.labelMedium?.copyWith(color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Fecha dia ${card.closingDay} · vence dia ${card.dueDay}',
                style: context.text.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CardFormScreen extends StatefulWidget {
  final CreditCard? card;
  const CardFormScreen({super.key, this.card});
  @override
  State<CardFormScreen> createState() => _CardFormScreenState();
}

class _CardFormScreenState extends State<CardFormScreen> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.card?.name ?? '');
  late final bank = TextEditingController(text: widget.card?.bank ?? '');
  late final last4 = TextEditingController(text: widget.card?.lastFour ?? '');
  late final limit = TextEditingController(
    text: widget.card?.limit.formatPlain() ?? '',
  );
  late final closing = TextEditingController(
    text: '${widget.card?.closingDay ?? 1}',
  );
  late final due = TextEditingController(text: '${widget.card?.dueDay ?? 10}');
  late String brand = widget.card?.brand.isNotEmpty == true
      ? widget.card!.brand
      : 'Mastercard';
  late bool active = widget.card?.active ?? true;
  late String? payAccount = widget.card?.paymentAccountId;
  late int color = widget.card?.color ?? 0xFF1B2A4A;

  static const brands = [
    'Mastercard',
    'Visa',
    'Elo',
    'American Express',
    'Hipercard',
    'Outra',
  ];
  static const cardColors = [
    0xFF1B2A4A,
    0xFF820AD1,
    0xFFEC7000,
    0xFF2457D6,
    0xFF0F766E,
    0xFFB91C1C,
    0xFF374151,
    0xFFCA8A04,
  ];

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final c = widget.card;
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Novo cartão' : 'Editar cartão'),
        actions: [
          if (c != null)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (fc.cardInUse(c.id)) {
                  showMessage(
                    context,
                    'O cartão possui lançamentos. Desative-o em vez de excluir.',
                    error: true,
                  );
                  return;
                }
                final ok = await confirmDialog(
                  context,
                  title: 'Excluir cartão?',
                  message: 'Esta ação não pode ser desfeita.',
                  confirm: 'Excluir',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                final done = await runAction(
                  context,
                  () => fc.deleteCard(c),
                  success: 'Cartão excluído',
                );
                if (done && context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome do cartão'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: bank,
              decoration: const InputDecoration(labelText: 'Banco emissor'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: brands.contains(brand) ? brand : 'Outra',
                    decoration: const InputDecoration(labelText: 'Bandeira'),
                    items: [
                      for (final b in brands)
                        DropdownMenuItem(value: b, child: Text(b)),
                    ],
                    onChanged: (b) => setState(() => brand = b!),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: last4,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Final',
                      counterText: '',
                    ),
                    validator: (v) => RegExp(r'^\d{4}$').hasMatch(v ?? '')
                        ? null
                        : '4 dígitos',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MoneyField(controller: limit, label: 'Limite de crédito'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: IntField(
                    controller: closing,
                    label: 'Dia de fechamento',
                    min: 1,
                    max: 31,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: IntField(
                    controller: due,
                    label: 'Dia de vencimento',
                    min: 1,
                    max: 31,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            Builder(
              builder: (context) {
                final cd = int.tryParse(closing.text);
                final dd = int.tryParse(due.text);
                if (cd == null ||
                    dd == null ||
                    cd < 1 ||
                    cd > 31 ||
                    dd < 1 ||
                    dd > 31) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Compras até o dia ${cd - 1 < 1 ? 'anterior ao fechamento' : cd - 1} entram na fatura do mês; '
                    'a fatura vence dia $dd ${dd > cd ? 'do mesmo mês' : 'do mês seguinte'}.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.primary,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: fc.data.accountById.containsKey(payAccount)
                  ? payAccount
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Conta de pagamento padrão',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Nenhuma')),
                for (final a in fc.activeAccounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => payAccount = v),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final col in {...cardColors, ...palette})
                  GestureDetector(
                    onTap: () => setState(() => color = col),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(col),
                      child: color == col
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cartão ativo'),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
            if (c != null)
              Text(
                'Alterar fechamento/vencimento recalcula automaticamente a alocação de compras e parcelas nas faturas.',
                style: context.text.bodySmall?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                final card =
                    (c ??
                            CreditCard(
                              id: newId('card_'),
                              name: name.text,
                              closingDay: 1,
                              dueDay: 1,
                            ))
                        .copyWith(
                          name: name.text.trim(),
                          bank: bank.text.trim(),
                          brand: brand,
                          lastFour: last4.text,
                          limit: Money.tryParse(limit.text)!,
                          closingDay: int.parse(closing.text),
                          dueDay: int.parse(due.text),
                          active: active,
                          paymentAccountId: payAccount,
                          color: color,
                        );
                final ok = await runAction(
                  context,
                  () => fc.saveCard(card),
                  success: 'Cartão salvo',
                );
                if (ok && context.mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
