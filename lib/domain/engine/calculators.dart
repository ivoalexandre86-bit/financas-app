import 'dart:math' as math;

import '../../core/money.dart';

// Calculadoras financeiras. Valores em centavos ([Money]); taxas como
// fração (1% = 0.01). As contas intermediárias usam double e o resultado é
// arredondado para centavos só no fim de cada etapa.

/// Taxa mensal equivalente a uma taxa anual (juros compostos).
double monthlyFromAnnual(double annual) =>
    annual <= -1 ? -1 : math.pow(1 + annual, 1 / 12).toDouble() - 1;

/// Taxa anual equivalente a uma taxa mensal.
double annualFromMonthly(double monthly) =>
    math.pow(1 + monthly, 12).toDouble() - 1;

Money _round(double cents) => Money(cents.round());

void _check(int months, double rate) {
  if (months <= 0) throw ArgumentError('Informe um prazo maior que zero');
  if (rate < 0 || !rate.isFinite) throw ArgumentError('Taxa inválida');
}

// -----------------------------------------------------------------------------
// Juros compostos

class CompoundYear {
  final int year;
  final Money invested;
  final Money interest;
  final Money balance;
  const CompoundYear(this.year, this.invested, this.interest, this.balance);
}

class CompoundResult {
  final Money total;
  final Money invested;
  final List<CompoundYear> years;
  const CompoundResult(this.total, this.invested, this.years);
  Money get interest => total - invested;
}

/// Montante com aporte [initial] e aportes mensais [monthly] (no fim de cada
/// mês) rendendo [rate] ao mês por [months] meses.
CompoundResult compoundInterest({
  required Money initial,
  required Money monthly,
  required double rate,
  required int months,
}) {
  _check(months, rate);
  var bal = initial.cents.toDouble();
  var invested = initial.cents;
  final years = <CompoundYear>[];
  for (var m = 1; m <= months; m++) {
    bal = bal * (1 + rate) + monthly.cents;
    invested += monthly.cents;
    if (m % 12 == 0 || m == months) {
      final b = _round(bal);
      years.add(
        CompoundYear((m + 11) ~/ 12, Money(invested), b - Money(invested), b),
      );
    }
  }
  return CompoundResult(_round(bal), Money(invested), years);
}

/// Aporte mensal para chegar a [target] em [months] meses, partindo de
/// [initial], com rendimento [rate] ao mês. Arredonda para cima (centavo).
Money monthlySavingsFor({
  required Money target,
  required double rate,
  required int months,
  Money initial = Money.zero,
}) {
  _check(months, rate);
  final grow = math.pow(1 + rate, months).toDouble();
  final missing = target.cents - initial.cents * grow;
  if (missing <= 0) return Money.zero;
  final pmt = rate == 0 ? missing / months : missing * rate / (grow - 1);
  return Money((pmt - 1e-6).ceil());
}

// -----------------------------------------------------------------------------
// Financiamento

enum AmortizationSystem {
  price('Price (parcelas iguais)'),
  sac('SAC (amortização constante)');

  final String label;
  const AmortizationSystem(this.label);
}

class AmortizationRow {
  final int number;
  final Money payment;
  final Money interest;
  final Money amortization;
  final Money balance;
  const AmortizationRow(
    this.number,
    this.payment,
    this.interest,
    this.amortization,
    this.balance,
  );
}

class LoanResult {
  final AmortizationSystem system;
  final Money principal;
  final List<AmortizationRow> rows;
  const LoanResult(this.system, this.principal, this.rows);

  Money get firstPayment => rows.first.payment;
  Money get lastPayment => rows.last.payment;
  Money get totalPaid => rows.fold(Money.zero, (a, r) => a + r.payment);
  Money get totalInterest => totalPaid - principal;
}

/// Parcela fixa da tabela Price.
Money pricePayment(Money principal, double rate, int months) {
  _check(months, rate);
  if (rate == 0) return Money((principal.cents / months).ceil());
  final f = math.pow(1 + rate, -months).toDouble();
  return _round(principal.cents * rate / (1 - f));
}

/// Tabela de amortização completa. A última parcela absorve a diferença de
/// arredondamento para zerar o saldo.
LoanResult loan({
  required Money principal,
  required double rate,
  required int months,
  AmortizationSystem system = AmortizationSystem.price,
}) {
  _check(months, rate);
  if (!principal.isPositive) throw ArgumentError('Informe o valor');
  final rows = <AmortizationRow>[];
  var balance = principal;
  final fixed = system == AmortizationSystem.price
      ? pricePayment(principal, rate, months)
      : null;
  final sacParts = system == AmortizationSystem.sac
      ? principal.split(months)
      : null;
  for (var n = 1; n <= months; n++) {
    final interest = _round(balance.cents * rate);
    var amort = fixed != null ? fixed - interest : sacParts![n - 1];
    if (n == months || amort > balance) amort = balance;
    balance -= amort;
    rows.add(AmortizationRow(n, amort + interest, interest, amort, balance));
  }
  return LoanResult(system, principal, rows);
}

// -----------------------------------------------------------------------------
// Quitar dívida antecipado × investir

class PrepayComparison {
  /// Parcela atual e depois de amortizar (mesmo prazo).
  final Money currentPayment;
  final Money newPayment;

  /// Juros que deixam de ser pagos ao amortizar.
  final Money interestSaved;

  /// Valor final ao amortizar e investir a economia das parcelas.
  final Money prepayValue;

  /// Valor final ao investir o dinheiro extra.
  final Money investValue;

  const PrepayComparison({
    required this.currentPayment,
    required this.newPayment,
    required this.interestSaved,
    required this.prepayValue,
    required this.investValue,
  });

  bool get prepayWins => prepayValue >= investValue;
  Money get difference => (prepayValue - investValue).abs();
}

/// Compara usar [extra] para amortizar a dívida (saldo [debt], taxa
/// [debtRate] ao mês, [months] parcelas restantes, mantendo o prazo) com
/// investir o mesmo valor a [investRate] ao mês pelo mesmo prazo.
PrepayComparison prepayVsInvest({
  required Money debt,
  required double debtRate,
  required int months,
  required Money extra,
  required double investRate,
}) {
  _check(months, debtRate);
  _check(months, investRate);
  if (!debt.isPositive) throw ArgumentError('Informe o saldo da dívida');
  final used = extra > debt ? debt : extra;
  final before = loan(principal: debt, rate: debtRate, months: months);
  final rest = debt - used;
  final after = rest.isPositive
      ? loan(principal: rest, rate: debtRate, months: months)
      : null;
  final saved = before.firstPayment - (after?.firstPayment ?? Money.zero);
  // A economia mensal é investida; o extra que sobrar também.
  final grow = math.pow(1 + investRate, months).toDouble();
  final annuity = investRate == 0 ? months.toDouble() : (grow - 1) / investRate;
  final leftover = (extra - used).cents * grow;
  return PrepayComparison(
    currentPayment: before.firstPayment,
    newPayment: after?.firstPayment ?? Money.zero,
    interestSaved: before.totalInterest - (after?.totalInterest ?? Money.zero),
    prepayValue: _round(saved.cents * annuity + leftover),
    investValue: _round(extra.cents * grow),
  );
}
