// Sincronização bancária automática: idempotência, agendados como
// previstos e conciliação (critério de aceite 1). Dados fictícios.

import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/finance_repository.dart';
import 'package:financas_app/data/open_finance.dart';
import 'package:financas_app/domain/engine/projection_filter.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/enums.dart';
import 'package:financas_app/domain/open_finance/bank_sync.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show MemoryRepo;

/// "Banco" fictício: o teste muda as transações entre uma leitura e outra.
/// Como o servidor, devolve tudo (o app precisa ignorar o que já conhece).
class FakeBank extends OpenFinanceProvider {
  final txs = <String, ProviderTransaction>{};
  int reads = 0;

  void put(
    String id,
    DateTime date,
    int cents,
    String desc, {
    bool pending = false,
    bool deleted = false,
  }) => txs[id] = ProviderTransaction(
    externalId: 'pluggy:$id',
    date: date,
    signedAmount: Money(cents),
    description: desc,
    pending: pending,
    deleted: deleted,
  );

  @override
  String get id => 'pluggy';
  @override
  String get displayName => 'Banco fictício';
  @override
  bool get isSandbox => false;

  @override
  Future<OFChanges> fetchChanges(
    OpenFinanceConnection connection, {
    String? cursor,
    DateTime? since,
  }) async {
    reads++;
    return OFChanges(txs.values.toList(), 'c$reads');
  }

  @override
  Future<List<OFInstitution>> institutions() async => const [];
  @override
  Future<ConsentResult> requestConsent(OFInstitution institution) =>
      throw UnimplementedError();
  @override
  Future<List<ExternalTransaction>> fetchTransactions(
    OpenFinanceConnection connection, {
    DateTime? since,
  }) async => const [];
  @override
  Future<void> revokeConsent(OpenFinanceConnection connection) async {}
}

