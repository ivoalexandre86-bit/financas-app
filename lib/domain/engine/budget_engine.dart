import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/entities.dart';
import '../models/planning.dart';
import 'financial_engine.dart';

/// Situação de um orçamento no mês (regime de caixa, como o resto do app).
class BudgetStatus {
  final Budget budget;

  /// Já gasto: lançamentos realizados (concluídos ou fatura fechada).
  final Money spent;

  /// Ainda previsto no mês: pendentes, planejados e recorrências.
  final Money planned;

  const BudgetStatus(this.budget, this.spent, this.planned);

  Money get forecast => spent + planned;
  Money get remaining => budget.amount - spent;

  /// Fração gasta do limite (0 = nada, 1 = no limite, >1 = estourado).
  double get ratio => budget.amount.cents <= 0
      ? (spent.cents > 0 ? 2 : 0)
      : spent.cents / budget.amount.cents;
  double get forecastRatio => budget.amount.cents <= 0
      ? (forecast.cents > 0 ? 2 : 0)
      : forecast.cents / budget.amount.cents;

  bool get isOver => spent > budget.amount;
  bool get isAlert => !isOver && ratio * 100 >= budget.alertPercent;

  /// Pelo previsto, vai passar do limite até o fim do mês.
  bool get willExceed => !isOver && forecast > budget.amount;
}

/// Situação de uma meta de economia.
class GoalStatus {
  final SavingsGoal goal;
  final Money saved;
  final DateTime today;

  const GoalStatus(this.goal, this.saved, this.today);

  Money get remaining {
    final r = goal.target - saved;
    return r.isNegative ? Money.zero : r;
  }

  double get progress => goal.target.cents <= 0
      ? 1
      : (saved.cents / goal.target.cents).clamp(0, 1).toDouble();
  bool get reached => goal.target.cents > 0 && saved >= goal.target;

  /// Meses até o prazo, contando o mês atual (nulo = sem prazo).
  int? get monthsLeft {
    final d = goal.deadline;
    if (d == null) return null;
    final n = YearMonth.of(today).monthsUntil(YearMonth.of(d)) + 1;
    return n < 1 ? 0 : n;
  }

  /// Quanto guardar por mês para chegar no prazo (nulo = sem prazo).
  Money? get monthlyNeeded {
    final n = monthsLeft;
    if (n == null || reached) return null;
    if (n == 0) return remaining;
    return Money((remaining.cents / n).ceil());
  }

  bool get overdue =>
      !reached && goal.deadline != null && goal.deadline!.isBefore(today);
}

/// Cálculos de orçamentos e metas sobre o [FinancialEngine].
class BudgetEngine {
  final FinancialEngine engine;
  BudgetEngine(this.engine);

  /// Gasto de uma categoria (e subcategorias) no mês, separado em realizado
  /// e previsto.
  ({Money spent, Money planned}) categorySpending(
    String categoryId,
    YearMonth month,
  ) {
    var spent = Money.zero;
    var planned = Money.zero;
    final filter = ProjectionFilter(
      categoryIds: {categoryId},
      types: const {TransactionType.expense},
    );
    for (final e in engine.monthEvents(filter, month)) {
      if (!e.isExpense) continue;
      if (engine.isRealized(e.tx)) {
        spent += -e.signed;
      } else {
        planned += -e.signed;
      }
    }
    return (spent: spent, planned: planned);
  }

  BudgetStatus status(Budget b, YearMonth month) {
    final s = categorySpending(b.categoryId, month);
    return BudgetStatus(b, s.spent, s.planned);
  }

  /// Orçamentos do mês, os mais apertados primeiro.
  List<BudgetStatus> statuses(List<Budget> budgets, YearMonth month) =>
      [for (final b in budgets) status(b, month)]
        ..sort((a, b) => b.ratio.compareTo(a.ratio));

  /// Média mensal de gastos realizados da categoria nos [months] meses
  /// anteriores a [month] (base para sugerir um limite).
  Money averageSpending(String categoryId, YearMonth month, {int months = 3}) {
    var total = Money.zero;
    for (var i = 1; i <= months; i++) {
      final s = categorySpending(categoryId, month.add(-i));
      total += s.spent + s.planned;
    }
    return Money((total.cents / months).round());
  }

  /// Categorias de despesa (raiz) com gasto no mês e sem orçamento, das
  /// que mais gastaram para as que menos.
  List<({FinCategory category, Money amount})> unbudgeted(
    List<Budget> budgets,
    YearMonth month,
  ) {
    final have = {for (final b in budgets) b.categoryId};
    final out = <({FinCategory category, Money amount})>[];
    for (final c in engine.data.categories) {
      if (c.kind != CategoryKind.expense || c.parentId != null) continue;
      if (have.contains(c.id)) continue;
      final s = categorySpending(c.id, month);
      final v = s.spent + s.planned;
      if (v.isPositive) out.add((category: c, amount: v));
    }
    out.sort((a, b) => b.amount.compareTo(a.amount));
    return out;
  }

  GoalStatus goal(SavingsGoal g) {
    final saved =
        g.accountId != null && engine.data.accountById.containsKey(g.accountId)
        ? engine.accountBalance(g.accountId!)
        : g.contributions.fold(Money.zero, (s, c) => s + c.amount);
    return GoalStatus(g, saved, engine.today);
  }
}
