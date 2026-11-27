import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/engine/month_end_planner.dart';
import 'package:financas_app/domain/models/debt.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/planning.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/projection/month_end_plan_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'controller_test.dart' show MemoryRepo;

// Dados fictícios. Datas relativas ao mês atual para o teste valer sempre.

final _now = DateTime.now();
final _month = YearMonth.now();
final _prev = _month.previous;
DateTime _d(YearMonth m, int day) => Dates.clampedDate(m.year, m.month, day);

FinTransaction _tx(
  String id,
  TransactionType type,
  int reais,
  DateTime date, {
  TransactionStatus status = TransactionStatus.completed,
}) => FinTransaction(
  id: id,
  type: type,
  amount: Money(reais * 100),
  description: id,
  date: date,
  accountId: 'a',
  status: status,
);

Future<FinanceController> _ctrl({
  required int initial,
  required int prevIncome,
  required int prevExpenses,
  int reserve = 0,
  List<FinTransaction> extra = const [],
}) async {
  final fc = FinanceController(MemoryRepo());
  await fc.load();
  await fc.saveAccount(
    Account(
      id: 'a',
      name: 'Conta fictícia',
      initialBalance: Money(initial * 100),
    ),
  );
  await fc.saveTransaction(
    _tx('Salário', TransactionType.income, prevIncome, _d(_prev, 5)),
  );
  await fc.saveTransaction(
    _tx(
      'Despesas do mês',
      TransactionType.expense,
      prevExpenses,
      _d(_prev, 10),
    ),
  );
  for (final t in extra) {
    await fc.saveTransaction(t);
  }
  await fc.closeMonth(_prev);
  if (reserve > 0) await fc.setMinimumReserve(Money(reserve * 100));
  return fc;
}

DebtContract _debt(
  String id,
  String name,
  int reais,
  double rate, {
  int months = 24,
}) => DebtContract(
  id: id,
  name: name,
  lender: 'Banco Fictício',
  kind: DebtKind.personalLoan,
  system: AmortizationSystem.price,
  monthlyRate: rate,
  outstanding: Money(reais * 100),
  remainingMonths: months,
  nextDueDate: _d(_month.next, 10),
  reduceTerm: OptionSupport.allowed,
  reducePayment: OptionSupport.allowed,
  payoff: OptionSupport.allowed,
);

