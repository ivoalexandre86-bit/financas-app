import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/auth_service.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/auth_controller.dart';
import '../../../state/finance_controller.dart';
import '../../app_shell.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../cards/invoice_details_screen.dart';
import '../cards/invoices_screen.dart';
import '../dashboards/dashboard_view.dart';
import '../dashboards/dashboards_screen.dart';
import '../installments/installments_screen.dart';
import '../projection/drilldown_screen.dart';
import '../recurring/recurring_screen.dart';
import '../transactions/transaction_details_screen.dart';
import '../transactions/transaction_form_screen.dart';

/// Painel inicial: resumo do mês, indicadores e próximos vencimentos.
/// Todos os valores vêm do [FinancialEngine].
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  YearMonth month = YearMonth.now();

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final user = context.watch<AuthController>().user;
    final e = fc.engine;
    final totals = e.monthTotals(ProjectionFilter.none, month);
    final projected = e
        .projection(MonthRange(month, month))
        .columns
        .first
        .accumulated;
    final hasData = fc.data.accounts.isNotEmpty;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-home',
        onPressed: () => push(context, const TransactionFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nova transação'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: fc.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _Header(
                user: user,
                month: month,
                onMonth: (m) => setState(() => month = m),
              ),
              const SizedBox(height: 8),
              if (!hasData)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SectionCard(
                    child: EmptyState(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Comece cadastrando uma conta',
                      message: 'Seus saldos e projeções são calculados a partir das contas e lançamentos.',
                      actionLabel: 'Ir para Contas',
                      onAction: () => AppShell.goToTab(context, 4),
                    ),
                  ),
                ),
              _BalanceHero(
                current: e.currentBalance,
                available: e.availableBalance,
                projected: projected,
                month: month,
              ),
              const SizedBox(height: 12),
              _PendingKpis(engine: e, month: month),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'Receitas',
                      value: totals.income,
                      color: context.fin.income,
                      icon: Icons.south_west,
                      onTap: () => push(
                        context,
                        DrilldownScreen(month: month, row: DrillRow.income),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      label: 'Despesas',
                      value: totals.expenses,
                      color: context.fin.expense,
                      icon: Icons.north_east,
                      onTap: () => push(
                        context,
                        DrilldownScreen(month: month, row: DrillRow.expenses),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _StatTile(
                label: 'Resultado do mês',
                value: totals.net,
                colorize: true,
                icon: Icons.balance,
                onTap: () => push(
                  context,
                  DrilldownScreen(month: month, row: DrillRow.net),
                ),
              ),
              const SizedBox(height: 12),
              _DefaultDashboardSection(reference: month),
              const SizedBox(height: 12),
              _UpcomingCard(engine: e),
              const SizedBox(height: 12),
              _CardBillsCard(engine: e),
              const SizedBox(height: 12),
              _CommitmentsCard(engine: e, month: month),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AppUser? user;
  final YearMonth month;
  final ValueChanged<YearMonth> onMonth;
  const _Header({
    required this.user,
    required this.month,
    required this.onMonth,
  });

  @override
  Widget build(BuildContext context) {
    final first = (user?.name ?? '').split(' ').first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.isDemo == true ? 'Olá!' : 'Olá, $first',
                style: context.text.titleLarge,
              ),
              Text(
                'Resumo financeiro',
                style: context.text.bodySmall?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
            ],
          ),
        ),
        MonthSwitcher(month: month, onChanged: onMonth),
      ],
    );
  }
}

/// Painel padrão do usuário (personalizável) exibido na tela inicial.
/// Segue o mês selecionado no topo como mês de referência.
class _DefaultDashboardSection extends StatelessWidget {
  final YearMonth reference;
  const _DefaultDashboardSection({required this.reference});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final d = fc.defaultDashboard;
    if (d == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.space_dashboard_outlined,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(d.name, style: context.text.titleMedium),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => push(
                      context,
                      DashboardsScreen(dashboardId: d.id, reference: reference),
                    ),
                    child: const Text('Meus painéis'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('customize-dashboard'),
                    icon: const Icon(Icons.dashboard_customize_outlined),
                    label: const Text('Personalizar painel'),
                    onPressed: () =>
                        push(context, customizeDashboard(d, reference)),
                  ),
                ],
              ),
            ],
          ),
        ),
        DashboardGrid(dashboard: d, reference: reference),
      ],
    );
  }
}

