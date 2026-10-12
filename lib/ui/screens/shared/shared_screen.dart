import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/other_entries_engine.dart';
import '../../../domain/engine/shared_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../domain/models/shared.dart';
import '../../../state/finance_controller.dart';
import '../../../state/shared_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../transactions/transaction_form_screen.dart';
import 'group_screen.dart';
import 'payment_dialogs.dart';
import 'share_dialog.dart';
import 'shared_expense_screen.dart';
import 'shared_widgets.dart';

/// "Despesas compartilhadas": despesas, resumo mensal e grupos.
class SharedScreen extends StatefulWidget {
  final int initialTab;
  const SharedScreen({super.key, this.initialTab = 0});

  @override
  State<SharedScreen> createState() => _SharedScreenState();
}

class _SharedScreenState extends State<SharedScreen> {
  @override
  void initState() {
    super.initState();
    final sc = context.read<SharedController>();
    if (sc.available) {
      WidgetsBinding.instance.addPostFrameCallback((_) => sc.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SharedController>();
    if (!sc.available) {
      return Scaffold(
        appBar: AppBar(title: const Text('Despesas compartilhadas')),
        body: const SharedUnavailable(),
      );
    }
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Despesas compartilhadas'),
          actions: [
            if (sc.loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: 'Atualizar',
                icon: const Icon(Icons.refresh),
                onPressed: sc.refresh,
              ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Despesas'),
              const Tab(text: 'Resumo'),
              Tab(
                child: Badge(
                  isLabelVisible: sc.state.invites.isNotEmpty,
                  label: Text('${sc.state.invites.length}'),
                  child: const Text('Grupos'),
                ),
              ),
            ],
          ),
        ),
        body: sc.error != null && !sc.loaded
            ? ErrorState(message: sc.error!, onRetry: sc.refresh)
            : !sc.loaded
            ? const Center(child: CircularProgressIndicator())
            : const TabBarView(
                children: [_ExpensesTab(), _SummaryTab(), _GroupsTab()],
              ),
      ),
    );
  }
}

// Despesas ----------------------------------------------------------------------

class _ExpensesTab extends StatefulWidget {
  const _ExpensesTab();

  @override
  State<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<_ExpensesTab> {
  YearMonth? month = YearMonth.now();
  SharedFilter filter = const SharedFilter();

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SharedController>();
    final st = sc.state;
    final f = filter.copyWith(from: month, to: month);
    final list = SharedReport.filter(st, f);
    final totals = SharedReport.totals(list);
    final me = sc.me;
    final mine = totals.byUser[me];
    final people = <String, String>{
      for (final g in st.groups)
        for (final m in g.members) m.userId: m.name,
    };
    final categories = {for (final e in st.allExpenses) e.categoryName}.toList()
      ..sort();
    Widget menu<T>(
      String label,
      T? value,
      Map<T, String> options,
      ValueChanged<T?> on,
    ) => PopupMenuButton<Object>(
      tooltip: label,
      onSelected: (v) => on(v == _all ? null : v as T),
      itemBuilder: (_) => [
        PopupMenuItem(value: _all, child: Text('Todos ($label)')),
        for (final o in options.entries)
          PopupMenuItem(value: o.key as Object, child: Text(o.value)),
      ],
      child: Chip(
        avatar: Icon(value == null ? Icons.filter_list : Icons.check, size: 16),
        label: Text(value == null ? label : '$label: ${options[value]}'),
      ),
    );
    return Scaffold(
      floatingActionButton: sc.managedGroups.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'share-existing',
                  tooltip: 'Compartilhar despesa já lançada',
                  onPressed: () => _pickTransaction(context),
                  child: const Icon(Icons.group_add_outlined),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'share-new',
                  icon: const Icon(Icons.add),
                  label: const Text('Nova despesa'),
                  onPressed: () => newSharedExpense(context),
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: sc.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            if (st.groups.isEmpty)
              EmptyState(
                icon: Icons.groups_outlined,
                title: 'Nenhum grupo ainda',
                message: st.invites.isNotEmpty
                    ? 'Você tem convite pendente na aba Grupos.'
                    : 'Crie um grupo e convide quem divide despesas com você.',
                actionLabel: 'Criar grupo',
                onAction: () => createGroupFlow(context),
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (month != null)
                    MonthSwitcher(
                      month: month!,
                      onChanged: (m) => setState(() => month = m),
                    )
                  else
                    Text('Todos os meses', style: context.text.titleMedium),
                  TextButton(
                    onPressed: () => setState(
                      () => month = month == null ? YearMonth.now() : null,
                    ),
                    child: Text(month == null ? 'Por mês' : 'Todos'),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (st.groups.length > 1)
                    menu<String>(
                      'Grupo',
                      filter.groupId,
                      {for (final g in st.groups) g.id: g.name},
                      (v) =>
                          setState(() => filter = filter.copyWith(groupId: v)),
                    ),
                  menu<String>(
                    'Pessoa',
                    filter.participantId,
                    people,
                    (v) => setState(
                      () => filter = filter.copyWith(participantId: v),
                    ),
                  ),
                  menu<String>(
                    'Pago por',
                    filter.ownerId,
                    people,
                    (v) => setState(() => filter = filter.copyWith(ownerId: v)),
                  ),
                  menu<String>(
                    'Categoria',
                    filter.category,
                    {for (final c in categories) c: c},
                    (v) =>
                        setState(() => filter = filter.copyWith(category: v)),
                  ),
                  menu<PayStatus>(
                    'Situação',
                    filter.status,
                    {for (final s in PayStatus.values) s: s.label},
                    (v) => setState(() => filter = filter.copyWith(status: v)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Kpi('Total do grupo', Money(totals.total)),
                  _Kpi('Minha parte', Money(mine?.owed ?? 0)),
                  _Kpi(
                    'Eu devo',
                    Money(
                      list
                          .where((e) => e.ownerId != me)
                          .fold(
                            0,
                            (a, e) => a + (e.shareOf(me)?.outstanding ?? 0),
                          ),
                    ),
                    color: context.fin.negative,
                  ),
                  _Kpi(
                    'A receber',
                    Money(
                      list
                          .where((e) => e.ownerId == me)
                          .fold(0, (a, e) => a + e.outstanding),
                    ),
                    color: context.fin.positive,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Nenhuma despesa neste filtro')),
                ),
              for (final e in list) _ExpenseTile(e),
            ],
          ],
        ),
      ),
    );
  }

