import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../import/expense_import_screen.dart';
import '../../widgets/common.dart';
import '../../widgets/invoice_tile.dart';
import '../../widgets/tx_grid.dart';
import '../cards/invoice_details_screen.dart';
import 'transaction_details_screen.dart';
import 'transaction_form_screen.dart';

/// Filtros da lista de transações.
class TxListFilter {
  final Set<TransactionType> types;
  final Set<TransactionStatus> statuses;
  final String? accountOrCard; // 'a:id' | 'c:id'
  final String? categoryId;
  final String? projectId;
  const TxListFilter({
    this.types = const {},
    this.statuses = const {},
    this.accountOrCard,
    this.categoryId,
    this.projectId,
  });
  int get count =>
      (types.isEmpty ? 0 : 1) +
      (statuses.isEmpty ? 0 : 1) +
      (accountOrCard == null ? 0 : 1) +
      (categoryId == null ? 0 : 1) +
      (projectId == null ? 0 : 1);
}

/// Filtro rápido de status (barra acima da lista).
enum QuickStatus {
  all('Todas'),
  pending('Pendentes'),
  completed('Concluídas');

  final String label;
  const QuickStatus(this.label);

  bool matches(TransactionStatus s) => switch (this) {
    QuickStatus.all => true,
    QuickStatus.pending =>
      s == TransactionStatus.pending || s == TransactionStatus.planned,
    QuickStatus.completed => s == TransactionStatus.completed,
  };
}

/// Filtro rápido de seção (Receitas / Despesas).
enum QuickType {
  all('Tudo', null),
  income('Receitas', TransactionType.income),
  expense('Despesas', TransactionType.expense);

