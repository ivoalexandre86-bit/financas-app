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
import '../../widgets/tx_grid.dart';
import '../transactions/transaction_details_screen.dart';
import 'card_details_screen.dart';
import 'cards_screen.dart';
import 'invoice_details_screen.dart';
import 'invoice_purchases.dart';

/// Visão consolidada das faturas de todos os cartões: indicadores no topo e
/// uma grade por cartão com o resumo de cada fatura (compras à vista,
/// parceladas e recorrentes, maior categoria, pago e restante). Cada fatura
/// pode ser expandida para ver as compras ali mesmo.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

/// Resumo de uma fatura para a grade.
class _Summary {
  final Invoice inv;
  final int count;
  final Money cash;
  final Money installments;
  final Money recurring;
  final ({String name, Color color, Money value})? top;
  _Summary(
    this.inv,
    this.count,
    this.cash,
    this.installments,
    this.recurring,
    this.top,
  );

  factory _Summary.of(FinancialEngine e, Invoice inv) {
    var cash = Money.zero, inst = Money.zero, rec = Money.zero;
    var count = 0;
    final byRoot = <String, Money>{};
    for (final t in inv.transactions) {
      final root = e.rootCategoryId(t.categoryId);
      byRoot[root] = (byRoot[root] ?? Money.zero) + Invoice.signedOf(t);
      if (t.type != TransactionType.expense) continue;
      count++;
      if (t.isInstallment) {
        inst += t.amount;
      } else if (t.isRecurring) {
        rec += t.amount;
      } else {
        cash += t.amount;
      }
    }
    ({String name, Color color, Money value})? top;
    for (final MapEntry(:key, :value) in byRoot.entries) {
      if (!value.isPositive) continue;
      if (top != null && top.value >= value) continue;
      final cat = e.data.categoryById[key];
      top = (
        name: e.categoryLabel(key.isEmpty ? null : key),
        color: Color(cat?.color ?? 0xFF94A3B8),
        value: value,
      );
    }
    return _Summary(inv, count, cash, inst, rec, top);
  }

  String get key => '${inv.card.id}|${inv.key}';

  bool get unpaid =>
      inv.remaining.isPositive && inv.status != InvoiceStatus.future;
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  /// Meses exibidos por cartão: 3 (anterior, atual e próxima) ou 6.
  int span = 3;
  final expanded = <String>{};