  /// Lança uma despesa nova e já segue para a divisão no grupo.
  Future<void> newSharedExpense(BuildContext context) async {
    final saved = await push<Object>(
      context,
      const TransactionFormScreen(sharing: true),
    );
    if (saved == null || !context.mounted) return;
    final ok = await showShareDialog(
      context,
      tx: saved is FinTransaction ? saved : null,
      rule: saved is RecurringRule ? saved : null,
    );
    if (!ok && context.mounted) {
      showMessage(
        context,
        'A despesa foi lançada só no seu orçamento. Para dividir, use '
        '"Compartilhar despesa já lançada".',
      );
    }
  }

  /// Escolhe uma despesa minha (ainda não compartilhada) para compartilhar.
  Future<void> _pickTransaction(BuildContext context) async {
    final fc = context.read<FinanceController>();
    final sc = context.read<SharedController>();
    final from = YearMonth.now().add(-3).firstDay;
    final to = YearMonth.now().add(2).lastDay;
    final shared = {
      for (final e in sc.state.allExpenses)
        if (e.ownerId == sc.me && !e.isDeleted) ?e.sourceKey,
    };
    final txs =
        fc.data.transactions
            .where(
              (t) =>
                  t.type == TransactionType.expense &&
                  t.status != TransactionStatus.cancelled &&
                  !SharedBudgetSync.isDerived(t.id) &&
                  !OtherSync.isDerived(t.id) &&
                  !shared.contains(t.id) &&
                  sc.expenseForTx(t) == null &&
                  !t.date.isBefore(from) &&
                  !t.date.isAfter(to),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final query = ValueNotifier('');
    final picked = await showDialog<FinTransaction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Qual despesa?'),
        content: SizedBox(
          width: 460,
          height: 480,
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar',
                ),
                onChanged: (v) => query.value = v.toLowerCase(),
              ),
              const SizedBox(height: 8),
              Text(
                'Para recorrências (aluguel, internet…), compartilhe pela tela '
                'da recorrência: as próximas ocorrências entram sozinhas.',
                style: ctx.text.bodySmall,
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: query,
                  builder: (_, q, _) {
                    final shown = txs
                        .where((t) => t.description.toLowerCase().contains(q))
                        .toList();
                    if (shown.isEmpty) {
                      return const Center(child: Text('Nenhuma despesa'));
                    }
                    return ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final t = shown[i];
                        return ListTile(
                          title: Text(t.description),
                          subtitle: Text(
                            '${Dates.format(t.date)}'
                            '${t.isCardTransaction ? ' · cartão' : ''}',
                          ),
                          trailing: MoneyText(t.amount),
                          onTap: () => Navigator.pop(ctx, t),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (picked != null && context.mounted) {
      await showShareDialog(context, tx: picked);
    }
  }
}

const _all = Object();

class _Kpi extends StatelessWidget {
  final String label;
  final Money value;
  final Color? color;
  const _Kpi(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.text.bodySmall),
            const SizedBox(height: 4),
            MoneyText(value, color: color, style: context.text.titleMedium),
          ],
        ),
      ),
    ),
  );
}