  final String label;
  final TransactionType? type;
  const QuickType(this.label, this.type);
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});
  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  YearMonth month = YearMonth.now();
  bool allPeriods = false;
  bool showForecast = true;
  bool searching = false;
  String query = '';
  TxListFilter filter = const TxListFilter();
  QuickStatus quickStatus = QuickStatus.all;
  QuickType quickType = QuickType.all;
  final searchCtrl = TextEditingController();

  /// Fatura selecionada com clique simples (desktop).
  String? selectedInvoice;

  /// Ordenação da grade (clique no cabeçalho da coluna).
  GridColumn sort = GridColumn.date;
  bool ascending = false;

  /// Colunas enquanto o usuário arrasta a borda de uma delas (salvas ao
  /// soltar).
  GridColumnsConfig? _draftColumns;
  GridLayout? _lastLayout;

  GridColumnsConfig _columns(FinanceController fc) =>
      _draftColumns ??
      GridColumnsConfig.fromJson(fc.data.settings.txGridColumns);

  @override
  void dispose() {
    searchCtrl.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  List<_Entry> _items(FinanceController fc) {
    final e = fc.engine;
    final until = allPeriods ? Dates.addMonths(e.today, 12) : month.lastDay;
    final from = allPeriods ? YearMonth(1970, 1) : month;
    final to = allPeriods ? YearMonth.of(until) : month;
    final q = query.trim().toLowerCase();
    final cats = <String>{};
    if (filter.categoryId != null) {
      cats.add(filter.categoryId!);
      cats.addAll(
        fc.data.categories
            .where((c) => c.parentId == filter.categoryId)
            .map((c) => c.id),
      );
    }
    // Compras do cartão aparecem uma a uma quando a preferência pede, e
    // sempre que o usuário busca ou filtra por categoria/projeto (para que
    // relatórios e buscas encontrem cada compra).
    final individualCards =
        !fc.data.settings.groupCardInvoices ||
        cats.isNotEmpty ||
        filter.projectId != null ||
        q.isNotEmpty;

    bool matches(FinTransaction t) {
      if (!showForecast && t.isVirtual) return false;
      if (filter.types.isNotEmpty && !filter.types.contains(t.type)) {
        return false;
      }
      if (quickType.type != null && t.type != quickType.type) return false;
      if (!quickStatus.matches(t.status)) return false;
      if (filter.statuses.isNotEmpty && !filter.statuses.contains(t.status)) {
        return false;
      }
      final loc = filter.accountOrCard;
      if (loc != null) {
        final id = loc.substring(2);
        final ok = loc.startsWith('a:')
            ? (t.accountId == id || t.destinationAccountId == id)
            : t.cardId == id;
        if (!ok) return false;
      }
      if (cats.isNotEmpty && !cats.contains(t.categoryId)) return false;
      if (filter.projectId != null && t.projectId != filter.projectId) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = [
          t.description,
          t.notes,
          e.categoryLabel(t.categoryId),
          e.locationLabel(t),
          t.amount.formatPlain(),
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }

    final out = <_Entry>[];
    for (final t in e.transactionsUntil(until)) {
      if (t.cardId != null && !t.isTransfer) continue; // entram pela fatura
      final d = t.date;
      if (!allPeriods && !month.contains(d)) continue;
      if (allPeriods && t.isVirtual && d.isAfter(until)) continue;
      if (matches(t)) out.add(_TxEntry(t, d, t.amount));
    }

    for (final (:invoice, :slice) in e.invoiceSlicesIn(from, to)) {
      if (individualCards) {
        for (final t in invoice.transactions) {
          if (!matches(t)) continue;
          for (final sh in invoice.shares[t.id] ?? const <TxShare>[]) {
            if (!identical(sh.slice, slice)) continue;
            out.add(
              _TxEntry(
                t,
                slice.date,
                Money(sh.amount.cents.abs()),
                isCard: true,
              ),
            );
          }
        }
        continue;
      }
      if (!_invoiceMatches(invoice, slice)) continue;
      out.add(_InvoiceEntry(invoice, slice));
    }
    out.sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    });
    return out;
  }

  bool _invoiceMatches(Invoice inv, InvoiceSlice slice) {
    if (!showForecast && inv.transactions.every((t) => t.isVirtual)) {
      if (inv.payments.isEmpty) return false;
    }
    if (quickType == QuickType.income) return false;
    if (filter.types.isNotEmpty &&
        !filter.types.contains(TransactionType.expense)) {
      return false;
    }
    final status = slice.settled
        ? TransactionStatus.completed
        : inv.status == InvoiceStatus.future
        ? TransactionStatus.planned
        : TransactionStatus.pending;
    if (!quickStatus.matches(status)) return false;
    if (filter.statuses.isNotEmpty && !filter.statuses.contains(status)) {
      return false;
    }
    final loc = filter.accountOrCard;
    if (loc != null) {
      if (loc.startsWith('a:')) {
        // Pagamentos feitos com a conta filtrada.
        final id = loc.substring(2);
        if (!slice.settled ||
            !inv.payments.any(
              (p) => p.accountId == id && YearMonth.of(p.date) == slice.month,
            )) {
          return false;
        }
      } else if (inv.card.id != loc.substring(2)) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final items = _items(fc);
    var inc = Money.zero, exp = Money.zero;
    var incOpen = Money.zero, expOpen = Money.zero;
    // A fatura conta uma única vez; as compras dentro dela não são somadas
    // de novo (na lista agrupada elas nem aparecem).
    for (final it in items) {
      switch (it) {
        case _TxEntry(:final tx, :final amount):
          if (tx.status == TransactionStatus.cancelled) continue;
          final open = tx.status != TransactionStatus.completed;
          if (tx.type == TransactionType.income) {
            inc += amount;
            if (open) incOpen += amount;
          }
          if (tx.type == TransactionType.expense) {
            exp += amount;
            if (open) expOpen += amount;
          }
        case _InvoiceEntry(:final slice):
          exp += slice.amount;
          if (!slice.settled) expOpen += slice.amount;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                controller: searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar descrição, categoria, valor…',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (v) => setState(() => query = v),
              )
            : const Text('Transações'),
        actions: [
          IconButton(
            tooltip: searching ? 'Fechar busca' : 'Buscar',
            icon: Icon(searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              searching = !searching;
              if (!searching) {
                query = '';
                searchCtrl.clear();
              }
            }),
          ),
          IconButton(
            tooltip: 'Filtros',
            icon: Badge(
              isLabelVisible: filter.count > 0,
              label: Text('${filter.count}'),
              child: const Icon(Icons.tune),
            ),
            onPressed: () async {
              final f = await showModalBottomSheet<TxListFilter>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _FilterSheet(fc: fc, initial: filter),
              );
              if (f != null) setState(() => filter = f);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-tx',
        onPressed: () => push(context, const TransactionFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nova transação'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (!allPeriods)
                  MonthSwitcher(
                    month: month,
                    onChanged: (m) => setState(() => month = m),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Todos os períodos',
                      style: context.text.titleMedium,
                    ),
                  ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Opções',
                  onSelected: (v) {
                    if (v == 'import') {
                      push(context, const ExpenseImportScreen());
                      return;
                    }
                    if (v == 'columns') {
                      _configureColumns(fc);
                      return;
                    }
                    setState(() {
                      if (v == 'all') allPeriods = !allPeriods;
                      if (v == 'forecast') showForecast = !showForecast;
                    });
                  },
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(
                      value: 'all',
                      checked: allPeriods,
                      child: const Text('Todos os períodos'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'forecast',
                      checked: showForecast,
                      child: const Text('Mostrar recorrências previstas'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'columns',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.view_column_outlined),
                        title: Text('Configurar colunas'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.upload_file),
                        title: Text('Importar despesas (Excel)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _QuickFilters(
              type: quickType,
              status: quickStatus,
              onType: (v) => setState(() => quickType = v),
              onStatus: (v) => setState(() => quickStatus = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                if (quickType != QuickType.expense)
                  _Total('Receitas', inc, context.fin.positive, incOpen),
                if (quickType == QuickType.all) const SizedBox(width: 16),
                if (quickType != QuickType.income)
                  _Total('Despesas', exp, context.fin.negative, expOpen),
                const Spacer(),
                Text(
                  '${items.length} itens',
                  style: context.text.labelMedium?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: query.isNotEmpty || filter.count > 0
                        ? 'Nada encontrado'
                        : 'Sem transações neste período',
                    message: query.isNotEmpty || filter.count > 0
                        ? 'Ajuste a busca ou os filtros.'
                        : 'Registre receitas, despesas e transferências.',
                    actionLabel: 'Nova transação',
                    onAction: () =>
                        push(context, const TransactionFormScreen()),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      final pad = box.maxWidth < 640 ? 8.0 : 16.0;
                      final layout = GridLayout.of(
                        box.maxWidth - 2 * pad - 2,
                        _columns(fc),
                      );
                      _lastLayout = layout;
                      _sortItems(items, e);
                      final list = ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: items.length,
                        itemBuilder: (context, i) => switch (items[i]) {
                          final _TxEntry it => _txRow(
                            context,
                            fc,
                            it,
                            i,
                            layout,
                          ),
                          final _InvoiceEntry it => _invoiceRow(
                            context,
                            it,
                            i,
                            layout,
                          ),
                        },
                      );
                      return Padding(
                        padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                        child: GridPanel(
                          child: layout.compact
                              ? list
                              : Scrollbar(
                                  controller: _hScroll,
                                  child: SingleChildScrollView(
                                    controller: _hScroll,
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: layout.totalWidth,
                                      child: Column(
                                        children: [
                                          GridHeader(
                                            layout: layout,
                                            sort: sort,
                                            ascending: ascending,
                                            onSort: _onSort,
                                            onResize: _onResize,
                                            onResizeEnd: () =>
                                                _saveColumns(fc, _columns(fc)),
                                            onConfigure: () =>
                                                _configureColumns(fc),
                                          ),
                                          Expanded(child: list),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  final _hScroll = ScrollController();

  /// Arrasto da borda: parte da largura exibida (que pode incluir a sobra
  /// de espaço) para a coluna acompanhar o mouse.
  void _onResize(GridColumn c, double delta) {
    final fc = context.read<FinanceController>();
    final shown = _lastLayout?.cells
        .where((x) => x.$1 == c)
        .map((x) => x.$2)
        .firstOrNull;
    final cfg = _columns(fc);
    final base = shown ?? cfg.columns.firstWhere((s) => s.column == c).width;
    setState(() => _draftColumns = cfg.withWidth(c, base + delta));
  }

  Future<void> _saveColumns(FinanceController fc, GridColumnsConfig cfg) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await fc.saveSettings(
        fc.data.settings.copyWith(txGridColumns: cfg.toJson()),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível salvar as colunas: $e')),
      );
    }
    if (mounted) setState(() => _draftColumns = null);
  }

  Future<void> _configureColumns(FinanceController fc) async {
    final cfg = await showModalBottomSheet<GridColumnsConfig>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => GridColumnsSheet(initial: _columns(fc)),
    );
    if (cfg != null) await _saveColumns(fc, cfg);
  }

  void _onSort(GridColumn s) => setState(() {
    if (s == sort) {
      ascending = !ascending;
    } else {
      sort = s;
      // Datas e valores começam do maior; textos, de A a Z.
      ascending = s != GridColumn.date && s != GridColumn.amount;
    }
  });

  void _sortItems(List<_Entry> items, FinancialEngine e) {
    if (sort == GridColumn.date && !ascending) return; // ordem de _items
    int text(String Function(_Cols) f, _Entry a, _Entry b) =>
        f(_cols(e, a)).toLowerCase().compareTo(f(_cols(e, b)).toLowerCase());
    int cmp(_Entry a, _Entry b) => switch (sort) {
      GridColumn.date => a.date.compareTo(b.date),
      GridColumn.dueDate => (_due(e, a) ?? a.date).compareTo(
        _due(e, b) ?? b.date,
      ),
      GridColumn.category => text((c) => c.category, a, b),
      GridColumn.subcategory => text((c) => c.sub, a, b),
      GridColumn.description => text((c) => c.desc, a, b),
      GridColumn.notes => text((c) => c.notes, a, b),
      GridColumn.amount => _amount(a).cents.compareTo(_amount(b).cents),
      GridColumn.status => _statusRank(e, a).compareTo(_statusRank(e, b)),
    };
    items.sort((a, b) {
      final c = ascending ? cmp(a, b) : cmp(b, a);
      return c != 0 ? c : b.date.compareTo(a.date);
    });
  }

  /// Textos de categoria, subcategoria, descrição e observações da grade.
  static _Cols _cols(FinancialEngine e, _Entry it) {
    switch (it) {
      case _InvoiceEntry(:final invoice):
        return (
          category: 'Cartão',
          sub: invoice.card.name,
          desc: invoice.title,
          notes: '',
        );
      case _TxEntry(:final tx):
        final notes = tx.notes.trim();
        if (tx.isTransfer) {
          return (
            category: 'Transferência',
            sub: e.locationLabel(tx),
            desc: tx.description,
            notes: notes,
          );
        }
        final cat = e.data.categoryById[tx.categoryId];
        final parent = e.data.categoryById[cat?.parentId];
        if (cat == null) {
          return (
            category: 'Sem categoria',
            sub: '',
            desc: tx.description,
            notes: notes,
          );
        }
        return parent == null
            ? (category: cat.name, sub: '', desc: tx.description, notes: notes)
            : (
                category: parent.name,
                sub: cat.name,
                desc: tx.description,
                notes: notes,
              );
    }
  }

  /// Vencimento exibido na grade: o da fatura para compras no cartão; o
  /// informado pelo usuário para os demais lançamentos.
  static DateTime? _due(FinancialEngine e, _Entry it) => switch (it) {
    _InvoiceEntry(:final invoice) => invoice.dueDate,
    _TxEntry(:final tx) =>
      tx.cardId != null ? e.invoiceOf(tx)?.dueDate : tx.dueDate,
  };

  /// Valor com sinal: receitas positivas, despesas negativas.
  static Money _amount(_Entry it) => switch (it) {
    _InvoiceEntry(:final slice) => -slice.amount,
    _TxEntry(:final tx, :final amount) =>
      tx.type == TransactionType.expense ? -amount : amount,
  };

  static int _statusRank(FinancialEngine e, _Entry it) => switch (it) {
    _InvoiceEntry(:final slice) => slice.settled ? 3 : 1,
    _TxEntry(:final tx) => switch (tx.status) {
      TransactionStatus.completed => 3,
      TransactionStatus.cancelled => 4,
      TransactionStatus.planned => 2,
      TransactionStatus.pending =>
        tx.effectiveDueDate.isBefore(e.today) ? 0 : 1,
    },
  };

  Widget _txRow(
    BuildContext context,
    FinanceController fc,
    _TxEntry it,
    int index,
    GridLayout layout,
  ) {
    final e = fc.engine;
    final tx = it.tx;
    final (category: catName, sub: subName, :desc, :notes) = _cols(e, it);
    final showSub = layout.shows(GridColumn.subcategory);
    final cat = e.data.categoryById[tx.categoryId];
    final catColor = tx.isTransfer
        ? context.fin.subtle
        : Color(cat?.color ?? context.fin.subtle.toARGB32());
    final isIncome = tx.type == TransactionType.income;
    final accent = tx.isTransfer
        ? context.fin.subtle
        : isIncome
        ? context.fin.positive
        : context.fin.expense;
    final cancelled = tx.status == TransactionStatus.cancelled;
    final completed = tx.status == TransactionStatus.completed;
    final overdue =
        !completed && !cancelled && tx.effectiveDueDate.isBefore(e.today);
    final (statusLabel, statusColor) = cancelled
        ? ('Cancelada', context.fin.subtle)
        : completed
        ? (
            tx.isTransfer ? 'Concluída' : (isIncome ? 'Recebida' : 'Paga'),
            context.fin.positive,
          )
        : overdue
        ? ('Atrasada', context.fin.negative)
        : tx.status == TransactionStatus.planned
        ? ('Prevista', context.colors.primary)
        : ('Pendente', context.fin.warning);
    // Status direto na grade, em lista suspensa. Compras no cartão seguem
    // o status da fatura.
    final canPick = tx.cardId == null;
    final status = Builder(
      builder: (cell) => NeonStatus(
        key: ValueKey('tx-status-${tx.id}-${tx.date.toIso8601String()}'),
        label: statusLabel,
        color: statusColor,
        done: completed,
        dropdown: true,
        tooltip: 'Alterar status',
        onTap: canPick ? () => _pickStatus(cell, fc, tx) : null,
      ),
    );
    final money = MoneyText(
      isIncome || tx.isTransfer ? it.amount : -it.amount,
      showPlus: isIncome,
      color: tx.isTransfer
          ? context.fin.subtle
          : isIncome
          ? context.fin.positive
          : null,
      style: context.text.bodyMedium?.copyWith(
        fontWeight: FontWeight.w700,
        decoration: cancelled ? TextDecoration.lineThrough : null,
      ),
    );
    final invoice = it.isCard ? e.invoiceOf(tx) : null;
    final invoiceLink = invoice == null
        ? null
        : InkWell(
            onTap: () => _openInvoice(invoice),
            borderRadius: BorderRadius.circular(4),
            child: Text(
              '${invoice.title} ›',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: GridPalette.of(context).neon,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
    final extras = [
      if (tx.isInstallment) tx.installmentLabel,
      if (invoice != null) 'compra ${Dates.formatShort(tx.date)}',
      if (tx.dueDate != null &&
          invoice == null &&
          (layout.compact || !layout.shows(GridColumn.dueDate)))
        'vence ${Dates.formatShort(tx.dueDate!)}',
    ].join(' · ');
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final descStyle = context.text.bodyMedium?.copyWith(
      fontWeight: layout.compact ? FontWeight.w600 : null,
      decoration: cancelled ? TextDecoration.lineThrough : null,
    );
    void open() => push(context, TransactionDetailsScreen(tx: tx));
    Future<void> save(FinTransaction t) => _saveInline(context, fc, t);
    final key = '${tx.id}-${tx.date.toIso8601String()}';

    if (layout.compact) {
      // No celular: data, descrição, categoria e valor também editam ali
      // mesmo; tocar no resto da linha abre os detalhes.
      final catLine = Row(
        children: [
          _Dot(catColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              [
                subName.isEmpty || !showSub ? catName : '$catName › $subName',
                if (extras.isNotEmpty) extras,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtle,
            ),
          ),
        ],
      );
      return GridRowShell(
        accent: accent,
        zebra: index.isOdd,
        dimmed: cancelled,
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
          child: Row(
            children: [
              InlinePickerCell(
                key: ValueKey('tx-edit-date-$key'),
                dense: true,
                tooltip: 'Alterar data',
                onPick: (_) => _pickDate(context, fc, tx),
                display: _DateBadge(it.date),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InlineTextCell(
                      key: ValueKey('tx-edit-description-$key'),
                      dense: true,
                      value: tx.description,
                      hint: 'Descrição',
                      validate: (v) =>
                          v.isEmpty ? 'Informe uma descrição' : null,
                      onSubmit: (v) => save(tx.copyWith(description: v)),
                      display: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              desc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: descStyle,
                            ),
                          ),
                          if (tx.isRecurring) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.autorenew,
                              size: 12,
                              color: context.fin.subtle,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    tx.isTransfer
                        ? catLine
                        : InlinePickerCell(
                            key: ValueKey('tx-edit-category-$key'),
                            dense: true,
                            tooltip: 'Alterar categoria',
                            onPick: (cell) =>
                                _pickCategory(cell, fc, tx, onlyRoots: false),
                            display: catLine,
                          ),
                    ?invoiceLink,
                    if (notes.isNotEmpty && layout.shows(GridColumn.notes))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.sticky_note_2_outlined,
                              size: 12,
                              color: context.fin.subtle,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                notes,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: subtle?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 112,
                    child: InlineTextCell(
                      key: ValueKey('tx-edit-amount-$key'),
                      dense: true,
                      right: true,
                      value: tx.amount.formatPlain(),
                      hint: '0,00',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validate: _validateAmount,
                      onSubmit: (v) =>
                          save(tx.copyWith(amount: Money.tryEval(v))),
                      display: money,
                    ),
                  ),
                  const SizedBox(height: 4),
                  status,
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Edição direta na grade (como numa planilha). A compra no cartão
    // mostra a data da fatura, mas a edição altera a data da compra.
    final canCategorize = !tx.isTransfer;
    final catLabel = Row(
      children: [
        _Dot(catColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            showSub || subName.isEmpty ? catName : '$catName › $subName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyMedium,
          ),
        ),
      ],
    );
    final subLabel = Text(
      subName.isEmpty ? '—' : subName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: subName.isEmpty ? subtle : context.text.bodyMedium,
    );

    Widget cell(GridColumn c) => switch (c) {
      GridColumn.date => InlinePickerCell(
        key: ValueKey('tx-edit-date-$key'),
        tooltip: invoice == null ? 'Alterar data' : 'Alterar data da compra',
        onPick: (_) => _pickDate(context, fc, tx),
        display: Text(
          Dates.format(it.date),
          style: context.text.bodySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      GridColumn.dueDate =>
        invoice != null
            ? GridCell(
                child: Tooltip(
                  message: 'Vencimento da fatura',
                  child: Text(
                    Dates.format(invoice.dueDate),
                    style: subtle?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              )
            : InlinePickerCell(
                key: ValueKey('tx-edit-due-$key'),
                tooltip: 'Alterar vencimento',
                onPick: (cell) => _pickDueDate(cell, fc, tx),
                display: Text(
                  tx.dueDate == null ? '—' : Dates.format(tx.dueDate!),
                  style: tx.dueDate == null
                      ? subtle
                      : context.text.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                          color: overdue ? context.fin.negative : null,
                        ),
                ),
              ),
      GridColumn.category =>
        canCategorize
            ? InlinePickerCell(
                key: ValueKey('tx-edit-category-$key'),
                tooltip: 'Alterar categoria',
                onPick: (cell) =>
                    _pickCategory(cell, fc, tx, onlyRoots: showSub),
                display: catLabel,
              )
            : GridCell(child: catLabel),
      GridColumn.subcategory =>
        canCategorize && cat != null
            ? InlinePickerCell(
                key: ValueKey('tx-edit-subcategory-$key'),
                tooltip: 'Alterar subcategoria',
                onPick: (cell) => _pickSubcategory(cell, fc, tx),
                display: subLabel,
              )
            : GridCell(child: subLabel),
      GridColumn.description => InlineTextCell(
        key: ValueKey('tx-edit-description-$key'),
        value: tx.description,
        hint: 'Descrição',
        validate: (v) => v.isEmpty ? 'Informe uma descrição' : null,
        onSubmit: (v) => save(tx.copyWith(description: v)),
        display: Row(
          children: [
            Flexible(
              child: Text(
                desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: descStyle,
              ),
            ),
            if (tx.isRecurring) ...[
              const SizedBox(width: 4),
              Icon(Icons.autorenew, size: 13, color: context.fin.subtle),
            ],
            if (extras.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  extras,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtle,
                ),
              ),
            ],
            if (invoiceLink != null) ...[
              const SizedBox(width: 8),
              Flexible(child: invoiceLink),
            ],
          ],
        ),
      ),
      GridColumn.notes => InlineTextCell(
        key: ValueKey('tx-edit-notes-$key'),
        value: tx.notes,
        hint: 'Observações',
        onSubmit: (v) => save(tx.copyWith(notes: v)),
        display: Text(
          notes.isEmpty ? '—' : notes,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: notes.isEmpty
              ? subtle
              : context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      ),
      GridColumn.amount => InlineTextCell(
        key: ValueKey('tx-edit-amount-$key'),
        value: tx.amount.formatPlain(),
        right: true,
        hint: '0,00',
        background: GridPalette.of(context).valueBg,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validate: _validateAmount,
        onSubmit: (v) => save(tx.copyWith(amount: Money.tryEval(v))),
        display: Opacity(opacity: completed ? 1 : 0.8, child: money),
      ),
      GridColumn.status => GridCell(child: status),
    };

    return GridRowShell(
      accent: accent,
      zebra: index.isOdd,
      dimmed: cancelled,
      height: GridLayout.rowH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (c, w) in layout.cells) SizedBox(width: w, child: cell(c)),
          SizedBox(
            width: GridLayout.actionW,
            child: Center(
              child: IconButton(
                key: ValueKey('tx-open-$key'),
                tooltip: 'Abrir detalhes',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                color: GridPalette.of(context).neon,
                icon: const Icon(Icons.chevron_right),
                onPressed: open,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _invoiceRow(
    BuildContext context,
    _InvoiceEntry it,
    int index,
    GridLayout layout,
  ) {
    final inv = it.invoice;
    final slice = it.slice;
    final p = GridPalette.of(context);
    final n = inv.transactions.length;
    final partial = slice.amount != inv.total && !inv.isCredit;
    final info = [
      '$n ${n == 1 ? 'lançamento' : 'lançamentos'}',
      if (slice.settled)
        'paga ${Dates.formatShort(slice.date)}'
      else
        'vence ${Dates.formatShort(inv.dueDate)}',
      if (partial) 'parte de ${inv.total.format()}',
    ].join(' · ');
    final touch = isTouchPlatform;
    final selected = selectedInvoice == it.key;
    final status = NeonStatus(
      label: invoiceSliceStatus(inv, slice),
      color: invoiceSliceColor(context, inv, slice),
      done: slice.settled && inv.isSettled,
    );
    final money = MoneyText(
      -slice.amount,
      showPlus: slice.amount.isNegative,
      color: slice.amount.isNegative ? context.fin.positive : null,
      style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    final openBtn = IconButton(
      key: ValueKey('invoice-open-${inv.card.id}-${inv.key}'),
      tooltip: 'Abrir fatura',
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      color: p.neon,
      icon: const Icon(Icons.chevron_right),
      onPressed: () => _openInvoice(inv),
    );
    final cardColor = Color(inv.card.color);
    final linkStyle = context.text.bodyMedium?.copyWith(
      color: p.neon,
      fontWeight: FontWeight.w600,
    );
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final title = Text(
      inv.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    );

    if (layout.compact) {
      return GridRowShell(
        key: ValueKey('invoice-${inv.card.id}-${inv.key}'),
        accent: cardColor,
        zebra: index.isOdd,
        selected: selected,
        onTap: touch ? () => _openInvoice(inv) : () => _select(it),
        onDoubleTap: touch ? null : () => _openInvoice(inv),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 0, 5),
          child: Row(
            children: [
              _DateBadge(it.date),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.credit_card, size: 12, color: cardColor),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            info,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: subtle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [money, const SizedBox(height: 4), status],
              ),
              openBtn,
            ],
          ),
        ),
      );
    }

    final showSub = layout.shows(GridColumn.subcategory);
    Widget cell(GridColumn c) => switch (c) {
      GridColumn.date => GridCell(
        child: Text(
          Dates.format(it.date),
          style: context.text.bodySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      GridColumn.dueDate => GridCell(
        child: Text(
          Dates.format(inv.dueDate),
          style: context.text.bodySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      GridColumn.category => GridCell(
        child: Row(
          children: [
            Icon(Icons.credit_card, size: 14, color: cardColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                showSub ? 'Cartão' : 'Cartão › ${inv.card.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: linkStyle,
              ),
            ),
          ],
        ),
      ),
      GridColumn.subcategory => GridCell(
        child: Text(
          inv.card.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodyMedium,
        ),
      ),
      GridColumn.description => GridCell(
        child: Row(
          children: [
            Flexible(flex: 3, child: title),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text(
                info,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtle,
              ),
            ),
          ],
        ),
      ),
      GridColumn.notes => GridCell(child: Text('—', style: subtle)),
      GridColumn.amount => GridCell(
        right: true,
        background: p.valueBg,
        child: money,
      ),
      GridColumn.status => GridCell(child: status),
    };

    return GridRowShell(
      key: ValueKey('invoice-${inv.card.id}-${inv.key}'),
      accent: cardColor,
      zebra: index.isOdd,
      selected: selected,
      height: GridLayout.rowH,
      onTap: touch ? () => _openInvoice(inv) : () => _select(it),
      onDoubleTap: touch ? null : () => _openInvoice(inv),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (c, w) in layout.cells) SizedBox(width: w, child: cell(c)),
          SizedBox(
            width: GridLayout.actionW,
            child: Center(child: openBtn),
          ),
        ],
      ),
    );
  }

  Future<void> _saveInline(
    BuildContext context,
    FinanceController fc,
    FinTransaction t,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await fc.saveInline(t);
    } catch (e) {
      final msg = e is ArgumentError ? '${e.message}' : '$e';
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível salvar: $msg')),
      );
    }
  }

  static String? _validateAmount(String v) {
    final m = Money.tryEval(v);
    if (m == null) return 'Valor inválido';
    if (m.cents <= 0) return 'O valor deve ser maior que zero';
    return null;
  }

  Future<void> _pickDate(
    BuildContext context,
    FinanceController fc,
    FinTransaction tx,
  ) async {
    final d = await showDatePicker(
      context: context,
      initialDate: tx.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(fc.today.year + 30),
      locale: const Locale('pt', 'BR'),
    );
    if (d == null || !context.mounted) return;
    if (Dates.dateOnly(d) == Dates.dateOnly(tx.date)) return;
    await _saveInline(context, fc, tx.copyWith(date: d));
  }

  /// Vencimento do lançamento. Sem vencimento, abre direto o calendário;
  /// com vencimento, oferece alterar ou remover.
  Future<void> _pickDueDate(
    BuildContext cell,
    FinanceController fc,
    FinTransaction tx,
  ) async {
    if (tx.dueDate != null) {
      final action = await showCellMenu(cell, const [
        CellMenuOption('change', 'Alterar vencimento'),
        CellMenuOption('clear', 'Remover vencimento'),
      ]);
      if (action == null || !cell.mounted) return;
      if (action == 'clear') {
        await _saveInline(cell, fc, tx.copyWith(dueDate: null));
        return;
      }
    }
    final d = await showDatePicker(
      context: cell,
      initialDate: tx.dueDate ?? tx.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(fc.today.year + 30),
      helpText: 'Data de vencimento',
      locale: const Locale('pt', 'BR'),
    );
    if (d == null || !cell.mounted) return;
    final due = Dates.dateOnly(d);
    if (tx.dueDate != null && due == Dates.dateOnly(tx.dueDate!)) return;
    await _saveInline(cell, fc, tx.copyWith(dueDate: due));
  }

  /// Categorias do tipo do lançamento. Com a coluna Subcategoria visível,
  /// a coluna Categoria lista só as principais; sem ela, mostra a árvore.
  Future<void> _pickCategory(
    BuildContext cell,
    FinanceController fc,
    FinTransaction tx, {
    required bool onlyRoots,
  }) async {
    final kind = tx.type == TransactionType.income
        ? CategoryKind.income
        : CategoryKind.expense;
    List<FinCategory> sorted(bool Function(FinCategory) test) =>
        fc.data.categories.where(test).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    final current = fc.data.categoryById[tx.categoryId];
    final rootId = current?.parentId ?? current?.id;
    final picked = await showCellMenu(cell, [
      for (final r in sorted((c) => c.kind == kind && c.parentId == null)) ...[
        CellMenuOption(
          r.id,
          r.name,
          color: Color(r.color),
          selected: onlyRoots ? r.id == rootId : r.id == tx.categoryId,
        ),
        if (!onlyRoots)
          for (final s in sorted((c) => c.parentId == r.id))
            CellMenuOption(
              s.id,
              s.name,
              indent: true,
              selected: s.id == tx.categoryId,
            ),
      ],
    ]);
    if (picked == null || !cell.mounted) return;
    // Mesma categoria principal: mantém a subcategoria escolhida.
    if (picked == tx.categoryId || (onlyRoots && picked == rootId)) return;
    await _saveInline(cell, fc, tx.copyWith(categoryId: picked));
  }

  Future<void> _pickSubcategory(
    BuildContext cell,
    FinanceController fc,
    FinTransaction tx,
  ) async {
    final current = fc.data.categoryById[tx.categoryId];
    final root = fc.data.categoryById[current?.parentId] ?? current;
    if (root == null) return;
    final subs = fc.data.categories.where((c) => c.parentId == root.id).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (subs.isEmpty) {
      ScaffoldMessenger.of(cell).showSnackBar(
        SnackBar(content: Text('${root.name} não tem subcategorias')),
      );
      return;
    }
    final picked = await showCellMenu(cell, [
      CellMenuOption(
        root.id,
        'Nenhuma (só ${root.name})',
        selected: tx.categoryId == root.id,
      ),
      for (final s in subs)
        CellMenuOption(s.id, s.name, selected: s.id == tx.categoryId),
    ]);
    if (picked == null || picked == tx.categoryId || !cell.mounted) return;
    await _saveInline(cell, fc, tx.copyWith(categoryId: picked));
  }

  void _select(_InvoiceEntry it) => setState(() => selectedInvoice = it.key);

  void _openInvoice(Invoice inv) {
    setState(() => selectedInvoice = '${inv.card.id}|${inv.key}');
    push(context, InvoiceDetailsScreen(cardId: inv.card.id, month: inv.month));
  }

  /// Lista de status do lançamento, aberta logo abaixo da célula.
  Future<void> _pickStatus(
    BuildContext cell,
    FinanceController fc,
    FinTransaction tx,
  ) async {
    final messenger = ScaffoldMessenger.of(cell);
    final picked = await showCellMenu(cell, [
      for (final s in TransactionStatus.values)
        CellMenuOption(
          s,
          statusOptionLabel(s, tx.type),
          color: statusOptionColor(cell, s),
          selected: s == tx.status,
        ),
    ]);
    if (picked == null || picked == tx.status || !cell.mounted) return;
    try {
      await fc.setStatusInline(tx, picked);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível alterar o status: $e')),
      );
    }
  }
}

/// Rótulo do status na lista suspensa ("Paga"/"Recebida" para concluída).
String statusOptionLabel(TransactionStatus s, TransactionType type) =>
    switch (s) {
      TransactionStatus.planned => 'Prevista',
      TransactionStatus.pending => 'Pendente',
      TransactionStatus.completed => switch (type) {
        TransactionType.income => 'Recebida',
        TransactionType.expense => 'Paga',
        TransactionType.transfer => 'Concluída',
      },
      TransactionStatus.cancelled => 'Cancelada',
    };

Color statusOptionColor(BuildContext context, TransactionStatus s) =>
    switch (s) {
      TransactionStatus.planned => context.colors.primary,
      TransactionStatus.pending => context.fin.warning,
      TransactionStatus.completed => context.fin.positive,
      TransactionStatus.cancelled => context.fin.subtle,
    };

typedef _Cols = ({String category, String sub, String desc, String notes});

/// Item da lista: lançamento (ou parte de uma compra no cartão) ou fatura.
sealed class _Entry {
  DateTime get date;
  DateTime get createdAt;
}

class _TxEntry extends _Entry {
  final FinTransaction tx;
  @override
  final DateTime date;

  /// Valor exibido (parte da compra quando a fatura foi paga em partes).
  final Money amount;

  /// Compra no cartão exibida individualmente (mostra a fatura).
  final bool isCard;
  _TxEntry(this.tx, this.date, this.amount, {this.isCard = false});
  @override
  DateTime get createdAt => tx.createdAt;
}

class _InvoiceEntry extends _Entry {
  final Invoice invoice;
  final InvoiceSlice slice;
  _InvoiceEntry(this.invoice, this.slice);
  String get key => '${invoice.card.id}|${invoice.key}';
  @override
  DateTime get date => slice.date;
  @override
  DateTime get createdAt => invoice.dueDate;
}

class _Total extends StatelessWidget {
  final String label;
  final Money value;
  final Color color;
  final Money open;
  const _Total(this.label, this.value, this.color, this.open);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: context.text.labelSmall?.copyWith(color: context.fin.subtle),
      ),
      MoneyText(value, style: context.text.titleSmall?.copyWith(color: color)),
      Text(
        open.isZero ? 'Tudo concluído' : 'Pendente ${open.format()}',
        style: context.text.labelSmall?.copyWith(
          color: open.isZero ? context.fin.subtle : context.fin.warning,
        ),
      ),
    ],
  );
}

/// Barra de filtros rápidos: seção (receitas/despesas) e status.
class _QuickFilters extends StatelessWidget {
  final QuickType type;
  final QuickStatus status;
  final ValueChanged<QuickType> onType;
  final ValueChanged<QuickStatus> onStatus;
  const _QuickFilters({
    required this.type,
    required this.status,
    required this.onType,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap, {Key? key}) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            key: key,
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onTap(),
          ),
        );
    // Em telas estreitas os dois grupos quebram em duas linhas.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final t in QuickType.values)
                chip(
                  t.label,
                  type == t,
                  () => onType(t),
                  key: ValueKey('qt-${t.name}'),
                ),
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.only(left: 2, right: 8),
                color: context.colors.outlineVariant,
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in QuickStatus.values)
                chip(
                  s.label,
                  status == s,
                  () => onStatus(s),
                  key: ValueKey('qs-${s.name}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final FinanceController fc;
  final TxListFilter initial;
  const _FilterSheet({required this.fc, required this.initial});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<TransactionType> types = {...widget.initial.types};
  late Set<TransactionStatus> statuses = {...widget.initial.statuses};
  late String? loc = widget.initial.accountOrCard;
  late String? cat = widget.initial.categoryId;
  late String? prj = widget.initial.projectId;

  @override
  Widget build(BuildContext context) {
    final fc = widget.fc;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtrar transações', style: context.text.titleLarge),
            const SizedBox(height: 16),
            Text('Tipo', style: context.text.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                for (final t in TransactionType.values)
                  FilterChip(
                    label: Text(t.label),
                    selected: types.contains(t),
                    onSelected: (s) =>
                        setState(() => s ? types.add(t) : types.remove(t)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Status', style: context.text.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                for (final s in TransactionStatus.values)
                  FilterChip(
                    label: Text(s.label),
                    selected: statuses.contains(s),
                    onSelected: (v) => setState(
                      () => v ? statuses.add(s) : statuses.remove(s),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: loc,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Conta ou cartão'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                for (final a in fc.data.accounts)
                  DropdownMenuItem(value: 'a:${a.id}', child: Text(a.name)),
                for (final c in fc.data.cards)
                  DropdownMenuItem(value: 'c:${c.id}', child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => loc = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: cat,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                for (final c in fc.data.categories)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(fc.engine.categoryLabel(c.id)),
                  ),
              ],
              onChanged: (v) => setState(() => cat = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: prj,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Projeto'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                for (final p in fc.data.projects)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => prj = v),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, const TxListFilter()),
                  child: const Text('Limpar'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    TxListFilter(
                      types: types,
                      statuses: statuses,
                      accountOrCard: loc,
                      categoryId: cat,
                      projectId: prj,
                    ),
                  ),
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Data compacta (dia/mês + dia da semana) das linhas no celular.
class _DateBadge extends StatelessWidget {
  final DateTime date;
  const _DateBadge(this.date);

  @override
  Widget build(BuildContext context) {
    const wd = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
    final p = GridPalette.of(context);
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: p.neon.withValues(alpha: 0.07),
        border: Border.all(color: p.neon.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Dates.formatShort(date),
            style: context.text.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            wd[date.weekday - 1].toUpperCase(),
            style: context.text.labelSmall?.copyWith(
              color: p.neon,
              fontSize: 9,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ponto luminoso com a cor da categoria.
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
