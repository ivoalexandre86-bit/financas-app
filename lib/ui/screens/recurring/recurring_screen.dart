import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/recurrence.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/filters_panel.dart';
import '../../widgets/remembered_filters.dart';
import '../../widgets/sort_grid.dart';
import '../../widgets/tx_grid.dart';
import '../../widgets/view_mode.dart';
import '../installments/installments_screen.dart' show fmtMoney;
import '../simulations/sim_common.dart' show SimKpi;
import 'recurring_form_screen.dart';

String frequencyLabel(RecurringRule r) {
  if (r.frequency != RecurrenceFrequency.custom) {
    final day = r.dayOfMonth ?? Recurrence.firstOccurrence(r).day;
    return r.frequency == RecurrenceFrequency.weekly
        ? 'Semanal'
        : '${r.frequency.label} · dia $day';
  }
  return 'A cada ${r.interval} ${r.unit.label}';
}

enum RecurringState {
  active('Ativa'),
  paused('Pausada'),
  ended('Encerrada');

  final String label;
  const RecurringState(this.label);
}

/// Dados de uma recorrência usados na grade e nos indicadores.
class RecurringSummary {
  final RecurringRule rule;
  final String category;
  final String where;
  final DateTime? next;
  final RecurringState state;

  /// Valor mensal equivalente, positivo para receitas e negativo para
  /// despesas.
  final int monthly;

  RecurringSummary._(
    this.rule,
    this.category,
    this.where,
    this.next,
    this.state,
    this.monthly,
  );

  factory RecurringSummary.of(FinanceController fc, RecurringRule r) {
    final today = fc.today;
    final ended = r.isEndedBy(today);
    final m = Recurrence.monthlyEquivalentCents(r);
    return RecurringSummary._(
      r,
      fc.engine.categoryLabel(r.categoryId),
      (r.cardId != null
              ? fc.data.cardById[r.cardId]?.name
              : fc.data.accountById[r.accountId]?.name) ??
          '—',
      ended || r.isPaused ? null : Recurrence.nextOccurrence(r, today),
      ended
          ? RecurringState.ended
          : r.isPaused
          ? RecurringState.paused
          : RecurringState.active,
      isIncomeRule(r) ? m : -m,
    );
  }

  bool get isIncome => isIncomeRule(rule);

  /// `c:<cartão>` ou `a:<conta>`, para o filtro.
  String get whereKey =>
      rule.cardId != null ? 'c:${rule.cardId}' : 'a:${rule.accountId ?? ''}';
}

bool isIncomeRule(RecurringRule r) => r.type == TransactionType.income;

/// Filtro de situação: "Em vigor" (padrão) esconde as encerradas.
enum _StateFilter {
  current('Em vigor'),
  active('Ativas'),
  paused('Pausadas'),
  ended('Encerradas'),
  all('Todas');

  final String label;
  const _StateFilter(this.label);

