import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/projection_filter.dart';
import 'package:financas_app/domain/engine/simulation_engine.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/simulation.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/simulations/simulation_screen.dart';
import 'package:financas_app/ui/screens/simulations/simulations_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

final _jan = YearMonth.now().add(3);
final _dec = _jan.add(11);
final _mar = _jan.add(2);

Future<FinanceController> _setup() async {
  final fc = FinanceController(MemoryRepo());
  await fc.load();
  await fc.saveAccount(
    Account(id: 'a', name: 'Conta', initialBalance: const Money(1000000)),
  );
  await fc.createRule(
    RecurringRule(
      id: 'rent',
      type: TransactionType.expense,
      amount: const Money(100000),
      description: 'Aluguel',
      accountId: 'a',
      dayOfMonth: 5,
      startDate: Dates.clampedDate(_jan.year, _jan.month, 5),
    ),
  );
  await fc.createRule(
    RecurringRule(
      id: 'salary',
      type: TransactionType.income,
      amount: const Money(500000),
      description: 'Salário',
      accountId: 'a',
      dayOfMonth: 1,
      startDate: Dates.clampedDate(_jan.year, _jan.month, 1),
    ),
  );
  await fc.saveTransaction(
    FinTransaction(
      id: 'bonus',
      type: TransactionType.income,
      amount: const Money(50000),
      description: 'Bônus',
      date: Dates.clampedDate(_mar.year, _mar.month, 10),
      accountId: 'a',
      status: TransactionStatus.planned,
    ),
  );
  return fc;
}

void main() {
  test('simulação copia o orçamento do período e nunca altera os dados '
      'reais; aplicar exige o plano', () async {
    final fc = await _setup();
    final sim = await fc.createSimulation(
      name: 'Carro novo',
      from: _jan,
      to: _dec,
    );
    expect(sim.months.length, 12);
    expect(sim.items.length, 3);
    final rent = sim.items.firstWhere((i) => i.description == 'Aluguel');
    expect(rent.sourceKey, 'r:rent');
    expect(rent.recurrence, SimRecurrence.monthly);
    expect(rent.totalIn(sim.months), 1200000);
    final bonus = sim.items.firstWhere((i) => i.description == 'Bônus');
    expect(bonus.valueAt(_mar), 50000);
    expect(sim.opening, 1000000);

    // Totais: 5000 − 1000 por mês, + 500 em março.
    final t = SimTotals.of(sim.items, sim.months, sim.opening);
    expect(t.months[2].net, 450000);
    expect(t.finalBalance, 1000000 + 12 * 400000 + 50000);

    // Edições: aluguel 1200 em março, carro 2500/mês, sem bônus.
    final car = SimItem(
      id: 'car',
      type: TransactionType.expense,
      description: 'Financiamento do carro',
      accountId: 'a',
      day: 15,
    ).fill(250000, _jan, _dec, SimRecurrence.monthly);
    final edited = sim.copyWith(
      items: [
        for (final i in sim.items)
          if (i.id == rent.id)
            i.withValue(_mar, 120000)
          else if (i.id != bonus.id)
            i,
        car,
      ],
    );
    final txBefore = fc.data.transactions.length;
    final rulesBefore = fc.data.recurringRules.length;
    await fc.saveSimulation(edited);
    // Sandbox: nada mudou nos lançamentos oficiais.
    expect(fc.data.transactions.length, txBefore);
    expect(fc.data.recurringRules.length, rulesBefore);
    expect(
      fc.engine.monthTotals(ProjectionFilter.none, _mar).expenses,
      const Money(100000),
    );

    final saved = fc.simulationById(sim.id)!;
    final impacts = SimulationEngine.impacts(saved);
    expect(impacts.first.item.description, 'Financiamento do carro');
    expect(impacts.first.effect, -3000000);

    final plan = fc.simulationPlan(saved);
    expect(plan.changes.map((c) => c.kind).toSet(), {
      SimChangeKind.newExpense,
      SimChangeKind.modifiedExpense,
      SimChangeKind.removedIncome,
    });
    expect(plan.rules.single.amount, const Money(250000));

    await fc.applySimulation(saved);
    final m = fc.engine.monthTotals(ProjectionFilter.none, _mar);
    expect(m.expenses, const Money(120000 + 250000));
    expect(m.income, const Money(500000));
    expect(fc.data.transactions.any((t) => t.id == 'bonus'), isFalse);
    expect(fc.simulationById(sim.id)!.appliedAt, isNotNull);
  });

  test('duplicar cria cenário independente', () async {
    final fc = await _setup();
    final a = await fc.createSimulation(name: 'A', from: _jan, to: _dec);
    final b = await fc.duplicateSimulation(a, 'A + férias');
    await fc.saveSimulation(b.copyWith(items: b.items.take(1).toList()));
    expect(fc.simulationById(a.id)!.items.length, 3);
    expect(fc.simulationById(b.id)!.items.length, 1);
    expect(fc.simulationById(b.id)!.baseName, 'A');

    final fromSim = await fc.createSimulation(
      name: 'Só março',
      from: _mar,
      to: _mar,
      base: fc.simulationById(a.id),
    );
    // Saldo inicial de março = saldo inicial + jan e fev da base.
    expect(fromSim.opening, 1000000 + 2 * 400000);
    expect(fromSim.months, [_mar]);
  });

  testWidgets('gestão e planilha: criar, editar célula, salvar', (
    tester,
  ) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late FinanceController fc;
    late Simulation sim;
    await tester.runAsync(() async {
      fc = await _setup();
      sim = await fc.createSimulation(name: 'Base 1', from: _jan, to: _dec);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SimulationsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Base 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('sim-create')), findsOneWidget);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SimulationScreen(simulationId: sim.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rent = sim.items.firstWhere((i) => i.description == 'Aluguel');
    final cell = find.byKey(ValueKey('sim-cell-${rent.id}-${_jan.key}'));
    expect(cell, findsOneWidget);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sim-cell-editor')),
      '1000+250',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('não salva'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sim-save')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final saved = fc.simulationById(sim.id)!;
    expect(
      saved.items.firstWhere((i) => i.id == rent.id).valueAt(_jan),
      125000,
    );
    // Dados reais intactos.
    expect(fc.data.transactions.length, 1);

    // Abas de comparação e painel desenham sem erros.
    await tester.tap(find.text('Comparação'));
    await tester.pumpAndSettle();
    expect(find.text('Total do período'), findsOneWidget);
    await tester.tap(find.text('Painel'));
    await tester.pumpAndSettle();
    expect(find.text('Maiores impactos'), findsOneWidget);
  });
}
