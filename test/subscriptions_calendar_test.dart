import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/calendar/calendar_screen.dart';
import 'package:financas_app/ui/screens/subscriptions/subscriptions_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  late FinanceController fc;
  final now = YearMonth.now();
  var n = 0;
  FinTransaction tx(
    String desc,
    int cents,
    DateTime d, {
    TransactionType type = TransactionType.expense,
    TransactionStatus status = TransactionStatus.completed,
  }) => FinTransaction(
    id: 't${n++}',
    type: type,
    amount: Money(cents),
    description: desc,
    date: d,
    accountId: 'a',
    status: status,
  );

  Future<void> setup(
    WidgetTester tester,
    Widget home,
    List<FinTransaction> txs, {
    Size size = const Size(1200, 1000),
  }) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      for (final t in txs) {
        await fc.saveTransaction(t);
      }
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('assinaturas: detectada, totais, grade e criar recorrência', (
    tester,
  ) async {
    await setup(tester, const SubscriptionsScreen(), [
      for (var i = 0; i < 3; i++)
        tx('Streaming', 3990, now.add(-i - 1).firstDay),
      tx('Streaming', 4990, now.firstDay),
    ]);
    expect(find.text('Streaming'), findsOneWidget);
    expect(find.text('Custo mensal'), findsOneWidget);
    expect(find.text(const Money(3990).format()), findsNWidgets(2));
    expect(find.text(const Money(47880).format()), findsOneWidget); // anual
    expect(find.textContaining('Detectada'), findsOneWidget);
    expect(find.textContaining('Aumento de 25%'), findsOneWidget);
    expect(find.text('1 assinatura ficou mais cara'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subscriptions-view-grid')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('subs-sort-name')), findsOneWidget);
    expect(find.text('+25%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subscriptions-view-cards')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar recorrência'));
    await tester.pumpAndSettle();
    expect(find.text('Nova recorrência'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Streaming'), findsOneWidget);
  });

  testWidgets('assinaturas: lista vazia', (tester) async {
    await setup(tester, const SubscriptionsScreen(), const []);
    expect(find.text('Nenhuma assinatura encontrada'), findsOneWidget);
  });

  testWidgets('calendário: valores por dia, dia selecionado e vencidos', (
    tester,
  ) async {
    final prev = now.previous;
    await setup(tester, const CalendarScreen(), [
      tx('Mercado', 25000, DateTime(now.year, now.month, 1)),
      tx(
        'Salário',
        500000,
        DateTime(now.year, now.month, 1),
        type: TransactionType.income,
      ),
      tx(
        'Conta de luz',
        18000,
        DateTime(prev.year, prev.month, 10),
        status: TransactionStatus.pending,
      ),
    ]);
    expect(find.text('Dom'), findsOneWidget);
    expect(find.text('Sáb'), findsOneWidget);
    // Célula larga: totais compactos do dia.
    final day1 = find.byKey(const Key('cal-day-1'));
    expect(
      find.descendant(of: day1, matching: find.text('5.000')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: day1, matching: find.text('250')),
      findsOneWidget,
    );

    await tester.tap(day1);
    await tester.pumpAndSettle();
    expect(find.text('Mercado'), findsOneWidget);
    expect(find.text('Salário'), findsOneWidget);
    expect(find.text(const Money(-25000).format()), findsOneWidget);

    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cal-day-10')));
    await tester.pumpAndSettle();
    expect(find.text('Conta de luz'), findsOneWidget);
    expect(find.text('Vencida'), findsOneWidget);

    await tester.tap(find.text('Conta de luz'));
    await tester.pumpAndSettle();
    expect(find.text('Conta de luz'), findsWidgets);
    expect(find.byType(CalendarScreen), findsNothing);
  });

  testWidgets('calendário no celular mostra pontos', (tester) async {
    await setup(tester, const CalendarScreen(), [
      tx('Mercado', 25000, DateTime(now.year, now.month, 1)),
    ], size: const Size(390, 844));
    final day1 = find.byKey(const Key('cal-day-1'));
    expect(find.descendant(of: day1, matching: find.text('250')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
