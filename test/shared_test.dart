import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/cloud/shared_api.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/engine/shared_engine.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/shared.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/state/shared_controller.dart';
import 'package:financas_app/ui/screens/shared/shared_expense_screen.dart';
import 'package:financas_app/ui/screens/shared/shared_screen.dart';
import 'package:financas_app/ui/screens/shared/shared_widgets.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

const ana = 'u-ana', bia = 'u-bia', caio = 'u-caio';

ShareGroup _group({
  List<SharedExpense> expenses = const [],
  List<ShareRecurrence> recurrences = const [],
  ShareRole role = ShareRole.owner,
}) => ShareGroup(
  id: 'g1',
  name: 'Casa',
  ownerId: ana,
  myRole: role,
  members: const [
    ShareMember(userId: ana, name: 'Ana', role: ShareRole.owner),
    ShareMember(userId: bia, name: 'Bia'),
  ],
  categories: const [
    ShareCategory(
      id: 'c-luz',
      name: 'Luz e água',
      percentages: {ana: 6000, bia: 4000},
    ),
    ShareCategory(
      id: 'c-outras',
      name: 'Outras despesas',
      percentages: {ana: 5000, bia: 5000},
    ),
  ],
  recurrences: recurrences,
  expenses: expenses,
);

SharedExpense _luz({
  List<SharePayment> payments = const [],
  DateTime? deletedAt,
  String? sourceKey = 'tx-luz',
}) => SharedExpense(
  id: 'e1',
  groupId: 'g1',
  ownerId: ana,
  categoryId: 'c-luz',
  categoryName: 'Luz e água',
  description: 'Conta de luz',
  total: 30000,
  date: DateTime(2026, 10, 10),
  dueDate: DateTime(2026, 10, 15),
  source: 'account',
  sourceKey: sourceKey,
  allocations: const [
    ShareAllocation(ana, 6000, 18000),
    ShareAllocation(bia, 4000, 12000),
  ],
  payments: payments,
  deletedAt: deletedAt,
);

/// API falsa: guarda o estado e registra as chamadas.
class FakeSharedApi implements SharedApi {
  SharedState current;
  final calls = <String>[];
  final bodies = <Map<String, Object?>>[];
  FakeSharedApi(this.current);

  @override
  Future<SharedState> state() async => current;
  @override
  Future<String> upsertExpense(Map<String, Object?> body) async {
    calls.add('upsert ${body['sourceKey']}');
    bodies.add(body);
    return 'new';
  }

  @override
  Future<void> deleteExpense(String id) async => calls.add('delete $id');
  @override
  Future<String> createRecurrence(Map<String, Object?> body) async {
    calls.add('recurrence ${body['sourceRuleId']}');
    bodies.add(body);
    return 'r1';
  }

