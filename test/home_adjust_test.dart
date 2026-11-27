import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/auth_service.dart';
import 'package:financas_app/domain/engine/projection_filter.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/auth_controller.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/home/home_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
  });

  Future<FinanceController> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta A'));
      await fc.saveAccount(Account(id: 'b', name: 'Conta B'));
      final now = DateTime.now();
      await fc.saveTransaction(
        FinTransaction(
          id: 'sal',
          type: TransactionType.income,
          amount: const Money(100000),
          description: 'salário',
          date: DateTime(now.year, now.month, 1),
          accountId: 'a',
          status: TransactionStatus.completed,
        ),
      );
      await fc.saveTransaction(
        FinTransaction(
          id: 'alug',
          type: TransactionType.expense,
          amount: const Money(150000),
          description: 'aluguel',
          date: DateTime(now.year, now.month, 1),
          accountId: 'a',
          status: TransactionStatus.completed,
        ),
      );
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthController(LocalAuthService()),
          ),
          ChangeNotifierProvider.value(value: fc),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const HomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return fc;
  }

  testWidgets('Início: ajustar saldo direto no card Saldo atual', (
    tester,
  ) async {
    final fc = await pumpHome(tester);
    expect(fc.engine.currentBalance.cents, -50000);

    await tester.tap(find.byKey(const ValueKey('home-adjust-balance')));
    await tester.pumpAndSettle();
    expect(find.text('Qual conta você quer ajustar?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('adjust-pick-a')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('acc-adjust-value')),
      '0,00',
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('acc-adjust-ok')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(fc.engine.accountBalance('a'), Money.zero);
    expect(fc.engine.currentBalance, Money.zero);
  });

  testWidgets('Início: ajuste do fechamento aparece em linha própria', (
    tester,
  ) async {
    final fc = await pumpHome(tester);
    final month = YearMonth.now();
    await tester.runAsync(
      () => fc.adjustMonthResult(
        month,
        income: const Money(150000),
        expenses: const Money(150000),
      ),
    );
    await tester.pumpAndSettle();
    // Receitas e despesas continuam as dos lançamentos; o ajuste fica à parte.
    expect(find.byKey(const ValueKey('home-month-adjustment')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-month-adjustment')),
        matching: find.textContaining('500,00'),
      ),
      findsOneWidget,
    );
    final t = fc.engine.monthTotals(ProjectionFilter.none, month);
    expect(t.income.cents, 100000);
    expect(t.expenses.cents, 150000);
    expect(t.adjustment.cents, 50000);
    expect(t.net, Money.zero);
  });
}