class _ExpenseTile extends StatelessWidget {
  final SharedExpense e;
  const _ExpenseTile(this.e);

  @override
  Widget build(BuildContext context) {
    final sc = context.read<SharedController>();
    final g = sc.group(e.groupId)!;
    final me = sc.me;
    final mine = e.shareOf(me);
    final status = e.ownerId == me ? e.status : mine?.status;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => push(context, SharedExpenseScreen(expenseId: e.id)),
        leading: CircleAvatar(
          child: Icon(
            e.recurrenceId != null ? Icons.autorenew : Icons.call_split,
            size: 20,
          ),
        ),
        title: Text(
          e.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${e.categoryName} · ${Dates.format(e.cashDate)} · '
          'pago por ${e.ownerId == me ? 'você' : g.nameOf(e.ownerId)}'
          '${sc.groups.length > 1 ? ' · ${g.name}' : ''}',
          maxLines: 2,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MoneyText(Money(e.total)),
            Text(
              mine == null
                  ? 'sem parte'
                  : 'minha: ${Money(mine.owed).format()}',
              style: context.text.bodySmall,
            ),
            payStatusPill(context, status),
          ],
        ),
      ),
    );
  }
}

// Resumo -------------------------------------------------------------------------

class _SummaryTab extends StatefulWidget {
  const _SummaryTab();