  @override
  dynamic noSuchMethod(Invocation i) => Future.value();
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
  });

  group('ShareMath', () {
    test('divide sem perder centavos (igual ao servidor)', () {
      final a = ShareMath.allocate(30000, {ana: 6000, bia: 4000});
      expect(a.map((x) => x.amount), [18000, 12000]);
      final t = ShareMath.allocate(10000, {ana: 3334, bia: 3333, caio: 3333});
      expect(t.map((x) => x.amount), [3334, 3333, 3333]);
      final odd = ShareMath.allocate(101, {ana: 5000, bia: 5000});
      expect(odd.map((x) => x.amount), [51, 50]);
    });

    test('valida 100% e participantes ativos', () {
      expect(
        ShareMath.checkPercentages({ana: 6000, bia: 3000}, [ana, bia]),
        contains('100%'),
      );
      expect(
        ShareMath.checkPercentages({ana: 6000, caio: 4000}, [ana, bia]),
        contains('ativos'),
      );
      expect(
        ShareMath.checkPercentages({ana: 6000, bia: 4000}, [ana, bia]),
        isNull,
      );
      expect(
        ShareMath.equal([ana, bia, caio]).values.reduce((a, b) => a + b),
        fullBp,
      );
      expect(parseBp('33,33'), 3333);
      expect(parseBp('abc'), isNull);
      expect(bpLabel(3333), '33,33%');
    });
  });

  group('Orçamento de cada participante', () {
    final cats = [
      FinCategory(id: 'luz', name: 'Luz e Agua', kind: CategoryKind.expense),
    ];

    test('participante recebe só a parte dele; pagamento parcial divide', () {
      final s = SharedState(
        userId: bia,
        groups: [
          _group(
            role: ShareRole.member,
            expenses: [
              _luz(
                payments: [
                  SharePayment(
                    id: 'p1',
                    userId: bia,
                    amount: 5000,
                    date: DateTime(2026, 10, 20),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final txs = SharedBudgetSync.desired(
        state: s,
        categories: cats,
        accountId: 'acc',
      );
      expect(txs.map((t) => t.id), ['sh_pp_p1', 'sh_pr_e1']);
      final paid = txs.first, open = txs.last;
      expect(paid.amount.cents, 5000);
      expect(paid.status, TransactionStatus.completed);
      expect(open.amount.cents, 7000);
      expect(open.type, TransactionType.expense);
      expect(open.date, DateTime(2026, 10, 15));
      // Categoria pelo nome, ignorando acento e maiúsculas.
      expect(open.categoryId, 'luz');
      // Nunca o valor total (não duplica a despesa original).
      expect(txs.fold(0, (a, t) => a + t.amount.cents), 12000);
    });

    test('quem pagou recebe reembolsos (recebido e a receber)', () {
      final s = SharedState(
        userId: ana,
        groups: [
          _group(
            expenses: [
              _luz(
                payments: [
                  SharePayment(
                    id: 'p1',
                    userId: bia,
                    amount: 2000,
                    date: DateTime(2026, 10, 20),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final txs = SharedBudgetSync.desired(
        state: s,
        categories: const [],
        accountId: 'acc',
      );
      expect(txs.map((t) => t.id), ['sh_rp_p1', 'sh_rr_e1_$bia']);
      expect(txs.every((t) => t.type == TransactionType.income), isTrue);
      expect(txs.last.amount.cents, 10000);
      expect(txs.last.status, TransactionStatus.planned);
    });

    test('despesa excluída mantém só o que já foi pago', () {
      final s = SharedState(
        userId: bia,
        groups: [
          _group(
            expenses: [
              _luz(
                deletedAt: DateTime(2026, 10, 21),
                payments: [
                  SharePayment(
                    id: 'p1',
                    userId: bia,
                    amount: 5000,
                    date: DateTime(2026, 10, 20),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final txs = SharedBudgetSync.desired(
        state: s,
        categories: const [],
        accountId: 'acc',
      );
      expect(txs.map((t) => t.id), ['sh_pp_p1']);
    });

    test('ao sair do grupo, pendentes saem e pagos ficam', () {
      final existing = [
        FinTransaction(
          id: 'sh_pr_e1',
          type: TransactionType.expense,
          amount: const Money(100),
          description: 'x',
          date: DateTime(2026, 10, 1),
          accountId: 'acc',
          status: TransactionStatus.pending,
        ),
        FinTransaction(
          id: 'sh_pp_p1',
          type: TransactionType.expense,
          amount: const Money(100),
          description: 'x',
          date: DateTime(2026, 10, 1),
          accountId: 'acc',
          status: TransactionStatus.completed,
        ),
        FinTransaction(
          id: 'normal',
          type: TransactionType.expense,
          amount: const Money(100),
          description: 'x',
          date: DateTime(2026, 10, 1),
          accountId: 'acc',
        ),
      ];
      final (puts, deletes) = SharedBudgetSync.diff(
        existing: existing,
        desired: const [],
      );
      expect(puts, isEmpty);
      expect(deletes, ['sh_pr_e1']);
    });
  });

  group('Mudanças no orçamento de quem compartilhou', () {
    FinanceData data({
      List<FinTransaction> txs = const [],
      List<RecurringRule> rules = const [],
    }) => FinanceData(
      accounts: [Account(id: 'acc', name: 'Conta')],
      transactions: txs,
      recurringRules: rules,
    );
    final luzTx = FinTransaction(
      id: 'tx-luz',
      type: TransactionType.expense,
      amount: const Money(30000),
      description: 'Conta de luz',
      date: DateTime(2026, 10, 10),
      dueDate: DateTime(2026, 10, 15),
      accountId: 'acc',
    );

    test('sem mudança, nada a enviar; valor editado e exclusão sobem', () {
      final s = SharedState(
        userId: ana,
        groups: [
          _group(expenses: [_luz()]),
        ],
      );
      var engine = FinancialEngine(
        data(txs: [luzTx]),
        today: DateTime(2026, 10, 11),
      );
      var (ups, dels) = OwnerReconcile.plan(state: s, engine: engine);
      expect(ups, isEmpty);
      expect(dels, isEmpty);

      final edited = FinTransaction.fromJson({
        ...luzTx.toJson(),
        'amount': 32000,
      });
      engine = FinancialEngine(
        data(txs: [edited]),
        today: DateTime(2026, 10, 11),
      );
      (ups, dels) = OwnerReconcile.plan(state: s, engine: engine);
      expect(ups.single.total, 32000);
      expect(ups.single.sourceKey, 'tx-luz');

      engine = FinancialEngine(data(), today: DateTime(2026, 10, 11));
      (ups, dels) = OwnerReconcile.plan(state: s, engine: engine);
      expect(dels, ['e1']);
    });

    test('recorrência compartilhada gera as ocorrências do horizonte', () {
      final rule = RecurringRule(
        id: 'rule-net',
        type: TransactionType.expense,
        amount: const Money(12000),
        description: 'Internet',
        accountId: 'acc',
        frequency: RecurrenceFrequency.monthly,
        startDate: DateTime(2026, 1, 5),
      );
      final rec = ShareRecurrence(
        id: 'r1',
        ownerId: ana,
        sourceRuleId: 'rule-net',
        categoryId: 'c-outras',
        description: 'Internet',
        createdAt: DateTime(2026, 10, 1),
      );
      final s = SharedState(
        userId: ana,
        groups: [
          _group(recurrences: [rec]),
        ],
      );
      final engine = FinancialEngine(
        data(rules: [rule]),
        today: DateTime(2026, 10, 11),
      );
      final (ups, _) = OwnerReconcile.plan(state: s, engine: engine);
      // Out/2026 até Out/2027 (13 ocorrências), nenhuma antes de compartilhar.
      expect(ups.length, 13);
      expect(ups.first.sourceKey, 'r:rule-net:2026-10-05');
      expect(ups.first.recurrenceId, 'r1');
      expect(ups.first.source, 'recurring');

      // Pausada: nada novo.
      final paused = SharedState(
        userId: ana,
        groups: [
          _group(
            recurrences: [
              ShareRecurrence(
                id: 'r1',
                ownerId: ana,
                sourceRuleId: 'rule-net',
                description: 'Internet',
                paused: true,
                createdAt: DateTime(2026, 10, 1),
              ),
            ],
          ),
        ],
      );
      expect(OwnerReconcile.plan(state: paused, engine: engine).$1, isEmpty);
    });

    test('participante comum não envia nada', () {
      final s = SharedState(
        userId: ana,
        groups: [
          _group(role: ShareRole.member, expenses: [_luz()]),
        ],
      );
      final engine = FinancialEngine(data(), today: DateTime(2026, 10, 11));
      final (ups, dels) = OwnerReconcile.plan(state: s, engine: engine);
      expect(ups, isEmpty);
      expect(dels, isEmpty);
    });
  });

  group('Relatórios e simulação', () {
    test('totais por pessoa, filtro por situação e saldo entre pares', () {
      final e = _luz(
        payments: [
          SharePayment(
            id: 'p1',
            userId: bia,
            amount: 2000,
            date: DateTime(2026, 10, 20),
          ),
        ],
      );
      final s = SharedState(
        userId: ana,
        groups: [
          _group(expenses: [e]),
        ],
      );
      final t = SharedReport.totals([e]);
      expect(t.total, 30000);
      expect(t.user(ana).owed, 18000);
      expect(t.user(ana).paid, 18000);
      expect(t.user(ana).fronted, 30000);
      expect(t.user(bia).outstanding, 10000);
      expect(e.status, PayStatus.partial);
      expect(SharedReport.owedBetween([e], bia, ana), 10000);
      expect(
        SharedReport.filter(s, const SharedFilter(status: PayStatus.paid)),
        isEmpty,
      );
      expect(
        SharedReport.filter(
          s,
          const SharedFilter(participantId: ana, status: PayStatus.paid),
        ),
        hasLength(1),
      );
    });

    test('simulação muda percentuais sem tocar nos dados reais', () {
      final g = _group(expenses: [_luz()]);
      final base = SharedScenario.of(g);
      final sim = SharedScenario(
        percentages: {
          ...base.percentages,
          'c-luz': {ana: 5000, bia: 5000},
        },
        participants: base.participants,
        extra: const [SimSharedItem('Faxina', 'c-outras', 40000)],
      );
      final r = SharedSimulation.run(
        g,
        sim,
        from: YearMonth(2026, 10),
        months: 2,
      );
      expect(r[0].current[bia], 12000);
      expect(r[0].sim[bia], 15000 + 20000);
      expect(r[1].sim[bia], 20000);
      expect(r[0].simTotal, 70000);
      // Dados reais intactos.
      expect(g.expenses.first.allocationOf(bia)!.amount, 12000);

      // Pessoa hipotética entrando com 1/3 em tudo.
      final three = SharedScenario(
        percentages: {
          'c-luz': {ana: 3334, bia: 3333, 'sim:1': 3333},
          'c-outras': {ana: 3334, bia: 3333, 'sim:1': 3333},
        },
        participants: [ana, bia, 'sim:1'],
      );
      expect(three.error(g), isNull);
      final r3 = SharedSimulation.run(
        g,
        three,
        from: YearMonth(2026, 10),
        months: 1,
      );
      expect(r3[0].sim['sim:1'], 9999);
    });
  });

  group('SharedController', () {
    Future<(FinanceController, SharedController, FakeSharedApi)> setup(
      SharedState s,
    ) async {
      final fc = FinanceController(MemoryRepo());
      await fc.load();
      await fc.saveAccount(Account(id: 'acc', name: 'Conta'));
      final api = FakeSharedApi(s);
      final sc = SharedController(api, fc);
      await sc.refresh();
      return (fc, sc, api);
    }

    test('refresh grava a parte da participante no orçamento dela', () async {
      final (fc, sc, _) = await setup(
        SharedState(
          userId: bia,
          groups: [
            _group(role: ShareRole.member, expenses: [_luz()]),
          ],
        ),
      );
      final mine = fc.data.transactions
          .where((t) => t.id.startsWith('sh_'))
          .toList();
      expect(mine.single.amount.cents, 12000);
      expect(
        fc.data.categories.any(
          (c) => c.id == SharedBudgetSync.sharedCategoryId,
        ),
        isTrue,
      );
      // Idempotente: um novo refresh não duplica.
      await sc.refresh();
      expect(
        fc.data.transactions.where((t) => t.id.startsWith('sh_')),
        hasLength(1),
      );
      sc.dispose();
    });

    test(
      'marcar a minha parte como paga no orçamento registra o pagamento',
      () async {
        final (fc, sc, api) = await setup(
          SharedState(
            userId: bia,
            groups: [
              _group(role: ShareRole.member, expenses: [_luz()]),
            ],
          ),
        );
        final open = fc.data.transactions.firstWhere((t) => t.id == 'sh_pr_e1');
        expect(sc.paidInBudget(), isEmpty);
        await fc.toggleCompleted(open, true);
        final p = sc.paidInBudget().single;
        expect(p.userId, bia);
        expect(p.amount, 12000);
        expect(p.expense.id, 'e1');
        sc.dispose();
      },
    );

    test(
      'compartilhar compra no cartão usa a data de pagamento da fatura',
      () async {
        final (fc, sc, api) = await setup(
          SharedState(userId: ana, groups: [_group()]),
        );
        await fc.saveCard(
          CreditCard(
            id: 'card',
            name: 'C6',
            closingDay: 5,
            dueDay: 12,
            paymentAccountId: 'acc',
          ),
        );
        final t = FinTransaction(
          id: 'tx-mercado',
          type: TransactionType.expense,
          amount: const Money(50000),
          description: 'Mercado',
          date: DateTime(2026, 10, 10),
          cardId: 'card',
          categoryId: 'cat-food',
        );
        await fc.saveTransaction(t);
        final g = sc.groups.single;
        await sc.shareTransaction(t, group: g, category: g.categories.last);
        final body = api.bodies.single;
        expect(body['source'], 'card');
        expect(body['total'], 50000);
        expect(body['dueDate'], '2026-11-12');
        expect(body['categoryId'], 'c-outras');
        expect(body['budgetCategoryId'], 'cat-food');
        expect(body.containsKey('override'), isFalse);
        expect(
          () => sc.shareTransaction(
            t,
            group: g,
            category: g.categories.last,
            override: {ana: 9000},
          ),
          throwsArgumentError,
        );
        sc.dispose();
      },
    );
  });

  testWidgets('tela de despesas e detalhe da despesa', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'acc', name: 'Conta'));
    });
    final now = Dates.today();
    final e = SharedExpense(
      id: 'e1',
      groupId: 'g1',
      ownerId: ana,
      categoryId: 'c-luz',
      categoryName: 'Luz e água',
      description: 'Conta de luz',
      total: 30000,
      date: now,
      allocations: const [
        ShareAllocation(ana, 6000, 18000),
        ShareAllocation(bia, 4000, 12000),
      ],
    );
    final api = FakeSharedApi(
      SharedState(
        userId: bia,
        groups: [
          _group(role: ShareRole.member, expenses: [e]),
        ],
      ),
    );
    final sc = SharedController(api, fc);
    await tester.runAsync(sc.refresh);
    Widget app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: fc),
        ChangeNotifierProvider.value(value: sc),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    );
    await tester.pumpWidget(app(const SharedScreen()));
    await tester.pump();
    expect(find.text('Conta de luz'), findsOneWidget);
    expect(find.textContaining('minha:'), findsOneWidget);
    await tester.pumpWidget(app(const SharedExpenseScreen(expenseId: 'e1')));
    await tester.pump();
    expect(find.text('Divisão'), findsOneWidget);
    expect(find.textContaining('em aberto'), findsOneWidget);
    expect(find.text('Pendente'), findsWidgets);
  });

  testWidgets('divisão por pessoa: adicionar, editar % e R\$', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, int>? value;
    String? error;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PercentEditor(
            ids: const [ana, bia],
            nameOf: (id) => id == ana ? 'Ana' : 'Bia',
            initial: const {ana: fullBp},
            total: 10000,
            onChanged: (v, e) {
              value = v;
              error = e;
            },
          ),
        ),
      ),
    );
    // Começa só com quem já tem percentual.
    expect(find.byKey(const ValueKey('share-person-1')), findsNothing);
    expect(find.text('Tudo distribuído (100%)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('share-value-0')), '60');
    await tester.pump();
    expect(find.text('Falta distribuir 40%'), findsOneWidget);
    expect(error, isNotNull);
    // Adicionar pessoa já sugere o que falta.
    await tester.tap(find.byKey(const ValueKey('share-add-person')));
    await tester.pump();
    expect(value, {ana: 6000, bia: 4000});
    expect(error, isNull);
    expect(find.byKey(const ValueKey('share-add-person')), findsNothing);
    // Em R\$: 25,00 de 100,00 = 25%.
    await tester.tap(find.text('R\$').last);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('share-value-1')), '25');
    await tester.pump();
    expect(value, {ana: 6000, bia: 2500});
    await tester.enterText(find.byKey(const ValueKey('share-value-0')), '75');
    await tester.pump();
    expect(value, {ana: 7500, bia: 2500});
    expect(error, isNull);
    // Remover a pessoa.
    await tester.tap(find.byTooltip('Remover').last);
    await tester.pump();
    expect(value, {ana: 7500});
    expect(find.text('Falta distribuir 25%'), findsOneWidget);
  });
}
