import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/month_closing.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/projection/month_adjust_screen.dart';
import 'package:financas_app/ui/screens/projection/month_closing_ui.dart';
import 'package:financas_app/ui/screens/projection/month_end_plan_screen.dart';
import 'package:financas_app/ui/screens/projection/projection_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

FinTransaction _tx(String id, TransactionType type, int cents, DateTime date) =>
    FinTransaction(
      id: id,
      type: type,
      amount: Money(cents),
      description: id,
      date: date,
      accountId: 'a',
    );

Future<FinanceController> _setup() async {
  final fc = FinanceController(MemoryRepo());
  await fc.load();
  await fc.saveAccount(Account(id: 'a', name: 'Conta'));
  final now = DateTime.now();
  final m = DateTime(now.year, now.month, 5);
  final prev = DateTime(now.year, now.month - 1, 5);
  await fc.saveTransaction(_tx('sal', TransactionType.income, 500000, m));
  await fc.saveTransaction(_tx('alug', TransactionType.expense, 200000, m));
  await fc.saveTransaction(_tx('old', TransactionType.income, 100000, prev));
  return fc;
}

void main() {
  final month = YearMonth.now();
  final prev = month.add(-1);

  test('JSON do fechamento ida e volta', () {
    final c = MonthClosing(
      month: month,
      income: const Money(100),
      expenses: const Money(40),
      computedIncome: const Money(100),
      computedExpenses: const Money(30),
      note: 'extrato',
    );
    final r = MonthClosing.fromJson(c.toJson());
    expect(r.id, month.key);
    expect(r.net, const Money(60));
    expect(r.isAdjusted, isTrue);
    expect(r.adjustment, const Money(-10));
    expect(r.note, 'extrato');
  });

  test('fechar mês congela o resultado e reabrir reverte', () async {
    final fc = await _setup();
    expect(
      fc.engine.monthTotals(ProjectionFilter.none, month).net.cents,
      300000,
    );

    final c = await fc.closeMonth(month);
    expect(c.isAdjusted, isFalse);

    // Lançamento novo no mês fechado não muda o resultado.
    final now = DateTime.now();
    await fc.saveTransaction(
      _tx(
        'extra',
        TransactionType.expense,
        50000,
        DateTime(now.year, now.month, 6),
      ),
    );
    expect(
      fc.engine.monthTotals(ProjectionFilter.none, month).net.cents,
      300000,
    );
    expect(
      fc.engine.computedMonthTotals(ProjectionFilter.none, month).net.cents,
      250000,
    );
    // Com filtro, continua mostrando o cálculo.
    final f = ProjectionFilter.none.copyWith(types: {TransactionType.expense});
    expect(fc.engine.monthTotals(f, month).expenses.cents, 250000);

    await fc.reopenMonth(month);
    expect(fc.closingOf(month), isNull);
    expect(
      fc.engine.monthTotals(ProjectionFilter.none, month).net.cents,
      250000,
    );
  });

  test(
    'ajuste manual muda o resultado e o acumulado dos meses seguintes',
    () async {
      final fc = await _setup();
      final range = MonthRange(prev, month.add(1));
      final before = fc.engine.projection(range);
      expect(before.columns[0].net.cents, 100000);

      await fc.adjustMonthResult(
        prev,
        income: const Money(100000),
        expenses: const Money(30000),
        note: 'tarifa não lançada',
      );
      final c = fc.closingOf(prev)!;
      expect(c.isAdjusted, isTrue);
      expect(c.adjustment.cents, -30000);

      final after = fc.engine.projection(range);
      expect(after.columns[0].net.cents, 70000);
      expect(after.columns[1].net.cents, 300000);
      expect(
        after.columns.last.accumulated.cents,
        before.columns.last.accumulated.cents - 30000,
      );

      // Mês fechado antes do período também entra no saldo inicial.
      final later = fc.engine.projection(MonthRange(month, month));
      final laterBefore = before.columns[1].opening;
      expect(later.openingBalance.cents, laterBefore.cents - 30000);

      // Reverter todos os ajustes.
      await fc.closeMonth(month);
      expect(await fc.reopenMonths(), 2);
      expect(fc.monthClosings, isEmpty);
      expect(fc.engine.projection(range).columns[0].net.cents, 100000);
    },
  );

  test('ajustes mês a mês: soma ao resultado e zero reabre', () async {
    final fc = await _setup();
    await fc.closeMonth(prev);
    await fc.saveMonthAdjustments({
      month: const Money(-50000),
      month.add(1): const Money(12345),
      prev: Money.zero,
    });
    final c = fc.closingOf(month)!;
    expect(c.income.cents, 500000);
    expect(c.expenses.cents, 250000);
    expect(c.adjustment, const Money(-50000));
    final next = fc.closingOf(month.add(1))!;
    expect(next.net, const Money(12345));
    expect(next.isAdjusted, isTrue);
    expect(fc.closingOf(prev), isNull);
    expect(
      fc.engine.monthTotals(ProjectionFilter.none, month).net,
      const Money(250000),
    );
  });

  test('ajuste não aceita valores negativos', () async {
    final fc = await _setup();
    expect(
      () => fc.adjustMonthResult(
        month,
        income: const Money(-1),
        expenses: Money.zero,
      ),
      throwsArgumentError,
    );
  });

  testWidgets('projeção: tocar no mês fecha, ajusta e reabre', (tester) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late FinanceController fc;
    await tester.runAsync(() async => fc = await _setup());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const ProjectionScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(ValueKey('proj-month-${month.key}')));
    await tester.pumpAndSettle();
    expect(find.text('Fechar mês'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('closing-close')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(fc.closingOf(month), isNotNull);
    // Último passo do fechamento: "O que fazer agora?".
    expect(find.byType(MonthEndPlanScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('fechado'), findsOneWidget);

    // Ajuste manual: abre a grade mês a mês e digita o ajuste.
    await tester.tap(find.byKey(ValueKey('proj-month-${month.key}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('closing-adjust')));
    await tester.pumpAndSettle();
    expect(find.byType(MonthAdjustScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(ValueKey('adjust-cell-${month.key}')),
      '-500',
    );
    await tester.pump();
    expect(find.text('Salvar (1)'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('adjust-grid-save')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(MonthAdjustScreen), findsNothing);
    expect(fc.closingOf(month)!.expenses.cents, 250000);
    expect(fc.closingOf(month)!.isAdjusted, isTrue);
    expect(find.text('ajustado'), findsOneWidget);

    // Lista de fechamentos: reverter ajustes manuais.
    await tester.tap(find.byKey(const ValueKey('proj-closings')));
    await tester.pumpAndSettle();
    expect(find.byType(MonthClosingsScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('closings-revert-adjusted')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Reverter'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(fc.closingOf(month), isNull);
    expect(find.text('Nenhum mês fechado'), findsOneWidget);
  });
}
