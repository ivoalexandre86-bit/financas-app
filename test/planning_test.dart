import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/finance_repository.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/planning.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  late MemoryRepo repo;
  late FinanceController fc;
  final today = Dates.today();
  final month = YearMonth.of(today);

  setUp(() async {
    repo = MemoryRepo();
    fc = FinanceController(repo);
    await fc.load();
    await fc.saveAccount(Account(id: 'a', name: 'Conta'));
  });

  FinTransaction tx(
    String id,
    int cents,
    String cat, {
    TransactionStatus status = TransactionStatus.completed,
    DateTime? date,
  }) => FinTransaction(
    id: id,
    type: TransactionType.expense,
    amount: Money(cents),
    description: id,
    categoryId: cat,
    date: date ?? month.firstDay,
    accountId: 'a',
    status: status,
  );

  test('orçamento soma subcategorias e separa gasto de previsto', () async {
    await fc.saveTransaction(tx('aluguel', 150000, 'cat_rent'));
    await fc.saveTransaction(
      tx('luz', 30000, 'cat_energy', status: TransactionStatus.pending),
    );
    await fc.saveBudget(
      Budget(id: 'b', categoryId: 'cat_housing', amount: const Money(170000)),
    );
    final s = fc.budgetEngine.status(fc.budgets.single, month);
    expect(s.spent, const Money(150000));
    expect(s.planned, const Money(30000));
    expect(s.isAlert, isTrue); // 88% ≥ 80%
    expect(s.isOver, isFalse);
    expect(s.willExceed, isTrue);
    expect(repo.stores[Coll.budgets]!.length, 1);

    // Recarrega do repositório.
    final again = FinanceController(repo);
    await again.load();
    expect(again.budgets.single.amount, const Money(170000));
  });

  test('uma categoria só pode ter um orçamento', () async {
    await fc.saveBudget(
      Budget(id: 'b1', categoryId: 'cat_housing', amount: const Money(100)),
    );
    expect(
      () => fc.saveBudget(
        Budget(id: 'b2', categoryId: 'cat_housing', amount: const Money(200)),
      ),
      throwsArgumentError,
    );
  });

  test('categoria sem orçamento aparece com o gasto do mês', () async {
    await fc.saveTransaction(tx('aluguel', 150000, 'cat_rent'));
    final free = fc.budgetEngine.unbudgeted(fc.budgets, month);
    expect(free.single.category.id, 'cat_housing');
    expect(free.single.amount, const Money(150000));
  });

  test('excluir categoria remove o orçamento dela', () async {
    await fc.saveCategory(
      FinCategory(
        id: 'x',
        name: 'Pets',
        kind: CategoryKind.expense,
        icon: 'pets',
        color: 0xFF000000,
      ),
    );
    await fc.saveBudget(
      Budget(id: 'b', categoryId: 'x', amount: const Money(100)),
    );
    await fc.deleteCategory(fc.data.categoryById['x']!);
    expect(fc.budgets, isEmpty);
    expect(repo.stores[Coll.budgets], isEmpty);
  });

  test('meta com aportes calcula quanto guardar por mês', () async {
    final g = SavingsGoal(
      id: 'g',
      name: 'Viagem',
      target: const Money(120000),
      deadline: month.add(3).firstDay,
      contributions: [
        GoalContribution(id: 'c', date: today, amount: const Money(40000)),
      ],
    );
    await fc.saveGoal(g);
    final st = fc.budgetEngine.goal(fc.goals.single);
    expect(st.saved, const Money(40000));
    expect(st.remaining, const Money(80000));
    expect(st.monthsLeft, 4);
    expect(st.monthlyNeeded, const Money(20000));

    await fc.addGoalContribution(
      fc.goals.single,
      GoalContribution(id: 'c2', date: today, amount: const Money(-10000)),
    );
    expect(fc.budgetEngine.goal(fc.goals.single).saved, const Money(30000));
  });

  test('meta vinculada usa o saldo da conta', () async {
    await fc.saveAccount(
      Account(id: 'r', name: 'Reserva', initialBalance: const Money(50000)),
    );
    await fc.saveGoal(
      SavingsGoal(
        id: 'g',
        name: 'Reserva',
        target: const Money(100000),
        accountId: 'r',
      ),
    );
    final st = fc.budgetEngine.goal(fc.goals.single);
    expect(st.saved, const Money(50000));
    expect(st.progress, 0.5);
  });
}