final _debtA = _debt('carro', 'Financiamento do carro', 20000, 0.02);
final _debtB = _debt('pessoal', 'Empréstimo pessoal', 8000, 0.045);

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
  });

  test('dívida sem dados: mostra o que falta antes de estimar', () async {
    final fc = await _ctrl(
      initial: 10000,
      prevIncome: 5000,
      prevExpenses: 2000,
    );
    final semTaxa = DebtContract(
      id: 'cartao',
      name: 'Parcelamento do cartão',
      lender: 'Banco Fictício',
      kind: DebtKind.personalLoan,
      outstanding: const Money(300000),
    );
    final a = fc.monthEndAnalysis(_prev, debts: [semTaxa]);
    final o = a.options.firstWhere(
      (o) => o.kind == MonthEndOptionKind.debtPrepay,
    );
    expect(o.isComplete, isFalse);
    expect(o.interestSavings, isNull);
    expect(o.missingFields, contains(DebtField.rate.label));
    expect(o.missingFields, contains(DebtField.remainingMonths.label));
  });

  group('O que fazer agora?', () {
    test('sobra disponível: compara caixa, reserva, meta e dívidas', () async {
      final fc = await _ctrl(
        initial: 10000,
        prevIncome: 5000,
        prevExpenses: 2000,
        reserve: 3000,
        extra: [
          _tx(
            'Aluguel',
            TransactionType.expense,
            1500,
            _d(_month, 28),
            status: TransactionStatus.pending,
          ),
        ],
      );
      await fc.saveGoal(
        SavingsGoal(id: 'g1', name: 'Viagem', target: const Money(500000)),
      );
      final a = fc.monthEndAnalysis(_prev, debts: [_debtA, _debtB]);
      expect(a.isClosed, isTrue);
      expect(a.result, const Money(300000));
      expect(a.cash, const Money(1300000));
      expect(a.committed, const Money(150000));
      // 13.000 − 1.500 − 3.000 de reserva.
      expect(a.available, const Money(850000));
      expect(a.scenario, MonthEndScenario.surplus);

      final kinds = a.options.map((o) => o.kind).toList();
      expect(kinds.first, MonthEndOptionKind.keepCash);
      expect(kinds, contains(MonthEndOptionKind.reserve));
      expect(kinds, contains(MonthEndOptionKind.goal));
      expect(kinds.where((k) => k == MonthEndOptionKind.debtPrepay).length, 2);
      final goal = a.options.firstWhere(
        (o) => o.kind == MonthEndOptionKind.goal,
      );
      expect(goal.upfront, const Money(500000)); // só o que falta na meta

      // Antes e depois: a amortização tira o valor do caixa agora.
      final debt = a.options.firstWhere((o) => o.targetId == 'carro');
      expect(debt.interestSavings!.isPositive, isTrue);
      expect(debt.upfront, const Money(850000));
      final cmp = a.compare(debt);
      expect(cmp.first.after, cmp.first.before - const Money(850000));
      expect(a.cashNextMonthAfter(a.options.first), cmp.first.before);

      // Aplicar: só o planejamento futuro muda; o mês fechado fica igual.
      final closedBefore = fc.closingOf(_prev)!;
      final before = fc.engine.projection(MonthRange.starting(_month, 1));
      await fc.applyMonthEndOption(a, debt);
      final after = fc.engine.projection(MonthRange.starting(_month, 1));
      expect(
        after.columns.first.accumulated,
        before.columns.first.accumulated - const Money(850000),
      );
      final closedAfter = fc.closingOf(_prev)!;
      expect(closedAfter.income, closedBefore.income);
      expect(closedAfter.expenses, closedBefore.expenses);
      expect(closedAfter.decision!.kind, 'debtPrepay');
      expect(
        fc.engine.monthTotals(ProjectionFilter.none, _prev).net,
        const Money(300000),
      );
      final planned = fc.data.transactions.firstWhere(
        (t) => t.description.startsWith('Amortização extra'),
      );
      expect(planned.status, TransactionStatus.pending);
      expect(YearMonth.of(planned.date), _month);
    });

    test('salvar opção como cenário não muda o orçamento base', () async {
      final fc = await _ctrl(
        initial: 10000,
        prevIncome: 5000,
        prevExpenses: 2000,
      );
      final a = fc.monthEndAnalysis(_prev, debts: [_debtA]);
      final debt = a.options.firstWhere((o) => o.targetId == 'carro');
      final before = fc.engine.projection(MonthRange.starting(_month, 3));
      final sc = await fc.saveMonthEndScenario(a, debt);
      expect(sc.kind, 'monthEnd');
      expect(sc.flows.first.amount, -debt.upfront);
      expect(sc.flows.every((f) => f.refId == _prev.key), isTrue);
      final after = fc.engine.projection(MonthRange.starting(_month, 3));
      expect(after.columns.last.accumulated, before.columns.last.accumulated);
      expect(fc.closingOf(_prev)!.decision, isNull);
    });

    test('ordenar dívidas: maior economia x maior alívio mensal', () async {
      final fc = await _ctrl(
        initial: 10000,
        prevIncome: 5000,
        prevExpenses: 2000,
      );
      final a = fc.monthEndAnalysis(
        _prev,
        debts: [_debtA, _debtB],
        amount: const Money(400000),
      );
      final debts = a.options
          .where((o) => o.kind == MonthEndOptionKind.debtPrepay)
          .toList();
      expect(debts.every((o) => o.upfront == const Money(400000)), isTrue);
      // Mesmo prazo: 4,5% a.m. economiza mais que 2% a.m. com o mesmo valor.
      debts.sort((x, y) => y.interestSavings!.compareTo(x.interestSavings!));
      expect(debts.first.targetId, 'pessoal');
    });

    test('resultado positivo com caixa comprometido', () async {
      final fc = await _ctrl(
        initial: 2000,
        prevIncome: 5000,
        prevExpenses: 3000,
        reserve: 1000,
        extra: [
          _tx(
            'Escola',
            TransactionType.expense,
            3000,
            _d(_month, 28),
            status: TransactionStatus.pending,
          ),
        ],
      );
      final a = fc.monthEndAnalysis(_prev, debts: [_debtA]);
      expect(a.result.isPositive, isTrue);
      expect(a.cash, const Money(400000));
      expect(a.setAside, const Money(300000));
      expect(a.available, Money.zero);
      expect(a.scenario, MonthEndScenario.committed);
      expect(a.obligations.single.description, 'Escola');
      expect(a.obligations.single.date, _d(_month, 28));
      // Sem sobra: a sugestão de amortizar não traz estimativa.
      final debt = a.options.firstWhere(
        (o) => o.kind == MonthEndOptionKind.debtPrepay,
      );
      expect(debt.isComplete, isFalse);
      expect(debt.interestSavings, isNull);
      expect(a.options.any((o) => o.kind == MonthEndOptionKind.goal), isFalse);
    });

    test('déficit previsto: meses afetados, maiores gastos e opções', () async {
      final next = _month.next;
      final fc = await _ctrl(
        initial: 1000,
        prevIncome: 3000,
        prevExpenses: 3500,
        extra: [
          _tx(
            'Conserto do carro',
            TransactionType.expense,
            2000,
            _d(next, 15),
            status: TransactionStatus.pending,
          ),
          _tx(
            'Mercado',
            TransactionType.expense,
            300,
            _d(next, 20),
            status: TransactionStatus.pending,
          ),
        ],
      );
      const offer = RenegotiationOffer(
        name: 'Empréstimo pessoal',
        currentInstallment: Money(80000),
        currentRemainingMonths: 10,
        newInstallment: Money(50000),
        newMonths: 20,
      );
      final a = fc.monthEndAnalysis(_prev, offers: [offer]);
      expect(a.result.isNegative, isTrue);
      expect(a.scenario, MonthEndScenario.shortfall);
      final sf = a.shortfalls.first;
      expect(sf.month, next);
      expect(sf.contributors.first.description, 'Conserto do carro');
      expect(sf.contributors.first.amount, const Money(200000));

      final cut = a.options.firstWhere(
        (o) => o.kind == MonthEndOptionKind.cutDiscretionary,
      );
      expect(cut.deltas[next], const Money(23000)); // 10% de 2.300

      final post = a.options.firstWhere(
        (o) => o.kind == MonthEndOptionKind.postpone,
      );
      expect(post.postponed.single.description, 'Conserto do carro');
      final cmp = a.compare(post);
      final n = cmp.firstWhere((c) => c.month == next);
      expect(n.after, n.before + const Money(200000));
      expect(cmp.firstWhere((c) => c.month == next.next).change, Money.zero);
      expect(a.shortfallMonthsAfter(post) < a.shortfalls.length, isTrue);

      final reneg = a.options.firstWhere(
        (o) => o.kind == MonthEndOptionKind.renegotiate,
      );
      expect(reneg.monthlyRelief, const Money(30000));
      expect(reneg.totalCostChange, const Money(200000)); // 10.000 − 8.000
      expect(reneg.isLenderQuote, isTrue);
      // Sem sobra no déficit: nada de metas nem amortização.
      expect(
        a.options.any(
          (o) =>
              o.kind == MonthEndOptionKind.goal ||
              o.kind == MonthEndOptionKind.debtPrepay,
        ),
        isFalse,
      );

      // Aplicar o adiamento mexe só no futuro; o mês fechado fica igual.
      final closed = fc.closingOf(_prev)!;
      await fc.applyMonthEndOption(a, post);
      final moved = fc.data.transactions.firstWhere(
        (t) => t.description == 'Conserto do carro',
      );
      expect(YearMonth.of(moved.date), next.next);
      expect(fc.closingOf(_prev)!.net, closed.net);
      expect(fc.closingOf(_prev)!.decision!.kind, 'postpone');
    });

    test('nunca planeja dentro de mês fechado', () async {
      final fc = await _ctrl(
        initial: 10000,
        prevIncome: 5000,
        prevExpenses: 2000,
      );
      await fc.closeMonth(_month);
      final planner = MonthEndPlanner(fc.engine);
      expect(planner.firstOpenMonth(), _month.next);
      expect(planner.firstOpenDate(), _month.next.firstDay);
      final a = fc.monthEndAnalysis(_month, debts: [_debtA]);
      final debt = a.options.firstWhere(
        (o) => o.kind == MonthEndOptionKind.debtPrepay,
      );
      final closedNow = fc.closingOf(_month)!;
      await fc.applyMonthEndOption(a, debt);
      final planned = fc.data.transactions.firstWhere(
        (t) => t.description.startsWith('Amortização extra'),
      );
      expect(YearMonth.of(planned.date), _month.next);
      expect(
        fc.engine.monthTotals(ProjectionFilter.none, _month).net,
        closedNow.net,
      );
    });

    test('mês aberto não pode ser planejado', () async {
      final fc = await _ctrl(
        initial: 1000,
        prevIncome: 1000,
        prevExpenses: 500,
      );
      final a = fc.monthEndAnalysis(_month);
      expect(a.isClosed, isFalse);
      expect(
        () => fc.applyMonthEndOption(a, a.options.first),
        throwsArgumentError,
      );
    });
  });

  testWidgets('tela: sobra, dívida informada e aplicar', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late FinanceController fc;
    await tester.runAsync(
      () async => fc = await _ctrl(
        initial: 10000,
        prevIncome: 5000,
        prevExpenses: 2000,
        reserve: 3000,
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: MonthEndPlanScreen(month: _prev),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('month-end-scenario-surplus')),
      findsOneWidget,
    );
    expect(find.text('Livre para decidir'), findsOneWidget);
    expect(find.text(const Money(1000000).format()), findsWidgets);

    expect(find.byKey(const ValueKey('month-end-no-debts')), findsOneWidget);

    // Escolhe "manter em caixa" e aplica: só registra a decisão.
    await tester.tap(find.text('Manter o dinheiro em conta'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('month-end-apply')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Aplicar'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(fc.closingOf(_prev)!.decision!.kind, 'keepCash');
    expect(find.byKey(const ValueKey('month-end-decision')), findsOneWidget);
  });

  test('reserva mínima vai e volta no JSON das configurações', () {
    final s = const AppSettings(minimumReserve: Money(123456));
    expect(
      AppSettings.fromJson(s.toJson()).minimumReserve,
      const Money(123456),
    );
    expect(AppSettings.fromJson(const {}).minimumReserve, Money.zero);
    expect(_now.year > 2000, isTrue);
  });
}