  List<YearMonth> _months(CreditCard card, DateTime today) {
    final cur = BillingCycle.currentInvoice(card, today);
    final from = span == 3 ? 1 : 3;
    final to = span == 3 ? 1 : 2;
    return [for (var i = -from; i <= to; i++) cur.add(i)];
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final cards = fc.data.cards.where((c) => c.active).toList();
    if (cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Faturas')),
        body: EmptyState(
          icon: Icons.receipt_outlined,
          title: 'Nenhum cartão ativo',
          actionLabel: 'Cadastrar cartão',
          onAction: () => push(context, const CardFormScreen()),
        ),
      );
    }
    final byCard = {
      for (final card in cards)
        card: [
          for (final m in _months(card, e.today))
            _Summary.of(e, e.invoice(card, m)),
        ],
    };
    final all = byCard.values.expand((l) => l).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faturas'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<int>(
              key: const ValueKey('invoices-span'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 3, label: Text('3 meses')),
                ButtonSegment(value: 6, label: Text('6 meses')),
              ],
              selected: {span},
              onSelectionChanged: (s) => setState(() => span = s.first),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final pad = box.maxWidth < 640 ? 8.0 : 16.0;
          final width = box.maxWidth - 2 * pad - 2;
          final compact = width < 760;
          final layout = compact ? null : _Layout.of(width);
          return ListView(
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
            children: [
              _Kpis(summaries: all, engine: e, cards: cards),
              const SizedBox(height: 16),
              for (final card in cards) ...[
                _CardHeader(card: card, engine: e),
                const SizedBox(height: 6),
                GridPanel(
                  child: compact
                      ? Column(
                          children: [
                            for (final (i, s) in byCard[card]!.indexed)
                              ..._rows(context, s, i, null),
                          ],
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: layout!.totalWidth,
                            child: Column(
                              children: [
                                _Header(layout: layout),
                                for (final (i, s) in byCard[card]!.indexed)
                                  ..._rows(context, s, i, layout),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 20),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _rows(
    BuildContext context,
    _Summary s,
    int index,
    _Layout? layout,
  ) {
    final open = expanded.contains(s.key);
    void toggle() =>
        setState(() => open ? expanded.remove(s.key) : expanded.add(s.key));
    void openInvoice() => push(
      context,
      InvoiceDetailsScreen(cardId: s.inv.card.id, month: s.inv.month),
    );
    return [
      layout == null
          ? _CompactInvoiceRow(
              s: s,
              index: index,
              expanded: open,
              onToggle: toggle,
              onOpen: openInvoice,
            )
          : _InvoiceRow(
              s: s,
              index: index,
              layout: layout,
              expanded: open,
              onToggle: toggle,
              onOpen: openInvoice,
            ),
      if (open) _Purchases(s: s, onOpen: openInvoice),
    ];
  }
}

/// Indicadores das faturas exibidas: em aberto, próximo vencimento,
/// próximas faturas planejadas e parcelas ainda por vir.
class _Kpis extends StatelessWidget {
  final List<_Summary> summaries;
  final FinancialEngine engine;
  final List<CreditCard> cards;
  const _Kpis({
    required this.summaries,
    required this.engine,
    required this.cards,
  });

  @override
  Widget build(BuildContext context) {
    final e = engine;
    final unpaid = summaries.where((s) => s.unpaid).toList();
    final open = unpaid.map((s) => s.inv.remaining).sum();
    final overdue = unpaid
        .where((s) => s.inv.status == InvoiceStatus.overdue)
        .length;
    final upcoming =
        unpaid
            .where((s) => !Dates.dateOnly(s.inv.dueDate).isBefore(e.today))
            .toList()
          ..sort((a, b) => a.inv.dueDate.compareTo(b.inv.dueDate));
    final next = upcoming.firstOrNull;
    final planned = summaries
        .where((s) => s.inv.status == InvoiceStatus.future)
        .toList();
    // Parcelas que caem depois da fatura atual de cada cartão.
    var future = Money.zero;
    final current = {
      for (final c in cards) c.id: BillingCycle.currentInvoice(c, e.today),
    };
    for (final t in e.data.transactions) {
      final cur = current[t.cardId];
      if (cur == null ||
          !t.isInstallment ||
          t.status == TransactionStatus.cancelled ||
          t.type != TransactionType.expense) {
        continue;
      }
      final card = e.data.cardById[t.cardId]!;
      if (BillingCycle.invoiceForTransaction(card, t) > cur) {
        future += t.amount;
      }
    }
    final tiles = [
      _KpiTile(
        key: const ValueKey('invoices-kpi-open'),
        label: 'Em aberto',
        value: open.format(),
        detail: overdue > 0
            ? '$overdue ${overdue == 1 ? 'fatura vencida' : 'faturas vencidas'}'
            : '${unpaid.length} ${unpaid.length == 1 ? 'fatura' : 'faturas'}',
        detailColor: overdue > 0 ? context.fin.negative : null,
        icon: Icons.account_balance_wallet_outlined,
        color: overdue > 0 ? context.fin.negative : context.fin.warning,
      ),
      _KpiTile(
        key: const ValueKey('invoices-kpi-next'),
        label: 'Próximo vencimento',
        value: next?.inv.remaining.format() ?? '—',
        detail: next == null
            ? 'Nada a pagar'
            : '${next.inv.card.name} · ${Dates.format(next.inv.dueDate)}',
        icon: Icons.event_outlined,
        color: context.colors.primary,
      ),
      _KpiTile(
        key: const ValueKey('invoices-kpi-planned'),
        label: 'Próximas faturas',
        value: planned.map((s) => s.inv.total).sum().format(),
        detail: 'parcelas e recorrências já previstas',
        icon: Icons.upcoming_outlined,
        color: GridPalette.of(context).neon,
      ),
      _KpiTile(
        key: const ValueKey('invoices-kpi-installments'),
        label: 'Parcelas a vencer',
        value: future.format(),
        detail: 'após a fatura atual de cada cartão',
        icon: Icons.view_week_outlined,
        color: GridPalette.of(context).neon2,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 640 ? 4 : 2;
        const gap = 8.0;
        final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final Color? detailColor;
  final IconData icon;
  final Color color;
  const _KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    this.detailColor,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: context.colors.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(
              color: detailColor ?? context.fin.subtle,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Nome do cartão, limite disponível e atalho para todas as faturas.
class _CardHeader extends StatelessWidget {
  final CreditCard card;
  final FinancialEngine engine;
  const _CardHeader({required this.card, required this.engine});

  @override
  Widget build(BuildContext context) {
    final hasLimit = card.limit.isPositive;
    final available = hasLimit ? engine.availableLimit(card) : Money.zero;
    final used = hasLimit
        ? ((card.limit - available).cents / card.limit.cents).clamp(0.0, 1.0)
        : 0.0;
    final bar = Tooltip(
      message: 'Limite usado: ${(used * 100).round()}%',
      child: SizedBox(
        width: 72,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: used,
            minHeight: 6,
            color: used > 0.9 ? context.fin.negative : Color(card.color),
            backgroundColor: context.colors.outlineVariant,
          ),
        ),
      ),
    );
    final name = Text(
      card.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.text.titleMedium,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 560;
        return Row(
          children: [
            Icon(Icons.credit_card, color: Color(card.color)),
            const SizedBox(width: 8),
            if (narrow)
              Expanded(child: name)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: name,
              ),
            if (hasLimit) ...[
              const SizedBox(width: 12),
              bar,
              if (!narrow) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'disponível ${available.format()} de ${card.limit.format()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.fin.subtle,
                    ),
                  ),
                ),
              ],
            ] else if (!narrow)
              const Spacer(),
            TextButton(
              onPressed: () =>
                  push(context, CardDetailsScreen(cardId: card.id)),
              child: const Text('Todas'),
            ),
          ],
        );
      },
    );
  }
}

enum _Col {
  invoice('Fatura', 110, 96),
  closing('Fechamento', 116, 108),
  due('Vencimento', 104, 96),
  count('Compras', 86, 80, right: true),
  cash('À vista', 118, 104, right: true),
  installments('Parcelado', 118, 104, right: true),
  recurring('Recorrente', 118, 104, right: true),
  top('Maior categoria', 200, 120, flexible: true),
  total('Total', 128, 112, right: true),
  paid('Pago', 118, 104, right: true),
  remaining('Restante', 124, 108, right: true),
  status('Status', 150, 132);

  final String label;
  final double width;
  final double minWidth;
  final bool right;
  final bool flexible;
  const _Col(
    this.label,
    this.width,
    this.minWidth, {
    this.right = false,
    this.flexible = false,
  });
}

class _Layout {
  final List<(_Col, double)> cells;
  final double totalWidth;
  const _Layout(this.cells, this.totalWidth);

  static const stripeW = GridLayout.stripeW;
  static const actionW = 84.0;

  /// A sobra de espaço vai para "Maior categoria"; faltando espaço, ela
  /// encolhe até o mínimo e depois a grade rola na horizontal.
  factory _Layout.of(double width) {
    var sum = stripeW + actionW;
    for (final c in _Col.values) {
      sum += c.width;
    }
    final top = _Col.top;
    final delta = width - sum;
    final topW = (top.width + delta).clamp(top.minWidth, double.infinity);
    return _Layout([
      for (final c in _Col.values) (c, c == top ? topW : c.width),
    ], sum - top.width + topW);
  }
}

class _Header extends StatelessWidget {
  final _Layout layout;
  const _Header({required this.layout});

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    return Container(
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: p.header),
        border: Border(bottom: BorderSide(color: p.neon, width: 2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _Layout.stripeW),
          for (final (c, w) in layout.cells)
            SizedBox(
              width: w,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  c.label.toUpperCase(),
                  textAlign: c.right ? TextAlign.right : TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: p.headerText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          const SizedBox(width: _Layout.actionW),
        ],
      ),
    );
  }
}

