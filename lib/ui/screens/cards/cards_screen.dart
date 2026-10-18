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
import '../../widgets/remembered_filters.dart';
import '../../widgets/sort_grid.dart';
import '../../widgets/tx_grid.dart';
import '../../widgets/view_mode.dart';
import 'card_details_screen.dart';

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> with RememberedFilters {
  ViewMode view = ViewMode.cards;

  @override
  String get filterKey => 'cards';

  @override
  Map<String, Object?> filtersToJson() => {'view': view.name};

  @override
  void restoreFilters(Map<String, Object?> saved, FinanceController fc) =>
      view = FilterJson.enumOrNull(ViewMode.values, saved['view']) ?? view;

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
      appBar: AppBar(
        title: const Text('Cartões de crédito'),
        actions: [
          ViewModeToggle(
            keyPrefix: 'cards',
            mode: view,
            onChanged: (v) => setFilters(() => view = v),
          ),
        ],
      ),
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
          : view == ViewMode.grid
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [CardsGrid(cards: cards)],
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

/// Cartões no padrão de grade de Faturas: ordenável, com totais de fatura
/// atual, limite e disponível.
class CardsGrid extends StatelessWidget {
  final List<CreditCard> cards;
  const CardsGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    final e = context.watch<FinanceController>().engine;
    final p = GridPalette.of(context);
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final tab = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final small = context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    final strong = context.text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
    );
    int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    final invoice = {
      for (final c in cards)
        c.id: e.invoice(c, BillingCycle.currentInvoice(c, e.today)),
    };
    final available = {for (final c in cards) c.id: e.availableLimit(c)};
    String bank(CreditCard c) => c.bank.isEmpty && c.bankCode.isEmpty
        ? ''
        : institutionLabel(c.bankCode, c.bank);
    Money current(CreditCard c) => invoice[c.id]!.total;
    Money free(CreditCard c) => available[c.id]!;
    double usage(CreditCard c) => c.limit.cents <= 0
        ? 0.0
        : ((c.limit - free(c)).cents / c.limit.cents).clamp(0.0, 1.0);
    Money total(List<CreditCard> l, Money Function(CreditCard) f) =>
        l.where((c) => c.active).map(f).sum();
    Widget usageBar(CreditCard c) => Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            '${(usage(c) * 100).round()}%',
            style: tab?.copyWith(color: p.neon, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: usage(c),
              minHeight: 5,
              backgroundColor: context.fin.gridLine,
              color: Color(c.color),
            ),
          ),
        ),
      ],
    );
    Widget status(CreditCard c) => NeonStatus(
      label: c.active ? 'Ativo' : 'Inativo',
      color: c.active ? context.fin.positive : context.fin.subtle,
      done: !c.active,
    );

    return SortGrid<CreditCard>(
      keyPrefix: 'card',
      rows: cards,
      rowId: (c) => c.id,
      accent: (context, c) => Color(c.color),
      dimmed: (c) => !c.active,
      onOpen: (c) => push(context, CardDetailsScreen(cardId: c.id)),
      initialSort: 'name',
      tieBreak: (a, b) => text(a.name, b.name),
      columns: [
        SortCol(
          id: 'name',
          label: 'Cartão',
          width: 170,
          minWidth: 120,
          flexible: true,
          fill: true,
          compare: (a, b) =>
              a.active == b.active ? text(a.name, b.name) : (a.active ? -1 : 1),
          cell: (context, c) => GridCell(
            child: Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SortCol(
          id: 'bank',
          label: 'Banco',
          width: 150,
          minWidth: 100,
          flexible: true,
          compare: (a, b) => text(bank(a), bank(b)),
          cell: (context, c) => GridCell(
            child: Text(
              bank(c).isEmpty ? '—' : bank(c),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtle,
            ),
          ),
        ),
        SortCol(
          id: 'brand',
          label: 'Bandeira',
          width: 110,
          minWidth: 90,
          flexible: true,
          compare: (a, b) => text(a.brand, b.brand),
          cell: (context, c) => GridCell(
            child: Text(
              '${c.brand} •••• ${c.lastFour}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          ),
        ),
        SortCol(
          id: 'days',
          label: 'Fecha/vence',
          width: 100,
          compare: (a, b) => a.dueDay.compareTo(b.dueDay),
          cell: (context, c) => GridCell(
            child: Text('${c.closingDay} / ${c.dueDay}', style: tab),
          ),
        ),
        SortCol(
          id: 'invoice',
          label: 'Fatura atual',
          width: 124,
          right: true,
          highlight: true,
          compare: (a, b) => current(a).compareTo(current(b)),
          cell: (context, c) => GridCell(
            right: true,
            child: Text(current(c).format(), style: strong),
          ),
          footer: (context, l) =>
              Text(total(l, current).format(), style: strong),
        ),
        SortCol(
          id: 'limit',
          label: 'Limite',
          width: 116,
          right: true,
          compare: (a, b) => a.limit.compareTo(b.limit),
          cell: (context, c) => GridCell(
            right: true,
            child: Text(c.limit.format(), style: context.text.bodySmall),
          ),
          footer: (context, l) =>
              Text(total(l, (c) => c.limit).format(), style: small),
        ),
        SortCol(
          id: 'available',
          label: 'Disponível',
          width: 116,
          right: true,
          compare: (a, b) => free(a).compareTo(free(b)),
          cell: (context, c) => GridCell(
            right: true,
            child: Text(
              free(c).format(),
              style: context.text.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: free(c).cents < 0 ? context.fin.negative : null,
              ),
            ),
          ),
          footer: (context, l) => Text(total(l, free).format(), style: small),
        ),
        SortCol(
          id: 'usage',
          label: 'Uso',
          width: 110,
          compare: (a, b) => usage(a).compareTo(usage(b)),
          cell: (context, c) => GridCell(child: usageBar(c)),
        ),
        SortCol(
          id: 'status',
          label: 'Situação',
          width: 104,
          compare: (a, b) => (a.active ? 0 : 1).compareTo(b.active ? 0 : 1),
          cell: (context, c) => GridCell(child: status(c)),
        ),
      ],
      compactRow: (context, c) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    if (bank(c).isNotEmpty) bank(c),
                    '•••• ${c.lastFour}',
                    'fecha ${c.closingDay} · vence ${c.dueDay}',
                    if (!c.active) 'Inativo',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtle,
                ),
                const SizedBox(height: 4),
                SizedBox(width: 160, child: usageBar(c)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(current(c).format(), style: strong),
              Text('disp. ${free(c).format()}', style: subtle),
            ],
          ),
        ],
      ),
      footerLabel: (context, l) => Text(
        'Total dos ativos · ${l.length} ${l.length == 1 ? 'cartão' : 'cartões'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: gridFooterLabelStyle(context),
      ),
      compactFooter: (context, l) =>
          Text(total(l, current).format(), style: strong),
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
                '${card.bank.isEmpty ? '' : '${institutionLabel(card.bankCode, card.bank)} · '}'
                '•••• ${card.lastFour}'
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
  late Institution bank = (
    code: widget.card?.bankCode ?? '',
    name: widget.card?.bank ?? '',
  );
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
            BankField(
              label: 'Banco emissor',
              value: bank,
              onChanged: (v) => setState(() => bank = v),
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
                          bank: bank.name,
                          bankCode: bank.code,
                          brand: brand,
                          lastFour: last4.text,
                          limit: Money.tryEval(limit.text)!,
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
