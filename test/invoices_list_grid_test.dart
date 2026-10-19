import 'package:financas_app/core/dates.dart';
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
  Future<(FinanceController, String)> setup(
    WidgetTester tester, {
    bool showDueMonth = true,
  }) async {
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
      await fc.saveCard(
        CreditCard(id: 'nu', name: 'Nubank', closingDay: 3, dueDay: 10),
      );
      final cur = BillingCycle.currentInvoice(card, fc.today);
      key = 'c6|${cur.key}';
      // A fatura atual vence no mês seguinte; a grade abre no mês atual.
      if (showDueMonth) {
        await fc.saveGridFilter('invoices', {
          'months': [YearMonth.of(BillingCycle.dueDate(card, cur)).key],
        });
      }
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

    // Grade única: os dois cartões no mês escolhido, com a coluna Cartão.
    final rows = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('invoices-row-'),
    );
    expect(rows, findsNWidgets(2));
    expect(find.text('Nubank'), findsWidgets);
    expect(find.byKey(const ValueKey('invoices-sort-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('invoices-footer')), findsOneWidget);

    // Filtro por cartão.
    await tester.tap(find.byKey(const ValueKey('invoices-filter-card-nu')));
    await tester.pump();
    expect(rows, findsNWidgets(1));
    expect(find.byKey(ValueKey('invoices-row-$key')), findsNothing);

    // Limpar mostra todos os cartões e todos os meses.
    await tester.tap(find.byKey(const ValueKey('invoices-filters-clear')));
    await tester.pump();
    expect(rows, findsNWidgets(20));

    // Mês filtra pelo vencimento: no C6 (fecha 25, vence 5) a fatura que
    // vence neste mês é a de referência do mês anterior.
    final now = YearMonth.of(fc.today);
    await tester.tap(find.byKey(ValueKey('invoices-filter-month-${now.key}')));
    await tester.pump();
    final cur = BillingCycle.currentInvoice(fc.data.cardById['c6']!, fc.today);
    final dueNow = [for (var i = -2; i <= 2; i++) cur.add(i)].firstWhere(
      (m) =>
          YearMonth.of(BillingCycle.dueDate(fc.data.cardById['c6']!, m)) == now,
    );
    expect(
      find.byKey(ValueKey('invoices-row-c6|${dueNow.key}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('invoices-row-c6|${dueNow.next.key}')),
      findsNothing,
    );

    // Filtros recolhem.
    await tester.tap(find.byKey(const ValueKey('invoices-filters-toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('invoices-filter-card-nu')), findsNothing);
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

  testWidgets('lembra o mês escolhido ao reabrir; padrão é o mês atual', (
    tester,
  ) async {
    final (fc, key) = await setup(tester, showDueMonth: false);
    await tester.binding.setSurfaceSize(const Size(1800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc));
    await tester.pump();
    final now = YearMonth.of(fc.today);
    Finder chip(YearMonth m) =>
        find.byKey(ValueKey('invoices-filter-month-${m.key}'));
    bool selected(YearMonth m) => tester.widget<FilterChip>(chip(m)).selected;
    expect(selected(now), isTrue);
    expect(selected(now.next), isFalse);
    expect(find.byKey(ValueKey('invoices-row-$key')), findsNothing);

    await tester.tap(chip(now));
    await tester.pump();
    await tester.tap(chip(now.next));
    await tester.pump();
    expect(find.byKey(ValueKey('invoices-row-$key')), findsOneWidget);
    expect(fc.repo is MemoryRepo, isTrue);
    expect((fc.repo as MemoryRepo).settings.gridFilters?['invoices'], {
      'cards': <String>[],
      'months': [now.next.key],
      'status': <String>[],
      'sort': 'due',
      'asc': true,
      'view': 'grid',
    });

    // Reabre a tela: continua no mês escolhido.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(fc));
    await tester.pump();
    expect(selected(now), isFalse);
    expect(selected(now.next), isTrue);
    expect(find.byKey(ValueKey('invoices-row-$key')), findsOneWidget);
  });

  testWidgets('modo cartões: uma fatura por cartão e lembra a escolha', (
    tester,
  ) async {
    final (fc, key) = await setup(tester);
    await tester.binding.setSurfaceSize(const Size(1800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc));
    await tester.pump();
    expect(find.byKey(ValueKey('invoices-row-$key')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('invoices-view-cards')));
    await tester.pump();
    expect(find.byKey(ValueKey('invoices-row-$key')), findsNothing);
    final card = find.byKey(ValueKey('invoices-card-$key'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.textContaining('C6')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('400,00')),
      findsOneWidget,
    );
    expect(
      ((fc.repo as MemoryRepo).settings.gridFilters?['invoices']
          as Map?)?['view'],
      'cards',
    );

    // Reabre a tela: continua no modo cartões.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(fc));
    await tester.pump();
    expect(find.byKey(ValueKey('invoices-card-$key')), findsOneWidget);
  });
}
