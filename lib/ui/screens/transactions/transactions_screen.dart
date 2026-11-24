import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/engine/other_entries_engine.dart';
import '../../../domain/engine/shared_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../import/expense_import_screen.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/entry_origin.dart';
import '../../widgets/filters_panel.dart';
import '../../widgets/header_actions.dart';
import '../../widgets/invoice_tile.dart';
import '../../widgets/remembered_filters.dart';
import '../../widgets/tx_grid.dart';
import '../../widgets/tx_inline_edit.dart';
import '../../widgets/view_mode.dart';
import '../cards/invoice_details_screen.dart';
import 'transaction_details_screen.dart';
import 'transaction_form_screen.dart';

/// Filtros da lista de transações. Cada conjunto vazio = sem filtro; com
/// vários valores, vale qualquer um deles.
class TxListFilter {
  final Set<TransactionType> types;
  final Set<TransactionStatus> statuses;
  final Set<String> locations; // 'a:id' | 'c:id'
  final Set<String> categoryIds;
  final Set<String> projectIds;
  final Set<String> tags;

  /// Quem usou: nomes dos dependentes e/ou [FinanceData.holderTitular].
  final Set<String> holders;
  const TxListFilter({
    this.types = const {},
    this.statuses = const {},
    this.locations = const {},
    this.categoryIds = const {},
    this.projectIds = const {},
    this.tags = const {},
    this.holders = const {},
  });
  int get count => [
    types,
    statuses,
    locations,
    categoryIds,
    projectIds,
    tags,
    holders,
  ].where((s) => s.isNotEmpty).length;

  TxListFilter copyWith({
    Set<TransactionType>? types,
    Set<TransactionStatus>? statuses,
    Set<String>? locations,
    Set<String>? categoryIds,
    Set<String>? projectIds,
    Set<String>? tags,
    Set<String>? holders,
  }) => TxListFilter(
    types: types ?? this.types,
    statuses: statuses ?? this.statuses,
    locations: locations ?? this.locations,
    categoryIds: categoryIds ?? this.categoryIds,
    projectIds: projectIds ?? this.projectIds,
    tags: tags ?? this.tags,
    holders: holders ?? this.holders,
  );

  TxListFilter withoutTypes() => copyWith(types: const {});
  TxListFilter withoutStatuses() => copyWith(statuses: const {});
  TxListFilter withoutLocation() => copyWith(locations: const {});
  TxListFilter withoutCategory() => copyWith(categoryIds: const {});
  TxListFilter withoutProject() => copyWith(projectIds: const {});
  TxListFilter withoutTag() => copyWith(tags: const {});
  TxListFilter withoutHolder() => copyWith(holders: const {});
}

/// Opções do filtro "Quem usou": o titular e os nomes dos dependentes de
/// todas as contas e cartões (o mesmo nome em vários junta tudo).
List<String> holderNames(FinanceData d) {
  final names = <String>{
    for (final a in d.accounts) ...a.dependents.map((x) => x.name),
    for (final c in d.cards) ...c.dependents.map((x) => x.name),
  }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [FinanceData.holderTitular, ...names];
}

/// Nome da conta ('a:id') ou do cartão ('c:id') de um filtro.
String locationName(FinanceData d, String loc) {
  final id = loc.substring(2);
  return (loc.startsWith('a:')
          ? d.accountById[id]?.name
          : d.cardById[id]?.name) ??
      '?';
}

