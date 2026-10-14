import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/tx_grid.dart';
import '../../widgets/tx_inline_edit.dart';
import '../installments/installment_edit_screen.dart';
import '../recurring/recurring_form_screen.dart';
import '../transactions/transaction_details_screen.dart';
import '../transactions/transaction_form_screen.dart';

/// Indicadores da fatura: quantidade e ticket médio, maior compra, quanto
/// é parcelado (e quanto ainda vem nas próximas faturas) e recorrências.
class InvoiceKpis extends StatelessWidget {
  final Invoice invoice;
  final FinancialEngine engine;
  const InvoiceKpis({super.key, required this.invoice, required this.engine});

  @override
  Widget build(BuildContext context) {
    final txs = invoice.transactions;
    final expenses = txs.where((t) => t.type == TransactionType.expense);
    final n = expenses.length;
    final spent = expenses.map((t) => t.amount).sum();
    final biggest = expenses.isEmpty
        ? null
        : expenses.reduce((a, b) => a.amount >= b.amount ? a : b);
    final inst = expenses.where((t) => t.isInstallment).toList();
    final future = inst.map((t) => futureInstallments(engine, t)).sum();
    final rec = expenses.where((t) => t.isRecurring).toList();
    final credits = txs
        .where((t) => t.type == TransactionType.income)
        .map((t) => t.amount)
        .sum();
    final tiles = [
      _KpiTile(
        key: const ValueKey('invoice-kpi-count'),
        label: 'Compras',
        value: '$n',
        detail: n == 0
            ? 'Nenhuma compra'
            : 'ticket médio ${Money(spent.cents ~/ n).format()}',
        icon: Icons.receipt_long_outlined,
        color: context.colors.primary,
      ),
      _KpiTile(
        key: const ValueKey('invoice-kpi-biggest'),
        label: 'Maior compra',
        value: biggest?.amount.format() ?? '—',
        detail: biggest?.description ?? '—',
        icon: Icons.trending_up,
        color: context.fin.expense,
      ),
      _KpiTile(
        key: const ValueKey('invoice-kpi-installments'),
        label: 'Parcelado',
        value: inst.map((t) => t.amount).sum().format(),
        detail: inst.isEmpty
            ? 'Nenhuma parcela'
            : '${inst.length} ${inst.length == 1 ? 'parcela' : 'parcelas'} · '
                  '${future.format()} nas próximas',
        icon: Icons.view_week_outlined,
        color: GridPalette.of(context).neon2,
      ),
      _KpiTile(
        key: const ValueKey('invoice-kpi-recurring'),
        label: credits.isPositive ? 'Recorrentes · estornos' : 'Recorrentes',
        value: rec.map((t) => t.amount).sum().format(),
        detail: [
          '${rec.length} ${rec.length == 1 ? 'cobrança' : 'cobranças'}',
          if (credits.isPositive) 'estornos ${credits.format()}',
        ].join(' · '),
        icon: Icons.autorenew,
        color: GridPalette.of(context).neon,
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
  final IconData icon;
  final Color color;
  const _KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
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
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
        ],
      ),
    ),
  );
}

/// Soma das parcelas seguintes de uma compra parcelada (as que ainda vão
/// cair nas próximas faturas).
Money futureInstallments(FinancialEngine e, FinTransaction t) {
  final g = t.installmentGroupId;
  final n = t.installmentNumber;
  if (g == null || n == null) return Money.zero;
  final rest = e.data.transactions.where(
    (x) =>
        x.installmentGroupId == g &&
        (x.installmentNumber ?? 0) > n &&
        x.status != TransactionStatus.cancelled,
  );
  if (rest.isNotEmpty) return rest.map((x) => x.amount).sum();
  final count = t.installmentCount ?? n;
  return t.amount * (count - n);
}