void main() {
  // Mês seguinte: datas futuras de verdade (agendamentos).
  final next = YearMonth.of(Dates.today()).add(1);
  DateTime day(int d) => DateTime(next.year, next.month, d);

  late MemoryRepo repo;
  late FakeBank bank;
  late FinanceController fc;

  Future<OpenFinanceConnection> connect({bool autoImport = true}) async {
    final c = OpenFinanceConnection(
      id: 'ofc_1',
      providerId: 'pluggy',
      institutionName: 'Banco Fictício · Conta',
      consentStatus: ConsentStatus.active,
      providerItemId: 'item-1',
      providerAccountId: 'acc-1',
      linkedAccountId: 'acc_app',
      autoImport: autoImport,
    );
    await repo.write([
      WriteOp.put(Coll.openFinanceConnections, c.id, c.toJson()),
    ]);
    await fc.load();
    return fc.connections.single;
  }

  Future<BankSyncResult> sync() => fc.syncConnection(fc.connections.single);

  List<FinTransaction> fromBank() => [
    for (final t in fc.data.transactions)
      if (t.description.contains('ALUGUEL') ||
          t.description.contains('MERCADO') ||
          t.description.contains('ACADEMIA'))
        t,
  ];

  Money expensesNextMonth() =>
      fc.engine.monthTotals(const ProjectionFilter(), next).expenses;

  setUp(() async {
    repo = MemoryRepo();
    await repo.write([
      WriteOp.put(
        Coll.accounts,
        'acc_app',
        Account(id: 'acc_app', name: 'Conta Fictícia').toJson(),
      ),
    ]);
    bank = FakeBank();
    fc = FinanceController(repo, openFinance: bank, autoSyncOnLoad: false);
    await fc.load();
  });

  tearDown(() => fc.dispose());

  test('sincronizar várias vezes cria uma única transação', () async {
    await connect();
    bank.put('t1', day(3), -8990, 'MERCADO FICTICIO');
    final first = await sync();
    expect(first.added, 1);
    expect(first.imported, 1);
    for (var i = 0; i < 3; i++) {
      final again = await sync();
      expect(again.isEmpty, isTrue, reason: 'repetição não grava nada');
    }
    expect(fromBank(), hasLength(1));
    expect(fc.externalTransactions, hasLength(1));
    expect(fromBank().single.status, TransactionStatus.completed);
    expect(fromBank().single.externalId, 'pluggy:t1');
  });

  test('sincronização automática traz o que mudou sem tocar em nada', () async {
    await connect();
    bank.put('t1', day(3), -8990, 'MERCADO FICTICIO');
    await Future.wait([fc.autoSync(), fc.autoSync(), sync()]);
    expect(fromBank(), hasLength(1));
    expect(fc.connections.single.syncCursor, isNotNull);
    expect(fc.lastAutoSyncAt, isNotNull);
  });

  test(
    'agendado entra como previsto e, ao ser confirmado, conta uma vez só',
    () async {
      await connect(autoImport: false);
      final before = expensesNextMonth();
      bank.put('p1', day(10), -150000, 'PIX AGENDADO ALUGUEL', pending: true);
      final r = await sync();
      expect(r.scheduled, 1);
      final planned = fromBank().single;
      expect(planned.status, TransactionStatus.planned);
      expect(expensesNextMonth() - before, const Money(150000));

      // O banco confirma (mesmo ID, agora POSTED).
      bank.put('p1', day(10), -150000, 'PIX AGENDADO ALUGUEL');
      final c = await sync();
      expect(c.confirmed, 1);
      expect(fromBank(), hasLength(1));
      expect(fromBank().single.id, planned.id);
      expect(fromBank().single.status, TransactionStatus.completed);
      expect(expensesNextMonth() - before, const Money(150000));
      expect((await sync()).isEmpty, isTrue);
    },
  );

  test(
    'confirmado com outro ID (remove o previsto e cria o confirmado)',
    () async {
      await connect(autoImport: false);
      bank.put('p1', day(10), -150000, 'PIX AGENDADO ALUGUEL', pending: true);
      await sync();
      final planned = fromBank().single;
      bank.put(
        'p1',
        day(10),
        -150000,
        'PIX AGENDADO ALUGUEL',
        pending: true,
        deleted: true,
      );
      bank.put('t2', day(11), -150000, 'PIX ALUGUEL');
      final r = await sync();
      expect(r.removed, 1);
      expect(r.matched, 1);
      expect(fromBank(), hasLength(1));
      expect(fromBank().single.id, planned.id);
      expect(fromBank().single.externalId, 'pluggy:t2');
      expect(fromBank().single.status, TransactionStatus.completed);
      expect(fromBank().single.date, day(11));
    },
  );

  test('confirmado com outro ID antes de a remoção chegar', () async {
    await connect(autoImport: true);
    bank.put('p1', day(10), -150000, 'PIX AGENDADO ALUGUEL', pending: true);
    await sync();
    bank.txs.remove('p1'); // remoção ainda não chegou
    bank.put('t2', day(10), -150000, 'PIX ALUGUEL');
    await sync();
    expect(fromBank(), hasLength(1));
    expect(fromBank().single.externalId, 'pluggy:t2');
    final old = fc.externalTransactions.firstWhere(
      (e) => e.externalId == 'pluggy:p1',
    );
    expect(old.status, ExternalTxStatus.superseded);
    // A remoção chega depois: nada muda.
    bank.put(
      'p1',
      day(10),
      -150000,
      'PIX AGENDADO ALUGUEL',
      pending: true,
      deleted: true,
    );
    final r = await sync();
    expect(r.removed, 0);
    expect(fromBank(), hasLength(1));
  });

  test('agendamento cancelado no banco sai da projeção', () async {
    await connect();
    final before = expensesNextMonth();
    bank.put('p1', day(10), -150000, 'PIX AGENDADO ALUGUEL', pending: true);
    await sync();
    bank.put(
      'p1',
      day(10),
      -150000,
      'PIX AGENDADO ALUGUEL',
      pending: true,
      deleted: true,
    );
    final r = await sync();
    expect(r.removed, 1);
    expect(fromBank(), isEmpty);
    expect(expensesNextMonth(), before);
  });

  test('concilia com a recorrência já cadastrada, sem somar de novo', () async {
    await repo.write([
      WriteOp.put(
        Coll.recurringTransactions,
        'rec_gym',
        RecurringRule(
          id: 'rec_gym',
          type: TransactionType.expense,
          amount: const Money(12000),
          description: 'Academia (manual)',
          accountId: 'acc_app',
          categoryId: 'cat_other_expense',
          startDate: DateTime(next.year, next.month - 2, 8),
          dayOfMonth: 8,
        ).toJson(),
      ),
    ]);
    await connect(autoImport: true);
    final before = expensesNextMonth();
    bank.put('g1', day(9), -12000, 'ACADEMIA FICTICIA', pending: true);
    final r = await sync();
    expect(r.matched, 1);
    expect(r.scheduled, 0);
    expect(expensesNextMonth(), before, reason: 'a ocorrência já contava');
    final occ = fc.data.transactions.singleWhere(
      (t) => t.recurringId == 'rec_gym',
    );
    expect(occ.externalId, 'pluggy:g1');
    expect(occ.occurrenceDate, day(8));

    bank.put('g1', day(9), -12000, 'ACADEMIA FICTICIA');
    await sync();
    final done = fc.data.transactions.singleWhere(
      (t) => t.recurringId == 'rec_gym',
    );
    expect(done.status, TransactionStatus.completed);
    expect(expensesNextMonth(), before);
  });

  test('concilia com lançamento manual e não duplica', () async {
    await connect(autoImport: true);
    await fc.saveTransaction(
      FinTransaction(
        id: 'tx_manual',
        type: TransactionType.expense,
        amount: const Money(4590),
        description: 'Mercado do bairro',
        categoryId: 'cat_other_expense',
        date: day(2),
        accountId: 'acc_app',
        status: TransactionStatus.pending,
      ),
    );
    bank.put('m1', day(4), -4590, 'MERCADO BAIRRO');
    final r = await sync();
    expect(r.matched, 1);
    expect(r.imported, 0);
    final t = fc.data.transactions.singleWhere((t) => t.id == 'tx_manual');
    expect(t.externalId, 'pluggy:m1');
    expect(t.status, TransactionStatus.completed);
    expect(
      fc.data.transactions.where((t) => t.amount == const Money(4590)),
      hasLength(1),
    );
  });

  test('sem vínculo com conta do app, nada é lançado sozinho', () async {
    final c = OpenFinanceConnection(
      id: 'ofc_2',
      providerId: 'pluggy',
      institutionName: 'Sem vínculo',
      consentStatus: ConsentStatus.active,
      providerAccountId: 'acc-2',
      autoImport: true,
    );
    await repo.write([
      WriteOp.put(Coll.openFinanceConnections, c.id, c.toJson()),
    ]);
    await fc.load();
    bank.put('x', day(3), -1000, 'MERCADO');
    bank.put('y', day(9), -2000, 'ALUGUEL', pending: true);
    final r = await sync();
    expect(r.added, 2);
    expect(fromBank(), isEmpty);
    expect(fc.externalTransactions.map((e) => e.status).toSet(), {
      ExternalTxStatus.pending,
    });
  });

  test('dois aparelhos chegam aos mesmos documentos (IDs determinísticos)', () {
    final c = OpenFinanceConnection(
      id: 'ofc_1',
      providerId: 'pluggy',
      institutionName: 'X',
      consentStatus: ConsentStatus.active,
      linkedAccountId: 'acc_app',
      autoImport: true,
    );
    final f = [
      ProviderTransaction(
        externalId: 'pluggy:abc',
        date: day(1),
        signedAmount: const Money(-500),
        description: 'MERCADO',
      ),
    ];
    BankSyncResult run() => BankSync.plan(
      connection: c,
      fetched: f,
      existing: const [],
      candidates: const [],
      categoryFor: (_, _) => null,
    );
    final a = run(), b = run();
    expect(a.transactions.single.id, b.transactions.single.id);
    expect(a.externals.single.id, b.externals.single.id);
  });
}
