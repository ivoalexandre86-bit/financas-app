import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/transactions/transactions_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  Future<FinanceController> setup(WidgetTester tester, Size size) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      final today = fc.engine.today;
      for (final (id, desc, cents) in [
        ('t1', 'Aluguel', 210000),
        ('t2', 'Mercado', 50000),
      ]) {
        await fc.saveTransaction(
          FinTransaction(
            id: id,
            type: TransactionType.expense,
            amount: Money(cents),
            description: desc,
            date: today,
            accountId: 'a',
            status: TransactionStatus.pending,
          ),
        );
      }
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TransactionsScreen(),
        ),
      ),
    );
    await tester.pump();
    return fc;
  }

  testWidgets('grade larga: cabeçalho, ordenação e status com um toque', (
    tester,
  ) async {
    final fc = await setup(tester, const Size(1200, 800));
    expect(find.text('DATA'), findsOneWidget);
    expect(find.text('SUBCATEGORIA'), findsOneWidget);

    // Ordena por valor (maior primeiro) e depois inverte.
    await tester.tap(find.byKey(const ValueKey('grid-sort-amount')));
    await tester.pump();
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Mercado') < y('Aluguel'), isTrue); // -500 > -2100
    await tester.tap(find.byKey(const ValueKey('grid-sort-amount')));
    await tester.pump();
    expect(y('Aluguel') < y('Mercado'), isTrue);

    // Status alterna sem abrir os detalhes.
    await tester.runAsync(() async {
      await tester.tap(find.text('Pendente').first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(
      fc.data.transactions.where(
        (t) => t.status == TransactionStatus.completed,
      ),
      hasLength(1),
    );
    expect(find.text('Paga'), findsOneWidget);
  });

  testWidgets('celular: linhas compactas sem cabeçalho de colunas', (
    tester,
  ) async {
    await setup(tester, const Size(620, 900));
    expect(find.text('DATA'), findsNothing);
    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('Pendente'), findsNWidgets(2));
  });
}
