import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/billing_cycle.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show MemoryRepo;

/// Regime de caixa: compras no cartão contam no mês de pagamento da fatura.
void main() {
  // Fecha dia 25, vence dia 1 do mês seguinte: a fatura Out/26 vence 01/11.
  final card = CreditCard(id: 'c6', name: 'C6', closingDay: 25, dueDay: 1);
  final acc = Account(id: 'a', name: 'Conta');
  final cats = [
    FinCategory(id: 'ass', name: 'Assinaturas', kind: CategoryKind.expense),
    FinCategory(id: 'mer', name: 'Mercado', kind: CategoryKind.expense),
  ];
  final oct = YearMonth(2026, 10);
  final nov = YearMonth(2026, 11);
  final dec = YearMonth(2026, 12);

  FinTransaction buy(
    String id,
    int cents,
    DateTime date, {
    String cat = 'mer',
    TransactionType type = TransactionType.expense,
  }) => FinTransaction(
    id: id,
    type: type,
    amount: Money(cents),
    description: id,
    date: date,
    cardId: 'c6',
    categoryId: cat,
    status: TransactionStatus.pending,
  );

  final purchases = [
    buy('microsoft', 6000, DateTime(2026, 10, 15), cat: 'ass'),
    buy('mercado', 33333, DateTime(2026, 10, 2)),
    buy('padaria', 1001, DateTime(2026, 9, 30)),
  ];
  // Conta: despesa fora do cartão, em outubro.
  final rent = FinTransaction(
    id: 'aluguel',
    type: TransactionType.expense,
    amount: const Money(150000),
    description: 'Aluguel',
    date: DateTime(2026, 10, 5),
    accountId: 'a',
    categoryId: 'mer',
    status: TransactionStatus.completed,
  );

  FinancialEngine engine({
    List<InvoicePayment> pays = const [],
    List<FinTransaction>? txs,
    DateTime? today,
  }) => FinancialEngine(
    FinanceData(
      accounts: [acc],
      cards: [card],
      categories: cats,
      transactions: txs ?? [...purchases, rent],
      invoicePayments: pays,
    ),
    today: today ?? DateTime(2026, 10, 3),
  );

  InvoicePayment pay(int cents, DateTime date, {String id = 'p1'}) =>
      InvoicePayment(
        id: id,
        cardId: 'c6',
        invoiceKey: '2026-10',
        amount: Money(cents),
        date: date,
        accountId: 'a',
      );

  Money cardExpenses(FinancialEngine e, YearMonth m) => e
      .monthEvents(ProjectionFilter.none, m)
      .where((x) => x.tx.cardId != null)
      .map((x) => -x.signed)
      .sum();

  Money categoryTotal(FinancialEngine e, YearMonth m, String cat) => e
      .monthEvents(ProjectionFilter(categoryIds: {cat}), m)
      .map((x) => -x.signed)
      .sum();

  test('compra após o fechamento vai para a fatura seguinte', () {
    expect(
      BillingCycle.invoiceFor(card, DateTime(2026, 10, 24)),
      YearMonth(2026, 10),
    );
    expect(
      BillingCycle.invoiceFor(card, DateTime(2026, 10, 25)),
      YearMonth(2026, 11),
    );
    expect(BillingCycle.dueDate(card, oct), DateTime(2026, 11, 1));
  });

  test('fatura não paga aparece no mês do vencimento', () {
    final e = engine();
    final inv = e.invoice(card, oct);
    expect(inv.total, const Money(40334));
    expect(inv.transactions.length, 3);
    expect(inv.cashDate, DateTime(2026, 11, 1));
    expect(cardExpenses(e, oct), Money.zero);
    expect(cardExpenses(e, nov), const Money(40334));
    // Total do mês conta a fatura uma única vez.
    final col = e.projection(MonthRange(oct, nov)).columns;
    expect(col[0].expenses, const Money(150000));
    expect(col[1].expenses, const Money(40334));
    // A compra de 15/10 conta como despesa de novembro.
    expect(e.recognitionMonth(purchases.first), nov);
    final slices = e.invoiceSlicesIn(nov, nov);
    expect(slices.single.invoice.title, 'Fatura C6 – Out/26');
    expect(slices.single.slice.amount, const Money(40334));
  });

  test('fatura paga antes do vencimento vai para o mês do pagamento', () {
    final e = engine(pays: [pay(40334, DateTime(2026, 10, 28))]);
    final inv = e.invoice(card, oct);
    expect(inv.isSettled, isTrue);
    expect(inv.cashDate, DateTime(2026, 10, 28));
    expect(cardExpenses(e, oct), const Money(40334));
    expect(cardExpenses(e, nov), Money.zero);
    expect(e.recognitionMonth(purchases.first), oct);
    // Soma por categoria = faturas pagas no mês + despesas fora do cartão.
    expect(
      categoryTotal(e, oct, 'ass') + categoryTotal(e, oct, 'mer'),
      const Money(40334) + rent.amount,
    );
  });

  test('alterar a data de pagamento move a fatura e as compras juntas', () {
    final late = engine(
      pays: [pay(40334, DateTime(2026, 12, 5))],
      today: DateTime(2026, 12, 10),
    );
    expect(late.invoice(card, oct).cashDate, DateTime(2026, 12, 5));
    expect(cardExpenses(late, nov), Money.zero);
    expect(cardExpenses(late, dec), const Money(40334));
    for (final t in purchases) {
      expect(late.recognitionMonth(t), dec);
    }
  });

  test('pagamento parcial: pago no mês do pagamento, saldo no vencimento', () {
    final e = engine(pays: [pay(10000, DateTime(2026, 10, 28))]);
    final inv = e.invoice(card, oct);
    expect(inv.slices.map((s) => s.amount), [
      const Money(10000),
      const Money(30334),
    ]);
    expect(cardExpenses(e, oct), const Money(10000));
    expect(cardExpenses(e, nov), const Money(30334));
    // Cada compra se divide sem perder centavos.
    for (final t in purchases) {
      expect(inv.shares[t.id]!.map((s) => s.amount).sum(), t.amount);
    }
    // Categorias do mês somam exatamente o valor pago no mês.
    expect(
      categoryTotal(e, oct, 'ass') + categoryTotal(e, oct, 'mer'),
      const Money(10000) + rent.amount,
    );
    expect(
      categoryTotal(e, nov, 'ass') + categoryTotal(e, nov, 'mer'),
      const Money(30334),
    );

    // Quitada em dezembro: o saldo segue para dezembro.
    final e2 = engine(
      pays: [
        pay(10000, DateTime(2026, 10, 28)),
        pay(30334, DateTime(2026, 12, 2), id: 'p2'),
      ],
      today: DateTime(2026, 12, 3),
    );
    expect(cardExpenses(e2, oct), const Money(10000));
    expect(cardExpenses(e2, nov), Money.zero);
    expect(cardExpenses(e2, dec), const Money(30334));
    expect(e2.invoice(card, oct).isSettled, isTrue);
  });

  test('estornos reduzem a fatura; saldo credor também aparece', () {
    final e = engine(
      txs: [
        buy('compra', 5000, DateTime(2026, 10, 2)),
        buy(
          'estorno',
          8000,
          DateTime(2026, 10, 3),
          type: TransactionType.income,
        ),
      ],
    );
    final inv = e.invoice(card, oct);
    expect(inv.total, const Money(-3000));
    expect(inv.isCredit, isTrue);
    final slice = e.invoiceSlicesIn(nov, nov).single.slice;
    expect(slice.amount, const Money(-3000));
  });

  test('editar uma compra recalcula a fatura', () {
    final edited = [
      purchases[0].copyWith(amount: const Money(12000)),
      ...purchases.skip(1),
    ];
    final e = engine(txs: edited);
    expect(e.invoice(card, oct).total, const Money(46334));
  });

  group('controlador', () {
    late MemoryRepo repo;
    late FinanceController fc;
    final today = Dates.today();

    setUp(() async {
      repo = MemoryRepo();
      fc = FinanceController(repo);
      await fc.load();
      await fc.saveAccount(acc);
      await fc.saveCard(card);
    });

    test('pagar a fatura quita todos os itens; desfazer reabre', () async {
      final month = BillingCycle.currentInvoice(card, today).add(-2);
      final d1 = BillingCycle.cycleStart(card, month);
      for (final (i, d) in [d1, d1.add(const Duration(days: 1))].indexed) {
        await fc.saveTransaction(buy('t$i', 1000 * (i + 1), d));
      }
      var inv = fc.engine.invoice(card, month);
      expect(inv.total, const Money(3000));

      await fc.payInvoice(inv, const Money(1000), date: today, accountId: 'a');
      expect(
        fc.data.transactions.every(
          (t) => t.status == TransactionStatus.pending,
        ),
        isTrue,
      );

      inv = fc.engine.invoice(card, month);
      await fc.payInvoice(inv, inv.remaining, date: today, accountId: 'a');
      expect(
        fc.data.transactions.every(
          (t) => t.status == TransactionStatus.completed,
        ),
        isTrue,
      );
      expect(fc.engine.invoice(card, month).isSettled, isTrue);

      await fc.deleteInvoicePayment(fc.data.invoicePayments.last);
      expect(
        fc.data.transactions.every(
          (t) => t.status == TransactionStatus.pending,
        ),
        isTrue,
      );
    });
  });
}