  bool accepts(RecurringState s) => switch (this) {
    current => s != RecurringState.ended,
    active => s == RecurringState.active,
    paused => s == RecurringState.paused,
    ended => s == RecurringState.ended,
    all => true,
  };
}

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen>
    with RememberedFilters {
  String query = '';
  TransactionType? type;
  String? categoryId;
  String? where;
  _StateFilter state = _StateFilter.current;
  ViewMode view = ViewMode.grid;

  /// null = aberto no desktop e recolhido no celular.
  bool? filtersOpen;
  final searchCtrl = TextEditingController();

  @override
  String get filterKey => 'recurring';

  @override
  Map<String, Object?> filtersToJson() => {
    'type': type?.name,
    'category': categoryId,
    'where': where,
    'state': state.name,
    'view': view.name,
  };

  @override
  void restoreFilters(Map<String, Object?> j, FinanceController fc) {
    type = FilterJson.enumOrNull(TransactionType.values, j['type']);
    categoryId = j['category'] as String?;
    where = j['where'] as String?;
    state = FilterJson.enumOrNull(_StateFilter.values, j['state']) ?? state;
    view = FilterJson.enumOrNull(ViewMode.values, j['view']) ?? view;
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  int get _activeFilters => [
    query.trim().isNotEmpty,
    type != null,
    categoryId != null,
    where != null,
    state != _StateFilter.current,
  ].where((b) => b).length;

  void _clearFilters() => setFilters(() {
    searchCtrl.clear();
    query = '';
    type = null;
    categoryId = null;
    where = null;
    state = _StateFilter.current;
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final all = [
      for (final r in fc.data.recurringRules) RecurringSummary.of(fc, r),
    ];
    final q = query.trim().toLowerCase();
    final list = all.where((s) {
      if (!state.accepts(s.state)) return false;
      if (type != null && s.rule.type != type) return false;
      if (categoryId != null && s.rule.categoryId != categoryId) return false;
      if (where != null && s.whereKey != where) return false;
      return q.isEmpty ||
          s.rule.description.toLowerCase().contains(q) ||
          s.rule.notes.toLowerCase().contains(q);
    }).toList();
    final running = list.where((s) => s.state == RecurringState.active);
    final income = running
        .where((s) => s.isIncome)
        .fold(0, (a, s) => a + s.monthly);
    final expense = -running
        .where((s) => !s.isIncome)
        .fold(0, (a, s) => a + s.monthly);
    int count(RecurringState st) => list.where((s) => s.state == st).length;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final wheres = <String, String>{for (final s in all) s.whereKey: s.where};
    // Filtro salvo que deixou de existir volta para "Todos".
    if (!wheres.containsKey(where)) where = null;
    final cats = <String, String>{
      for (final s in all)
        if (s.rule.categoryId != null) s.rule.categoryId!: s.category,
    };
    if (!cats.containsKey(categoryId)) categoryId = null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorrências'),
        actions: [
          ViewModeToggle(
            keyPrefix: 'recurring',
            mode: view,
            onChanged: (v) => setFilters(() => view = v),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-rec',
        onPressed: () => push(context, const RecurringFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nova recorrência'),
      ),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.autorenew,
              title: 'Nenhuma recorrência',
              message: 'Cadastre salário, aluguel, assinaturas e contas fixas para projetar meses futuros.',
              actionLabel: 'Nova recorrência',
              onAction: () => push(context, const RecurringFormScreen()),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                KpiWrap(
                  children: (kpiW) => [
                    SimKpi(
                      width: kpiW,
                      label: 'Receitas por mês',
                      value: fmtMoney(income),
                      icon: Icons.south_west,
                      color: context.fin.positive,
                    ),
                    SimKpi(
                      width: kpiW,
                      label: 'Despesas por mês',
                      value: fmtMoney(expense),
                      icon: Icons.north_east,
                      color: context.fin.negative,
                    ),
                    SimKpi(
                      width: kpiW,
                      label: 'Saldo mensal',
                      value: fmtMoney(income - expense),
                      detail: 'só as ativas, em valor mensal',
                      icon: Icons.account_balance_wallet_outlined,
                      color: income >= expense
                          ? context.fin.positive
                          : context.fin.negative,
                    ),
                    SimKpi(
                      width: kpiW,
                      label: 'Recorrências',
                      value: '${count(RecurringState.active)} ativas',
                      detail:
                          '${count(RecurringState.paused)} pausadas · '
                          '${count(RecurringState.ended)} encerradas',
                      icon: Icons.autorenew,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FiltersPanel(
                  keyPrefix: 'rec',
                  open: filtersOpen ?? !narrow,
                  active: _activeFilters,
                  onToggle: () =>
                      setState(() => filtersOpen = !(filtersOpen ?? !narrow)),
                  onClear: _clearFilters,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        child: TextField(
                          key: const ValueKey('rec-search'),
                          controller: searchCtrl,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Buscar descrição',
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => query = v),
                        ),
                      ),
                      FilterDropdown<TransactionType?>(
                        label: 'Tipo',
                        value: type,
                        items: const {
                          null: 'Todos',
                          TransactionType.income: 'Receitas',
                          TransactionType.expense: 'Despesas',
                        },
                        onChanged: (v) => setFilters(() => type = v),
                      ),
                      FilterDropdown<String?>(
                        label: 'Categoria',
                        value: categoryId,
                        items: {null: 'Todas', ...cats},
                        onChanged: (v) => setFilters(() => categoryId = v),
                      ),
                      FilterDropdown<String?>(
                        label: 'Conta/cartão',
                        value: where,
                        items: {null: 'Todos', ...wheres},
                        onChanged: (v) => setFilters(() => where = v),
                      ),
                      FilterDropdown<_StateFilter>(
                        key: const ValueKey('rec-state'),
                        label: 'Situação',
                        value: state,
                        items: {
                          for (final f in _StateFilter.values) f: f.label,
                        },
                        onChanged: (v) =>
                            setFilters(() => state = v ?? _StateFilter.current),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.autorenew,
                      title: 'Nada com esses filtros',
                    ),
                  )
                else if (view == ViewMode.grid)
                  RecurringGrid(
                    rows: list,
                    onOpen: (s) =>
                        push(context, RecurringFormScreen(rule: s.rule)),
                  )
                else
                  RecurringCards(
                    rows: list,
                    onOpen: (s) =>
                        push(context, RecurringFormScreen(rule: s.rule)),
                  ),
              ],
            ),
    );
  }
}

/// Recorrências em cartões, um por regra.
class RecurringCards extends StatelessWidget {
  final List<RecurringSummary> rows;
  final ValueChanged<RecurringSummary> onOpen;
  const RecurringCards({super.key, required this.rows, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    // Mesma ordem inicial da grade: receitas primeiro, depois A→Z.
    final sorted = [...rows]
      ..sort(
        (a, b) => a.isIncome != b.isIncome
            ? (a.isIncome ? -1 : 1)
            : a.rule.description.toLowerCase().compareTo(
                b.rule.description.toLowerCase(),
              ),
      );
    return Column(
      children: [
        for (final s in sorted)
          Card(
            key: ValueKey('rec-card-${s.rule.id}'),
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onOpen(s),
              child: Opacity(
                opacity: s.state == RecurringState.ended ? 0.6 : 1,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            (s.isIncome
                                    ? context.fin.positive
                                    : context.fin.negative)
                                .withValues(alpha: 0.12),
                        child: Icon(
                          s.isIncome ? Icons.south_west : Icons.north_east,
                          color: s.isIncome
                              ? context.fin.positive
                              : context.fin.negative,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s.rule.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                frequencyLabel(s.rule),
                                if (s.where != '—') s.where,
                                s.category,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: subtle,
                            ),
                            Text(
                              s.next != null
                                  ? 'Próxima ${Dates.format(s.next!)}'
                                  : s.rule.endDate != null
                                  ? 'Fim ${Dates.format(s.rule.endDate!)}'
                                  : 'Sem próxima ocorrência',
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
                          Text(
                            fmtMoney(s.rule.amount.cents),
                            style: context.text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: s.isIncome ? context.fin.positive : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          NeonStatus(
                            label: s.state.label,
                            color: switch (s.state) {
                              RecurringState.active => context.fin.positive,
                              RecurringState.paused => context.fin.warning,
                              RecurringState.ended => context.fin.subtle,
                            },
                            done: s.state == RecurringState.active,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Recorrências numa grade única, ordenável e com totais.
class RecurringGrid extends StatelessWidget {
  final List<RecurringSummary> rows;
  final ValueChanged<RecurringSummary> onOpen;
  const RecurringGrid({super.key, required this.rows, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final tab = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );
    final small = context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    Color typeColor(RecurringSummary s) =>
        s.isIncome ? context.fin.positive : context.fin.negative;
    Color stateColor(RecurringState st) => switch (st) {
      RecurringState.active => context.fin.positive,
      RecurringState.paused => context.fin.warning,
      RecurringState.ended => context.fin.subtle,
    };
    Widget status(RecurringSummary s) => NeonStatus(
      label: s.state.label,
      color: stateColor(s.state),
      done: s.state == RecurringState.active,
    );
    Widget date(DateTime? d) => d == null
        ? Text('—', style: subtle)
        : Text(Dates.format(d), style: tab);
    String signed(int v) => v < 0 ? '−${fmtMoney(-v)}' : fmtMoney(v);
    // Saldo mensal das ativas exibidas.
    int net(List<RecurringSummary> l) => l
        .where((s) => s.state == RecurringState.active)
        .fold(0, (a, s) => a + s.monthly);
    Widget netText(List<RecurringSummary> l, {bool strong = false}) {
      final v = net(l);
      return Text(
        signed(v),
        style: (strong ? context.text.bodyMedium : small)?.copyWith(
          fontWeight: FontWeight.w800,
          color: v >= 0 ? context.fin.positive : context.fin.negative,
        ),
      );
    }

    return SortGrid<RecurringSummary>(
      keyPrefix: 'rec',
      rows: rows,
      rowId: (s) => s.rule.id,
      accent: (context, s) =>
          s.state == RecurringState.active ? typeColor(s) : stateColor(s.state),
      dimmed: (s) => s.state == RecurringState.ended,
      onOpen: onOpen,
      initialSort: 'type',
      tieBreak: (a, b) => text(a.rule.description, b.rule.description),
      columns: [
        SortCol(
          id: 'description',
          label: 'Descrição',
          width: 180,
          minWidth: 120,
          flexible: true,
          fill: true,
          compare: (a, b) => text(a.rule.description, b.rule.description),
          cell: (context, s) => GridCell(
            child: Text(
              s.rule.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SortCol(
          id: 'type',
          label: 'Tipo',
          width: 84,
          compare: (a, b) => (a.isIncome ? 0 : 1).compareTo(b.isIncome ? 0 : 1),
          cell: (context, s) => GridCell(
            child: Text(
              s.isIncome ? 'Receita' : 'Despesa',
              style: context.text.bodySmall?.copyWith(
                color: typeColor(s),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SortCol(
          id: 'category',
          label: 'Categoria',
          width: 130,
          minWidth: 90,
          flexible: true,
          compare: (a, b) => text(a.category, b.category),
          cell: (context, s) => GridCell(
            child: Text(
              s.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtle,
            ),
          ),
        ),
        SortCol(
          id: 'where',
          label: 'Conta/cartão',
          width: 120,
          minWidth: 90,
          flexible: true,
          compare: (a, b) => text(a.where, b.where),
          cell: (context, s) => GridCell(
            child: Text(
              s.where,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          ),
        ),
        SortCol(
          id: 'frequency',
          label: 'Frequência',
          width: 130,
          compare: (a, b) =>
              text(frequencyLabel(a.rule), frequencyLabel(b.rule)),
          cell: (context, s) => GridCell(
            child: Text(
              frequencyLabel(s.rule),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          ),
        ),
        SortCol(
          id: 'end',
          label: 'Fim',
          width: 92,
          compare: (a, b) => (a.rule.endDate ?? DateTime(9999)).compareTo(
            b.rule.endDate ?? DateTime(9999),
          ),
          cell: (context, s) => GridCell(child: date(s.rule.endDate)),
        ),
        SortCol(
          id: 'next',
          label: 'Próxima',
          width: 92,
          compare: (a, b) =>
              (a.next ?? DateTime(9999)).compareTo(b.next ?? DateTime(9999)),
          cell: (context, s) => GridCell(child: date(s.next)),
        ),
        SortCol(
          id: 'amount',
          label: 'Valor',
          width: 112,
          right: true,
          highlight: true,
          compare: (a, b) => a.rule.amount.cents.compareTo(b.rule.amount.cents),
          cell: (context, s) => GridCell(
            right: true,
            child: Text(
              fmtMoney(s.rule.amount.cents),
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: s.isIncome ? context.fin.positive : null,
              ),
            ),
          ),
        ),
        SortCol(
          id: 'monthly',
          label: 'Por mês',
          width: 112,
          right: true,
          compare: (a, b) => a.monthly.compareTo(b.monthly),
          cell: (context, s) => GridCell(
            right: true,
            child: Text(
              signed(s.monthly),
              style: context.text.bodySmall?.copyWith(
                color: typeColor(s),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          footer: (context, l) => netText(l, strong: true),
        ),
        SortCol(
          id: 'status',
          label: 'Situação',
          width: 112,
          compare: (a, b) => a.state.index.compareTo(b.state.index),
          cell: (context, s) => GridCell(child: status(s)),
        ),
      ],
      compactRow: (context, s) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.rule.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    frequencyLabel(s.rule),
                    if (s.where != '—') s.where,
                    if (s.next != null) 'próx. ${Dates.formatShort(s.next!)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtle,
                ),
                Text(s.category, maxLines: 1, style: subtle),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmtMoney(s.rule.amount.cents),
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: s.isIncome ? context.fin.positive : null,
                ),
              ),
              const SizedBox(height: 3),
              status(s),
            ],
          ),
        ],
      ),
      footerLabel: (context, l) => Text(
        'Saldo mensal · ${l.length} '
        '${l.length == 1 ? 'recorrência' : 'recorrências'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: gridFooterLabelStyle(context),
      ),
      compactFooter: (context, l) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('por mês ', style: context.text.bodySmall),
          netText(l, strong: true),
        ],
      ),
    );
  }
}
