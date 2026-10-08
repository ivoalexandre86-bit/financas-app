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
import '../../widgets/tx_grid.dart';
import '../transactions/transaction_details_screen.dart';
import '../transactions/transactions_screen.dart'
    show statusOptionColor, statusOptionLabel;

enum DrillRow {
  income('Receitas'),
  expenses('Despesas'),
  net('Resultado');

  final String label;
  const DrillRow(this.label);
}

/// Detalhamento de um valor da matriz.
///
/// Navegação: total do mês → categorias (com a linha "Total", que abre
/// todas) → grade de lançamentos, igual à de Transações.
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

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ...summary,
          if (events.isEmpty)
            empty
          else ...[
            _totalTile(context, total, events.length),
            ..._groupList(
              context,
              events,
              keyOf: (x) => e.rootCategoryId(x.tx.categoryId),
              labelOf: (k) => e.data.categoryById[k]?.name ?? 'Sem categoria',
              iconOf: (k) {
                final c = e.data.categoryById[k];
                return (categoryIcon(c?.icon), Color(c?.color ?? 0xFF6B7280));
              },
              onTap: (k) => push(
                context,
                DrilldownScreen(
                  month: widget.month,
                  row: widget.row,
                  filter: widget.filter,
                  rootCategoryId: k,
                ),
              ),
              total: total,
            ),
          ],
        ],
      ),
    );
  }

  String _locationName(FinancialEngine e, String key) {
    final id = key.substring(2);
    return key.startsWith('c:')
        ? (e.data.cardById[id]?.name ?? 'Cartão')
        : (e.data.accountById[id]?.name ?? 'Sem conta');
  }

  /// Linha "Total": abre a grade com os lançamentos de todas as categorias.
  Widget _totalTile(BuildContext context, Money total, int count) {
    final color = context.colors.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const ValueKey('drill-total'),
          onTap: () => push(
            context,
            DrilldownScreen(
              month: widget.month,
              row: widget.row,
              filter: widget.filter,
              allCategories: true,
            ),
          ),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(Icons.functions, color: color, size: 20),
          ),
          title: Text(
            'Total',
            style: context.text.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'Todas as categorias · $count itens',
            style: context.text.labelSmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MoneyText(
                total,
                colorize: widget.row == DrillRow.net,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  List<Widget> _groupList(
    BuildContext context,
    List<RecognizedEvent> events, {
    required String Function(RecognizedEvent) keyOf,
    required String Function(String) labelOf,
    required (IconData, Color) Function(String) iconOf,
    required void Function(String) onTap,
    required Money total,
  }) {
    final sums = <String, Money>{};
    final counts = <String, int>{};
    for (final x in events) {
      final k = keyOf(x);
      sums[k] = (sums[k] ?? Money.zero) + _value(x);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final keys = sums.keys.toList()
      ..sort((a, b) => sums[b]!.cents.abs().compareTo(sums[a]!.cents.abs()));
    final denom = total.cents.abs() == 0 ? 1 : total.cents.abs();
    return [
      for (final k in keys)
        () {
          final (icon, color) = iconOf(k);
          final share = (sums[k]!.cents.abs() / denom).clamp(0.0, 1.0);
          return ListTile(
            onTap: () => onTap(k),
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color, size: 20),
            ),
            title: Text(labelOf(k)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 6,
                        color: color,
                        backgroundColor: context.fin.gridLine,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${(share * 100).toStringAsFixed(0)}% · ${counts[k]} itens',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoneyText(
                  sums[k]!,
                  colorize: widget.row == DrillRow.net,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          );
        }(),
    ];
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
        final layout = GridLayout.of(box.maxWidth - 2 * pad - 2, _columns(fc));
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
        TransactionStatus.pending =>
          tx.effectiveDueDate.isBefore(e.today) ? 0 : 1,
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
      if (sort == GridColumn.status) {
        return _statusRank(e, a.tx).compareTo(_statusRank(e, b.tx));
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
    final overdue =
        !completed && !cancelled && tx.effectiveDueDate.isBefore(e.today);
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