/// Colunas da grade de compras da fatura.
enum InvoiceColumn {
  date('Data', 92, 84),
  category('Categoria', 160, 96, flexible: true),
  subcategory('Subcategoria', 150, 84, flexible: true),
  description('Descrição', 280, 140, flexible: true),
  kind('Tipo', 128, 116),
  notes('Observações', 190, 90, flexible: true),
  future(
    'Próximas',
    118,
    100,
    right: true,
    tooltip: 'Parcelas que ainda virão nas próximas faturas',
  ),
  amount('Valor', 124, 104, right: true),
  share('% fatura', 96, 88, right: true);

  final String label;
  final double width;
  final double minWidth;
  final bool right;
  final bool flexible;
  final String? tooltip;
  const InvoiceColumn(
    this.label,
    this.width,
    this.minWidth, {
    this.right = false,
    this.flexible = false,
    this.tooltip,
  });
}

/// Compras da fatura: distribuição e filtro por categoria, busca e uma
/// grade como a de Transações (ordenável, com edição direta das células).
class InvoicePurchases extends StatefulWidget {
  final Invoice invoice;
  final FinancialEngine engine;
  const InvoicePurchases({
    super.key,
    required this.invoice,
    required this.engine,
  });

  @override
  State<InvoicePurchases> createState() => _InvoicePurchasesState();
}

typedef _Row = ({
  FinTransaction tx,
  String root,
  String category,
  String sub,
  Color color,
  Money signed,
  Money future,
});

class _InvoicePurchasesState extends State<InvoicePurchases> {
  bool byCategory = false;
  String? categoryFilter; // categoria raiz
  String query = '';
  InvoiceColumn sort = InvoiceColumn.date;
  bool ascending = false;
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  _Row _row(FinTransaction t) {
    final e = widget.engine;
    final cat = e.data.categoryById[t.categoryId];
    final parent = e.data.categoryById[cat?.parentId];
    final rootCat = parent ?? cat;
    return (
      tx: t,
      root: e.rootCategoryId(t.categoryId),
      category: rootCat?.name ?? 'Sem categoria',
      sub: parent == null ? '' : cat!.name,
      color: Color(rootCat?.color ?? 0xFF94A3B8),
      signed: Invoice.signedOf(t),
      future: futureInstallments(e, t),
    );
  }

  static int _kindRank(FinTransaction t) => t.type == TransactionType.income
      ? 4
      : t.isVirtual
      ? 3
      : t.isInstallment
      ? 1
      : t.isRecurring
      ? 2
      : 0;

  int _cmp(_Row a, _Row b) {
    int text(String x, String y) => x.toLowerCase().compareTo(y.toLowerCase());
    final c = switch (sort) {
      InvoiceColumn.date => a.tx.date.compareTo(b.tx.date),
      InvoiceColumn.category => text(a.category, b.category),
      InvoiceColumn.subcategory => text(a.sub, b.sub),
      InvoiceColumn.description => text(a.tx.description, b.tx.description),
      InvoiceColumn.kind => _kindRank(a.tx).compareTo(_kindRank(b.tx)),
      InvoiceColumn.notes => text(a.tx.notes, b.tx.notes),
      InvoiceColumn.future => a.future.cents.compareTo(b.future.cents),
      InvoiceColumn.amount ||
      InvoiceColumn.share => a.signed.cents.compareTo(b.signed.cents),
    };
    final r = ascending ? c : -c;
    return r != 0 ? r : b.tx.date.compareTo(a.tx.date);
  }

  void _onSort(InvoiceColumn c) => setState(() {
    if (c == sort) {
      ascending = !ascending;
    } else {
      sort = c;
      // Datas e valores começam do maior; textos, de A a Z.
      ascending =
          !(c == InvoiceColumn.date ||
              c == InvoiceColumn.amount ||
              c == InvoiceColumn.share ||
              c == InvoiceColumn.future);
    }
  });

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final e = widget.engine;
    final all = [for (final t in inv.transactions) _row(t)];
    final byRoot = <String, List<_Row>>{};
    for (final r in all) {
      byRoot.putIfAbsent(r.root, () => []).add(r);
    }
    Money subtotal(List<_Row> l) => l.map((r) => r.signed).sum();
    final roots = byRoot.keys.toList()
      ..sort((a, b) => subtotal(byRoot[b]!).compareTo(subtotal(byRoot[a]!)));
    final total = inv.total;
    String pct(Money m) {
      if (!total.isPositive) return '—';
      final v = m.cents * 100 / total.cents;
      return '${v.toStringAsFixed(v.abs() < 10 ? 1 : 0).replaceAll('.', ',')}%';
    }

