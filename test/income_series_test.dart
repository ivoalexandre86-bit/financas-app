import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/installments.dart';
import 'package:financas_app/domain/engine/recurrence.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/transactions/transaction_form_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

/// Receitas recorrentes por quantidade de vezes e receitas parceladas.
void main() {
  RecurringRule rule(RecurrenceFrequency f, DateTime start) => RecurringRule(
    id: 'r',
    type: TransactionType.income,
    amount: const Money(10000),
    description: 'Reembolso',
    frequency: f,
    startDate: start,
  );

  test('n-ésima ocorrência respeita a frequência e o fim do mês', () {
    final jan31 = DateTime(2026, 1, 31);
    expect(
      Recurrence.nthOccurrence(rule(RecurrenceFrequency.monthly, jan31), 1),
      jan31,
    );
    expect(
      Recurrence.nthOccurrence(rule(RecurrenceFrequency.monthly, jan31), 3),
      DateTime(2026, 3, 31),
    );
    expect(
      Recurrence.nthOccurrence(rule(RecurrenceFrequency.weekly, jan31), 3),
      DateTime(2026, 2, 14),
    );
    // Regra com data final na n-ésima ocorrência gera exatamente n vezes.
    final r = rule(RecurrenceFrequency.monthly, DateTime(2026, 5, 10));
    final end = Recurrence.nthOccurrence(r, 6);
    final limited = RecurringRule.fromJson({
      ...r.toJson(),
      'endDate': end.toIso8601String().substring(0, 10),
    });
    expect(
      Recurrence.occurrences(
        limited,
        DateTime(2026, 1, 1),
        DateTime(2030, 1, 1),
      ).length,
      6,
    );
  });

  test('receita parcelada gera parcelas de receita e sobrevive ao JSON', () {
    final g = InstallmentGroup(
      id: 'ig',
      type: TransactionType.income,
      description: 'Reembolso',
      totalAmount: const Money(100000),
      count: 3,
      purchaseDate: DateTime(2026, 12, 5),
      accountId: 'a',
    );
    final back = InstallmentGroup.fromJson(g.toJson());
    expect(back.isIncome, isTrue);
    final parts = Installments.build(back, today: DateTime(2026, 11, 27));
    expect(parts.map((t) => t.type).toSet(), {TransactionType.income});
    expect(parts.map((t) => t.amount.cents), [33334, 33333, 33333]);
    expect(parts.map((t) => t.date.month), [12, 1, 2]);
    // Compra parcelada antiga (sem "type") continua despesa.
    final old = g.toJson()..remove('type');
    expect(InstallmentGroup.fromJson(old).isIncome, isFalse);
    expect(
      InstallmentGroup(
        id: 'x',
        description: 'x',
        totalAmount: const Money(200),
        count: 2,
        purchaseDate: DateTime(2026),
        accountId: 'a',
      ).toJson().containsKey('type'),
      isFalse,
    );
  });

  group('formulário', () {
    Future<FinanceController> setup(WidgetTester tester) async {
      Intl.defaultLocale = 'pt_BR';
      await initializeDateFormatting('pt_BR');
      final fc = FinanceController(MemoryRepo());
      await tester.runAsync(() async {
        await fc.load();
        await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      });
      await tester.binding.setSurfaceSize(const Size(900, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      return fc;
    }

    Widget app(FinanceController fc) => ChangeNotifierProvider.value(
      value: fc,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const TransactionFormScreen(initialType: TransactionType.income),
      ),
    );

    Future<void> save(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('receita recorrente por quantidade de vezes', (tester) async {
      final fc = await setup(tester);
      await tester.pumpWidget(app(fc));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '150');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descrição'),
        'Reembolso',
      );
      await tester.tap(find.byKey(const ValueKey('switch-recurring')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recurrence-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Após uma quantidade de vezes').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('recurrence-count')),
          matching: find.byType(TextFormField),
        ),
        '4',
      );
      await tester.pumpAndSettle();
      final summary = tester
          .widget<Text>(find.byKey(const ValueKey('recurrence-summary')))
          .data!;
      expect(summary, contains('4 vezes'));
      expect(summary, contains('total R\$'));
      await save(tester);
      final r = fc.data.recurringRules.single;
      expect(r.type, TransactionType.income);
      final start = r.startDate;
      expect(r.endDate, Recurrence.nthOccurrence(r, 4));
      expect(
        Recurrence.occurrences(r, start, DateTime(start.year + 5)).length,
        4,
      );
    });

    testWidgets('receita parcelada: valor total e número de parcelas', (
      tester,
    ) async {
      final fc = await setup(tester);
      await tester.pumpWidget(app(fc));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('switch-installment')));
      await tester.pumpAndSettle();
      expect(find.text('Receita parcelada'), findsOneWidget);
      expect(find.text('Valor total a receber'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '900');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descrição'),
        'Reembolso plano',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Número de parcelas'),
        '3',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('3× de R\$'), findsOneWidget);
      await save(tester);
      final g = fc.data.installmentGroups.single;
      expect(g.isIncome, isTrue);
      final parts = fc.installmentsOf(g.id);
      expect(parts.length, 3);
      expect(parts.every((t) => t.type == TransactionType.income), isTrue);
      expect(parts.fold<int>(0, (s, t) => s + t.amount.cents), 90000);
      // Não entra como compromisso de parcelas futuras.
      expect(fc.engine.futureInstallments().count, 0);
    });
  });
}
