import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../import/expense_import_screen.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
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

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  List<FinTransaction> _items(FinanceController fc) {
    final e = fc.engine;
    final until = allPeriods ? Dates.addMonths(e.today, 12) : month.lastDay;
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
    final list =
        e.transactionsUntil(until).where((t) {
          if (!showForecast && t.isVirtual) return false;
          final d = e.listDate(t);
          if (!allPeriods && !month.contains(d)) return false;
          if (allPeriods && t.isVirtual && d.isAfter(until)) return false;
          if (filter.types.isNotEmpty && !filter.types.contains(t.type)) {
            return false;
          }
          if (quickType.type != null && t.type != quickType.type) return false;
          if (!quickStatus.matches(t.status)) return false;
          if (filter.statuses.isNotEmpty &&
              !filter.statuses.contains(t.status)) {
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
        }).toList()..sort((a, b) {
          final c = e.listDate(b).compareTo(e.listDate(a));
          return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
        });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final items = _items(fc);
    var inc = Money.zero, exp = Money.zero;
    var incOpen = Money.zero, expOpen = Money.zero;
    for (final t in items) {
      if (t.status == TransactionStatus.cancelled) continue;
      final open = t.status != TransactionStatus.completed;
      if (t.type == TransactionType.income) {
        inc += t.amount;
        if (open) incOpen += t.amount;
      }
      if (t.type == TransactionType.expense) {
        exp += t.amount;
        if (open) expOpen += t.amount;
      }
    }

    // Agrupa por dia.
    final groups = <DateTime, List<FinTransaction>>{};
    for (final t in items) {
      groups.putIfAbsent(e.listDate(t), () => []).add(t);
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
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: groups.length,
                    itemBuilder: (context, i) {
                      final day = groups.keys.elementAt(i);
                      final txs = groups[day]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              _dayLabel(day, e.today),
                              style: context.text.labelLarge?.copyWith(
                                color: context.fin.subtle,
                              ),
                            ),
                          ),
                          for (final t in txs)
                            TransactionTile(
                              tx: t,
                              engine: e,
                              showDate: false,
                              onStatusToggle: (done) =>
                                  _toggle(context, fc, t, done),
                              onTap: () => push(
                                context,
                                TransactionDetailsScreen(tx: t),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    FinanceController fc,
    FinTransaction t,
    bool done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await fc.toggleCompleted(t, done);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível alterar o status: $e')),
      );
    }
  }

  static String _dayLabel(DateTime d, DateTime today) {
    if (d == today) return 'Hoje · ${Dates.format(d)}';
    if (d == today.subtract(const Duration(days: 1))) {
      return 'Ontem · ${Dates.format(d)}';
    }
    if (d == today.add(const Duration(days: 1))) {
      return 'Amanhã · ${Dates.format(d)}';
    }
    const wd = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
    return '${wd[d.weekday - 1]} · ${Dates.format(d)}';
  }
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