class _BalanceHero extends StatelessWidget {
  final Money current;
  final Money available;
  final Money projected;
  final YearMonth month;
  const _BalanceHero({
    required this.current,
    required this.available,
    required this.projected,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final onHero = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.75);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1B3FA6), Color(0xFF2457D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saldo atual',
            style: context.text.labelLarge?.copyWith(color: muted),
          ),
          const SizedBox(height: 4),
          MoneyText(
            current,
            style: context.text.headlineMedium?.copyWith(color: onHero),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroValue(
                  label: 'Disponível',
                  tooltip: 'Saldo atual menos despesas e faturas em aberto até o fim deste mês',
                  value: available,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              const SizedBox(width: 16),
              Expanded(
                child: _HeroValue(
                  label: 'Projetado · fim de ${month.shortLabel}',
                  tooltip: 'Saldo acumulado da projeção, considerando lançamentos planejados, recorrências, parcelas e faturas',
                  value: projected,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroValue extends StatelessWidget {
  final String label;
  final String tooltip;
  final Money value;
  const _HeroValue({
    required this.label,
    required this.tooltip,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.text.labelMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 2),
        MoneyText(
          value,
          style: context.text.titleMedium?.copyWith(
            color: value.isNegative ? const Color(0xFFFFB4A9) : Colors.white,
          ),
        ),
      ],
    ),
  );
}

/// Indicadores (KPIs) das pendências do mês selecionado.
class _PendingKpis extends StatelessWidget {
  final FinancialEngine engine;
  final YearMonth month;
  const _PendingKpis({required this.engine, required this.month});

  @override
  Widget build(BuildContext context) {
    final p = engine.monthPendings(month);
    const pendingFilter = ProjectionFilter(
      statuses: {TransactionStatus.planned, TransactionStatus.pending},
    );
    final tiles = [
      _KpiTile(
        key: const ValueKey('kpi-expenses'),
        label: 'Despesas a pagar',
        tally: p.expenses,
        icon: Icons.north_east,
        color: context.fin.expense,
        onTap: () => push(
          context,
          DrilldownScreen(
            month: month,
            row: DrillRow.expenses,
            filter: pendingFilter,
          ),
        ),
      ),
      _KpiTile(
        key: const ValueKey('kpi-incomes'),
        label: 'Receitas a receber',
        tally: p.incomes,
        icon: Icons.south_west,
        color: context.fin.income,
        onTap: () => push(
          context,
          DrilldownScreen(
            month: month,
            row: DrillRow.income,
            filter: pendingFilter,
          ),
        ),
      ),
      _KpiTile(
        key: const ValueKey('kpi-invoices'),
        label: 'Faturas a pagar',
        tally: p.invoices,
        icon: Icons.credit_card,
        color: context.colors.primary,
        onTap: () => push(context, const InvoicesScreen()),
      ),
      _KpiTile(
        key: const ValueKey('kpi-overdue'),
        label: 'Vencidas',
        tally: p.overdue,
        icon: Icons.warning_amber_rounded,
        color: p.overdue.count > 0 ? context.fin.negative : context.fin.subtle,
        highlight: p.overdue.count > 0,
        onTap: () => AppShell.goToTab(context, 1),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            'Pendências de ${month.longLabel.toLowerCase()}',
            style: context.text.titleSmall,
          ),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 640 ? 4 : 2;
            const gap = 8.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final t in tiles) SizedBox(width: w, child: t)],
            );
          },
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final PendingTally tally;
  final IconData icon;
  final Color color;
  final bool highlight;
  final VoidCallback onTap;
  const _KpiTile({
    super.key,
    required this.label,
    required this.tally,
    required this.icon,
    required this.color,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final n = tally.count;
    return Card(
      color: highlight ? color.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlight
              ? color.withValues(alpha: 0.5)
              : context.colors.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelMedium?.copyWith(
                        color: context.fin.subtle,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  tally.total,
                  style: context.text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                n == 0 ? 'Nada pendente' : '$n ${n == 1 ? 'item' : 'itens'}',
                style: context.text.bodySmall?.copyWith(
                  color: n == 0 ? context.fin.subtle : color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final Money value;
  final Color? color;
  final bool colorize;
  final IconData icon;
  final VoidCallback? onTap;
  const _StatTile({
    required this.label,
    required this.value,
    this.color,
    this.colorize = false,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        color ??
        (value.isNegative ? context.fin.negative : context.fin.positive);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: context.text.labelMedium?.copyWith(
                        color: context.fin.subtle,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(
                        value,
                        colorize: colorize,
                        style: context.text.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: context.fin.subtle),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  final FinancialEngine engine;
  const _UpcomingCard({required this.engine});

  @override
  Widget build(BuildContext context) {
    final items = engine.upcoming(days: 30, limit: 8);
    return SectionCard(
      title: 'Próximos vencimentos',
      trailing: TextButton(
        onPressed: () => AppShell.goToTab(context, 1),
        child: const Text('Ver todos'),
      ),
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhum vencimento nos próximos 30 dias.'),
            )
          : Column(
              children: [
                for (final it in items)
                  ListTile(
                    dense: true,
                    onTap: () {
                      if (it.invoice != null) {
                        push(
                          context,
                          InvoiceDetailsScreen(
                            cardId: it.invoice!.card.id,
                            month: it.invoice!.month,
                          ),
                        );
                      } else if (it.tx != null) {
                        push(context, TransactionDetailsScreen(tx: it.tx!));
                      }
                    },
                    leading: _DateBadge(date: it.date, overdue: it.overdue),
                    title: Text(
                      it.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${it.where} · ${it.overdue ? 'Atrasado' : it.statusLabel}',
                      style: TextStyle(
                        color: it.overdue ? context.fin.negative : null,
                      ),
                    ),
                    trailing: MoneyText(
                      it.isIncome ? it.amount : -it.amount,
                      showPlus: it.isIncome,
                      color: it.isIncome ? context.fin.positive : null,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  final DateTime date;
  final bool overdue;
  const _DateBadge({required this.date, required this.overdue});
  @override
  Widget build(BuildContext context) {
    final c = overdue ? context.fin.negative : context.colors.primary;
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${date.day}'.padLeft(2, '0'),
            style: context.text.titleSmall?.copyWith(
              color: c,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          Text(
            YearMonth.of(date).shortLabel.split('/').first,
            style: context.text.labelSmall?.copyWith(color: c, height: 1.1),
          ),
        ],
      ),
    );
  }
}

class _CardBillsCard extends StatelessWidget {
  final FinancialEngine engine;
  const _CardBillsCard({required this.engine});

  @override
  Widget build(BuildContext context) {
    final cards = engine.data.cards.where((c) => c.active).toList();
    if (cards.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: 'Faturas de cartão',
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Column(
        children: [
          for (final card in cards)
            () {
              // Próxima fatura a vencer com saldo (ou a fatura aberta).
              final invs = engine.invoicesForCard(card);
              final next = invs
                  .where(
                    (i) =>
                        !i.dueDate.isBefore(engine.today) ||
                        !i.remaining.isZero,
                  )
                  .where((i) => !i.isSettled)
                  .toList();
              final inv = next.isNotEmpty ? next.first : invs.last;
              return ListTile(
                onTap: () => push(
                  context,
                  InvoiceDetailsScreen(cardId: card.id, month: inv.month),
                ),
                leading: Icon(Icons.credit_card, color: Color(card.color)),
                title: Text(card.name),
                subtitle: Text(
                  '${inv.status.label} · vence ${Dates.format(inv.dueDate)}',
                ),
                trailing: MoneyText(
                  inv.remaining,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}

class _CommitmentsCard extends StatelessWidget {
  final FinancialEngine engine;
  final YearMonth month;
  const _CommitmentsCard({required this.engine, required this.month});

  @override
  Widget build(BuildContext context) {
    final recurring = engine.recurringExpensesIn(month);
    final activeRules = engine.data.recurringRules
        .where(
          (r) =>
              r.type == TransactionType.expense &&
              !r.isPaused &&
              !r.isEndedBy(engine.today),
        )
        .length;
    final inst = engine.futureInstallments();
    final planned = engine.monthEvents(
      const ProjectionFilter(
        types: {TransactionType.expense},
        statuses: {TransactionStatus.planned, TransactionStatus.pending},
      ),
      month,
    );
    return SectionCard(
      title: 'Compromissos',
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.autorenew),
            title: const Text('Despesas recorrentes no mês'),
            subtitle: Text('$activeRules regras ativas'),
            trailing: MoneyText(
              recurring,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => push(context, const RecurringScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.view_week_outlined),
            title: const Text('Parcelas futuras'),
            subtitle: Text('${inst.count} parcelas a vencer'),
            trailing: MoneyText(
              inst.total,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => push(context, const InstallmentsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: const Text('Ainda a pagar no mês'),
            subtitle: Text(
              '${planned.length} lançamentos planejados/pendentes',
            ),
            trailing: MoneyText(
              planned.map((e) => -e.signed).sum(),
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => push(
              context,
              DrilldownScreen(
                month: month,
                row: DrillRow.expenses,
                filter: const ProjectionFilter(
                  statuses: {
                    TransactionStatus.planned,
                    TransactionStatus.pending,
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
