import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/billing_cycle.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/engine/installments.dart';
import 'package:financas_app/domain/engine/recurrence.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('Money', () {
    test('parse e formatação pt-BR', () {
      expect(Money.tryParse('1.234,56'), const Money(123456));
      expect(Money.tryParse('R\$ 55,90'), const Money(5590));
      expect(Money.tryParse('3600'), const Money(360000));
      expect(Money.tryParse('10,5'), const Money(1050));
      expect(Money.tryParse('1.000'), const Money(100000));
      expect(Money.tryParse('abc'), isNull);
      expect(const Money(123456).format(), 'R\$ 1.234,56');
      expect(const Money(-5590).format(), '-R\$ 55,90');
    });
    test('divisão exata em parcelas', () {
      expect(const Money(360000).split(12).toSet(), {const Money(30000)});
      final p = const Money(100000).split(3);
      expect(p, [const Money(33334), const Money(33333), const Money(33333)]);
      expect(p.sum(), const Money(100000));
    });
  });

  group('Ciclo de faturamento', () {
    final card = CreditCard(id: 'c', name: 'Visa', closingDay: 10, dueDay: 17);
    test('compra antes/depois do fechamento', () {
      expect(
        BillingCycle.invoiceFor(card, DateTime(2026, 8, 9)),
        YearMonth(2026, 8),
      );
      expect(
        BillingCycle.invoiceFor(card, DateTime(2026, 8, 11)),
        YearMonth(2026, 9),
      );
      expect(
        BillingCycle.invoiceFor(card, DateTime(2026, 8, 10)),
        YearMonth(2026, 9),
      );
      expect(
        BillingCycle.dueDate(card, YearMonth(2026, 8)),
        DateTime(2026, 8, 17),
      );
    });
    test('virada de ano e meses curtos', () {
      final c31 = CreditCard(id: 'x', name: 'X', closingDay: 31, dueDay: 8);
      expect(
        BillingCycle.closingDate(c31, YearMonth(2026, 2)),
        DateTime(2026, 2, 28),
      );
      expect(
        BillingCycle.invoiceFor(c31, DateTime(2026, 2, 27)),
        YearMonth(2026, 2),
      );
      expect(
        BillingCycle.invoiceFor(c31, DateTime(2026, 2, 28)),
        YearMonth(2026, 3),
      );
      expect(
        BillingCycle.dueDate(c31, YearMonth(2026, 12)),
        DateTime(2027, 1, 8),
      );
      expect(
        BillingCycle.invoiceFor(c31, DateTime(2026, 12, 31)),
        YearMonth(2027, 1),
      );
    });
    test('parcela N cai N-1 faturas depois', () {
      final g = InstallmentGroup(
        id: 'g',
        description: 'Notebook',
        totalAmount: const Money(360000),
        count: 12,
        purchaseDate: DateTime(2026, 1, 29),
        cardId: 'x',
      );
      final c = CreditCard(id: 'x', name: 'X', closingDay: 30, dueDay: 7);
      final parts = Installments.build(g);
      expect(parts.length, 12);
      expect(
        BillingCycle.invoiceForTransaction(c, parts[0]),
        YearMonth(2026, 1),
      );
      expect(
        BillingCycle.invoiceForTransaction(c, parts[1]),
        YearMonth(2026, 2),
      );
      expect(
        BillingCycle.invoiceForTransaction(c, parts[11]),
        YearMonth(2026, 12),
      );
    });
  });

  group('Recorrência', () {
    test('mensal no dia 31 sem deriva', () {
      final r = RecurringRule(
        id: 'r',
        type: TransactionType.expense,
        amount: const Money(100),
        description: 'Aluguel',
        startDate: DateTime(2026, 1, 31),
      );
      final occ = Recurrence.occurrences(
        r,
        DateTime(2026, 1, 1),
        DateTime(2026, 4, 30),
      );
      expect(occ, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });
    test('dia do mês, data final e pausa', () {
      final r = RecurringRule(
        id: 'n',
        type: TransactionType.expense,
        amount: const Money(5590),
        description: 'Netflix',
        dayOfMonth: 10,
        startDate: DateTime(2026, 1, 15),
        endDate: DateTime(2026, 8, 1),
        pauses: [PausePeriod(DateTime(2026, 4, 1), DateTime(2026, 6, 1))],
      );
      final occ = Recurrence.occurrences(
        r,
        DateTime(2025, 1, 1),
        DateTime(2027, 1, 1),
      );
      expect(occ, [
        DateTime(2026, 2, 10),
        DateTime(2026, 3, 10),
        DateTime(2026, 6, 10),
        DateTime(2026, 7, 10),
      ]);
    });
    test('semanal, trimestral e personalizada', () {
      RecurringRule rule(
        RecurrenceFrequency f, {
        int interval = 1,
        RecurrenceUnit unit = RecurrenceUnit.months,
      }) => RecurringRule(
        id: 'w',
        type: TransactionType.expense,
        amount: const Money(1),
        description: '',
        frequency: f,
        interval: interval,
        unit: unit,
        startDate: DateTime(2026, 1, 1),
      );
      expect(
        Recurrence.occurrences(
          rule(RecurrenceFrequency.weekly),
          DateTime(2026, 1, 1),
          DateTime(2026, 1, 31),
        ).length,
        5,
      );
      expect(
        Recurrence.occurrences(
          rule(RecurrenceFrequency.quarterly),
          DateTime(2026, 1, 1),
          DateTime(2026, 12, 31),
        ),
        [
          DateTime(2026, 1, 1),
          DateTime(2026, 4, 1),
          DateTime(2026, 7, 1),
          DateTime(2026, 10, 1),
        ],
      );
      expect(
        Recurrence.occurrences(
          rule(
            RecurrenceFrequency.custom,
            interval: 10,
            unit: RecurrenceUnit.days,
          ),
          DateTime(2026, 3, 1),
          DateTime(2026, 3, 31),
        ).first,
        DateTime(2026, 3, 2),
      );
    });
  });

  group('Motor financeiro', () {
    final acc = Account(
      id: 'a',
      name: 'Conta',
      initialBalance: const Money(1000000),
    );
    final card = CreditCard(
      id: 'c',
      name: 'Cartão',
      closingDay: 10,
      dueDay: 17,
      limit: const Money(1000000),
    );

    FinanceData base(
      List<FinTransaction> txs, {
      List<RecurringRule> rules = const [],
      List<InvoicePayment> pays = const [],
    }) => FinanceData(
      accounts: [acc],
      cards: [card],
      transactions: txs,
      recurringRules: rules,
      invoicePayments: pays,
    );

    test('compra no cartão conta uma vez; pagamento não é despesa', () {
      final txs = [
        FinTransaction(
          id: '1',
          type: TransactionType.expense,
          amount: const Money(50000),
          description: 'Mercado',
          date: DateTime(2026, 8, 5),
          cardId: 'c',
        ),
      ];
      final pays = [
        InvoicePayment(
          id: 'p',
          cardId: 'c',
          invoiceKey: '2026-08',
          amount: const Money(50000),
          date: DateTime(2026, 8, 17),
          accountId: 'a',
        ),
      ];
      final e = FinancialEngine(
        base(txs, pays: pays),
        today: DateTime(2026, 8, 20),
      );
      final proj = e.projection(
        MonthRange(YearMonth(2026, 8), YearMonth(2026, 9)),
      );
      expect(proj.columns[0].expenses, const Money(50000));
      expect(proj.columns[1].expenses, Money.zero);
      expect(proj.columns[0].accumulated, const Money(950000));
      expect(e.accountBalance('a'), const Money(950000));
      final inv = e.invoice(card, YearMonth(2026, 8));
      expect(inv.status, InvoiceStatus.paid);
      expect(e.availableLimit(card), const Money(1000000));
    });

    test('transferência não é receita nem despesa', () {
      final acc2 = Account(id: 'b', name: 'Poupança');
      final data = FinanceData(
        accounts: [acc, acc2],
        transactions: [
          FinTransaction(
            id: 't',
            type: TransactionType.transfer,
            amount: const Money(20000),
            description: 'Reserva',
            date: DateTime(2026, 8, 1),
            accountId: 'a',
            destinationAccountId: 'b',
          ),
        ],
      );
      final e = FinancialEngine(data, today: DateTime(2026, 8, 2));
      final p = e.projection(
        MonthRange(YearMonth(2026, 8), YearMonth(2026, 8)),
      );
      expect(p.columns[0].income, Money.zero);
      expect(p.columns[0].expenses, Money.zero);
      expect(p.columns[0].accumulated, const Money(1000000));
      expect(e.accountBalance('b'), const Money(20000));
      final onlyB = e.projection(
        MonthRange(YearMonth(2026, 8), YearMonth(2026, 8)),
        filter: const ProjectionFilter(accountIds: {'b'}),
      );
      expect(onlyB.columns[0].accumulated, const Money(20000));
    });

    test('recorrência virtual deduplicada com ocorrência materializada', () {
      final rule = RecurringRule(
        id: 'r',
        type: TransactionType.income,
        amount: const Money(1500000),
        description: 'Salário',
        accountId: 'a',
        dayOfMonth: 5,
        startDate: DateTime(2026, 8, 1),
      );
      final confirmed = FinTransaction(
        id: 'm',
        type: TransactionType.income,
        amount: const Money(1550000),
        description: 'Salário',
        date: DateTime(2026, 8, 6),
        accountId: 'a',
        recurringId: 'r',
        occurrenceDate: DateTime(2026, 8, 5),
      );
      final e = FinancialEngine(
        base([confirmed], rules: [rule]),
        today: DateTime(2026, 8, 10),
      );
      final p = e.projection(
        MonthRange(YearMonth(2026, 8), YearMonth(2026, 10)),
      );
      expect(p.columns.map((c) => c.income.cents), [1550000, 1500000, 1500000]);
      expect(
        p.columns.last.accumulated,
        const Money(1000000 + 1550000 + 3000000),
      );
    });

    test('parcelas distribuídas pelas faturas e filtro por origem', () {
      final g = InstallmentGroup(
        id: 'g',
        description: 'Notebook',
        totalAmount: const Money(360000),
        count: 12,
        purchaseDate: DateTime(2026, 8, 9),
        cardId: 'c',
      );
      final e = FinancialEngine(
        base(Installments.build(g)),
        today: DateTime(2026, 8, 9),
      );
      final p = e.projection(
        MonthRange(YearMonth(2026, 8), YearMonth(2027, 8)),
        filter: const ProjectionFilter(sources: {EventSource.installment}),
      );
      expect(p.columns.first.expenses, const Money(30000)); // vence 17/08
      expect(p.columns[11].expenses, const Money(30000)); // jul/27
      expect(p.columns[12].expenses, Money.zero);
      expect(p.totalExpenses, const Money(360000));
      expect(p.openingIsAccountBalance, isFalse);
      expect(e.availableLimit(card), const Money(1000000 - 360000));
    });

    test('drill-down usa as mesmas regras da matriz', () {
      final txs = [
        FinTransaction(
          id: '1',
          type: TransactionType.expense,
          amount: const Money(1000),
          description: 'A',
          date: DateTime(2026, 10, 2),
          accountId: 'a',
        ),
        FinTransaction(
          id: '2',
          type: TransactionType.expense,
          amount: const Money(2000),
          description: 'B',
          date: DateTime(2026, 9, 20),
          cardId: 'c',
        ), // fatura out/26, vence 17/10
        FinTransaction(
          id: '3',
          type: TransactionType.expense,
          amount: const Money(4000),
          description: 'C',
          date: DateTime(2026, 10, 3),
          accountId: 'a',
          status: TransactionStatus.cancelled,
        ),
      ];
      final e = FinancialEngine(base(txs), today: DateTime(2026, 9, 1));
      final ev = e.monthEvents(ProjectionFilter.none, YearMonth(2026, 10));
      expect(ev.map((x) => x.tx.id).toSet(), {'1', '2'});
      final col = e
          .projection(MonthRange(YearMonth(2026, 10), YearMonth(2026, 10)))
          .columns
          .single;
      expect(col.expenses, const Money(3000));
    });
  });
}
