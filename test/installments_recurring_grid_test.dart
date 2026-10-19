import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/installments/installments_screen.dart';
import 'package:financas_app/ui/screens/recurring/recurring_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  Future<FinanceController> setup(WidgetTester tester) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      await fc.saveCard(
        CreditCard(id: 'c6', name: 'C6', closingDay: 25, dueDay: 5),
      );
      final today = fc.today;
      await fc.createInstallmentPurchase(
        InstallmentGroup(
          id: 'tv',
          description: 'Televisão',
          totalAmount: const Money(120000),
          count: 12,
          purchaseDate: DateTime(today.year, today.month - 2, 10),
          accountId: 'a',
        ),
      );
      await fc.createInstallmentPurchase(
        InstallmentGroup(
          id: 'fone',
          description: 'Fone',
          totalAmount: const Money(30000),
          count: 3,
          purchaseDate: DateTime(today.year - 1, 1, 10),
          accountId: 'a',
        ),
      );
      await fc.createRule(
        RecurringRule(
          id: 'sal',
          type: TransactionType.income,
          amount: const Money(500000),
          description: 'Salário',
          accountId: 'a',
          startDate: DateTime(today.year - 1, 1, 5),
        ),
      );
      await fc.createRule(
        RecurringRule(
          id: 'net',
          type: TransactionType.expense,
          amount: const Money(10000),
          description: 'Internet',
          accountId: 'a',
          startDate: DateTime(today.year - 1, 1, 10),
        ),
      );
      await fc.createRule(
        RecurringRule(
          id: 'old',
          type: TransactionType.expense,
          amount: const Money(5000),
          description: 'Academia',
          accountId: 'a',
          startDate: DateTime(today.year - 2, 1, 10),
          endDate: DateTime(today.year - 1, 1, 10),
        ),
      );
    });
    return fc;
  }

  Widget app(FinanceController fc, Widget home) => ChangeNotifierProvider.value(
    value: fc,
    child: MaterialApp(theme: AppTheme.dark(), home: home),
  );

  testWidgets('parcelamentos: grade ordenável, totais e filtros', (
    tester,
  ) async {
    final fc = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc, const InstallmentsScreen()));
    await tester.pump();
    expect(find.byKey(const ValueKey('inst-row-tv')), findsOneWidget);
    expect(find.byKey(const ValueKey('inst-row-fone')), findsOneWidget);
    expect(find.text('Total · 2 compras'), findsOneWidget);
    expect(find.text(fmtMoney(150000)), findsWidgets);
    expect(find.text('Quitado'), findsOneWidget);
    // Compra mais recente primeiro; clicar em Descrição ordena A→Z.
    double y(String id) =>
        tester.getTopLeft(find.byKey(ValueKey('inst-row-$id'))).dy;
    expect(y('tv'), lessThan(y('fone')));
    await tester.tap(find.byKey(const ValueKey('inst-sort-description')));
    await tester.pump();
    expect(y('fone'), lessThan(y('tv')));
    // Filtro de busca e Limpar.
    await tester.enterText(find.byKey(const ValueKey('inst-search')), 'tele');
    await tester.pump();
    expect(find.byKey(const ValueKey('inst-row-fone')), findsNothing);
    expect(find.text('1 ativo'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('inst-filters-clear')));
    await tester.pump();
    expect(find.byKey(const ValueKey('inst-row-fone')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recorrências: grade, encerradas ocultas e saldo mensal', (
    tester,
  ) async {
    final fc = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc, const RecurringScreen()));
    await tester.pump();
    expect(find.byKey(const ValueKey('rec-row-sal')), findsOneWidget);
    expect(find.byKey(const ValueKey('rec-row-net')), findsOneWidget);
    expect(find.byKey(const ValueKey('rec-row-old')), findsNothing);
    expect(find.text('Saldo mensal · 2 recorrências'), findsOneWidget);
    expect(find.text(fmtMoney(490000)), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('rec-state')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rec-row-old')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('celular usa linhas compactas com filtros recolhidos', (
    tester,
  ) async {
    final fc = await setup(tester);
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(fc, const InstallmentsScreen()));
    await tester.pump();
    expect(find.byKey(const ValueKey('inst-search')), findsNothing);
    expect(find.byKey(const ValueKey('inst-row-tv')), findsOneWidget);
    expect(find.byKey(const ValueKey('inst-sort-description')), findsNothing);
    await tester.pumpWidget(app(fc, const RecurringScreen()));
    await tester.pump();
    expect(find.byKey(const ValueKey('rec-row-sal')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parcelamentos: alterna para cartões e lembra a escolha', (
    tester,
  ) async {
    final fc = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc, const InstallmentsScreen()));
    await tester.pump();
    expect(find.byKey(const ValueKey('inst-row-tv')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('installments-view-cards')));
    await tester.pump();
    expect(find.byKey(const ValueKey('inst-row-tv')), findsNothing);
    expect(find.byKey(const ValueKey('inst-card-tv')), findsOneWidget);
    expect(find.byKey(const ValueKey('inst-card-fone')), findsOneWidget);
    expect(find.text('Televisão'), findsOneWidget);
    expect(fc.gridFilter('installments')?['view'], 'cards');
    expect(tester.takeException(), isNull);
  });

  testWidgets('recorrências: alterna para cartões e lembra a escolha', (
    tester,
  ) async {
    final fc = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc, const RecurringScreen()));
    await tester.pump();
    expect(find.byKey(const ValueKey('rec-row-sal')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recurring-view-cards')));
    await tester.pump();
    expect(find.byKey(const ValueKey('rec-row-sal')), findsNothing);
    expect(find.byKey(const ValueKey('rec-card-sal')), findsOneWidget);
    expect(find.byKey(const ValueKey('rec-card-old')), findsNothing);
    expect(find.text('Salário'), findsOneWidget);
    expect(fc.gridFilter('recurring')?['view'], 'cards');
    expect(tester.takeException(), isNull);
  });
}
