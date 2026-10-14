import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/cards/invoice_details_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  Future<(FinanceController, YearMonth)> setup(WidgetTester tester) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    final fc = FinanceController(MemoryRepo());
    late YearMonth month;
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      await fc.saveCard(
        CreditCard(id: 'c6', name: 'C6', closingDay: 25, dueDay: 5),
      );
      // Fatura que fecha no próximo mês: compras de 26/(mês-1) a 24/(mês).
      month = YearMonth.now().next;
      final start = Dates.clampedDate(
        month.previous.year,
        month.previous.month,
        26,
      );
      final cats = fc.data.categories
          .where((c) => c.kind == CategoryKind.expense && c.parentId == null)
          .toList();
      await fc.saveTransaction(
        FinTransaction(
          id: 'big',
          type: TransactionType.expense,
          amount: const Money(30000),
          description: 'Mercado',
          notes: 'compra do mês',
          date: start,
          cardId: 'c6',
          categoryId: cats[0].id,
          status: TransactionStatus.pending,
        ),
      );
      await fc.saveTransaction(
        FinTransaction(
          id: 'small',
          type: TransactionType.expense,
          amount: const Money(10000),
          description: 'Cinema',
          date: start.add(const Duration(days: 1)),
          cardId: 'c6',
          categoryId: cats[1].id,
          status: TransactionStatus.pending,
        ),
      );
      await fc.createInstallmentPurchase(
        InstallmentGroup(
          id: 'g',
          description: 'Notebook',
          totalAmount: const Money(120000),
          count: 12,
          purchaseDate: start.add(const Duration(days: 2)),
          cardId: 'c6',
          categoryId: cats[0].id,
        ),
      );
    });
    return (fc, month);
  }

  Widget app(FinanceController fc, YearMonth month) =>
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: InvoiceDetailsScreen(cardId: 'c6', month: month),
        ),
      );

  testWidgets('fatura mostra indicadores e grade de compras', (tester) async {
    final (fc, month) = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(1600, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc, month));
    await tester.pump();

    // Indicadores.
    expect(find.byKey(const ValueKey('invoice-kpi-count')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('invoice-kpi-biggest')),
        matching: find.text('Mercado'),
      ),
      findsOneWidget,
    );
    // Parcela 1/12 de R$ 100,00: R$ 1.100,00 ainda por vir.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('invoice-kpi-installments')),
        matching: find.textContaining('1.100,00'),
      ),
      findsOneWidget,
    );

    // Grade com cabeçalho, tipo, observação, % e total.
    expect(find.byKey(const ValueKey('invoice-sort-amount')), findsOneWidget);
    expect(find.text('Parcela 1/12'), findsOneWidget);
    expect(find.text('À vista'), findsNWidgets(2));
    expect(find.text('compra do mês'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget); // 300 de 500
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('invoice-footer')),
        matching: find.textContaining('500,00'),
      ),
      findsOneWidget,
    );

    // Ordena por valor (maior primeiro).
    await tester.tap(find.byKey(const ValueKey('invoice-sort-amount')));
    await tester.pump();
    final y = {
      for (final d in ['Mercado', 'Notebook', 'Cinema'])
        d: tester.getTopLeft(find.text(d).last).dy,
    };
    expect(y['Mercado']! < y['Notebook']!, isTrue);
    expect(y['Notebook']! < y['Cinema']!, isTrue);

    // Busca filtra as linhas e o total.
    await tester.enterText(
      find.byKey(const ValueKey('invoice-search')),
      'cine',
    );
    await tester.pump();
    expect(find.text('Notebook'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('invoice-footer')),
        matching: find.textContaining('100,00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('descrição é editada direto na grade da fatura', (tester) async {
    final (fc, month) = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(1600, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc, month));
    await tester.pump();

    final cell = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(
            'invoice-edit-description-small',
          ),
    );
    await tester.tap(cell);
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Cinema IMAX');
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(
      fc.data.transactions.firstWhere((t) => t.id == 'small').description,
      'Cinema IMAX',
    );
  });

  testWidgets('celular usa linhas compactas', (tester) async {
    final (fc, month) = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(390, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc, month));
    await tester.pump();
    expect(find.byKey(const ValueKey('invoice-sort-amount')), findsNothing);
    expect(find.text('Mercado'), findsWidgets);
    expect(find.text('Parcela 1/12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
