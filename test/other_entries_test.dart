import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/other_entries_engine.dart';
import 'package:financas_app/domain/engine/projection_filter.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/other_entry.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/simulations/simulations_screen.dart';
import 'package:financas_app/ui/screens/transactions/transaction_details_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

final _m = YearMonth.now().add(1);

Future<FinanceController> _setup() async {
  final fc = FinanceController(MemoryRepo());
  await fc.load();
  await fc.saveAccount(
    Account(id: 'a', name: 'Conta', initialBalance: const Money(100000)),
  );
  await fc.savePeople(const [
    Person(id: 'ivo', name: 'Ivo', isMe: true),
    Person(id: 'pai', name: 'Pai'),
    Person(id: 'mae', name: 'Mãe'),
  ]);
  return fc;
}

List<FinTransaction> _derived(FinanceController fc) =>
    fc.data.transactions.where((t) => OtherSync.isDerived(t.id)).toList();

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
  });

  test('divisão por % e valor fixo, sem perder centavos', () {
    final e = OtherEntry(
      id: 'x',
      type: TransactionType.expense,
      description: 'Plano de saúde',
      amount: 100001,
      month: _m,
      allocations: const [
        Allocation('pai', AllocMode.percent, 50),
        Allocation('mae', AllocMode.percent, 25),
        Allocation('ivo', AllocMode.fixed, 10000),
      ],
    );
    final owed = e.owedByPerson();
    expect(owed['ivo'], 10000);
    expect(owed['pai']! + owed['mae']!, 75001);
    expect(e.unallocated, 100001 - 10000 - 75001);
    final back = OtherEntry.fromJson(e.toJson());
    expect(back.owedByPerson(), owed);
  });

  test('vinculados viram uma linha por mês; reembolsos viram receita; '
      'editar e excluir não duplicam', () async {
    final fc = await _setup();
    final a = await fc.saveOtherEntry(
      OtherEntry(
        id: 'oe1',
        type: TransactionType.expense,
        description: 'Plano de saúde',
        amount: 120000,
        month: _m,
        dueDate: Dates.clampedDate(_m.year, _m.month, 10),
        allocations: const [
          Allocation('ivo', AllocMode.percent, 25),
          Allocation('pai', AllocMode.percent, 50),
          Allocation('mae', AllocMode.percent, 25),
        ],
      ),
    );
    await fc.saveOtherEntry(
      OtherEntry(
        id: 'oe2',
        type: TransactionType.expense,
        description: 'Farmácia',
        amount: 30000,
        month: _m,
      ),
    );
    await fc.saveOtherEntry(
      OtherEntry(
        id: 'oe3',
        type: TransactionType.expense,
        description: 'Fora do orçamento',
        amount: 99900,
        month: _m,
        linked: false,
      ),
    );
    var d = _derived(fc);
    expect(d.length, 1);
    expect(d.single.id, OtherSync.monthTxId(TransactionType.expense, _m));
    expect(d.single.amount, const Money(150000));
    expect(d.single.date.day, 10);
    expect(
      fc.engine.monthTotals(ProjectionFilter.none, _m).expenses,
      const Money(150000),
    );
    expect(
      fc.data.categories.any((c) => c.id == OtherSync.expenseCategoryId),
      isTrue,
    );

    // Pagamento parcial do pai e um segundo pagamento.
    final today = Dates.today();
    await fc.saveOtherPayment(
      fc.otherEntryById('oe1')!,
      OtherPayment(id: 'p1', personId: 'pai', amount: 20000, date: today),
    );
    var e = fc.otherEntryById('oe1')!;
    expect(
      e.shares().firstWhere((s) => s.personId == 'pai').status,
      PayStatus.partial,
    );
    expect(e.reimbursementStatus(fc.meIds), PayStatus.partial);
    await fc.saveOtherPayment(
      e,
      OtherPayment(id: 'p2', personId: 'pai', amount: 40000, date: today),
    );
    e = fc.otherEntryById('oe1')!;
    expect(
      e.shares().firstWhere((s) => s.personId == 'pai').status,
      PayStatus.paid,
    );
    d = _derived(fc);
    expect(d.where((t) => t.type == TransactionType.income).length, 2);
    final r1 = d.firstWhere((t) => t.id == 'oe_pay_p1');
    expect(r1.amount, const Money(20000));
    expect(r1.date, today);
    expect(r1.description, contains('Pai'));

    // Editar o pagamento atualiza a receita (mesmo id, sem duplicar).
    await fc.saveOtherPayment(e, e.payments.first.copyWith(amount: 25000));
    d = _derived(fc);
    expect(
      d.where((t) => t.id == 'oe_pay_p1').single.amount,
      const Money(25000),
    );
    expect(d.length, 3);

    // Excluir o pagamento remove a receita.
    e = fc.otherEntryById('oe1')!;
    await fc.deleteOtherPayment(e, e.payments.firstWhere((p) => p.id == 'p2'));
    expect(_derived(fc).any((t) => t.id == 'oe_pay_p2'), isFalse);

    // Alterar o valor recalcula a linha do mês.
    await fc.saveOtherEntry(fc.otherEntryById('oe2')!.copyWith(amount: 50000));
    expect(
      _derived(fc).firstWhere((t) => t.type == TransactionType.expense).amount,
      const Money(170000),
    );

    // Exclusão lógica: sai da linha, mantém pagamentos e histórico.
    await fc.deleteOtherEntry(fc.otherEntryById('oe1')!);
    e = fc.otherEntryById('oe1')!;
    expect(e.isDeleted, isTrue);
    expect(e.payments, isNotEmpty);
    expect(e.history.map((h) => h.text), contains('Excluído'));
    expect(
      _derived(fc).firstWhere((t) => t.type == TransactionType.expense).amount,
      const Money(50000),
    );
    await fc.restoreOtherEntry(e);
    expect(
      _derived(fc).firstWhere((t) => t.type == TransactionType.expense).amount,
      const Money(170000),
    );

    // Sem nada vinculado no mês, a linha some.
    for (final x in fc.otherEntries.toList()) {
      if (x.linked) await fc.deleteOtherEntry(x);
    }
    expect(
      _derived(fc).where((t) => t.type == TransactionType.expense),
      isEmpty,
    );
    expect(a.id, 'oe1');
  });

  test('receitas: previsto, recebido e a receber', () async {
    final fc = await _setup();
    await fc.saveOtherEntry(
      OtherEntry(
        id: 'r1',
        type: TransactionType.income,
        description: 'Aluguel da sala',
        amount: 80000,
        month: _m,
        allocations: const [Allocation('pai', AllocMode.percent, 100)],
      ),
    );
    await fc.saveOtherPayment(
      fc.otherEntryById('r1')!,
      OtherPayment(
        id: 'rp',
        personId: 'pai',
        amount: 30000,
        date: Dates.today(),
      ),
    );
    final s = OtherSummary.of(fc.otherEntries, fc.meIds);
    expect(s.total, 80000);
    expect(s.received, 30000);
    expect(s.outstanding, 50000);
    expect(s.partial, 1);
    // Receita não gera reembolso extra (sem contagem dupla).
    final d = _derived(fc);
    expect(d.length, 1);
    expect(d.single.amount, const Money(80000));
  });

  testWidgets('tela: nova despesa dividida, pagamento e resumo', (
    tester,
  ) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late FinanceController fc;
    await tester.runAsync(() async => fc = await _setup());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SimulationsScreen(initialTab: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('oe-new-expense')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('oe-desc')), 'Mercado');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('oe-amount')),
        matching: find.byType(TextField),
      ),
      '300',
    );
    await tester.tap(find.byKey(const ValueKey('oe-equal')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tudo distribuído'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('oe-save')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final e = fc.otherEntries.single;
    expect(e.amount, 30000);
    expect(e.owedByPerson().values.fold(0, (a, v) => a + v), 30000);
    expect(find.text('Mercado'), findsOneWidget);

    await tester.tap(find.text('Mercado'));
    await tester.pumpAndSettle();
    expect(find.text('Partes por pessoa'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('oe-pay-pai')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('oe-pay-save')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(fc.otherEntries.single.payments.single.amount, 10000);
    expect(find.textContaining('Pagamento registrado'), findsOneWidget);
    expect(_derived(fc).length, 2);

    // A linha consolidada do orçamento abre o detalhamento do mês.
    final line = _derived(fc)
        .firstWhere((t) => t.type == TransactionType.expense);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.light(),
          home: TransactionDetailsScreen(tx: line),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('lançamento consolidado'), findsOneWidget);
    expect(find.text('Mercado'), findsOneWidget);
  });
}
