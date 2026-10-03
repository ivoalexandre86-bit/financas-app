import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/finance_repository.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositório em memória para testar regras de negócio do controlador.
class MemoryRepo implements FinanceRepository {
  final stores = <Coll, Map<String, Map<String, Object?>>>{
    for (final c in Coll.values) c: {},
  };
  AppSettings settings = const AppSettings();

  List<T> _all<T>(Coll c, T Function(Map<String, Object?>) f) =>
      stores[c]!.values.map(f).toList();

  @override
  Future<FinanceData> load() async => FinanceData(
    accounts: _all(Coll.accounts, Account.fromJson),
    cards: _all(Coll.cards, CreditCard.fromJson),
    categories: _all(Coll.categories, FinCategory.fromJson),
    projects: _all(Coll.projects, Project.fromJson),
    transactions: _all(Coll.transactions, FinTransaction.fromJson),
    recurringRules: _all(Coll.recurringTransactions, RecurringRule.fromJson),
    installmentGroups: _all(Coll.installmentGroups, InstallmentGroup.fromJson),
    invoicePayments: _all(Coll.invoicePayments, InvoicePayment.fromJson),
    settings: settings,
  );
  @override
  Future<List<OpenFinanceConnection>> loadConnections() async =>
      _all(Coll.openFinanceConnections, OpenFinanceConnection.fromJson);
  @override
  Future<List<ExternalTransaction>> loadExternalTransactions() async =>
      _all(Coll.externalTransactions, ExternalTransaction.fromJson);
  @override
  Future<void> write(List<WriteOp> ops) async {
    for (final op in ops) {
      if (op.json == null) {
        stores[op.coll]!.remove(op.id);
      } else {
        stores[op.coll]![op.id] = op.json!;
      }
    }
  }

  @override
  Future<void> saveSettings(AppSettings s) async => settings = s;
  @override
  Future<void> close() async {}
  @override
  Future<void> destroy() async {}
}

void main() {
  late MemoryRepo repo;
  late FinanceController fc;
  final today = Dates.today();

  setUp(() async {
    repo = MemoryRepo();
    fc = FinanceController(repo);
    await fc.load();
    await fc.saveAccount(Account(id: 'a', name: 'Conta'));
  });

  test('editar regra "somente futuras" preserva histórico concluído', () async {
    final rule = RecurringRule(
      id: 'r',
      type: TransactionType.expense,
      amount: const Money(5590),
      description: 'Netflix',
      accountId: 'a',
      startDate: Dates.addMonths(today, -3),
    );
    await fc.createRule(rule);
    final past = Dates.addMonths(today, -2);
    await fc.saveTransaction(
      FinancialEngine.virtualOccurrence(
        rule,
        past,
      ).copyWith(status: TransactionStatus.completed),
    );

    await fc.updateRule(
      rule,
      rule.copyWith(amount: const Money(6590)),
      RuleEditScope.futureOnly,
    );

    final rules = fc.data.recurringRules;
    expect(rules.length, 2);
    final old = rules.firstWhere((r) => r.id == 'r');
    expect(old.endDate, today.subtract(const Duration(days: 1)));
    final completed = fc.data.transactions.single;
    expect(completed.amount, const Money(5590));
    expect(completed.recurringId, 'r');
    final next = fc.engine
        .transactionsUntil(Dates.addMonths(today, 2))
        .where((t) => t.isVirtual && !t.date.isBefore(today));
    expect(next.every((t) => t.amount == const Money(6590)), isTrue);
  });

  test('excluir regra mantém lançamentos concluídos', () async {
    final rule = RecurringRule(
      id: 'r',
      type: TransactionType.expense,
      amount: const Money(1000),
      description: 'Academia',
      accountId: 'a',
      startDate: Dates.addMonths(today, -2),
    );
    await fc.createRule(rule);
    final occ = fc.engine.transactionsUntil(today).where((t) => t.isVirtual);
    await fc.saveTransaction(
      occ.first.copyWith(status: TransactionStatus.completed),
    );
    await fc.saveTransaction(
      occ.last.copyWith(status: TransactionStatus.pending),
    );
    await fc.deleteRule(rule);
    expect(fc.data.recurringRules, isEmpty);
    expect(fc.data.transactions.length, 1);
    expect(fc.data.transactions.single.status, TransactionStatus.completed);
  });

  test('pausar e retomar recorrência', () async {
    final rule = RecurringRule(
      id: 'r',
      type: TransactionType.income,
      amount: const Money(100),
      description: 'Aluguel recebido',
      accountId: 'a',
      frequency: RecurrenceFrequency.weekly,
      startDate: today.subtract(const Duration(days: 30)),
    );
    await fc.createRule(rule);
    await fc.pauseRule(fc.data.ruleById['r']!);
    expect(fc.data.ruleById['r']!.isPaused, isTrue);
    final future = fc.engine
        .transactionsUntil(today.add(const Duration(days: 60)))
        .where((t) => t.isVirtual && !t.date.isBefore(today));
    expect(future, isEmpty);
    await fc.resumeRule(fc.data.ruleById['r']!);
    expect(fc.data.ruleById['r']!.isPaused, isFalse);
  });

  test('cancelar parcelas futuras preserva as já faturadas', () async {
    await fc.saveCard(
      CreditCard(id: 'c', name: 'Cartão', closingDay: 10, dueDay: 17),
    );
    final g = await fc.createInstallmentPurchase(
      InstallmentGroup(
        id: 'g',
        description: 'Laptop',
        totalAmount: const Money(360000),
        count: 12,
        purchaseDate: Dates.addMonths(today, -3),
        cardId: 'c',
      ),
    );
    final n = await fc.cancelFutureInstallments(g.id);
    final parts = fc.installmentsOf(g.id);
    final cancelled = parts
        .where((t) => t.status == TransactionStatus.cancelled)
        .length;
    expect(cancelled, n);
    expect(n, inInclusiveRange(7, 9));
    expect(parts.length, 12);
  });

  test('validações de transação', () {
    FinTransaction t({
      String? acc,
      String? card,
      String? dest,
      TransactionType type = TransactionType.expense,
    }) => FinTransaction(
      id: 'x',
      type: type,
      amount: const Money(100),
      description: 'x',
      date: today,
      accountId: acc,
      cardId: card,
      destinationAccountId: dest,
    );
    expect(fc.validateTransaction(t()), isNotNull);
    expect(fc.validateTransaction(t(acc: 'a', card: 'c')), isNotNull);
    expect(fc.validateTransaction(t(acc: 'a')), isNull);
    expect(
      fc.validateTransaction(
        t(acc: 'a', dest: 'a', type: TransactionType.transfer),
      ),
      isNotNull,
    );
  });
}
