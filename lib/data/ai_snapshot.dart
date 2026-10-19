import '../core/dates.dart';
import '../core/money.dart';
import '../domain/engine/budget_engine.dart';
import '../domain/engine/financial_engine.dart';
import '../domain/models/entities.dart';
import '../domain/models/planning.dart';
import 'report_export.dart';

/// Retrato das finanças em texto para o assistente com IA: saldos, meses
/// (passados e projetados), categorias, orçamentos, metas e pendências do
/// mês. Usa o mesmo motor das telas (visão de caixa).
String buildAiSnapshot(
  FinancialEngine engine, {
  List<Budget> budgets = const [],
  List<SavingsGoal> goals = const [],
  int monthsBack = 6,
  int monthsAhead = 3,
}) {
  final b = StringBuffer();
  String brl(Money m) => m.formatVisible();
  final now = engine.currentMonth;
  b.writeln('Hoje: ${Dates.format(engine.today)}');

  b.writeln('\nSaldos das contas ativas:');
  for (final a in engine.data.accounts.where((a) => a.active)) {
    b.writeln('- ${a.name}: ${brl(engine.accountBalance(a.id))}');
  }
  b.writeln('Saldo total: ${brl(engine.currentBalance)}');
  final cards = engine.data.cards.where((c) => c.active).toList();
  if (cards.isNotEmpty) {
    b.writeln('Cartões: ${cards.map((c) => c.name).join(', ')}');
  }

  final r = ReportExport(
    engine,
    now.add(-(monthsBack - 1)),
    now.add(monthsAhead),
  );
  b.writeln(
    '\nReceitas e despesas por mês (meses depois de ${now.longLabel} são '
    'projeção com recorrências, parcelas e faturas):',
  );
  for (final m in r.monthly) {
    b.writeln(
      '- ${m.month.longLabel}: receitas ${brl(m.income)}, despesas '
      '${brl(m.expenses)}, resultado ${brl(m.income - m.expenses)}',
    );
  }

  final recent = [for (var i = 3; i >= 0; i--) now.add(-i)];
  b.writeln(
    '\nDespesas por categoria (${recent.map((m) => m.shortLabel).join(' | ')}):',
  );
  for (final c in r.expensesByCategory.take(20)) {
    final vals = [for (final m in recent) brl(c.byMonth[m] ?? Money.zero)]
        .join(' | ');
    b.writeln('- ${c.category}: $vals');
  }

  final be = BudgetEngine(engine);
  if (budgets.isNotEmpty) {
    b.writeln('\nOrçamentos de ${now.longLabel}:');
    for (final s in be.statuses(budgets, now)) {
      b.writeln(
        '- ${engine.categoryLabel(s.budget.categoryId)}: limite '
        '${brl(s.budget.amount)}, gasto ${brl(s.spent)}, previsto '
        '${brl(s.planned)}, uso ${(s.ratio * 100).round()}%',
      );
    }
  }

  final active = goals.where((g) => !g.archived).toList();
  if (active.isNotEmpty) {
    b.writeln('\nMetas de economia:');
    for (final g in active) {
      final s = be.goal(g);
      b.writeln(
        '- ${g.name}: alvo ${brl(g.target)}, guardado ${brl(s.saved)}'
        '${g.deadline == null ? '' : ', prazo ${Dates.format(g.deadline!)}'}'
        '${s.monthlyNeeded == null ? '' : ', precisa ${brl(s.monthlyNeeded!)} por mês'}',
      );
    }
  }

  final month = ReportExport(engine, now, now).rows;
  final open = month
      .where(
        (e) =>
            e.status == TransactionStatus.pending ||
            e.status == TransactionStatus.planned,
      )
      .toList();
  if (open.isNotEmpty) {
    b.writeln('\nEm aberto em ${now.longLabel} (data no caixa):');
    for (final e in open.take(40)) {
      b.writeln(
        '- ${Dates.format(e.cashDate)} ${e.description} (${e.category}): '
        '${brl(e.amount)}',
      );
    }
  }
  final top = [...month.where((e) => e.amount.isNegative)]
    ..sort((a, b) => a.amount.compareTo(b.amount));
  if (top.isNotEmpty) {
    b.writeln('\nMaiores despesas de ${now.longLabel}:');
    for (final e in top.take(10)) {
      b.writeln(
        '- ${Dates.format(e.cashDate)} ${e.description} (${e.category}, '
        '${e.where}): ${brl(e.amount)}',
      );
    }
  }
  return b.toString();
}
