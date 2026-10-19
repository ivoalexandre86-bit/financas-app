import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/calculators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Price: 100.000 a 1% a.m. em 12x → 8.884,88', () {
    expect(pricePayment(const Money(10000000), 0.01, 12), const Money(888488));
    final r = loan(principal: const Money(10000000), rate: 0.01, months: 12);
    expect(r.firstPayment, const Money(888488));
    expect(r.rows.first.interest, const Money(100000));
    expect(r.rows.first.amortization, const Money(788488));
    expect(r.rows.last.balance, Money.zero);
    // A última parcela absorve o arredondamento.
    expect((r.lastPayment - const Money(888488)).cents.abs(), lessThan(10));
    expect(r.totalInterest.cents, closeTo(661856, 10));
  });

  test('SAC: amortização constante e parcela decrescente', () {
    final r = loan(
      principal: const Money(12000000),
      rate: 0.01,
      months: 12,
      system: AmortizationSystem.sac,
    );
    expect(r.rows.first.amortization, const Money(1000000));
    expect(r.firstPayment, const Money(1120000)); // 10.000 + 1.200
    expect(r.lastPayment, const Money(1010000)); // 10.000 + 100
    expect(r.totalInterest, const Money(780000)); // 1.200 + ... + 100
    expect(r.rows.last.balance, Money.zero);
  });

  test('financiamento sem juros divide o valor', () {
    final r = loan(principal: const Money(100000), rate: 0, months: 3);
    expect(r.totalPaid, const Money(100000));
    expect(r.totalInterest, Money.zero);
  });

  test('juros compostos com aporte mensal', () {
    // 1.000 inicial + 100/mês a 1% a.m. por 12 meses.
    final r = compoundInterest(
      initial: const Money(100000),
      monthly: const Money(10000),
      rate: 0.01,
      months: 12,
    );
    // 1000·1,01^12 = 1126,83 ; 100·((1,01^12−1)/0,01) = 1268,25
    expect(r.total, const Money(239508));
    expect(r.invested, const Money(220000));
    expect(r.interest, const Money(19508));
    expect(r.years.single.balance, r.total);
  });

  test('tabela por ano inclui o ano parcial', () {
    final r = compoundInterest(
      initial: const Money(100000),
      monthly: Money.zero,
      rate: 0,
      months: 30,
    );
    expect(r.years.map((y) => y.year), [1, 2, 3]);
    expect(r.total, const Money(100000));
  });

  test('taxa anual equivalente', () {
    expect(monthlyFromAnnual(0.12682503), closeTo(0.01, 1e-8));
    expect(annualFromMonthly(0.01), closeTo(0.126825, 1e-6));
  });

  test('quanto guardar por mês', () {
    // 12.000 em 12 meses sem rendimento → 1.000/mês.
    expect(
      monthlySavingsFor(target: const Money(1200000), rate: 0, months: 12),
      const Money(100000),
    );
    // Com 1% a.m.: 12.000 / 12,682503 = 946,18…
    final pmt = monthlySavingsFor(
      target: const Money(1200000),
      rate: 0.01,
      months: 12,
    );
    expect(pmt, const Money(94619));
    final check = compoundInterest(
      initial: Money.zero,
      monthly: pmt,
      rate: 0.01,
      months: 12,
    );
    expect(check.total >= const Money(1200000), isTrue);
    // Já tendo o suficiente, não precisa guardar.
    expect(
      monthlySavingsFor(
        target: const Money(100000),
        rate: 0.01,
        months: 12,
        initial: const Money(100000),
      ),
      Money.zero,
    );
  });

  test('quitar ou investir segue a maior taxa', () {
    final debtWins = prepayVsInvest(
      debt: const Money(10000000),
      debtRate: 0.02,
      months: 24,
      extra: const Money(2000000),
      investRate: 0.008,
    );
    expect(debtWins.prepayWins, isTrue);
    expect(debtWins.newPayment < debtWins.currentPayment, isTrue);
    expect(debtWins.interestSaved.isPositive, isTrue);

    final investWins = prepayVsInvest(
      debt: const Money(10000000),
      debtRate: 0.005,
      months: 24,
      extra: const Money(2000000),
      investRate: 0.01,
    );
    expect(investWins.prepayWins, isFalse);
    expect(investWins.investValue.cents, closeTo(2000000 * 1.2697346, 2));
  });

  test('quitar tudo: parcela zera e a sobra é investida', () {
    final r = prepayVsInvest(
      debt: const Money(100000),
      debtRate: 0.02,
      months: 10,
      extra: const Money(150000),
      investRate: 0.01,
    );
    expect(r.newPayment, Money.zero);
    expect(r.prepayWins, isTrue);
  });

  test('prazo inválido', () {
    expect(() => pricePayment(const Money(100), 0.01, 0), throwsArgumentError);
  });
}
