import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/fgts_engine.dart';
import 'package:financas_app/domain/engine/projection_filter.dart';
import 'package:financas_app/domain/models/asset.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/fgts.dart';
import 'package:financas_app/domain/models/scenario.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/fgts/fgts_screen.dart';
import 'package:financas_app/ui/screens/networth/networth_screen.dart';
import 'package:financas_app/ui/screens/projection/projection_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

// Dados fictícios.
Asset _fgts({int cents = 2000000, int deposit = 40000, DateTime? date}) =>
    Asset(
      id: 'fgts1',
      name: 'FGTS',
      kind: AssetKind.fgts,
      value: Money(cents),
      fgts: FgtsDetails(
        monthlyDeposit: Money(deposit),
        annualRatePct: 3,
        balanceConfirmed: true,
        balanceDate: date ?? DateTime(2026, 1, 15),
      ),
    );

ScenarioFlow _withdrawal(
  String id,
  int cents,
  DateTime date, {
  bool amountConfirmed = false,
}) => ScenarioFlow(
  id: id,
  date: date,
  amount: Money(cents),
  description: 'Saque do FGTS',
  source: ScenarioSource.fgts,
  refId: 'fgts1',
  purpose: FgtsPurpose.homePurchase.name,
  amountConfirmed: amountConfirmed,
);

Future<FinanceController> _setup() async {
  final fc = FinanceController(MemoryRepo());
  await fc.load();
  await fc.saveAccount(
    Account(id: 'a', name: 'Conta', initialBalance: const Money(100000)),
  );
  final now = DateTime.now();
  await fc.saveTransaction(
    FinTransaction(
      id: 'sal',
      type: TransactionType.income,
      amount: const Money(500000),
      description: 'Salário',
      date: DateTime(now.year, now.month, 5),
      accountId: 'a',
    ),
  );
  await fc.saveAsset(_fgts(date: Dates.dateOnly(now)));
  return fc;
}