String locationFilterLabel(FinanceData d, String loc) =>
    '${loc.startsWith('a:') ? 'Conta' : 'Cartão'}: ${locationName(d, loc)}';

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
  /// Só as transações do próprio usuário: esconde as linhas geradas por
  /// Outras despesas/receitas (`oe_`) e por Compartilhadas (`sh_`).
  final bool ownOnly;

  /// Dentro da tela unificada de lançamentos: sem barra de título; busca,
  /// filtros e modo de exibição vão para a linha do mês.
  final bool embedded;

  const TransactionsScreen({
    super.key,
    this.ownOnly = false,
    this.embedded = false,
  });
  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with RememberedFilters {
  YearMonth month = YearMonth.now();
  bool allPeriods = false;
  bool showForecast = true;
  bool searching = false;
  String query = '';
  TxListFilter filter = const TxListFilter();
  QuickStatus quickStatus = QuickStatus.all;
  QuickType quickType = QuickType.all;

  /// Filtros rápidos dinâmicos (gerados a partir das linhas do período):
  /// tipo de lançamento (coluna "Tipo") e categoria raiz.
  Set<EntryOrigin> origins = {};
  String? quickCategory;
  ViewMode view = ViewMode.grid;
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
  String get filterKey => 'transactions';

  @override
  Map<String, Object?> filtersToJson() => {
    'month': month.key,
    'allPeriods': allPeriods,
    'forecast': showForecast,
    'types': FilterJson.enums(filter.types),
    'statuses': FilterJson.enums(filter.statuses),
    'location': FilterJson.ids(filter.locations),
    'category': FilterJson.ids(filter.categoryIds),
    'project': FilterJson.ids(filter.projectIds),
    'tag': FilterJson.ids(filter.tags),
    'holder': FilterJson.ids(filter.holders),
    'quickStatus': quickStatus.name,
    'quickType': quickType.name,
    'origins': FilterJson.enums(origins),
    'quickCategory': quickCategory,
    'sort': sort.name,
    'asc': ascending,
    'view': view.name,
  };

  @override
  void restoreFilters(Map<String, Object?> j, FinanceController fc) {
    final d = fc.data;
    month = FilterJson.month(j['month']) ?? month;
    allPeriods = j['allPeriods'] as bool? ?? allPeriods;
    showForecast = j['forecast'] as bool? ?? showForecast;
    filter = TxListFilter(
      types: FilterJson.enumSet(TransactionType.values, j['types']),
      statuses: FilterJson.enumSet(TransactionStatus.values, j['statuses']),
      locations: FilterJson.idsOrOne(j['location'], [
        for (final a in d.accounts) 'a:${a.id}',
        for (final c in d.cards) 'c:${c.id}',
      ]),
      categoryIds: FilterJson.idsOrOne(
        j['category'],
        d.categories.map((c) => c.id),
      ),
      projectIds: FilterJson.idsOrOne(
        j['project'],
        d.projects.map((p) => p.id),
      ),
      tags: FilterJson.idsOrOne(j['tag'], fc.allTags),
      holders: FilterJson.idsOrOne(j['holder'], holderNames(d)),
    );
    quickStatus =
        FilterJson.enumOrNull(QuickStatus.values, j['quickStatus']) ??
        quickStatus;
    quickType =
        FilterJson.enumOrNull(QuickType.values, j['quickType']) ?? quickType;
    origins = FilterJson.enumSet(EntryOrigin.values, j['origins']);
    quickCategory = j['quickCategory'] as String?;
    sort = FilterJson.enumOrNull(GridColumn.values, j['sort']) ?? sort;
    ascending = j['asc'] as bool? ?? ascending;
    view = FilterJson.enumOrNull(ViewMode.values, j['view']) ?? view;
  }

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
    if (filter.categoryIds.isNotEmpty) {
      cats.addAll(filter.categoryIds);
      cats.addAll(
        fc.data.categories
            .where((c) => filter.categoryIds.contains(c.parentId))
            .map((c) => c.id),
      );
    }
    // Compras do cartão aparecem uma a uma quando a preferência pede, e
    // sempre que o usuário busca ou filtra por categoria/projeto (para que
    // relatórios e buscas encontrem cada compra).
    final individualCards =
        !fc.data.settings.groupCardInvoices ||
        cats.isNotEmpty ||
        filter.projectIds.isNotEmpty ||
        filter.tags.isNotEmpty ||
        filter.holders.isNotEmpty ||
        q.isNotEmpty;

    bool matches(FinTransaction t) {
      if (!showForecast && t.isVirtual) return false;
      if (widget.ownOnly &&
          (OtherSync.isDerived(t.id) || SharedBudgetSync.isDerived(t.id))) {
        return false;
      }
      if (filter.types.isNotEmpty && !filter.types.contains(t.type)) {
        return false;
      }
      if (quickType.type != null && t.type != quickType.type) return false;
      if (!quickStatus.matches(t.status)) return false;
      if (filter.statuses.isNotEmpty && !filter.statuses.contains(t.status)) {
        return false;
      }
      final locs = filter.locations;
      if (locs.isNotEmpty &&
          !locs.contains('a:${t.accountId}') &&
          !locs.contains('a:${t.destinationAccountId}') &&
          !locs.contains('c:${t.cardId}')) {
        return false;
      }
      if (cats.isNotEmpty && !cats.contains(t.categoryId)) return false;
      if (filter.projectIds.isNotEmpty &&
          !filter.projectIds.contains(t.projectId)) {
        return false;
      }
      if (filter.tags.isNotEmpty && !t.tags.any(filter.tags.contains)) {
        return false;
      }
      if (filter.holders.isNotEmpty &&
          !filter.holders.contains(fc.data.holderName(t))) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = [
          t.description,
          t.notes,
          ...t.tags,
          e.categoryLabel(t.categoryId),
          e.locationLabel(t),
          if (t.holderId != null) fc.data.holderName(t),
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

  static String _holderOf(FinancialEngine e, _Entry it) => switch (it) {
    _InvoiceEntry() => '',
    _TxEntry(:final tx) => e.data.holderName(tx).toLowerCase(),
  };

  static EntryOrigin _originOf(_Entry it) => switch (it) {
    _InvoiceEntry() => EntryOrigin.invoice,
    _TxEntry(:final tx) => EntryOrigin.of(tx),
  };

  /// Chave da categoria raiz de uma linha (a mesma da coluna Categoria):
  /// faturas = 'card', transferências = 'transfer', sem categoria = ''.
  static String _categoryKey(FinancialEngine e, _Entry it) => switch (it) {
    _InvoiceEntry() => 'card',
    _TxEntry(:final tx) when tx.isTransfer => 'transfer',
    _TxEntry(:final tx) => e.rootCategoryId(tx.categoryId),
  };

  bool _quickMatches(FinancialEngine e, _Entry it) {
    if (origins.isNotEmpty && !origins.contains(_originOf(it))) return false;
    if (quickCategory != null && _categoryKey(e, it) != quickCategory) {
      return false;
    }
    return true;
  }

  /// Botões gerados a partir do que existe no período: filtros escondidos
  /// no painel (com X para remover), tipos de lançamento e categorias, cada
  /// um com a quantidade de linhas.
  Widget _dynamicFilters(
    BuildContext context,
    FinanceController fc,
    List<_Entry> base,
  ) {
    final e = fc.engine;
    final d = fc.data;
    final originCount = <EntryOrigin, int>{};
    final catCount = <String, int>{};
    final catLabel = <String, String>{};
    for (final it in base) {
      final o = _originOf(it);
      originCount[o] = (originCount[o] ?? 0) + 1;
      // A contagem de categorias respeita o tipo escolhido.
      if (origins.isNotEmpty && !origins.contains(o)) continue;
      final k = _categoryKey(e, it);
      catCount[k] = (catCount[k] ?? 0) + 1;
      catLabel[k] ??= _cols(e, it).category;
    }
    if (quickCategory != null && !catCount.containsKey(quickCategory)) {
      catCount[quickCategory!] = 0;
      catLabel[quickCategory!] = quickCategory == 'card'
          ? 'Cartão'
          : quickCategory == 'transfer'
          ? 'Transferência'
          : e.categoryLabel(quickCategory);
    }
    for (final o in origins) {
      originCount.putIfAbsent(o, () => 0);
    }
    final originList = EntryOrigin.values
        .where(originCount.containsKey)
        .toList();
    final cats = catCount.keys.toList()
      ..sort((a, b) {
        final c = catCount[b]!.compareTo(catCount[a]!);
        return c != 0 ? c : catLabel[a]!.compareTo(catLabel[b]!);
      });

    final active = <(String, String, VoidCallback)>[
      if (filter.types.isNotEmpty)
        (
          'f-types',
          'Tipo: ${filter.types.map((t) => t.label).join(', ')}',
          () => setFilters(() => filter = filter.withoutTypes()),
        ),
      if (filter.statuses.isNotEmpty)
        (
          'f-statuses',
          'Status: ${filter.statuses.map((s) => s.label).join(', ')}',
          () => setFilters(() => filter = filter.withoutStatuses()),
        ),
      if (filter.locations.isNotEmpty)
        (
          'f-location',
          filter.locations.length == 1
              ? locationFilterLabel(d, filter.locations.first)
              : 'Contas/cartões: ${filter.locations.map((l) => locationName(d, l)).join(', ')}',
          () => setFilters(() => filter = filter.withoutLocation()),
        ),
      if (filter.categoryIds.isNotEmpty)
        (
          'f-category',
          'Categoria: ${filter.categoryIds.map(e.categoryLabel).join(', ')}',
          () => setFilters(() => filter = filter.withoutCategory()),
        ),
      if (filter.projectIds.isNotEmpty)
        (
          'f-project',
          'Projeto: ${filter.projectIds.map((p) => d.projectById[p]?.name ?? '?').join(', ')}',
          () => setFilters(() => filter = filter.withoutProject()),
        ),
      if (filter.tags.isNotEmpty)
        (
          'f-tag',
          filter.tags.map((t) => '#$t').join(' '),
          () => setFilters(() => filter = filter.withoutTag()),
        ),
      if (filter.holders.isNotEmpty)
        (
          'f-holder',
          'Quem usou: ${filter.holders.join(', ')}',
          () => setFilters(() => filter = filter.withoutHolder()),
        ),
    ];
    final showOrigins = originList.length > 1 || origins.isNotEmpty;
    final showCats = cats.length > 1 || quickCategory != null;
    if (active.isEmpty && !showOrigins && !showCats) {
      return const SizedBox.shrink();
    }

    Widget gap() => Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.only(left: 2, right: 8),
      color: context.colors.outlineVariant,
    );
    Widget pad(Widget w) =>
        Padding(padding: const EdgeInsets.only(right: 6), child: w);

    final children = <Widget>[
      for (final (key, label, onClear) in active)
        pad(
          InputChip(
            key: ValueKey(key),
            label: Text(label),
            avatar: const Icon(Icons.filter_alt, size: 16),
            visualDensity: VisualDensity.compact,
            onDeleted: onClear,
            deleteButtonTooltipMessage: 'Remover filtro',
          ),
        ),
      if (active.length > 1)
        pad(
          ActionChip(
            key: const ValueKey('f-clear'),
            label: const Text('Limpar filtros'),
            visualDensity: VisualDensity.compact,
            onPressed: () => setFilters(() => filter = const TxListFilter()),
          ),
        ),
      if (active.isNotEmpty && (showOrigins || showCats)) gap(),
      if (showOrigins) ...[
        for (final o in originList)
          pad(
            FilterChip(
              key: ValueKey('qo-${o.name}'),
              avatar: Icon(o.icon, size: 16),
              label: Text('${o.label} ${originCount[o]}'),
              selected: origins.contains(o),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setFilters(() {
                origins = {...origins};
                v ? origins.add(o) : origins.remove(o);
              }),
            ),
          ),
        if (showCats) gap(),
      ],
      if (showCats)
        for (final k in cats)
          pad(
            FilterChip(
              key: ValueKey('qc-$k'),
              label: Text('${catLabel[k]} ${catCount[k]}'),
              selected: quickCategory == k,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setFilters(() => quickCategory = v ? k : null),
            ),
          ),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        key: const ValueKey('tx-dynamic-filters'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        children: children,
      ),
    );
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
    final locs = filter.locations;
    if (locs.isNotEmpty && !locs.contains('c:${inv.card.id}')) {
      // Pagamentos feitos com uma das contas filtradas.
      if (!slice.settled ||
          !inv.payments.any(
            (p) =>
                locs.contains('a:${p.accountId}') &&
                YearMonth.of(p.date) == slice.month,
          )) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final base = _items(fc);
    final items = [
      for (final it in base)
        if (_quickMatches(e, it)) it,
    ];
    final hiddenFilters =
        filter.count + origins.length + (quickCategory == null ? 0 : 1);
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

    final actions = <Widget>[
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
      ViewModeToggle(
        keyPrefix: 'tx',
        mode: view,
        onChanged: (v) => setFilters(() => view = v),
      ),
      FilterButton(
        keyPrefix: 'tx',
        active: filter.count,
        panel: FilterPanel(
          keyPrefix: 'tx',
          title: 'Filtrar transações',
          active: filter.count,
          onClear: () => setFilters(() => filter = const TxListFilter()),
          fields: (context) => txFilterFields(
            context,
            fc,
            filter,
            (f) => setFilters(() => filter = f),
          ),
        ),
      ),
    ];
    final menu = PopupMenuButton<String>(
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
        setFilters(() {
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
        if (view == ViewMode.grid)
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
    );
    // Dentro de Movimentações os botões vão para a barra de título, com
    // Filtros no canto superior direito.
    final inHeader =
        widget.embedded &&
        HeaderActionsScope.publish(context, [
          ...actions.take(actions.length - 1),
          menu,
          actions.last,
        ]);
    final searchField = TextField(
      controller: searchCtrl,
      autofocus: true,
      decoration: const InputDecoration(
        hintText: 'Buscar descrição, categoria, valor…',
        border: InputBorder.none,
        filled: false,
      ),
      onChanged: (v) => setState(() => query = v),
    );
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: searching ? searchField : const Text('Transações'),
              actions: actions,
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-tx',
        onPressed: () => push(context, const TransactionFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nova transação'),
      ),
      body: Column(
        children: [
          if (widget.embedded && searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: searchField,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (!allPeriods)
                  MonthSwitcher(
                    month: month,
                    onChanged: (m) => setFilters(() => month = m),
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
                if (!inHeader) ...[if (widget.embedded) ...actions, menu],
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _QuickFilters(
              type: quickType,
              status: quickStatus,
              onType: (v) => setFilters(() {
                quickType = v;
                // O botão manda: um filtro de tipo esquecido no painel de
                // filtros escondia, por exemplo, todas as receitas.
                if (v != QuickType.all) filter = filter.withoutTypes();
              }),
              onStatus: (v) => setFilters(() {
                quickStatus = v;
                if (v != QuickStatus.all) filter = filter.withoutStatuses();
              }),
            ),
          ),
          _dynamicFilters(context, fc, base),
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
                    title: query.isNotEmpty || hiddenFilters > 0
                        ? 'Nada encontrado'
                        : 'Sem transações neste período',
                    message: query.isNotEmpty || hiddenFilters > 0
                        ? 'Ajuste a busca ou os filtros.'
                        : 'Registre receitas, despesas e transferências.',
                    actionLabel: 'Nova transação',
                    onAction: () =>
                        push(context, const TransactionFormScreen()),
                  )
                : view == ViewMode.cards
                ? _cardsList(context, fc, items)
                : LayoutBuilder(
                    builder: (context, box) {
                      final pad = box.maxWidth < 640 ? 8.0 : 16.0;
                      final layout = GridLayout.of(
                        box.maxWidth - 2 * pad - 2,
                        _columns(
                          fc,
                        ).showingIf(GridColumn.holder, fc.data.hasDependents),
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

  void _onSort(GridColumn s) => setFilters(() {
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
      GridColumn.kind => _originOf(a).label.compareTo(_originOf(b).label),
      GridColumn.holder => _holderOf(e, a).compareTo(_holderOf(e, b)),
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
      tx.cardId != null ? e.invoiceOf(tx)?.dueDate : tx.shownDueDate,
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
      TransactionStatus.pending => e.isOverdue(tx) ? 0 : 1,
    },
  };

  /// Rótulo e cor do status de um lançamento (grade e cartões).
  static (String, Color) _txStatus(
    BuildContext context,
    FinancialEngine e,
    FinTransaction tx,
  ) {
    final isIncome = tx.type == TransactionType.income;
    return switch (tx.status) {
      TransactionStatus.cancelled => ('Cancelada', context.fin.subtle),
      TransactionStatus.completed => (
        tx.isTransfer ? 'Concluída' : (isIncome ? 'Recebida' : 'Paga'),
        context.fin.positive,
      ),
      _ when e.isOverdue(tx) => ('Atrasada', context.fin.negative),
      TransactionStatus.planned => ('Prevista', context.colors.primary),
      TransactionStatus.pending => ('Pendente', context.fin.warning),
    };
  }

  /// Modo cartões: lançamentos agrupados por dia, um cartão por item.
  Widget _cardsList(
    BuildContext context,
    FinanceController fc,
    List<_Entry> items,
  ) {
    final e = fc.engine;
    final days = <DateTime, List<_Entry>>{};
    for (final it in items) {
      days.putIfAbsent(Dates.dateOnly(it.date), () => []).add(it);
    }
    const wd = [
      'segunda-feira',
      'terça-feira',
      'quarta-feira',
      'quinta-feira',
      'sexta-feira',
      'sábado',
      'domingo',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        for (final MapEntry(key: day, value: list) in days.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              '${Dates.format(day)} · ${wd[day.weekday - 1]}',
              style: context.text.labelLarge?.copyWith(
                color: context.fin.subtle,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final it in list)
            switch (it) {
              final _TxEntry it => _txCard(context, e, it),
              final _InvoiceEntry it => Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                clipBehavior: Clip.antiAlias,
                child: InvoiceTile(
                  invoice: it.invoice,
                  slice: it.slice,
                  selected: selectedInvoice == it.key,
                  onOpen: () => _openInvoice(it.invoice),
                  onSelect: () => _select(it),
                ),
              ),
            },
        ],
      ],
    );
  }

  Widget _txCard(BuildContext context, FinancialEngine e, _TxEntry it) {
    final tx = it.tx;
    final cat = e.data.categoryById[tx.categoryId];
    final isIncome = tx.type == TransactionType.income;
    final color = tx.isTransfer
        ? context.fin.subtle
        : Color(cat?.color ?? context.fin.subtle.toARGB32());
    final icon = tx.isTransfer ? Icons.swap_horiz : categoryIcon(cat?.icon);
    final cancelled = tx.status == TransactionStatus.cancelled;
    final (statusLabel, statusColor) = _txStatus(context, e, tx);
    final subtitle = [
      tx.isTransfer ? 'Transferência' : e.categoryLabel(tx.categoryId),
      e.locationLabel(tx),
      if (tx.isInstallment) 'Parcela ${tx.installmentLabel}',
    ].join(' · ');
    return Card(
      key: ValueKey('tx-card-${tx.id}-${tx.date.toIso8601String()}'),
      margin: const EdgeInsets.symmetric(vertical: 3),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => push(context, TransactionDetailsScreen(tx: tx)),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                tx.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (tx.isRecurring) ...[
              const SizedBox(width: 6),
              Icon(Icons.autorenew, size: 14, color: context.fin.subtle),
            ],
          ],
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MoneyText(
              isIncome || tx.isTransfer ? it.amount : -it.amount,
              showPlus: isIncome,
              color: tx.isTransfer
                  ? context.fin.subtle
                  : isIncome
                  ? context.fin.positive
                  : context.fin.expense,
              style: context.text.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                decoration: cancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            const SizedBox(height: 4),
            Pill(statusLabel, color: statusColor),
          ],
        ),
      ),
    );
  }

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
    final overdue = e.isOverdue(tx);
    final (statusLabel, statusColor) = _txStatus(context, e, tx);
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
          Dates.dateOnly(tx.dueDate!) != Dates.dateOnly(tx.date) &&
          (layout.compact || !layout.shows(GridColumn.dueDate)))
        'vence ${Dates.formatShort(tx.dueDate!)}',
    ].join(' · ');
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final descStyle = context.text.bodyMedium?.copyWith(
      fontWeight: layout.compact ? FontWeight.w600 : null,
      decoration: cancelled ? TextDecoration.lineThrough : null,
    );
    void open() => push(context, TransactionDetailsScreen(tx: tx));
    Future<void> save(FinTransaction t) => saveTxInline(context, fc, t);
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
                onPick: (_) => pickTxDate(context, fc, tx),
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
                                pickTxCategory(cell, fc, tx, onlyRoots: false),
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
                      validate: validateInlineAmount,
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
        onPick: (_) => pickTxDate(context, fc, tx),
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
                  tx.shownDueDate == null
                      ? '—'
                      : Dates.format(tx.shownDueDate!),
                  style: tx.shownDueDate == null
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
                    pickTxCategory(cell, fc, tx, onlyRoots: showSub),
                display: catLabel,
              )
            : GridCell(child: catLabel),
      GridColumn.subcategory =>
        canCategorize && cat != null
            ? InlinePickerCell(
                key: ValueKey('tx-edit-subcategory-$key'),
                tooltip: 'Alterar subcategoria',
                onPick: (cell) => pickTxSubcategory(cell, fc, tx),
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
        validate: validateInlineAmount,
        onSubmit: (v) => save(tx.copyWith(amount: Money.tryEval(v))),
        display: Opacity(opacity: completed ? 1 : 0.8, child: money),
      ),
      GridColumn.status => GridCell(child: status),
      GridColumn.kind => GridCell(child: EntryOriginLabel(EntryOrigin.of(tx))),
      GridColumn.holder =>
        tx.isTransfer
            ? GridCell(child: Text('—', style: subtle))
            : InlinePickerCell(
                key: ValueKey('tx-edit-holder-$key'),
                tooltip: 'Alterar quem usou',
                onPick: (cell) => pickTxHolder(cell, fc, tx),
                display: Text(
                  fc.data.holderName(tx),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tx.holderId == null ? subtle : context.text.bodyMedium,
                ),
              ),
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
      GridColumn.kind => const GridCell(
        child: EntryOriginLabel(EntryOrigin.invoice),
      ),
      GridColumn.holder => GridCell(child: Text('—', style: subtle)),
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

  /// Vencimento do lançamento. Sem vencimento, abre direto o calendário;
  /// com vencimento, oferece alterar ou remover (despesas em conta sempre
  /// têm vencimento: só alterar).
  Future<void> _pickDueDate(
    BuildContext cell,
    FinanceController fc,
    FinTransaction tx,
  ) async {
    if (tx.dueDate != null && !tx.hasOwnDueDate) {
      final action = await showCellMenu(cell, const [
        CellMenuOption('change', 'Alterar vencimento'),
        CellMenuOption('clear', 'Remover vencimento'),
      ]);
      if (action == null || !cell.mounted) return;
      if (action == 'clear') {
        await saveTxInline(cell, fc, tx.copyWith(dueDate: null));
        return;
      }
    }
    final d = await showDatePicker(
      context: cell,
      initialDate: tx.shownDueDate ?? tx.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(fc.today.year + 30),
      helpText: 'Data de vencimento',
      locale: const Locale('pt', 'BR'),
    );
    if (d == null || !cell.mounted) return;
    final due = Dates.dateOnly(d);
    final current = tx.shownDueDate;
    if (current != null && due == Dates.dateOnly(current)) return;
    // Despesa com vencimento na própria data não grava: acompanha a data.
    final keep = !tx.hasOwnDueDate || due != Dates.dateOnly(tx.date);
    await saveTxInline(cell, fc, tx.copyWith(dueDate: keep ? due : null));
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

/// Campos do painel de filtros da lista de transações.
List<Widget> txFilterFields(
  BuildContext context,
  FinanceController fc,
  TxListFilter f,
  ValueChanged<TxListFilter> set,
) {
  final d = fc.data;
  Widget group<T extends Enum>(
    String key,
    String label,
    List<T> values,
    String Function(T) name,
    Set<T> sel,
    TxListFilter Function(Set<T>) apply,
  ) => FilterChipGroup(
    keyName: 'tx-filter-$key',
    label: label,
    onClear: () => set(apply(const {})),
    options: [
      for (final v in values)
        (
          key: v.name,
          label: name(v),
          color: null,
          selected: sel.contains(v),
          onTap: () =>
              set(apply(sel.contains(v) ? ({...sel}..remove(v)) : {...sel, v})),
        ),
    ],
  );

  Widget select(
    String key,
    String label,
    Map<String, String> options,
    Set<String> sel,
    TxListFilter Function(Set<String>) apply, {
    String allLabel = 'Todos',
  }) => FilterSelect<String>(
    key: ValueKey('filter-$key'),
    keyName: 'tx-filter-$key',
    label: label,
    allLabel: allLabel,
    options: options,
    selected: sel,
    onChanged: (v) => set(apply(v)),
  );

  return [
    group(
      'types',
      'Tipo',
      TransactionType.values,
      (t) => t.label,
      f.types,
      (v) => f.copyWith(types: v),
    ),
    group(
      'statuses',
      'Status',
      TransactionStatus.values,
      (t) => t.label,
      f.statuses,
      (v) => f.copyWith(statuses: v),
    ),
    select(
      'location',
      'Conta ou cartão',
      {
        for (final a in d.accounts) 'a:${a.id}': a.name,
        for (final c in d.cards) 'c:${c.id}': c.name,
      },
      f.locations,
      (v) => f.copyWith(locations: v),
    ),
    select(
      'category',
      'Categoria',
      {for (final c in d.categories) c.id: fc.engine.categoryLabel(c.id)},
      f.categoryIds,
      (v) => f.copyWith(categoryIds: v),
      allLabel: 'Todas',
    ),
    select(
      'project',
      'Projeto',
      {for (final p in d.projects) p.id: p.name},
      f.projectIds,
      (v) => f.copyWith(projectIds: v),
    ),
    if (fc.allTags.isNotEmpty)
      select(
        'tag',
        'Tag',
        {for (final t in fc.allTags) t: t},
        f.tags,
        (v) => f.copyWith(tags: v),
        allLabel: 'Todas',
      ),
    if (d.hasDependents)
      select(
        'holder',
        'Quem usou',
        {for (final n in holderNames(d)) n: n},
        f.holders,
        (v) => f.copyWith(holders: v),
      ),
  ];
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
