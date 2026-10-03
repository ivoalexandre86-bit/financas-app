import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/transactions/transactions_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  testWidgets('lista agrupa compras do cartão em uma linha por fatura', (
    tester,
  ) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    final fc = FinanceController(MemoryRepo());
    late YearMonth invMonth;
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      // Fecha 25, vence 1: a fatura do mês anterior vence neste mês.
      final card = CreditCard(id: 'c6', name: 'C6', closingDay: 25, dueDay: 1);
      await fc.saveCard(card);
      invMonth = YearMonth.now().previous;
      final start = Dates.clampedDate(
        invMonth.previous.year,
        invMonth.previous.month,
        26,
      );
      for (var i = 0; i < 3; i++) {
        await fc.saveTransaction(
          FinTransaction(
            id: 't$i',
            type: TransactionType.expense,
            amount: Money(1000 * (i + 1)),
            description: 'Compra $i',
            date: start.add(Duration(days: i)),
            cardId: 'c6',
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

    final title = 'Fatura C6 – ${invMonth.shortLabel}';
    expect(find.text(title), findsOneWidget);
    expect(find.text('Compra 0'), findsNothing);
    expect(find.text('3 itens'), findsNothing);
    expect(find.textContaining('3 lançamentos'), findsOneWidget);
    expect(find.textContaining('60,00'), findsWidgets);

    // Chevron abre os detalhes da fatura.
    await tester.tap(find.byTooltip('Abrir fatura'));
    await tester.pumpAndSettle();
    expect(find.text('Fatura C6'), findsOneWidget);
    expect(find.text('Compra 2'), findsOneWidget);
    Navigator.of(tester.element(find.text('Fatura C6'))).pop();
    await tester.pumpAndSettle();

    // Preferência: mostrar compras individualmente.
    await tester.runAsync(
      () =>
          fc.saveSettings(fc.data.settings.copyWith(groupCardInvoices: false)),
    );
    await tester.pump();
    expect(find.text('Compra 0'), findsOneWidget);
    expect(find.text('$title ›'), findsNWidgets(3));

    // Desktop: clique simples seleciona; duplo clique abre.
    await tester.runAsync(
      () => fc.saveSettings(fc.data.settings.copyWith(groupCardInvoices: true)),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TransactionsScreen(),
        ),
      ),
    );
    await tester.tap(find.text(title));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Fatura C6'), findsNothing);
    await tester.tap(find.text(title));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text(title));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Fatura C6'), findsOneWidget);
    Navigator.of(tester.element(find.text('Fatura C6'))).pop();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
