import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/entry_origin.dart';
import '../../widgets/sort_grid.dart';
import '../../widgets/tx_grid.dart';
import '../transactions/transaction_details_screen.dart';
import 'month_closing_ui.dart';
import '../transactions/transactions_screen.dart'
    show statusOptionColor, statusOptionLabel;

enum DrillRow {
  income('Receitas'),
  expenses('Despesas'),
  net('Resultado');

  final String label;
  const DrillRow(this.label);
}

/// Linha da grade-resumo do primeiro nível do detalhamento.
class _Group {
  final String key; // 'a:id' | 'c:id' | id da categoria principal
  final String label;
  final String kind;
  final IconData icon;
  final Color color;
  final Money sum;
  final int count;
  const _Group({
    required this.key,
    required this.label,
    required this.kind,
    required this.icon,
    required this.color,
    required this.sum,
    required this.count,
  });
}

/// Detalhamento de um valor da matriz.
///
/// Navegação: total do mês → grade-resumo por conta/cartão (ou por
/// categoria, pelo botão) → grade de lançamentos, igual à de Transações.
/// Usa exatamente os mesmos filtros e regras de reconhecimento da matriz
/// ([FinancialEngine.monthEvents]).
class DrilldownScreen extends StatefulWidget {
  final YearMonth month;
  final DrillRow row;
  final ProjectionFilter filter;
  final String? rootCategoryId; // grade de uma categoria
  final bool allCategories; // grade de todas as categorias
  final String? locationKey; // recorte por conta/cartão ('a:id' | 'c:id')
  const DrilldownScreen({
    super.key,
    required this.month,
    required this.row,
    this.filter = ProjectionFilter.none,
    this.rootCategoryId,
    this.allCategories = false,
    this.locationKey,
  });

  @override
  State<DrilldownScreen> createState() => _DrilldownScreenState();
}

class _DrilldownScreenState extends State<DrilldownScreen> {
  EventSource? source;

  /// Primeiro nível agrupado por categoria (em vez de conta/cartão).
  /// Lembrado enquanto o app estiver aberto.
  static bool _byCategory = false;

  /// Ordenação da grade (clique no cabeçalho da coluna).
  GridColumn sort = GridColumn.date;
  bool ascending = true;
  GridColumnsConfig? _draftColumns;
  GridLayout? _lastLayout;
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  bool get _isGrid =>
      widget.allCategories ||
      widget.rootCategoryId != null ||
      widget.locationKey != null;

  bool _rowMatch(RecognizedEvent e) => switch (widget.row) {
    DrillRow.income => e.isIncome,
    DrillRow.expenses => e.isExpense,
    DrillRow.net => true,
  };

  Money _value(RecognizedEvent e) =>
      widget.row == DrillRow.expenses ? -e.signed : e.signed;

  String _locKey(FinTransaction t) =>
      t.cardId != null ? 'c:${t.cardId}' : 'a:${t.accountId}';

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final all = e
        .monthEvents(widget.filter, widget.month)
        .where(_rowMatch)
        .where(
          (x) =>
              widget.rootCategoryId == null ||
              e.rootCategoryId(x.tx.categoryId) == widget.rootCategoryId,
        )
        .where(
          (x) =>
              widget.locationKey == null || _locKey(x.tx) == widget.locationKey,
        )
        .toList();
    final events = source == null
        ? all
        : all.where((x) => x.source == source).toList();
    final total = events.map(_value).sum();
    final closing = source == null
        ? e.closingFor(widget.filter, widget.month)
        : null;
    final closedValue = closing == null
        ? null
        : switch (widget.row) {
            DrillRow.income => closing.income,
            DrillRow.expenses => closing.expenses,
            DrillRow.net => closing.net,
          };

    final crumbs = [
      if (widget.allCategories) 'Todas as categorias',
      if (widget.rootCategoryId != null)
        e.data.categoryById[widget.rootCategoryId]?.name ?? 'Sem categoria',
      if (widget.locationKey != null) _locationName(e, widget.locationKey!),
    ];
    final title = crumbs.isEmpty
        ? '${widget.row.label} · ${widget.month.shortLabel}'
        : crumbs.last;

    // Resumo por origem (sempre sobre o conjunto do nível).
    final bySource = <EventSource, Money>{};
    for (final x in all) {
      bySource[x.source] = (bySource[x.source] ?? Money.zero) + _value(x);
    }

