import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/billing_cycle.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/cards/invoices_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  Future<(FinanceController, String)> setup(WidgetTester tester) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    final fc = FinanceController(MemoryRepo());
    late String key;
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      final card = CreditCard(
        id: 'c6',
        name: 'C6',
        closingDay: 25,
        dueDay: 5,
        limit: const Money(500000),
      );
      await fc.saveCard(card);
      final cur = BillingCycle.currentInvoice(card, fc.today);
      key = 'c6|${cur.key}';
      final start = BillingCycle.cycleStart(card, cur);
      final cats = fc.data.categories
          .where((c) => c.kind == CategoryKind.expense && c.parentId == null)
          .toList();
      await fc.saveTransaction(
        FinTransaction(
          id: 'm',
          type: TransactionType.expense,
          amount: const Money(30000),
          description: 'Mercado',
          date: start,
          cardId: 'c6',
          categoryId: cats[0].id,
          status: TransactionStatus.pending,
        ),
      );
      await fc.createInstallmentPurchase(
        InstallmentGroup(
          id: 'g',
          description: 'Notebook',
          totalAmount: const Money(120000),
          count: 12,
          purchaseDate: start.add(const Duration(days: 1)),
          cardId: 'c6',
          categoryId: cats[1].id,
        ),
      );
    });
    return (fc, key);
  }

  Widget app(FinanceController fc) => ChangeNotifierProvider.value(
    value: fc,
    child: MaterialApp(theme: AppTheme.dark(), home: const InvoicesScreen()),
  );

  testWidgets('lista de faturas mostra indicadores, grade e compras', (
    tester,
  ) async {
    final (fc, key) = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(1800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc));
    await tester.pump();

    expect(find.byKey(const ValueKey('invoices-kpi-open')), findsOneWidget);
    // Parcelas 2..12 depois da fatura atual: 11 × R$ 100,00.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('invoices-kpi-installments')),
        matching: find.textContaining('1.100,00'),
      ),
      findsOneWidget,
    );
    final row = find.byKey(ValueKey('invoices-row-$key'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.textContaining('400,00')),
      findsNWidgets(2),
    ); // total e restante
    expect(
      find.descendant(of: row, matching: find.textContaining('300,00')),
      findsOneWidget,
    ); // à vista
    expect(find.text('Notebook'), findsNothing);

    // Expandir mostra as compras da fatura.
    await tester.tap(find.byKey(ValueKey('invoices-expand-$key')));
    await tester.pump();
    expect(find.byKey(ValueKey('invoices-purchases-$key')), findsOneWidget);
    expect(find.text('Notebook'), findsOneWidget);
    expect(find.text('Parcela 1/12'), findsOneWidget);

    // 6 meses por cartão.
    await tester.tap(find.text('6 meses'));
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('invoices-row-'),
      ),
      findsNWidgets(6),
    );
  });

  testWidgets('celular usa linhas compactas', (tester) async {
    final (fc, key) = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc));
    await tester.pump();
    expect(find.byKey(ValueKey('invoices-row-$key')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('invoices-row-$key')));
    await tester.pump();
    expect(find.text('Notebook'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