    final q = query.trim().toLowerCase();
    final rows = all.where((r) {
      if (categoryFilter != null && r.root != categoryFilter) return false;
      if (q.isEmpty) return true;
      return r.tx.description.toLowerCase().contains(q) ||
          r.tx.notes.toLowerCase().contains(q) ||
          r.category.toLowerCase().contains(q) ||
          r.sub.toLowerCase().contains(q) ||
          r.tx.amount.formatPlain().contains(q);
    }).toList()..sort(_cmp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: LayoutBuilder(
            builder: (context, box) {
              final search = SizedBox(
                height: 40,
                child: TextField(
                  key: const ValueKey('invoice-search'),
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar compra',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              );
              final narrow = box.maxWidth < 640;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Compras (${inv.transactions.length})',
                          style: context.text.titleMedium,
                        ),
                      ),
                      if (!narrow) ...[
                        SizedBox(width: 260, child: search),
                        const SizedBox(width: 8),
                      ],
                      FilterChip(
                        key: const ValueKey('invoice-by-category'),
                        label: const Text('Por categoria'),
                        selected: byCategory,
                        onSelected: (v) => setState(() => byCategory = v),
                      ),
                    ],
                  ),
                  if (narrow) ...[const SizedBox(height: 8), search],
                ],
              );
            },
          ),
        ),
        if (roots.length > 1 && total.isPositive)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _CategoryBar(
              parts: [
                for (final r in roots)
                  if (subtotal(byRoot[r]!).isPositive)
                    (
                      label: e.categoryLabel(r.isEmpty ? null : r),
                      value: subtotal(byRoot[r]!),
                      color: byRoot[r]!.first.color,
                      selected: categoryFilter == null || categoryFilter == r,
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
                      key: ValueKey('invoice-cat-$r'),
                      avatar: CircleAvatar(
                        radius: 5,
                        backgroundColor: byRoot[r]!.first.color,
                      ),
                      label: Text(
                        '${e.categoryLabel(r.isEmpty ? null : r)} · '
                        '${subtotal(byRoot[r]!).format()} · '
                        '${pct(subtotal(byRoot[r]!))}',
                      ),
                      selected: categoryFilter == r,
                      onSelected: (_) => setState(
                        () => categoryFilter = categoryFilter == r ? null : r,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (inv.transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhuma compra nesta fatura.'),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final pad = box.maxWidth < 640 ? 8.0 : 16.0;
              final width = box.maxWidth - 2 * pad - 2;
              final List<(String?, List<_Row>)> groups = byCategory
                  ? [
                      for (final r in roots)
                        if (rows.any((x) => x.root == r))
                          (r, rows.where((x) => x.root == r).toList()),
                    ]
                  : [(null, rows)];
              final compact = width < 640;
              final layout = compact ? null : _Layout.of(width);
              var index = 0;
              final body = <Widget>[];
              for (final (root, list) in groups) {
                if (root != null) {
                  body.add(
                    _GroupHeader(
                      label: e.categoryLabel(root.isEmpty ? null : root),
                      color: list.first.color,
                      count: list.length,
                      total: subtotal(list),
                      share: pct(subtotal(list)),
                    ),
                  );
                }
                for (final r in list) {
                  body.add(
                    compact
                        ? _CompactRow(
                            row: r,
                            index: index++,
                            share: pct(r.signed),
                          )
                        : _GridRow(
                            row: r,
                            index: index++,
                            layout: layout!,
                            share: pct(r.signed),
                          ),
                  );
                }
              }
              if (rows.isEmpty) {
                body.add(
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nenhuma compra encontrada.'),
                  ),
                );
              }
              body.add(
                _Footer(
                  layout: layout,
                  count: rows.length,
                  total: subtotal(rows),
                  future: rows.map((r) => r.future).sum(),
                  share: pct(subtotal(rows)),
                ),
              );
              final content = Column(children: body);
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: GridPanel(
                  child: compact
                      ? content
                      : Scrollbar(
                          controller: _hScroll,
                          child: SingleChildScrollView(
                            controller: _hScroll,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: layout!.totalWidth,
                              child: Column(
                                children: [
                                  _Header(
                                    layout: layout,
                                    sort: sort,
                                    ascending: ascending,
                                    onSort: _onSort,
                                  ),
                                  content,
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Larguras finais das colunas: a sobra vai para Descrição; se faltar
/// espaço, as colunas de texto encolhem até o mínimo e depois a grade
/// rola na horizontal.
class _Layout {
  final List<(InvoiceColumn, double)> cells;
  final double totalWidth;
  const _Layout(this.cells, this.totalWidth);

  static const stripeW = GridLayout.stripeW;
  static const actionW = 44.0;

  factory _Layout.of(double width) {
    const cols = InvoiceColumn.values;
    var sum = stripeW + actionW;
    var slack = 0.0;
    for (final c in cols) {
      sum += c.width;
      if (c.flexible) slack += c.width - c.minWidth;
    }
    final extra = width > sum ? width - sum : 0.0;
    final deficit = width < sum ? sum - width : 0.0;
    final shrink = slack <= 0 ? 0.0 : (deficit / slack).clamp(0.0, 1.0);
    double sized(InvoiceColumn c) {
      if (c == InvoiceColumn.description && extra > 0) return c.width + extra;
      if (!c.flexible) return c.width;
      return c.width - (c.width - c.minWidth) * shrink;
    }

    return _Layout([
      for (final c in cols) (c, sized(c)),
    ], sum + extra - slack * shrink);
  }
}

class _Header extends StatelessWidget {
  final _Layout layout;
  final InvoiceColumn sort;
  final bool ascending;
  final ValueChanged<InvoiceColumn> onSort;
  const _Header({
    required this.layout,
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    Widget cell(InvoiceColumn c) {
      final active = c == sort;
      final label = InkWell(
        key: ValueKey('invoice-sort-${c.name}'),
        onTap: () => onSort(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: c.right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  c.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: active ? p.neon : p.headerText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                active
                    ? (ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down)
                    : Icons.unfold_more,
                size: active ? 18 : 13,
                color: active ? p.neon : p.headerText.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      );
      return c.tooltip == null
          ? label
          : Tooltip(message: c.tooltip!, child: label);
    }

    return Container(
      height: 38,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: p.header),
        border: Border(bottom: BorderSide(color: p.neon, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: _Layout.stripeW),
          for (final (c, w) in layout.cells) SizedBox(width: w, child: cell(c)),
          const SizedBox(width: _Layout.actionW),
        ],
      ),
    );
  }
}

/// Rótulo e cor do tipo da compra (à vista, parcela, recorrente...).
(String, Color) _kindOf(BuildContext context, FinTransaction t) {
  final p = GridPalette.of(context);
  if (t.type == TransactionType.income) {
    return ('Estorno', context.fin.positive);
  }
  if (t.isVirtual) return ('Prevista', context.fin.warning);
  if (t.isInstallment) return ('Parcela ${t.installmentLabel}', p.neon2);
  if (t.isRecurring) return ('Recorrente', p.neon);
  return ('À vista', context.fin.subtle);
}

Widget _money(BuildContext context, FinTransaction t, {bool bold = true}) {
  final credit = t.type == TransactionType.income;
  return MoneyText(
    credit ? t.amount : -t.amount,
    showPlus: credit,
    color: credit ? context.fin.positive : null,
    style: context.text.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.w700 : null,
    ),
  );
}

class _GridRow extends StatelessWidget {
  final _Row row;
  final int index;
  final _Layout layout;
  final String share;
  const _GridRow({
    required this.row,
    required this.index,
    required this.layout,
    required this.share,
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final tx = row.tx;
    final p = GridPalette.of(context);
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final tab = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );
    final key = '${tx.id}-${tx.date.toIso8601String()}';
    Future<void> save(FinTransaction t) => saveTxInline(context, fc, t);
    final (kind, kindColor) = _kindOf(context, tx);
    final credit = tx.type == TransactionType.income;
    final cat = fc.data.categoryById[tx.categoryId];

    Widget cell(InvoiceColumn c) => switch (c) {
      InvoiceColumn.date => InlinePickerCell(
        key: ValueKey('invoice-edit-date-$key'),
        tooltip: 'Alterar data da compra',
        onPick: (_) => pickTxDate(context, fc, tx),
        display: Text(Dates.format(tx.date), style: tab),
      ),
      InvoiceColumn.category => InlinePickerCell(
        key: ValueKey('invoice-edit-category-$key'),
        tooltip: 'Alterar categoria',
        onPick: (cell) => pickTxCategory(cell, fc, tx, onlyRoots: true),
        display: Row(
          children: [
            _Dot(row.color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                row.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium,
              ),
            ),
          ],
        ),
      ),
      InvoiceColumn.subcategory =>
        cat == null
            ? GridCell(child: Text('—', style: subtle))
            : InlinePickerCell(
                key: ValueKey('invoice-edit-subcategory-$key'),
                tooltip: 'Alterar subcategoria',
                onPick: (cell) => pickTxSubcategory(cell, fc, tx),
                display: Text(
                  row.sub.isEmpty ? '—' : row.sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: row.sub.isEmpty ? subtle : context.text.bodyMedium,
                ),
              ),
      InvoiceColumn.description => InlineTextCell(
        key: ValueKey('invoice-edit-description-$key'),
        value: tx.description,
        hint: 'Descrição',
        validate: (v) => v.isEmpty ? 'Informe uma descrição' : null,
        onSubmit: (v) => save(tx.copyWith(description: v)),
        display: Text(
          tx.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      InvoiceColumn.kind => GridCell(
        child: NeonStatus(label: kind, color: kindColor, done: false),
      ),
      InvoiceColumn.notes => InlineTextCell(
        key: ValueKey('invoice-edit-notes-$key'),
        value: tx.notes,
        hint: 'Observações',
        onSubmit: (v) => save(tx.copyWith(notes: v)),
        display: Text(
          tx.notes.trim().isEmpty ? '—' : tx.notes.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tx.notes.trim().isEmpty
              ? subtle
              : context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      ),
      InvoiceColumn.future => GridCell(
        right: true,
        child: row.future.isPositive
            ? Tooltip(
                message:
                    'Faltam ${(tx.installmentCount ?? 0) - (tx.installmentNumber ?? 0)} parcelas',
                child: MoneyText(row.future, style: subtle),
              )
            : Text('—', style: subtle),
      ),
      InvoiceColumn.amount => InlineTextCell(
        key: ValueKey('invoice-edit-amount-$key'),
        value: tx.amount.formatPlain(),
        right: true,
        hint: '0,00',
        background: p.valueBg,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validate: validateInlineAmount,
        onSubmit: (v) => save(tx.copyWith(amount: Money.tryEval(v))),
        display: _money(context, tx),
      ),
      InvoiceColumn.share => GridCell(
        right: true,
        child: Text(
          credit ? '—' : share,
          style: subtle?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    };

    return GridRowShell(
      accent: credit ? context.fin.positive : row.color,
      zebra: index.isOdd,
      height: GridLayout.rowH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (c, w) in layout.cells) SizedBox(width: w, child: cell(c)),
          SizedBox(
            width: _Layout.actionW,
            child: Center(child: InvoicePurchaseMenu(tx: tx)),
          ),
        ],
      ),
    );
  }
}

/// Linha de duas linhas para o celular: tocar abre os detalhes.
class _CompactRow extends StatelessWidget {
  final _Row row;
  final int index;
  final String share;
  const _CompactRow({
    required this.row,
    required this.index,
    required this.share,
  });

  @override
  Widget build(BuildContext context) {
    final tx = row.tx;
    final (kind, kindColor) = _kindOf(context, tx);
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final credit = tx.type == TransactionType.income;
    return GridRowShell(
      accent: credit ? context.fin.positive : row.color,
      zebra: index.isOdd,
      onTap: () => push(context, TransactionDetailsScreen(tx: tx)),
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
                    tx.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _Dot(row.color),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          [
                            Dates.formatShort(tx.date),
                            row.sub.isEmpty
                                ? row.category
                                : '${row.category} › ${row.sub}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: subtle,
                        ),
                      ),
                    ],
                  ),
                  if (tx.notes.trim().isNotEmpty)
                    Text(
                      tx.notes.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtle?.copyWith(fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _money(context, tx),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!credit) ...[
                      Text(share, style: subtle),
                      const SizedBox(width: 6),
                    ],
                    NeonStatus(label: kind, color: kindColor),
                  ],
                ),
              ],
            ),
            InvoicePurchaseMenu(tx: tx),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final Color color;
  final int count;
  final Money total;
  final String share;
  const _GroupHeader({
    required this.label,
    required this.color,
    required this.count,
    required this.total,
    required this.share,
  });

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: p.line, width: 0.6)),
      ),
      child: Row(
        children: [
          _Dot(color),
          const SizedBox(width: 8),
          Text(
            label,
            style: context.text.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count ${count == 1 ? 'compra' : 'compras'} · $share',
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
          const Spacer(),
          MoneyText(
            -total,
            style: context.text.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// Rodapé com o total das compras exibidas (com filtro/busca aplicados).
class _Footer extends StatelessWidget {
  final _Layout? layout;
  final int count;
  final Money total;
  final Money future;
  final String share;
  const _Footer({
    required this.layout,
    required this.count,
    required this.total,
    required this.future,
    required this.share,
  });

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    final strong = context.text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: p.neon,
    );
    final label = Text(
      'Total · $count ${count == 1 ? 'compra' : 'compras'}',
      style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
    final decoration = BoxDecoration(
      color: p.neon.withValues(alpha: 0.06),
      border: Border(
        top: BorderSide(color: p.neon.withValues(alpha: 0.5), width: 1),
      ),
    );
    final l = layout;
    if (l == null) {
      return Container(
        key: const ValueKey('invoice-footer'),
        decoration: decoration,
        padding: const EdgeInsets.fromLTRB(13, 10, 48, 10),
        child: Row(
          children: [
            Expanded(child: label),
            MoneyText(-total, style: strong),
          ],
        ),
      );
    }
    Widget cell(InvoiceColumn c) => switch (c) {
      InvoiceColumn.date => GridCell(child: label),
      InvoiceColumn.future => GridCell(
        right: true,
        child: future.isPositive
            ? MoneyText(future, style: context.text.bodySmall)
            : const SizedBox.shrink(),
      ),
      InvoiceColumn.amount => GridCell(
        right: true,
        background: p.valueBg,
        child: MoneyText(-total, style: strong),
      ),
      InvoiceColumn.share => GridCell(
        right: true,
        child: Text(share, style: context.text.bodySmall),
      ),
      _ => const SizedBox.shrink(),
    };
    return Container(
      key: const ValueKey('invoice-footer'),
      height: 40,
      decoration: decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: _Layout.stripeW),
          for (final (c, w) in l.cells)
            SizedBox(
              width: w,
              child: c == InvoiceColumn.date
                  ? OverflowBox(
                      alignment: Alignment.centerLeft,
                      maxWidth: 260,
                      child: cell(c),
                    )
                  : cell(c),
            ),
          const SizedBox(width: _Layout.actionW),
        ],
      ),
    );
  }
}

/// Barra horizontal com a fatia de cada categoria no total da fatura.
class _CategoryBar extends StatelessWidget {
  final List<({String label, Money value, Color color, bool selected})> parts;
  const _CategoryBar({required this.parts});

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (final (i, part) in parts.indexed)
              Expanded(
                flex: part.value.cents,
                child: Tooltip(
                  message: '${part.label} · ${part.value.format()}',
                  child: Container(
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 1.5),
                    color: part.color.withValues(
                      alpha: part.selected ? 0.9 : 0.25,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 5),
      ],
    ),
  );
}

/// Ações de uma compra da fatura: detalhes, editar, parcelar / editar
/// parcelamento, tornar recorrente / editar recorrência e excluir.
class InvoicePurchaseMenu extends StatelessWidget {
  final FinTransaction tx;
  const InvoicePurchaseMenu({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final t = tx;
    final rule = fc.data.ruleById[t.recurringId];
    final group = fc.data.groupById[t.installmentGroupId];
    final plain = TransactionFormScreen.canConvert(t);
    final expense = t.type == TransactionType.expense;
    return PopupMenuButton<String>(
      key: ValueKey('purchase-menu-${t.id}'),
      tooltip: 'Ações da compra',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) async {
        switch (v) {
          case 'open':
            push(context, TransactionDetailsScreen(tx: t));
          case 'edit':
            push(context, TransactionFormScreen(tx: t));
          case 'split':
            push(
              context,
              TransactionFormScreen(tx: t, initialInstallment: true),
            );
          case 'group':
            push(context, InstallmentEditScreen(groupId: group!.id));
          case 'recurring':
            push(context, TransactionFormScreen(tx: t, initialRecurring: true));
          case 'rule':
            push(context, RecurringFormScreen(rule: rule));
          case 'delete':
            final ok = await confirmDialog(
              context,
              title: t.isVirtual ? 'Pular ocorrência?' : 'Excluir compra?',
              message: t.isVirtual
                  ? 'Esta cobrança prevista sai da fatura. A recorrência continua ativa.'
                  : t.isInstallment
                  ? 'Somente esta parcela será excluída. Para mudar o parcelamento use “Editar parcelamento”.'
                  : 'Esta ação não pode ser desfeita.',
              confirm: t.isVirtual ? 'Pular' : 'Excluir',
              destructive: true,
            );
            if (ok && context.mounted) {
              await runAction(
                context,
                () => fc.deleteTransaction(t),
                success: t.isVirtual ? 'Ocorrência pulada' : 'Compra excluída',
              );
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'open',
          child: _MenuRow(Icons.open_in_new, 'Ver detalhes'),
        ),
        PopupMenuItem(
          value: 'edit',
          child: _MenuRow(
            Icons.edit_outlined,
            t.isVirtual ? 'Editar esta cobrança' : 'Editar compra',
          ),
        ),
        if (group != null)
          const PopupMenuItem(
            value: 'group',
            child: _MenuRow(Icons.view_week_outlined, 'Editar parcelamento'),
          )
        else if (plain && expense)
          const PopupMenuItem(
            value: 'split',
            child: _MenuRow(Icons.view_week_outlined, 'Parcelar'),
          ),
        if (rule != null)
          const PopupMenuItem(
            value: 'rule',
            child: _MenuRow(Icons.autorenew, 'Editar recorrência'),
          )
        else if (plain)
          const PopupMenuItem(
            value: 'recurring',
            child: _MenuRow(Icons.autorenew, 'Tornar recorrente'),
          ),
        PopupMenuItem(
          value: 'delete',
          child: _MenuRow(
            Icons.delete_outline,
            t.isVirtual ? 'Pular esta cobrança' : 'Excluir',
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)],
  );
}
