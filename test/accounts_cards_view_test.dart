import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/accounts/accounts_screen.dart';
import 'package:financas_app/ui/screens/cards/cards_screen.dart';
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
      await fc.saveAccount(
        Account(id: 'nu', name: 'Nubank', initialBalance: const Money(100000)),
      );
      await fc.saveAccount(
        Account(
          id: 'old',
          name: 'Antiga',
          initialBalance: const Money(5000),
          active: false,
        ),
      );
      await fc.saveCard(
        CreditCard(
          id: 'c6',
          name: 'C6',
          closingDay: 25,
          dueDay: 5,
          lastFour: '1234',
          limit: const Money(500000),
        ),
      );
    });
    return fc;
  }

  Widget app(FinanceController fc, Widget home) => ChangeNotifierProvider.value(
    value: fc,
    child: MaterialApp(theme: AppTheme.dark(), home: home),
  );

  testWidgets('contas: alterna para grade e lembra a escolha', (tester) async {
    final fc = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc, const AccountsScreen()));
    await tester.pump();
    // Padrão: cartões (lista atual).
    expect(find.byKey(const ValueKey('acc-row-nu')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('accounts-view-grid')));
    await tester.pump();
    expect(find.byKey(const ValueKey('acc-row-nu')), findsOneWidget);
    expect(find.byKey(const ValueKey('acc-row-old')), findsOneWidget);
    expect(find.text('Saldo das ativas · 2 contas'), findsOneWidget);
    expect(fc.gridFilter('accounts'), {'view': 'grid'});
    // Reabrir a tela mantém a grade.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(fc, const AccountsScreen()));
    await tester.pump();
    expect(find.byKey(const ValueKey('acc-row-nu')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('accounts-view-cards')));
    await tester.pump();
    expect(find.byKey(const ValueKey('acc-row-nu')), findsNothing);
    expect(fc.gridFilter('accounts'), {'view': 'cards'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('cartões: grade com totais e linhas compactas no celular', (
    tester,
  ) async {
    final fc = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc, const CardsScreen()));
    await tester.pump();
    expect(find.byType(CreditCardVisual), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cards-view-grid')));
    await tester.pump();
    expect(find.byType(CreditCardVisual), findsNothing);
    expect(find.byKey(const ValueKey('card-row-c6')), findsOneWidget);
    expect(find.text('Total dos ativos · 1 cartão'), findsOneWidget);
    expect(fc.gridFilter('cards'), {'view': 'grid'});
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pump();
    expect(find.byKey(const ValueKey('card-row-c6')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