    final summary = [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.month.longLabel} — ${widget.row.label}',
              style: context.text.bodyMedium?.copyWith(
                color: context.fin.subtle,
              ),
            ),
            const SizedBox(height: 4),
            MoneyText(
              total,
              colorize: widget.row == DrillRow.net,
              style: context.text.headlineMedium,
            ),
            if (crumbs.isNotEmpty)
              Text(
                crumbs.join(' › '),
                style: context.text.labelMedium?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
            if (closing != null && !_isGrid) ...[
              const SizedBox(height: 8),
              Card(
                key: const ValueKey('drill-closing'),
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    closing.isAdjusted ? Icons.tune : Icons.lock,
                    color: context.colors.primary,
                  ),
                  title: Text(
                    closing.isAdjusted
                        ? 'Mês fechado com ajuste manual'
                        : 'Mês fechado',
                  ),
                  subtitle: Text(
                    'Vale ${closedValue!.format()} (lançamentos abaixo: '
                    '${total.format()}). Toque para ajustar ou reabrir.',
                  ),
                  onTap: () => showMonthClosingActions(context, widget.month),
                ),
              ),
            ],
          ],
        ),
      ),
      if (bySource.length > 1 || source != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in EventSource.values)
                if (bySource.containsKey(s))
                  FilterChip(
                    label: Text('${s.label}: ${bySource[s]!.format()}'),
                    selected: source == s,
                    onSelected: (v) => setState(() => source = v ? s : null),
                  ),
            ],
          ),
        ),
    ];
    const empty = EmptyState(
      icon: Icons.insights_outlined,
      title: 'Nenhum lançamento',
      message: 'Não há valores para este recorte.',
    );

    if (_isGrid) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...summary,
            Expanded(
              child: events.isEmpty ? empty : _grid(context, fc, events),
            ),
          ],
        ),
      );
    }

    final groups = _groups(e, events);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ...summary,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  key: const ValueKey('drill-group-toggle'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      label: Text('Conta e cartão'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.category_outlined),
                      label: Text('Categoria'),
                    ),
                  ],
                  selected: {_byCategory},
                  onSelectionChanged: (s) =>
                      setState(() => _byCategory = s.first),
                ),
                if (events.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('drill-total'),
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: Text('Ver todos os ${events.length} lançamentos'),
                    onPressed: () => push(
                      context,
                      DrilldownScreen(
                        month: widget.month,
                        row: widget.row,
                        filter: widget.filter,
                        allCategories: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (events.isEmpty)
            empty
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _groupGrid(context, groups, total),
            ),
        ],
      ),
    );
  }

  /// Agrupamento do primeiro nível: por conta/cartão (padrão) ou por
  /// categoria principal.
  List<_Group> _groups(FinancialEngine e, List<RecognizedEvent> events) {
    final sums = <String, Money>{};
    final counts = <String, int>{};
    for (final x in events) {
      final k = _byCategory ? e.rootCategoryId(x.tx.categoryId) : _locKey(x.tx);
      sums[k] = (sums[k] ?? Money.zero) + _value(x);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return [
      for (final k in sums.keys)
        if (_byCategory)
          () {
            final c = e.data.categoryById[k];
            return _Group(
              key: k,
              label: c?.name ?? 'Sem categoria',
              kind: 'Categoria',
              icon: categoryIcon(c?.icon),
              color: Color(c?.color ?? 0xFF6B7280),
              sum: sums[k]!,
              count: counts[k]!,
            );
          }()
        else
          () {
            final isCard = k.startsWith('c:');
            final id = k.substring(2);
            final color = isCard
                ? e.data.cardById[id]?.color
                : e.data.accountById[id]?.color;
            return _Group(
              key: k,
              label: _locationName(e, k),
              kind: isCard ? 'Cartão' : 'Conta',
              icon: isCard ? Icons.credit_card : Icons.account_balance_outlined,
              color: Color(color ?? 0xFF6B7280),
              sum: sums[k]!,
              count: counts[k]!,
            );
          }(),
    ];
  }

  void _openGroup(_Group g) => push(
    context,
    DrilldownScreen(
      month: widget.month,
      row: widget.row,
      filter: widget.filter,
      rootCategoryId: _byCategory ? g.key : null,
      locationKey: _byCategory ? null : g.key,
    ),
  );

  /// Grade-resumo do primeiro nível, no mesmo padrão das demais grades.
  Widget _groupGrid(BuildContext context, List<_Group> groups, Money total) {
    final denom = total.cents.abs() == 0 ? 1 : total.cents.abs();
    double share(_Group g) => (g.sum.cents.abs() / denom).clamp(0.0, 1.0);
    String pct(_Group g) => '${(share(g) * 100).toStringAsFixed(0)}%';
    int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    final colorize = widget.row == DrillRow.net;
    final count = groups.fold<int>(0, (s, g) => s + g.count);
    final bold = context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700);
    final tab = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget avatar(_Group g, {double size = 28}) => CircleAvatar(
      radius: size / 2,
      backgroundColor: g.color.withValues(alpha: 0.14),
      child: Icon(g.icon, color: g.color, size: size * 0.55),
    );

    Widget bar(_Group g) => ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: share(g),
        minHeight: 6,
        color: g.color,
        backgroundColor: context.fin.gridLine,
      ),
    );

    return SortGrid<_Group>(
      key: ValueKey('drill-groups-$_byCategory'),
      keyPrefix: 'drill-group',
      rows: groups,
      rowId: (g) => g.key,
      accent: (context, g) => g.color,
      onOpen: _openGroup,
      initialSort: 'value',
      initialAscending: false,
      compactBelow: 640,
      tieBreak: (a, b) => text(a.label, b.label),
      compactRow: (context, g) => Row(
        children: [
          avatar(g),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  g.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: bar(g)),
                    const SizedBox(width: 8),
                    Text(
                      '${pct(g)} · ${g.count} itens',
                      style: context.text.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MoneyText(g.sum, colorize: colorize, style: bold),
        ],
      ),
      footerLabel: (context, rows) =>
          Text('Total · $count itens', style: gridFooterLabelStyle(context)),
      compactFooter: (context, rows) =>
          MoneyText(total, colorize: colorize, style: bold),
      columns: [
        SortCol(
          id: 'name',
          label: _byCategory ? 'Categoria' : 'Conta / cartão',
          width: 220,
          minWidth: 150,
          flexible: true,
          fill: true,
          compare: (a, b) => text(a.label, b.label),
          cell: (context, g) => GridCell(
            child: Row(
              children: [
                avatar(g, size: 24),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    g.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!_byCategory)
          SortCol(
            id: 'kind',
            label: 'Tipo',
            width: 90,
            compare: (a, b) => text(a.kind, b.kind),
            cell: (context, g) =>
                GridCell(child: Text(g.kind, style: context.text.bodySmall)),
          ),
        SortCol(
          id: 'count',
          label: 'Itens',
          width: 80,
          right: true,
          compare: (a, b) => a.count.compareTo(b.count),
          cell: (context, g) =>
              GridCell(right: true, child: Text('${g.count}', style: tab)),
          footer: (context, rows) => Text('$count', style: tab),
        ),
        SortCol(
          id: 'share',
          label: '% do total',
          width: 170,
          minWidth: 120,
          flexible: true,
          compare: (a, b) => share(a).compareTo(share(b)),
          cell: (context, g) => GridCell(
            child: Row(
              children: [
                Expanded(child: bar(g)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(pct(g), textAlign: TextAlign.right, style: tab),
                ),
              ],
            ),
          ),
        ),
        SortCol(
          id: 'value',
          label: 'Valor',
          width: 130,
          right: true,
          highlight: true,
          compare: (a, b) => a.sum.cents.abs().compareTo(b.sum.cents.abs()),
          cell: (context, g) => GridCell(
            right: true,
            child: MoneyText(g.sum, colorize: colorize, style: bold),
          ),
          footer: (context, rows) =>
              MoneyText(total, colorize: colorize, style: bold),
        ),
      ],
    );
  }

  String _locationName(FinancialEngine e, String key) {
    final id = key.substring(2);
    return key.startsWith('c:')
        ? (e.data.cardById[id]?.name ?? 'Cartão')
        : (e.data.accountById[id]?.name ?? 'Sem conta');
  }

  // ---------------------------------------------------------------------
  // Grade de lançamentos (mesmas colunas e aparência de Transações).

  GridColumnsConfig _columns(FinanceController fc) =>
      _draftColumns ??
      GridColumnsConfig.fromJson(fc.data.settings.txGridColumns);

  Widget _grid(
    BuildContext context,
    FinanceController fc,
    List<RecognizedEvent> events,
  ) {
    final e = fc.engine;
    final items = [...events];
    _sortItems(items, e);
    return LayoutBuilder(
      builder: (context, box) {
        final pad = box.maxWidth < 640 ? 8.0 : 16.0;
        final layout = GridLayout.of(
          box.maxWidth - 2 * pad - 2,
          _columns(fc).showingIf(GridColumn.holder, fc.data.hasDependents),
        );
        _lastLayout = layout;
        final list = ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: items.length,
          itemBuilder: (context, i) => _row(context, fc, items[i], i, layout),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
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
                              onResizeEnd: () => _saveColumns(fc, _columns(fc)),
                              onConfigure: () => _configureColumns(fc),
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
    );
  }

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
      // Valores começam do maior; datas e textos, do primeiro.
      ascending = s != GridColumn.amount;
    }
  });

  /// Categoria, subcategoria, descrição e observações de um lançamento.
  static ({String category, String sub, String desc, String notes}) _cols(
    FinancialEngine e,
    FinTransaction tx,
  ) {
    final notes = tx.notes.trim();
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

  /// Vencimento: o da fatura para compras no cartão; o do lançamento nos
  /// demais casos (vazio quando não informado).
  static DateTime? _due(FinancialEngine e, FinTransaction tx) =>
      tx.cardId != null ? e.invoiceOf(tx)?.dueDate : tx.shownDueDate;

  static int _statusRank(FinancialEngine e, FinTransaction tx) =>
      switch (tx.status) {
        TransactionStatus.completed => 3,
        TransactionStatus.cancelled => 4,
        TransactionStatus.planned => 2,
        TransactionStatus.pending => e.isOverdue(tx) ? 0 : 1,
      };

  void _sortItems(List<RecognizedEvent> items, FinancialEngine e) {
    int text(
      String Function(RecognizedEvent) f,
      RecognizedEvent a,
      RecognizedEvent b,
    ) => f(a).toLowerCase().compareTo(f(b).toLowerCase());
    int cmp(RecognizedEvent a, RecognizedEvent b) {
      if (sort == GridColumn.category) {
        return text((x) => _cols(e, x.tx).category, a, b);
      }
      if (sort == GridColumn.subcategory) {
        return text((x) => _cols(e, x.tx).sub, a, b);
      }
      if (sort == GridColumn.description) {
        return text((x) => x.tx.description, a, b);
      }
      if (sort == GridColumn.notes) return text((x) => x.tx.notes, a, b);
      if (sort == GridColumn.amount) {
        return _value(a).cents.abs().compareTo(_value(b).cents.abs());
      }
      if (sort == GridColumn.dueDate) {
        return (_due(e, a.tx) ?? a.date).compareTo(_due(e, b.tx) ?? b.date);
      }
      if (sort == GridColumn.kind) {
        return EntryOrigin.of(a.tx).label.compareTo(EntryOrigin.of(b.tx).label);
      }
      if (sort == GridColumn.status) {
        return _statusRank(e, a.tx).compareTo(_statusRank(e, b.tx));
      }
      if (sort == GridColumn.holder) {
        return e.data.holderName(a.tx).compareTo(e.data.holderName(b.tx));
      }
      return a.date.compareTo(b.date);
    }

    items.sort((a, b) {
      final c = ascending ? cmp(a, b) : cmp(b, a);
      return c != 0 ? c : a.date.compareTo(b.date);
    });
  }

  Widget _row(
    BuildContext context,
    FinanceController fc,
    RecognizedEvent ev,
    int index,
    GridLayout layout,
  ) {
    final e = fc.engine;
    final tx = ev.tx;
    final (category: catName, sub: subName, :desc, :notes) = _cols(e, tx);
    final showSub = layout.shows(GridColumn.subcategory);
    final cat = e.data.categoryById[tx.categoryId];
    final catColor = Color(cat?.color ?? context.fin.subtle.toARGB32());
    final isIncome = ev.isIncome;
    final accent = isIncome ? context.fin.positive : context.fin.expense;
    final cancelled = tx.status == TransactionStatus.cancelled;
    final completed = tx.status == TransactionStatus.completed;
    final overdue = e.isOverdue(tx);
    final due = _due(e, tx);
    final (statusLabel, statusColor) = cancelled
        ? ('Cancelada', context.fin.subtle)
        : completed
        ? (isIncome ? 'Recebida' : 'Paga', context.fin.positive)
        : overdue
        ? ('Atrasada', context.fin.negative)
        : tx.status == TransactionStatus.planned
        ? ('Prevista', context.colors.primary)
        : ('Pendente', context.fin.warning);
    // Compras no cartão seguem o status da fatura.
    final canPick = tx.cardId == null;
    final status = Builder(
      builder: (cell) => NeonStatus(
        key: ValueKey('drill-status-${tx.id}-${tx.date.toIso8601String()}'),
        label: statusLabel,
        color: statusColor,
        done: completed,
        dropdown: canPick,
        tooltip: canPick ? 'Alterar status' : null,
        onTap: canPick ? () => _pickStatus(cell, fc, tx) : null,
      ),
    );
    final money = MoneyText(
      ev.signed,
      showPlus: isIncome,
      color: isIncome ? context.fin.positive : null,
      style: context.text.bodyMedium?.copyWith(
        fontWeight: FontWeight.w700,
        decoration: cancelled ? TextDecoration.lineThrough : null,
      ),
    );
    final extras = [
      if (tx.isInstallment) tx.installmentLabel,
      if (tx.cardId != null) 'compra ${Dates.formatShort(tx.date)}',
      if (tx.dueDate != null &&
          Dates.dateOnly(tx.dueDate!) != Dates.dateOnly(tx.date) &&
          (layout.compact || !layout.shows(GridColumn.dueDate)))
        'vence ${Dates.formatShort(tx.dueDate!)}',
      if (widget.locationKey == null) e.locationLabel(tx),
    ].where((s) => s.isNotEmpty).join(' · ');
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final descStyle = context.text.bodyMedium?.copyWith(
      fontWeight: layout.compact ? FontWeight.w600 : null,
      decoration: cancelled ? TextDecoration.lineThrough : null,
    );
    final catText = subName.isEmpty || showSub
        ? catName
        : '$catName › $subName';
    void open() => push(context, TransactionDetailsScreen(tx: tx));
    final key = '${tx.id}-${tx.date.toIso8601String()}';

    if (layout.compact) {
      return GridRowShell(
        key: ValueKey('drill-row-$key'),
        accent: accent,
        zebra: index.isOdd,
        dimmed: cancelled,
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  Dates.formatShort(ev.date),
                  style: context.text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: descStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        subName.isEmpty ? catName : '$catName › $subName',
                        if (extras.isNotEmpty) extras,
                      ].join(' · '),
                      maxLines: 1,
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
                children: [money, const SizedBox(height: 4), status],
              ),
            ],
          ),
        ),
      );
    }

    Widget text(String s, {TextStyle? style}) => GridCell(
      child: Text(
        s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style ?? context.text.bodyMedium,
      ),
    );

    Widget cell(GridColumn c) {
      if (c == GridColumn.date) {
        return GridCell(
          child: Text(
            Dates.format(ev.date),
            style: context.text.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      if (c == GridColumn.dueDate) {
        return GridCell(
          child: Text(
            due == null ? '—' : Dates.format(due),
            style: due == null
                ? subtle
                : context.text.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: overdue ? context.fin.negative : null,
                  ),
          ),
        );
      }
      if (c == GridColumn.category) {
        return GridCell(
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: catColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  catText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium,
                ),
              ),
            ],
          ),
        );
      }
      if (c == GridColumn.subcategory) {
        return text(
          subName.isEmpty ? '—' : subName,
          style: subName.isEmpty ? subtle : null,
        );
      }
      if (c == GridColumn.description) {
        return GridCell(
          child: Row(
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
            ],
          ),
        );
      }
      if (c == GridColumn.notes) {
        return text(
          notes.isEmpty ? '—' : notes,
          style: notes.isEmpty
              ? subtle
              : context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        );
      }
      if (c == GridColumn.amount) {
        return GridCell(
          right: true,
          background: GridPalette.of(context).valueBg,
          child: Opacity(opacity: completed ? 1 : 0.8, child: money),
        );
      }
      if (c == GridColumn.status) return GridCell(child: status);
      if (c == GridColumn.kind) {
        return GridCell(child: EntryOriginLabel(EntryOrigin.of(tx)));
      }
      if (c == GridColumn.holder) {
        return text(
          tx.isTransfer ? '—' : fc.data.holderName(tx),
          style: tx.holderId == null ? subtle : null,
        );
      }
      return const GridCell(child: SizedBox.shrink());
    }

    return GridRowShell(
      key: ValueKey('drill-row-$key'),
      accent: accent,
      zebra: index.isOdd,
      dimmed: cancelled,
      height: GridLayout.rowH,
      onTap: open,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (c, w) in layout.cells) SizedBox(width: w, child: cell(c)),
          SizedBox(
            width: GridLayout.actionW,
            child: Center(
              child: IconButton(
                tooltip: 'Abrir detalhes',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.chevron_right),
                onPressed: open,
              ),
            ),
          ),
        ],
      ),
    );
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
