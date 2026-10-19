import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/planning.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/budgets/budgets_screen.dart';
import 'package:financas_app/ui/screens/goals/goals_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  late FinanceController fc;

  Future<void> setup(WidgetTester tester, Widget home) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      await fc.saveTransaction(
        FinTransaction(
          id: 'm',
          type: TransactionType.expense,
          amount: const Money(90000),
          description: 'Mercado',
          categoryId: 'cat_groceries',
          date: YearMonth.now().firstDay,
          accountId: 'a',
        ),
      );
      await fc.saveTransaction(
        FinTransaction(
          id: 'r',
          type: TransactionType.expense,
          amount: const Money(150000),
          description: 'Aluguel',
          categoryId: 'cat_rent',
          date: YearMonth.now().firstDay,
          accountId: 'a',
        ),
      );
      await fc.saveBudget(
        Budget(id: 'b', categoryId: 'cat_food', amount: const Money(100000)),
      );
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('orçamentos mostram o gasto, o aviso e os gastos sem limite', (
    tester,
  ) async {
    await setup(tester, const BudgetsScreen());
    expect(find.text('Alimentação'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('Gastos sem orçamento'), findsOneWidget);
    expect(find.text('Moradia'), findsOneWidget);
  });

  testWidgets('metas: lista vazia e criação', (tester) async {
    await setup(tester, const GoalsScreen());
    expect(find.text('Nenhuma meta'), findsOneWidget);
    await tester.runAsync(
      () => fc.saveGoal(
        SavingsGoal(id: 'g', name: 'Viagem', target: const Money(100000)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Viagem'), findsOneWidget);
    expect(find.textContaining('(0%)'), findsOneWidget);
  });
}
