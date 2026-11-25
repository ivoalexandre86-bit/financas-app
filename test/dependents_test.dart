import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/engine/installments.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/cards/cards_screen.dart';
import 'package:financas_app/ui/screens/cards/invoice_details_screen.dart';
import 'package:financas_app/ui/screens/transactions/transaction_form_screen.dart';
import 'package:financas_app/ui/screens/transactions/transactions_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

/// Dependentes (cartões adicionais / quem usa a conta) e "Quem usou".
void main() {
  const ana = Dependent(id: 'dep_ana', name: 'Ana', lastFour: '4321');
  const leo = Dependent(id: 'dep_leo', name: 'Léo');
  final card = CreditCard(
    id: 'c6',
    name: 'C6',
    closingDay: 25,
    dueDay: 5,
    dependents: const [ana, leo],
  );

  FinTransaction buy(
    String id,
    int cents, {
    String? holder,
    bool refund = false,
  }) => FinTransaction(
    id: id,
    type: refund ? TransactionType.income : TransactionType.expense,
    amount: Money(cents),
    description: id,
    date: DateTime(2026, 10, 10),
    cardId: 'c6',
    holderId: holder,
    status: TransactionStatus.pending,
  );

  test('dependentes e quem usou sobrevivem ao JSON', () {
    final back = CreditCard.fromJson(card.toJson());
    expect(back.dependents.map((d) => d.label), ['Ana •• 4321', 'Léo']);
    // WhatsApp do dependente: só dígitos, omitido quando vazio.
    const bia = Dependent(id: 'dep_bia', name: 'Bia', phone: '11988881234');
    expect(Dependent.fromJson(bia.toJson()).phone, '11988881234');
    expect(ana.toJson().containsKey('phone'), isFalse);
    expect(Dependent.formatPhone('5511988881234'), '(11) 98888-1234');
    final acc = Account.fromJson(
      Account(id: 'a', name: 'Conta', dependents: const [leo]).toJson(),
    );
    expect(acc.dependents.single.name, 'Léo');
    // Sem dependentes: o JSON não muda (compatível com dados antigos).
    expect(
      Account(id: 'b', name: 'X').toJson().containsKey('dependents'),
      isFalse,
    );

    final t = FinTransaction.fromJson(
      buy('t', 100, holder: 'dep_ana').toJson(),
    );
    expect(t.holderId, 'dep_ana');
    expect(t.copyWith(holderId: null).holderId, isNull);
    expect(t.copyWith(amount: const Money(5)).holderId, 'dep_ana');
  });

  test('recorrência e parcelas herdam quem usou', () {
    final rule = RecurringRule(
      id: 'r',
      type: TransactionType.expense,
      amount: const Money(3990),
      description: 'Streaming',
      cardId: 'c6',
      holderId: 'dep_leo',
      startDate: DateTime(2026, 1, 3),
    );
    expect(RecurringRule.fromJson(rule.toJson()).holderId, 'dep_leo');
    expect(
      FinancialEngine.virtualOccurrence(rule, DateTime(2026, 5, 3)).holderId,
      'dep_leo',
    );
    final g = InstallmentGroup(
      id: 'g',
      description: 'Tênis',
      totalAmount: const Money(60000),
      count: 3,
      purchaseDate: DateTime(2026, 10, 1),
      cardId: 'c6',
      holderId: 'dep_ana',
    );
    expect(InstallmentGroup.fromJson(g.toJson()).holderId, 'dep_ana');
    final parts = Installments.build(
      g,
      firstStatus: TransactionStatus.pending,
      today: DateTime(2026, 10, 1),
    );
    expect(parts.map((p) => p.holderId).toSet(), {'dep_ana'});
  });

  test('fatura soma por pessoa e fecha com o total', () {
    final data = FinanceData(
      cards: [card],
      transactions: [
        buy('a1', 10000, holder: 'dep_ana'),
        buy('a2', 5000, holder: 'dep_ana'),
        buy('a3', 1000, holder: 'dep_ana', refund: true),
        buy('t1', 20000),
        buy('x', 700, holder: 'dep_removido'),
      ],
    );
    final e = FinancialEngine(data, today: DateTime(2026, 10, 12));
    final inv = e.invoice(card, YearMonth(2026, 10));
    final rows = {
      for (final h in inv.byHolder) h.holder?.name ?? 'Titular': h.total.cents,
    };
    // Léo não tem compras: não aparece. Dependente removido vira titular.
    expect(rows, {'Titular': 20700, 'Ana': 14000});
    expect(
      inv.byHolder.fold<int>(0, (s, h) => s + h.total.cents),
      inv.total.cents,
    );
    expect(data.holderName(buy('y', 1, holder: 'dep_leo')), 'Léo');
    expect(data.holderName(buy('z', 1, holder: 'dep_removido')), 'Titular');
    expect(data.hasDependents, isTrue);
    expect(FinanceData().hasDependents, isFalse);
    expect(holderNames(data), ['Titular', 'Ana', 'Léo']);
  });

  group('telas', () {
    Future<FinanceController> setup(WidgetTester tester) async {
      Intl.defaultLocale = 'pt_BR';
      await initializeDateFormatting('pt_BR');
      final fc = FinanceController(MemoryRepo());
      await tester.runAsync(() async {
        await fc.load();
        await fc.saveCard(card);
      });
      return fc;
    }

    Widget app(FinanceController fc, Widget home) =>
        ChangeNotifierProvider.value(
          value: fc,
          child: MaterialApp(theme: AppTheme.light(), home: home),
        );

    testWidgets('cartão lista e adiciona dependentes', (tester) async {
      final fc = await setup(tester);
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(fc, CardFormScreen(card: fc.data.cardById['c6'])),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dependentes'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Cartão final 4321'), findsOneWidget);

      await tester.tap(find.text('Adicionar dependente'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Bia');
      await tester.enterText(find.byKey(const ValueKey('dep-phone')), '123');
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar').last);
      await tester.pumpAndSettle();
      expect(find.text('Informe DDD e número'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('dep-phone')),
        '(11) 98888-1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar').last);
      await tester.pumpAndSettle();
      expect(find.text('Bia'), findsOneWidget);
      expect(find.text('WhatsApp (11) 98888-1234'), findsOneWidget);
    });

    testWidgets('nova compra no cartão pergunta quem usou', (tester) async {
      final fc = await setup(tester);
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(fc, const TransactionFormScreen(initialCardId: 'c6')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quem usou'), findsOneWidget);
      expect(find.text('Titular'), findsOneWidget);
    });

    testWidgets('compra em conta sem dependentes não mostra o campo', (
      tester,
    ) async {
      final fc = await setup(tester);
      await tester.runAsync(
        () => fc.saveAccount(Account(id: 'a', name: 'Conta')),
      );
      await tester.pumpWidget(app(fc, const TransactionFormScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Quem usou'), findsNothing);
    });

    testWidgets('fatura mostra o total por pessoa', (tester) async {
      final fc = await setup(tester);
      final month = YearMonth.now().next;
      final day = Dates.clampedDate(
        month.previous.year,
        month.previous.month,
        26,
      );
      await tester.runAsync(() async {
        await fc.saveTransaction(
          buy('p1', 12345, holder: 'dep_ana').copyWith(date: day),
        );
        await fc.saveTransaction(buy('p2', 10000).copyWith(date: day));
      });
      await tester.binding.setSurfaceSize(const Size(1400, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(fc, InvoiceDetailsScreen(cardId: 'c6', month: month)),
      );
      await tester.pump();
      expect(find.text('Por pessoa'), findsOneWidget);
      expect(find.text('Ana •• 4321 (1)'), findsOneWidget);
      expect(find.text('Titular (1)'), findsOneWidget);
    });
  });
}