void main() {
  test('FGTS: JSON ida e volta mantém estimado/confirmado', () {
    final a = _fgts();
    final r = Asset.fromJson(a.toJson());
    expect(r.isFgts, isTrue);
    expect(r.fgts!.monthlyDeposit, const Money(40000));
    expect(r.fgts!.balanceConfirmed, isTrue);
    expect(r.fgts!.balanceDate, DateTime(2026, 1, 15));

    final f = _withdrawal('w', 500000, DateTime(2027, 3, 10));
    final s = PlanScenario(id: 's', name: 'Casa', flows: [f]);
    final back = PlanScenario.fromJson(s.toJson());
    expect(back.flows.single.amountConfirmed, isFalse);
    expect(back.flows.single.isEstimate, isTrue);
    expect(back.flows.single.refId, 'fgts1');
    // FGTS fica fora do formulário genérico de bens.
    expect(AssetKind.of(liability: false), isNot(contains(AssetKind.fgts)));
  });

  test('saldo previsto: depósitos, rendimento e saques', () {
    final a = _fgts(cents: 1000000, deposit: 10000);
    // Mesmo dia: o saldo informado.
    expect(
      FgtsEngine.projectedBalance(a, DateTime(2026, 1, 15)),
      const Money(1000000),
    );
    // Um mês: 10.000 × (1,03^(1/12)) + 100 de depósito.
    final r = a.fgts!.monthlyRate;
    expect(
      FgtsEngine.projectedBalance(a, DateTime(2026, 2, 15)),
      Money((1000000 * (1 + r) + 10000).round()),
    );
    final w = _withdrawal('w', 300000, DateTime(2026, 2, 10));
    expect(
      FgtsEngine.projectedBalance(a, DateTime(2026, 2, 15), withdrawals: [w]),
      Money((1000000 * (1 + r) + 10000 - 300000).round()),
    );
    // Saque acima do saldo gera aviso.
    final big = _withdrawal('b', 9000000, DateTime(2026, 2, 10));
    expect(
      FgtsEngine.warnings(a, big, today: DateTime(2026, 1, 20)),
      isNotEmpty,
    );
  });

  test('saque-aniversário: alíquota + parcela adicional', () {
    expect(FgtsEngine.birthdayAmount(const Money(40000)), const Money(20000));
    expect(FgtsEngine.birthdayAmount(const Money(300000)), const Money(105000));
    expect(
      FgtsEngine.birthdayAmount(const Money(3000000)),
      const Money(440000),
    );
  });

  test(
    'critério 6: FGTS no patrimônio e saque só no próprio cenário',
    () async {
      final fc = await _setup();
      final nw = fc.netWorthEngine.compute(fc.assets);
      expect(nw.fgts, const Money(2000000));
      expect(nw.assets, Money.zero);
      expect(nw.total, nw.accounts + const Money(2000000));

      final e = fc.engine;
      final range = MonthRange.starting(e.currentMonth, 12);
      final base = e.projection(range);
      final date = e.currentMonth.add(3).firstDay.add(const Duration(days: 9));
      final withdrawal = PlanScenario(
        id: 'sw',
        name: 'Compra do apartamento',
        kind: ScenarioSource.fgts,
        flows: [_withdrawal('w1', 1500000, date)],
      );
      final other = PlanScenario(id: 'so', name: 'Outro cenário');
      await fc.saveScenario(withdrawal);
      await fc.saveScenario(other);

      final se = fc.scenarioEngine;
      final withIt = se.apply(base, fc.selectedScenario?.flows ?? const []);
      // Sem cenário escolhido: nada muda.
      expect(withIt.columns.last.accumulated, base.columns.last.accumulated);

      final a = se.apply(base, withdrawal.pendingFlows);
      final b = se.apply(base, other.pendingFlows);
      for (var i = 0; i < 3; i++) {
        expect(a.columns[i].accumulated, base.columns[i].accumulated);
      }
      expect(
        a.columns[3].income,
        base.columns[3].income + const Money(1500000),
      );
      expect(
        a.columns.last.accumulated,
        base.columns.last.accumulated + const Money(1500000),
      );
      expect(b.columns.last.accumulated, base.columns.last.accumulated);
      // O orçamento base continua igual com o cenário salvo.
      expect(
        fc.engine.projection(range).columns.last.accumulated,
        base.columns.last.accumulated,
      );
      // E o patrimônio não muda por simular.
      expect(fc.netWorthEngine.compute(fc.assets).total, nw.total);
    },
  );

  test('saque recebido entra uma vez só (lançamento real)', () async {
    final fc = await _setup();
    final e = fc.engine;
    final range = MonthRange.starting(e.currentMonth, 6);
    final base = e.projection(range);
    final s = PlanScenario(
      id: 'sw',
      name: 'Saque',
      kind: ScenarioSource.fgts,
      flows: [_withdrawal('w1', 300000, fc.today)],
    );
    await fc.saveScenario(s);
    await fc.receiveFgtsWithdrawal(
      fc.scenarios.single,
      fc.scenarios.single.flows.single,
      accountId: 'a',
      amount: const Money(280000),
      date: fc.today,
    );
    final after = fc.engine.projection(range);
    expect(
      after.columns.last.accumulated,
      base.columns.last.accumulated + const Money(280000),
    );
    final scenario = fc.scenarios.single;
    expect(scenario.flows.single.realized, isTrue);
    expect(scenario.flows.single.amountConfirmed, isTrue);
    final overlay = fc.scenarioEngine.apply(after, scenario.pendingFlows);
    expect(overlay.columns.last.accumulated, after.columns.last.accumulated);
    expect(fc.fgts!.value, const Money(2000000 - 280000));
    final tx = fc.data.transactions.firstWhere(
      (t) => t.id == scenario.flows.single.transactionId,
    );
    expect(tx.type, TransactionType.income);
    expect(tx.status, TransactionStatus.completed);
  });

  test(
    'saque atrasado ou em mês fechado vai para o próximo mês aberto',
    () async {
      final fc = await _setup();
      final cur = fc.engine.currentMonth;
      final past = _withdrawal('p', 1000, cur.add(-2).firstDay);
      expect(fc.scenarioEngine.monthOf(past), cur);
      await fc.closeMonth(cur);
      expect(fc.scenarioEngine.monthOf(past), cur.next);
      final range = MonthRange.starting(cur, 3);
      final base = fc.engine.projection(range);
      final a = fc.scenarioEngine.apply(base, [past]);
      expect(a.columns.first.income, base.columns.first.income);
      expect(a.columns[1].income, base.columns[1].income + const Money(1000));
    },
  );

  group('telas', () {
    setUp(() async {
      Intl.defaultLocale = 'pt_BR';
      await initializeDateFormatting('pt_BR');
    });

    Future<FinanceController> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late FinanceController fc;
      await tester.runAsync(() async => fc = await _setup());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: fc,
          child: MaterialApp(theme: AppTheme.dark(), home: home),
        ),
      );
      await tester.pump();
      return fc;
    }

    testWidgets('simular saque cria cenário e a Projeção o mostra', (
      tester,
    ) async {
      final fc = await pump(tester, const FgtsScreen());
      expect(find.byKey(const ValueKey('fgts-balance')), findsOneWidget);
      expect(find.text('Confirmado'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fgts-new-withdrawal')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('fgts-w-amount')),
          matching: find.byType(TextField),
        ),
        '3.000,00',
      );
      await tester.pump();
      expect(find.text('Caixa projetado'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('fgts-w-save')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(fc.scenarios, hasLength(1));
      final flow = fc.scenarios.single.flows.single;
      expect(flow.amount, const Money(300000));
      expect(flow.source, ScenarioSource.fgts);
      expect(flow.isEstimate, isTrue);
      expect(find.text('Valor estimado'), findsOneWidget);

      // Projeção: base x cenário.
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: fc,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const ProjectionScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('proj-scenario')), findsOneWidget);
      expect(find.byKey(const ValueKey('proj-scenario-result')), findsNothing);
      fc.selectScenario(fc.scenarios.single.id);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('proj-scenario-result')),
        findsOneWidget,
      );
      expect(find.textContaining('estimado'), findsWidgets);
    });

    testWidgets('registrar FGTS sem depósito mensal (campos opcionais)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late FinanceController fc;
      await tester.runAsync(() async {
        fc = FinanceController(MemoryRepo());
        await fc.load();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: fc,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const FgtsFormScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('fgts-form-balance')),
          matching: find.byType(TextField),
        ),
        '25.000,00',
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('fgts-form-save')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Valor inválido'), findsNothing);
      expect(fc.fgts?.value, const Money(2500000));
      expect(fc.fgts?.fgts?.monthlyDeposit, Money.zero);
    });

    testWidgets('patrimônio mostra o FGTS à parte', (tester) async {
      await pump(tester, const NetWorthScreen());
      expect(find.byKey(const ValueKey('networth-fgts')), findsOneWidget);
      expect(find.byKey(const ValueKey('networth-line-fgts')), findsOneWidget);
    });
  });
}
