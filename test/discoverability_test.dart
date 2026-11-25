import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/accounts/accounts_screen.dart';
import 'package:financas_app/ui/screens/cards/card_details_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

/// Ajustar saldo da conta e dependentes direto nos detalhes.
void main() {
  Future<FinanceController> setup(WidgetTester tester) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(
        Account(id: 'a1', name: 'Nubank', initialBalance: const Money(10000)),
      );
      await fc.saveCard(
        CreditCard(id: 'c1', name: 'C6', closingDay: 25, dueDay: 5),
      );
    });
    return fc;
  }

  Widget app(FinanceController fc, Widget home) => ChangeNotifierProvider.value(
    value: fc,
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );

  Future<void> big(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('ajustar saldo lança a diferença', (tester) async {
    final fc = await setup(tester);
    await big(tester);
    await tester.pumpWidget(
      app(fc, const AccountDetailsScreen(accountId: 'a1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('acc-adjust-balance')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('acc-adjust-value')),
      '75,50',
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('acc-adjust-ok')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(fc.engine.accountBalance('a1'), const Money(7550));
    final t = fc.data.transactions.single;
    expect(t.description, 'Ajuste de saldo');
    expect(t.type, TransactionType.expense);
    expect(t.amount, const Money(2450));
  });

  testWidgets('dependentes aparecem e são adicionados nos detalhes', (
    tester,
  ) async {
    final fc = await setup(tester);
    await big(tester);
    await tester.pumpWidget(
      app(fc, const AccountDetailsScreen(accountId: 'a1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acc-dependents')), findsOneWidget);

    await tester.pumpWidget(app(fc, CardDetailsScreen(cardId: 'c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar dependente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Bia');
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar').last);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(fc.data.cardById['c1']!.dependents.single.name, 'Bia');
    expect(find.text('Bia'), findsOneWidget);
  });
}
