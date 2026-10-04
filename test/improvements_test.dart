import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/models/dashboard.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/ui/widgets/form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('Valor como calculadora', () {
    test('contas com números no padrão brasileiro', () {
      expect(Money.tryEval('10*100'), const Money(100000));
      expect(Money.tryEval('10 x 100'), const Money(100000));
      expect(Money.tryEval('1.234,56 + 10'), const Money(124456));
      expect(Money.tryEval('(50+25)/3'), const Money(2500));
      expect(Money.tryEval('100 ÷ 3'), const Money(3333));
      expect(Money.tryEval('19,90 × 3'), const Money(5970));
      expect(Money.tryEval('200 - 50,5'), const Money(14950));
      expect(Money.tryEval('-10+5'), const Money(-500));
      expect(Money.tryEval('2*(3+4)'), const Money(1400));
    });
    test('valores simples continuam como antes', () {
      expect(Money.tryEval('1.234,56'), const Money(123456));
      expect(Money.tryEval('R\$ 55,90'), const Money(5590));
      expect(Money.tryEval('1.000'), const Money(100000));
      expect(Money.tryEval('-10'), const Money(-1000));
    });
    test('contas inválidas', () {
      expect(Money.tryEval('10*'), isNull);
      expect(Money.tryEval('10/0'), isNull);
      expect(Money.tryEval('(10+2'), isNull);
      expect(Money.tryEval('abc'), isNull);
      expect(Money.isExpression('1.234,56'), isFalse);
      expect(Money.isExpression('10*100'), isTrue);
    });

    testWidgets('campo mostra o resultado e troca a conta ao confirmar', (
      tester,
    ) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MoneyField(controller: ctrl)),
        ),
      );
      await tester.enterText(find.byType(TextFormField), '10*100');
      await tester.pump();
      expect(find.text('= ${const Money(100000).format()}'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(ctrl.text, '1.000,00');
    });

    testWidgets('teclado da calculadora devolve o resultado', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MoneyField(controller: ctrl)),
        ),
      );
      await tester.tap(find.byTooltip('Calculadora'));
      await tester.pumpAndSettle();
      for (final k in ['1', '0', '×', '1', '0', '0']) {
        await tester.tap(find.byKey(ValueKey('calc-$k')));
        await tester.pump();
      }
      expect(find.text('= ${const Money(100000).format()}'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calc-use')));
      await tester.pumpAndSettle();
      expect(ctrl.text, '1.000,00');
    });
  });

  group('Gráficos: cores e eixos', () {
    test('cores por coluna e eixos invertidos são salvos', () {
      const c = ChartConfig(
        id: 'g',
        type: ChartType.bar,
        colors: {'x:2026-08': 0xFFE34948, 's:expense': 0xFF15803D},
        swapAxes: true,
      );
      final back = ChartConfig.fromJson(c.toJson());
      expect(back.colors, c.colors);
      expect(back.swapAxes, isTrue);
      expect(back.horizontal, isTrue);
      // Tipos de linha não invertem.
      expect(back.copyWith(type: ChartType.line).horizontal, isFalse);
      // JSON antigo, sem os campos novos.
      final old = Map<String, Object?>.from(c.toJson())
        ..remove('colors')
        ..remove('swapAxes');
      final legacy = ChartConfig.fromJson(old);
      expect(legacy.colors, isEmpty);
      expect(legacy.swapAxes, isFalse);
    });
  });

  group('Pendências do mês', () {
    final acc = Account(id: 'a', name: 'Conta');
    final card = CreditCard(
      id: 'c',
      name: 'Visa',
      closingDay: 10,
      dueDay: 17,
      limit: const Money(1000000),
    );
    FinTransaction tx(
      String id,
      TransactionType type,
      int cents,
      DateTime date, {
      TransactionStatus status = TransactionStatus.pending,
      String? cardId,
    }) => FinTransaction(
      id: id,
      type: type,
      amount: Money(cents),
      description: id,
      date: date,
      accountId: cardId == null ? 'a' : null,
      cardId: cardId,
      status: status,
    );

    test('despesas, receitas, faturas e vencidas', () {
      final data = FinanceData(
        accounts: [acc],
        cards: [card],
        transactions: [
          tx('aluguel', TransactionType.expense, 200000, DateTime(2026, 8, 5)),
          tx('luz', TransactionType.expense, 30000, DateTime(2026, 8, 25)),
          tx(
            'pago',
            TransactionType.expense,
            10000,
            DateTime(2026, 8, 3),
            status: TransactionStatus.completed,
          ),
          tx(
            'cancelado',
            TransactionType.expense,
            9900,
            DateTime(2026, 8, 3),
            status: TransactionStatus.cancelled,
          ),
          tx('salario', TransactionType.income, 500000, DateTime(2026, 8, 30)),
          tx(
            'mercado',
            TransactionType.expense,
            45000,
            DateTime(2026, 8, 2),
            cardId: 'c',
          ),
          tx('setembro', TransactionType.expense, 1000, DateTime(2026, 9, 2)),
        ],
      );
      final e = FinancialEngine(data, today: DateTime(2026, 8, 20));
      final p = e.monthPendings(YearMonth(2026, 8));
      expect(p.expenses.count, 2);
      expect(p.expenses.total, const Money(230000));
      expect(p.incomes.count, 1);
      expect(p.incomes.total, const Money(500000));
      // Compra do dia 2 cai na fatura de agosto, que vence em 17/08.
      expect(p.invoices.count, 1);
      expect(p.invoices.total, const Money(45000));
      // Vencidas: aluguel (05/08) e a fatura (17/08).
      expect(p.overdue.count, 2);
      expect(p.overdue.total, const Money(245000));
    });
  });
}