Widget _status(BuildContext context, Invoice inv) => NeonStatus(
  label: inv.isCredit ? 'Saldo credor' : inv.status.label,
  color: inv.isCredit
      ? context.fin.positive
      : invoiceStatusColor(context, inv.status),
  done: inv.status == InvoiceStatus.paid,
);

class _InvoiceRow extends StatelessWidget {
  final _Summary s;
  final int index;
  final _Layout layout;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  const _InvoiceRow({
    required this.s,
    required this.index,
    required this.layout,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final inv = s.inv;
    final p = GridPalette.of(context);
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final tab = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );
    Widget money(Money m, {TextStyle? style}) => m.isZero
        ? Text('—', style: subtle)
        : MoneyText(m, style: style ?? context.text.bodySmall);
    final overdue = inv.status == InvoiceStatus.overdue;

    Widget cell(_Col c) => switch (c) {
      _Col.invoice => GridCell(
        child: Text(
          inv.month.shortLabel,
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      _Col.closing => GridCell(
        child: Text(Dates.format(inv.closingDate), style: tab),
      ),
      _Col.due => GridCell(
        child: Text(
          Dates.format(inv.dueDate),
          style: tab?.copyWith(color: overdue ? context.fin.negative : null),
        ),
      ),
      _Col.count => GridCell(
        right: true,
        child: Text(s.count == 0 ? '—' : '${s.count}', style: tab),
      ),
      _Col.cash => GridCell(right: true, child: money(s.cash)),
      _Col.installments => GridCell(right: true, child: money(s.installments)),
      _Col.recurring => GridCell(right: true, child: money(s.recurring)),
      _Col.top => GridCell(
        child: s.top == null
            ? Text('—', style: subtle)
            : Row(
                children: [
                  GlowDot(s.top!.color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      s.top!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    inv.total.isPositive
                        ? '${(s.top!.value.cents * 100 / inv.total.cents).round()}%'
                        : '',
                    style: subtle,
                  ),
                ],
              ),
      ),
      _Col.total => GridCell(
        right: true,
        background: p.valueBg,
        child: MoneyText(
          inv.isCredit ? -inv.total : inv.total,
          color: inv.isCredit ? context.fin.positive : null,
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      _Col.paid => GridCell(right: true, child: money(inv.paid, style: subtle)),
      _Col.remaining => GridCell(
        right: true,
        child: s.unpaid
            ? MoneyText(
                inv.remaining,
                color: overdue ? context.fin.negative : null,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              )
            : Text('—', style: subtle),
      ),
      _Col.status => GridCell(child: _status(context, inv)),
    };

    return GridRowShell(
      key: ValueKey('invoices-row-${s.key}'),
      accent: Color(inv.card.color),
      zebra: index.isOdd,
      selected: expanded,
      height: 40,
      onTap: onToggle,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (c, w) in layout.cells) SizedBox(width: w, child: cell(c)),
          SizedBox(
            width: _Layout.actionW,
            child: _Actions(
              s: s,
              expanded: expanded,
              onToggle: onToggle,
              onOpen: onOpen,
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final _Summary s;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  const _Actions({
    required this.s,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          key: ValueKey('invoices-expand-${s.key}'),
          tooltip: expanded ? 'Recolher compras' : 'Ver compras',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: p.neon,
          icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          onPressed: onToggle,
        ),
        IconButton(
          key: ValueKey('invoices-open-${s.key}'),
          tooltip: 'Abrir fatura',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: p.neon,
          icon: const Icon(Icons.chevron_right),
          onPressed: onOpen,
        ),
      ],
    );
  }
}

/// Linha da fatura no celular: duas linhas com o resumo.
class _CompactInvoiceRow extends StatelessWidget {
  final _Summary s;
  final int index;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  const _CompactInvoiceRow({
    required this.s,
    required this.index,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final inv = s.inv;
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final details = [
      '${s.count} ${s.count == 1 ? 'compra' : 'compras'}',
      if (s.installments.isPositive) 'parcelado ${s.installments.format()}',
      if (s.recurring.isPositive) 'recorrente ${s.recurring.format()}',
      if (s.top != null) 'maior: ${s.top!.name}',
    ].join(' · ');
    return GridRowShell(
      key: ValueKey('invoices-row-${s.key}'),
      accent: Color(inv.card.color),
      zebra: index.isOdd,
      selected: expanded,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Fatura ${inv.month.shortLabel}',
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'vence ${Dates.format(inv.dueDate)}'
                    '${inv.paid.isPositive && s.unpaid ? ' · falta ${inv.remaining.format()}' : ''}',
                    style: subtle,
                  ),
                  if (s.count > 0)
                    Text(
                      details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: subtle,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(
                  inv.isCredit ? -inv.total : inv.total,
                  color: inv.isCredit ? context.fin.positive : null,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                _status(context, inv),
              ],
            ),
            _Actions(
              s: s,
              expanded: expanded,
              onToggle: onToggle,
              onOpen: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compras da fatura expandida, logo abaixo da linha.
class _Purchases extends StatelessWidget {
  final _Summary s;
  final VoidCallback onOpen;
  const _Purchases({required this.s, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final e = fc.engine;
    final p = GridPalette.of(context);
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final txs = [...s.inv.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    return Container(
      key: ValueKey('invoices-purchases-${s.key}'),
      decoration: BoxDecoration(
        color: p.neon.withValues(alpha: 0.04),
        border: Border(
          left: BorderSide(color: p.neon.withValues(alpha: 0.6), width: 3),
          bottom: BorderSide(color: p.line),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 600;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (txs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Nenhuma compra nesta fatura.', style: subtle),
                ),
              for (final t in txs)
                InkWell(
                  onTap: () => push(context, TransactionDetailsScreen(tx: t)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 46,
                          child: Text(
                            Dates.formatShort(t.date),
                            style: subtle?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            t.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium,
                          ),
                        ),
                        if (!narrow) ...[
                          const SizedBox(width: 8),
                          GlowDot(
                            Color(
                              e
                                      .data
                                      .categoryById[e.rootCategoryId(
                                        t.categoryId,
                                      )]
                                      ?.color ??
                                  0xFF94A3B8,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 2,
                            child: Text(
                              e.categoryLabel(t.categoryId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtle,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: () {
                                final (label, color) = purchaseKind(context, t);
                                return NeonStatus(label: label, color: color);
                              }(),
                            ),
                          ),
                        ],
                        SizedBox(
                          width: 112,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: MoneyText(
                              t.type == TransactionType.income
                                  ? t.amount
                                  : -t.amount,
                              showPlus: t.type == TransactionType.income,
                              color: t.type == TransactionType.income
                                  ? context.fin.positive
                                  : null,
                              style: context.text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Abrir fatura completa'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