  @override
  State<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<_SummaryTab> {
  String? groupId;
  int year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SharedController>();
    final st = sc.state;
    if (st.groups.isEmpty) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: 'Sem dados ainda',
        message: 'Crie um grupo e compartilhe despesas para ver o resumo.',
      );
    }
    final g = st.group(groupId) ?? st.groups.first;
    final all = g.liveExpenses;
    final ofYear = all.where((e) => e.month.year == year).toList();
    final prevYear = all.where((e) => e.month.year == year - 1).toList();
    final totals = SharedReport.totals(ofYear);
    final byMonth = SharedReport.byMonth(ofYear);
    final prevByMonth = SharedReport.byMonth(prevYear);
    final ids = {
      ...g.activeIds,
      for (final e in ofYear) ...e.allocations.map((a) => a.userId),
    }.toList();
    final cats = totals.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCat = cats.isEmpty ? 1 : cats.first.value;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            if (st.groups.length > 1)
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: g.id,
                  decoration: const InputDecoration(labelText: 'Grupo'),
                  items: [
                    for (final x in st.groups)
                      DropdownMenuItem(value: x.id, child: Text(x.name)),
                  ],
                  onChanged: (v) => setState(() => groupId = v),
                ),
              )
            else
              Expanded(child: Text(g.name, style: context.text.titleMedium)),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => year--),
            ),
            Text('$year', style: context.text.titleMedium),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => year++),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Kpi('Total do grupo no ano', Money(totals.total)),
            _Kpi(
              'Em aberto',
              Money(totals.outstanding),
              color: context.fin.negative,
            ),
            _Kpi(
              'Ano anterior',
              Money(prevYear.fold(0, (a, e) => a + e.total)),
            ),
          ],
        ),
        SectionCard(
          title: 'Por participante',
          trailing: TextButton.icon(
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Acertar'),
            onPressed: () => showSettlementDialog(context, g),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              columns: const [
                DataColumn(label: Text('Pessoa')),
                DataColumn(numeric: true, label: Text('Responsabilidade')),
                DataColumn(numeric: true, label: Text('% do total')),
                DataColumn(numeric: true, label: Text('Pagou contas')),
                DataColumn(numeric: true, label: Text('Quitado')),
                DataColumn(numeric: true, label: Text('Em aberto')),
              ],
              rows: [
                for (final id in ids)
                  DataRow(
                    cells: [
                      DataCell(Text(g.nameOf(id))),
                      DataCell(Text(Money(totals.user(id).owed).format())),
                      DataCell(
                        Text(
                          totals.total == 0
                              ? '–'
                              : bpLabel(
                                  totals.user(id).owed * fullBp ~/ totals.total,
                                ),
                        ),
                      ),
                      DataCell(Text(Money(totals.user(id).fronted).format())),
                      DataCell(Text(Money(totals.user(id).paid).format())),
                      DataCell(
                        Text(
                          Money(totals.user(id).outstanding).format(),
                          style: TextStyle(
                            color: totals.user(id).outstanding > 0
                                ? context.fin.negative
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        SectionCard(
          title: 'Por categoria',
          child: Column(
            children: [
              if (cats.isEmpty) const Text('Sem despesas no ano'),
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 150, child: Text(c.key)),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: c.value / maxCat,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          Money(c.value).format(),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SectionCard(
          title: 'Mês a mês',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              columns: [
                const DataColumn(label: Text('Mês')),
                const DataColumn(numeric: true, label: Text('Total')),
                const DataColumn(numeric: true, label: Text('Ano anterior')),
                for (final id in ids)
                  DataColumn(numeric: true, label: Text(g.nameOf(id))),
                const DataColumn(numeric: true, label: Text('Pago')),
                const DataColumn(numeric: true, label: Text('Em aberto')),
              ],
              rows: [
                for (var m = 1; m <= 12; m++)
                  if (byMonth[YearMonth(year, m)] != null ||
                      prevByMonth[YearMonth(year - 1, m)] != null)
                    _monthRow(
                      YearMonth(year, m),
                      byMonth[YearMonth(year, m)],
                      prevByMonth[YearMonth(year - 1, m)],
                      ids,
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  DataRow _monthRow(
    YearMonth m,
    SharedTotals? t,
    SharedTotals? prev,
    List<String> ids,
  ) {
    final paid = t?.byUser.values.fold(0, (a, u) => a + u.paid) ?? 0;
    return DataRow(
      cells: [
        DataCell(Text(m.shortLabel)),
        DataCell(Text(Money(t?.total ?? 0).format())),
        DataCell(Text(prev == null ? '–' : Money(prev.total).format())),
        for (final id in ids)
          DataCell(Text(Money(t?.byUser[id]?.owed ?? 0).format())),
        DataCell(Text(Money(paid).format())),
        DataCell(Text(Money(t?.outstanding ?? 0).format())),
      ],
    );
  }
}

// Grupos -------------------------------------------------------------------------

class _GroupsTab extends StatelessWidget {
  const _GroupsTab();

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SharedController>();
    final st = sc.state;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Novo grupo'),
        onPressed: () => createGroupFlow(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          for (final i in st.invites)
            Card(
              color: context.colors.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text('Convite: ${i.groupName}'),
                subtitle: Text(
                  'De ${i.invitedBy ?? i.ownerName}. Ao aceitar, você vê as '
                  'despesas compartilhadas no grupo e a sua parte entra no '
                  'seu orçamento. Seu orçamento particular continua privado.',
                ),
                isThreeLine: true,
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Recusar',
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          runAction(context, () => sc.respondInvite(i, false)),
                    ),
                    IconButton(
                      tooltip: 'Aceitar',
                      icon: const Icon(Icons.check),
                      onPressed: () => runAction(
                        context,
                        () => sc.respondInvite(i, true),
                        success: 'Você entrou no grupo ${i.groupName}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (st.groups.isEmpty && st.invites.isEmpty)
            const EmptyState(
              icon: Icons.groups_outlined,
              title: 'Nenhum grupo',
              message:
                  'Grupos reúnem quem divide despesas: casa, casal, família, '
                  'moradores. Cada categoria tem o percentual de cada um.',
            ),
          for (final g in st.groups)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                title: Text(g.name + (g.archived ? ' (arquivado)' : '')),
                subtitle: Text(
                  '${g.kind.label} · ${g.activeMembers.map((m) => m.name).join(', ')}'
                  ' · ${g.liveExpenses.length} despesa(s)',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => push(context, GroupScreen(groupId: g.id)),
              ),
            ),
        ],
      ),
    );
  }
}
