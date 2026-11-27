import 'dart:math' as math;

import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/debt.dart';
import 'calculators.dart' show pricePayment, annualFromMonthly;
import 'financial_engine.dart' show ProjectionColumn;

// Motor de dívidas e contratos: cronogramas Price e SAC, antecipação,
// quitação e comparação entre dívidas. Puro (sem estado), reutilizado pelas
// telas de Dívidas e pelo planejamento do fechamento do mês.
//
// Convenções (mostradas ao usuário como premissas):
// - Taxa efetiva ao mês, juros compostos, parcelas mensais.
// - O saldo devedor informado é o saldo logo depois da última parcela paga;
//   a 1ª parcela do cronograma tem um mês cheio de juros. Juros pró-rata
//   por dias não são calculados (a cotação do credor prevalece).
// - Antecipação e quitação acontecem na data do cálculo, antes da próxima
//   parcela.
// - Valores arredondados para centavos a cada linha; a última parcela
//   absorve a diferença para zerar o saldo.

Money _round(double cents) => Money(cents.round());

/// Uma linha do cronograma.
class DebtRow {
  final int number;
  final DateTime dueDate;

  /// Parcela (juros + amortização), sem encargos.
  final Money payment;
  final Money interest;
  final Money amortization;

  /// Correção monetária do saldo no mês (indexador).
  final Money correction;

  /// Encargos mensais (seguros, taxas).
  final Money fees;

  /// Saldo devedor depois do pagamento.
  final Money balance;

  const DebtRow({
    required this.number,
    required this.dueDate,
    required this.payment,
    required this.interest,
    required this.amortization,
    required this.correction,
    required this.fees,
    required this.balance,
  });

  /// Valor que sai do caixa no vencimento.
  Money get total => payment + fees;
}

/// Cronograma de pagamentos.
class DebtSchedule {
  final AmortizationSystem? system;
  final Money principal;
  final List<DebtRow> rows;

  /// Custos pagos na contratação (IOF, tarifa de cadastro, avaliação).
  final Money upfrontCharges;

  /// `false` quando os juros não puderam ser separados da parcela (dados
  /// do contrato incompletos; cronograma montado só com as parcelas).
  final bool interestKnown;

  const DebtSchedule({
    required this.system,
    required this.principal,
    required this.rows,
    this.upfrontCharges = Money.zero,
    this.interestKnown = true,
  });

  static const empty = DebtSchedule(
    system: null,
    principal: Money.zero,
    rows: [],
  );

  int get months => rows.length;
  bool get isEmpty => rows.isEmpty;
  Money get firstPayment => rows.isEmpty ? Money.zero : rows.first.total;
  Money get lastPayment => rows.isEmpty ? Money.zero : rows.last.total;
  DateTime? get lastDueDate => rows.isEmpty ? null : rows.last.dueDate;

  Money _sum(Money Function(DebtRow) f) =>
      rows.fold(Money.zero, (a, r) => a + f(r));
  Money get totalInterest => _sum((r) => r.interest);
  Money get totalAmortization => _sum((r) => r.amortization);
  Money get totalCorrection => _sum((r) => r.correction);
  Money get totalFees => _sum((r) => r.fees);

  /// Soma das parcelas (juros + amortização).
  Money get totalPayments => _sum((r) => r.payment);

  /// Tudo que sai do caixa nas parcelas (parcelas + encargos).
  Money get totalPaid => _sum((r) => r.total);

  /// Custo total: parcelas, encargos e custos da contratação.
  Money get totalCost => totalPaid + upfrontCharges;

  /// Confere o cronograma ao centavo: parcela = juros + amortização,
  /// saldo anterior + correção − amortização = saldo, saldo final zero e
  /// amortizações = principal + correções.
  bool get reconciles {
    if (!interestKnown) return true;
    var bal = principal;
    for (final r in rows) {
      if (r.payment != r.interest + r.amortization) return false;
      bal = bal + r.correction - r.amortization;
      if (bal != r.balance) return false;
    }
    return bal.isZero && totalAmortization == principal + totalCorrection;
  }
}

DateTime _due(DateTime first, int i) =>
    Dates.addMonths(first, i, anchorDay: first.day);

/// Monta o cronograma de [months] parcelas mensais a partir de [firstDue].
///
/// Price: parcela fixa (recalculada sobre o saldo corrigido quando há
/// indexador). SAC: amortização constante (saldo corrigido ÷ parcelas
/// restantes quando há indexador). [fixedPayment] (Price) ou
/// [fixedAmortization] (SAC) mantêm a parcela/amortização atual, usado ao
/// reduzir o prazo; o cronograma termina quando o saldo zera.
DebtSchedule buildSchedule({
  required Money principal,
  required double monthlyRate,
  required int months,
  required AmortizationSystem system,
  required DateTime firstDue,
  Money monthlyFees = Money.zero,
  double indexRate = 0,
  Money upfrontCharges = Money.zero,
  Money? fixedPayment,
  Money? fixedAmortization,
}) {
  if (months <= 0) throw ArgumentError('Informe um prazo maior que zero');
  if (monthlyRate < 0 || !monthlyRate.isFinite) {
    throw ArgumentError('Taxa inválida');
  }
  if (!principal.isPositive) throw ArgumentError('Informe o valor');
  final price = system == AmortizationSystem.price;
  final indexed = indexRate != 0;
  final pmt = price && !indexed
      ? (fixedPayment ?? pricePayment(principal, monthlyRate, months))
      : null;
  final sacParts = !price && !indexed && fixedAmortization == null
      ? principal.split(months)
      : null;
  final rows = <DebtRow>[];
  var balance = principal;
  for (var n = 1; n <= months && balance.isPositive; n++) {
    final correction = indexed ? _round(balance.cents * indexRate) : Money.zero;
    balance += correction;
    final interest = _round(balance.cents * monthlyRate);
    final remaining = months - n + 1;
    Money amort;
    if (price) {
      final p = pmt ?? pricePayment(balance, monthlyRate, remaining);
      amort = p - interest;
    } else if (fixedAmortization != null) {
      amort = fixedAmortization;
    } else if (sacParts != null) {
      amort = sacParts[n - 1];
    } else {
      amort = _round(balance.cents / remaining);
    }
    if (n == months || amort > balance) amort = balance;
    balance -= amort;
    rows.add(
      DebtRow(
        number: n,
        dueDate: _due(firstDue, n - 1),
        payment: amort + interest,
        interest: interest,
        amortization: amort,
        correction: correction,
        fees: monthlyFees,
        balance: balance,
      ),
    );
  }
  return DebtSchedule(
    system: system,
    principal: principal,
    rows: rows,
    upfrontCharges: upfrontCharges,
  );
}

/// Recalcula juros, amortização e saldo para uma sequência de parcelas já
/// definidas ([payments]), a partir de [principal]. A última parcela é
/// ajustada para zerar o saldo.
DebtSchedule scheduleFromPayments({
  required Money principal,
  required double monthlyRate,
  required List<Money> payments,
  required DateTime firstDue,
  AmortizationSystem? system,
  Money monthlyFees = Money.zero,
  double indexRate = 0,
}) {
  final rows = <DebtRow>[];
  var balance = principal;
  for (var k = 0; k < payments.length && balance.isPositive; k++) {
    final correction = indexRate != 0
        ? _round(balance.cents * indexRate)
        : Money.zero;
    balance += correction;
    final interest = _round(balance.cents * monthlyRate);
    var amort = payments[k] - interest;
    if (k == payments.length - 1 || amort > balance) amort = balance;
    balance -= amort;
    rows.add(
      DebtRow(
        number: k + 1,
        dueDate: _due(firstDue, k),
        payment: amort + interest,
        interest: interest,
        amortization: amort,
        correction: correction,
        fees: monthlyFees,
        balance: balance,
      ),
    );
  }
  return DebtSchedule(system: system, principal: principal, rows: rows);
}

/// Cronograma só com as parcelas (juros desconhecidos).
DebtSchedule flatSchedule({
  required Money payment,
  required int months,
  required DateTime firstDue,
  Money monthlyFees = Money.zero,
}) => DebtSchedule(
  system: null,
  principal: Money.zero,
  interestKnown: false,
  rows: [
    for (var n = 1; n <= months; n++)
      DebtRow(
        number: n,
        dueDate: _due(firstDue, n - 1),
        payment: payment,
        interest: Money.zero,
        amortization: Money.zero,
        correction: Money.zero,
        fees: monthlyFees,
        balance: Money.zero,
      ),
  ],
);

// -----------------------------------------------------------------------------
// Novo financiamento: Price × SAC

/// Custo efetivo total ao mês (TIR): recebe [released] no início e paga as
/// parcelas totais do cronograma.
double? effectiveMonthlyCost(Money released, DebtSchedule s) {
  if (!released.isPositive || s.isEmpty) return null;
  double npv(double r) {
    var v = released.cents.toDouble();
    for (final row in s.rows) {
      v -= row.total.cents / math.pow(1 + r, row.number);
    }
    return v;
  }

  var lo = 0.0, hi = 1.0;
  if (npv(lo) > 0) return 0; // custo menor que zero: sem juros
  for (var k = 0; k < 200; k++) {
    final mid = (lo + hi) / 2;
    if (npv(mid) < 0) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

class FinancingOption {
  final DebtSchedule schedule;

  /// CET ao mês e ao ano (estimativa a partir dos custos informados).
  final double? cetMonthly;
  const FinancingOption(this.schedule, this.cetMonthly);
  double? get cetAnnual =>
      cetMonthly == null ? null : annualFromMonthly(cetMonthly!);
}

class FinancingComparison {
  final FinancingOption price;
  final FinancingOption sac;
  final DateTime calculatedAt;
  final List<String> assumptions;
  const FinancingComparison(
    this.price,
    this.sac,
    this.calculatedAt,
    this.assumptions,
  );

  /// Juros a menos no SAC.
  Money get sacInterestSavings =>
      price.schedule.totalInterest - sac.schedule.totalInterest;
}

/// Mesmo principal, taxa, prazo e início nos dois sistemas.
FinancingComparison compareFinancing({
  required Money principal,
  required double monthlyRate,
  required int months,
  required DateTime firstDue,
  Money monthlyFees = Money.zero,
  Money upfrontCharges = Money.zero,
  double indexRate = 0,
  DebtIndex index = DebtIndex.none,
  DateTime? calculatedAt,
}) {
  FinancingOption build(AmortizationSystem s) {
    final sch = buildSchedule(
      principal: principal,
      monthlyRate: monthlyRate,
      months: months,
      system: s,
      firstDue: firstDue,
      monthlyFees: monthlyFees,
      indexRate: indexRate,
      upfrontCharges: upfrontCharges,
    );
    return FinancingOption(
      sch,
      effectiveMonthlyCost(principal - upfrontCharges, sch),
    );
  }

  return FinancingComparison(
    build(AmortizationSystem.price),
    build(AmortizationSystem.sac),
    calculatedAt ?? DateTime.now(),
    [
      ..._baseAssumptions(monthlyRate, index, indexRate, monthlyFees),
      if (upfrontCharges.isPositive)
        'Custos na contratação de ${upfrontCharges.formatVisible()} pagos à '
            'vista (entram no custo total e no CET).',
      'Primeira parcela em ${Dates.format(firstDue)}.',
    ],
  );
}

List<String> _baseAssumptions(
  double rate,
  DebtIndex index,
  double indexRate,
  Money fees,
) => [
  'Juros de ${pct(rate)} ao mês (${pct(annualFromMonthly(rate))} ao ano), '
      'juros compostos.',
  if (index != DebtIndex.none || indexRate != 0)
    'Saldo corrigido por ${index.label} estimado em ${pct(indexRate)} ao mês '
        '(estimativa; o índice real varia).',
  if (fees.isPositive)
    'Encargos mensais (seguros e taxas) de ${fees.formatVisible()} '
        'enquanto houver parcelas.',
];

/// "1,25%"
String pct(double fraction, {int digits = 2}) =>
    '${(fraction * 100).toStringAsFixed(digits).replaceAll('.', ',')}%';

// -----------------------------------------------------------------------------
// Contratos existentes

enum EstimateSource {
  app('Estimativa do app'),
  lender('Cotação do credor');

  final String label;
  const EstimateSource(this.label);
}

/// Próxima parcela do contrato (ou um mês depois do saldo/hoje).
DateTime nextDueOf(DebtContract d, DateTime asOf) =>
    d.nextDueDate ?? Dates.addMonths(d.balanceDate ?? asOf, 1);

/// Campos que faltam para a estimativa do app.
List<DebtField> missingForEstimate(DebtContract d) => [
  if (d.outstanding == null || !d.outstanding!.isPositive)
    DebtField.outstanding,
  if (d.monthlyRate == null) DebtField.rate,
  if (d.remainingMonths == null || d.remainingMonths! <= 0)
    DebtField.remainingMonths,
  if (d.system == null) DebtField.system,
];

/// Campos que faltam para usar uma cotação do credor sem a estimativa.
List<DebtField> missingForQuote(DebtContract d) => [
  if (d.currentPayment == null || !d.currentPayment!.isPositive)
    DebtField.payment,
  if (d.remainingMonths == null || d.remainingMonths! <= 0)
    DebtField.remainingMonths,
];

/// Cronograma restante do contrato como está hoje, ou `null` se faltam
/// dados ([missingForEstimate]).
DebtSchedule? currentSchedule(DebtContract d, DateTime asOf) {
  if (missingForEstimate(d).isNotEmpty) return null;
  return buildSchedule(
    principal: d.outstanding!,
    monthlyRate: d.monthlyRate!,
    months: d.remainingMonths!,
    system: d.system!,
    firstDue: nextDueOf(d, asOf),
    monthlyFees: d.monthlyFees,
    indexRate: d.indexMonthlyRate,
  );
}

/// Cronograma restante: estimado quando há dados, senão só as parcelas
/// informadas (sem separar juros), senão `null`.
DebtSchedule? remainingSchedule(DebtContract d, DateTime asOf) =>
    currentSchedule(d, asOf) ??
    (missingForQuote(d).isEmpty
        ? flatSchedule(
            payment: d.currentPayment!,
            months: d.remainingMonths!,
            firstDue: nextDueOf(d, asOf),
            monthlyFees: d.monthlyFees,
          )
        : null);

/// Resultado de uma opção de antecipação/quitação.
class PrepayResult {
  final DebtContract debt;
  final PrepayOption option;
  final DateTime calculatedAt;
  final EstimateSource source;
  final LenderQuote? quote;

  /// Redução do saldo devedor (estimativa) e tarifa de antecipação.
  final Money principalReduction;
  final Money fee;

  /// Dinheiro que sai do caixa agora.
  final Money outflow;

  /// Parcelas antes e depois (restantes, a partir da próxima).
  final DebtSchedule before;
  final DebtSchedule after;

  /// Parcelas antecipadas (opção últimas parcelas).
  final int installmentsCovered;
  final List<String> assumptions;
  final List<String> warnings;

  const PrepayResult({
    required this.debt,
    required this.option,
    required this.calculatedAt,
    required this.source,
    this.quote,
    required this.principalReduction,
    required this.fee,
    required this.outflow,
    required this.before,
    required this.after,
    this.installmentsCovered = 0,
    this.assumptions = const [],
    this.warnings = const [],
  });

  bool get isLenderQuote => source == EstimateSource.lender;

  Money get totalBefore => before.totalPaid;
  Money get totalAfter => after.totalPaid;

  /// Economia estimada: o que deixaria de pagar menos o que sai agora.
  Money get totalSaved => totalBefore - totalAfter - outflow;

  /// Juros a menos (quando os juros são conhecidos).
  Money? get interestSaved => before.interestKnown && after.interestKnown
      ? before.totalInterest - after.totalInterest
      : null;

  Money get paymentBefore => before.firstPayment;
  Money get paymentAfter => after.firstPayment;

  /// Quanto a parcela mensal diminui (próxima parcela).
  Money get monthlyRelief => paymentBefore - paymentAfter;
  int get monthsBefore => before.months;
  int get monthsAfter => after.months;
  DateTime? get endBefore => before.lastDueDate;
  DateTime? get endAfter => after.lastDueDate;

  /// Efeito no caixa por mês: −saída no mês do cálculo; + parcelas que
  /// deixam de sair (ou − que aumentam) em cada vencimento.
  Map<YearMonth, Money> cashDelta() {
    final out = <YearMonth, Money>{};
    void add(DateTime d, Money v) {
      final m = YearMonth.of(d);
      out[m] = (out[m] ?? Money.zero) + v;
    }

    add(calculatedAt, -outflow);
    for (final r in before.rows) {
      add(r.dueDate, r.total);
    }
    for (final r in after.rows) {
      add(r.dueDate, -r.total);
    }
    out.removeWhere((_, v) => v.isZero);
    return out;
  }

  /// Resumo em JSON (para cenários salvos).
  Map<String, Object?> toSummary() => {
    'debtId': debt.id,
    'debtName': debt.name,
    'option': option.name,
    'source': source.name,
    'outflow': outflow.cents,
    'fee': fee.cents,
    'totalSaved': totalSaved.cents,
    'interestSaved': interestSaved?.cents,
    'paymentBefore': paymentBefore.cents,
    'paymentAfter': paymentAfter.cents,
    'monthlyRelief': monthlyRelief.cents,
    'monthsBefore': monthsBefore,
    'monthsAfter': monthsAfter,
    'installmentsCovered': installmentsCovered,
    'assumptions': assumptions,
  };
}

/// Resposta para uma opção: o resultado, ou o que falta/impede.
class DebtEstimate {
  final DebtContract debt;
  final PrepayOption option;
  final Money requested;
  final PrepayResult? result;

  /// Campos necessários para estimar (vazio quando há resultado).
  final List<DebtField> missing;

  /// Motivo de não haver resultado além de dados faltando (contrato não
  /// permite, valor insuficiente).
  final String? blocked;

  const DebtEstimate({
    required this.debt,
    required this.option,
    required this.requested,
    this.result,
    this.missing = const [],
    this.blocked,
  });

  bool get ok => result != null;
}

/// Estima uma opção de antecipação ou quitação do contrato [d].
///
/// [amount] é o dinheiro disponível para a opção (ignorado em
/// [PrepayOption.payoff], que usa o saldo). Em
/// [PrepayOption.lastInstallments], [installments] fixa quantas parcelas
/// antecipar; sem ele, antecipa o máximo que cabe em [amount].
/// Uma cotação do credor válida para a opção prevalece sobre a estimativa.
DebtEstimate estimatePrepayment(
  DebtContract d,
  PrepayOption option, {
  Money amount = Money.zero,
  int? installments,
  required DateTime asOf,
  bool useQuote = true,
}) {
  DebtEstimate fail({List<DebtField> missing = const [], String? blocked}) =>
      DebtEstimate(
        debt: d,
        option: option,
        requested: amount,
        missing: missing,
        blocked: blocked,
      );

  if (d.supportOf(option) == OptionSupport.notAllowed) {
    return fail(blocked: 'O contrato não permite esta opção.');
  }
  final quote = useQuote ? d.quoteFor(option, asOf) : null;
  final full = currentSchedule(d, asOf);
  final assumptions = <String>[
    if (full != null) ...[
      ..._baseAssumptions(
        d.monthlyRate!,
        d.index,
        d.indexMonthlyRate,
        d.monthlyFees,
      ),
      'Saldo devedor de ${d.outstanding!.formatVisible()}'
          '${d.balanceDate == null ? '' : ' em ${Dates.format(d.balanceDate!)}'}'
          ', considerado logo após a última parcela paga (sem juros pró-rata).',
    ],
    'Pagamento na data do cálculo (${Dates.format(asOf)}), antes da próxima '
        'parcela.',
    if (d.supportOf(option) == OptionSupport.unknown)
      'Confira no contrato se esta opção é permitida.',
  ];
  final warnings = <String>[
    if (full != null &&
        d.currentPayment != null &&
        d.index == DebtIndex.none &&
        (full.rows.first.payment - d.currentPayment!).abs().cents >
            math.max(100, d.currentPayment!.cents ~/ 100))
      'A parcela calculada (${full.rows.first.payment.formatVisible()}) difere '
          'da informada (${d.currentPayment!.formatVisible()}). Confira saldo, '
          'taxa e parcelas restantes, ou use a cotação do credor.',
  ];

  PrepayResult result({
    required EstimateSource source,
    required Money reduction,
    required Money fee,
    required Money outflow,
    required DebtSchedule before,
    required DebtSchedule after,
    int covered = 0,
  }) => PrepayResult(
    debt: d,
    option: option,
    calculatedAt: asOf,
    source: source,
    quote: source == EstimateSource.lender ? quote : null,
    principalReduction: reduction,
    fee: fee,
    outflow: outflow,
    before: before,
    after: after,
    installmentsCovered: covered,
    assumptions: [
      if (source == EstimateSource.lender)
        'Valor da cotação do credor de ${Dates.format(quote!.date)}'
            '${quote.validUntil == null ? '' : ', válida até ${Dates.format(quote.validUntil!)}'}.',
      ...assumptions,
    ],
    warnings: warnings,
  );

  // Cotação do credor ---------------------------------------------------------
  if (quote != null) {
    final before = full ?? remainingSchedule(d, asOf);
    if (before == null) return fail(missing: missingForQuote(d));
    final first = before.rows.first.dueDate;
    DebtSchedule after;
    var covered = 0;
    switch (option) {
      case PrepayOption.payoff:
        after = DebtSchedule.empty;
      case PrepayOption.lastInstallments:
        covered = quote.installments ?? 0;
        if (covered <= 0 || covered > before.months) {
          return fail(
            blocked: 'Informe na cotação quantas parcelas ela cobre.',
          );
        }
        after = _keepFirst(d, before, before.months - covered, quote.amount);
      case PrepayOption.reduceTerm || PrepayOption.reducePayment:
        final months = quote.newMonths ?? before.months;
        final payment =
            quote.newPayment ??
            before.rows.first.payment; // mesma parcela, prazo menor
        after = flatSchedule(
          payment: payment,
          months: months,
          firstDue: first,
          monthlyFees: d.monthlyFees,
        );
    }
    return DebtEstimate(
      debt: d,
      option: option,
      requested: amount,
      result: result(
        source: EstimateSource.lender,
        reduction: quote.amount,
        fee: Money.zero,
        outflow: quote.amount,
        before: before,
        after: after,
        covered: covered,
      ),
    );
  }

  // Estimativa do app ---------------------------------------------------------
  if (full == null) return fail(missing: missingForEstimate(d));
  final balance = d.outstanding!;
  final rate = d.monthlyRate!;
  final first = full.rows.first.dueDate;
  Money feeOf(Money v) => _round(v.cents * d.prepaymentFeeRate);

  switch (option) {
    case PrepayOption.payoff:
      final fee = feeOf(balance);
      return DebtEstimate(
        debt: d,
        option: option,
        requested: amount,
        result: result(
          source: EstimateSource.app,
          reduction: balance,
          fee: fee,
          outflow: balance + fee,
          before: full,
          after: DebtSchedule.empty,
        ),
      );

    case PrepayOption.lastInstallments:
      // Valor presente das últimas k parcelas à taxa do contrato.
      Money pvOf(int k) {
        var v = 0.0;
        for (final r in full.rows.sublist(full.months - k)) {
          v +=
              r.payment.cents /
              math.pow((1 + rate) * (1 + d.indexMonthlyRate), r.number);
        }
        return _round(v);
      }

      var k = installments ?? 0;
      if (k == 0) {
        while (k < full.months - 1 &&
            pvOf(k + 1) + feeOf(pvOf(k + 1)) <= amount) {
          k++;
        }
        if (k == 0) {
          return fail(
            blocked:
                'O valor não cobre nem a última parcela '
                '(${(pvOf(1) + feeOf(pvOf(1))).formatVisible()}).',
          );
        }
      }
      if (k >= full.months) {
        return fail(blocked: 'Para antecipar todas as parcelas, use Quitar.');
      }
      final pv = pvOf(k);
      return DebtEstimate(
        debt: d,
        option: option,
        requested: amount,
        result: result(
          source: EstimateSource.app,
          reduction: pv,
          fee: feeOf(pv),
          outflow: pv + feeOf(pv),
          before: full,
          after: _keepFirst(d, full, full.months - k, pv),
          covered: k,
        ),
      );

    case PrepayOption.reduceTerm || PrepayOption.reducePayment:
      // O valor disponível paga a amortização e a tarifa.
      final reduction = _round(amount.cents / (1 + d.prepaymentFeeRate));
      if (!reduction.isPositive) {
        return fail(blocked: 'Informe o valor para amortizar.');
      }
      if (reduction >= balance) {
        return fail(
          blocked:
              'O valor cobre o saldo devedor (${balance.formatVisible()}): '
              'use Quitar o contrato.',
        );
      }
      final rest = balance - reduction;
      final DebtSchedule after;
      if (option == PrepayOption.reducePayment) {
        after = buildSchedule(
          principal: rest,
          monthlyRate: rate,
          months: full.months,
          system: d.system!,
          firstDue: first,
          monthlyFees: d.monthlyFees,
          indexRate: d.indexMonthlyRate,
        );
      } else {
        final r = (1 + rate) * (1 + d.indexMonthlyRate) - 1;
        final row1 = full.rows.first;
        int months;
        if (d.system == AmortizationSystem.price) {
          final p = row1.payment.cents.toDouble();
          months = r == 0
              ? (rest.cents / p).ceil()
              : (-math.log(1 - rest.cents * r / p) / math.log(1 + r)).ceil();
        } else {
          months = (rest.cents / row1.amortization.cents).ceil();
        }
        months = months.clamp(1, full.months);
        after = buildSchedule(
          principal: rest,
          monthlyRate: rate,
          months: months,
          system: d.system!,
          firstDue: first,
          monthlyFees: d.monthlyFees,
          indexRate: d.indexMonthlyRate,
          fixedPayment: d.system == AmortizationSystem.price
              ? row1.payment
              : null,
          fixedAmortization: d.system == AmortizationSystem.sac
              ? row1.amortization
              : null,
        );
      }
      final fee = amount - reduction;
      return DebtEstimate(
        debt: d,
        option: option,
        requested: amount,
        result: result(
          source: EstimateSource.app,
          reduction: reduction,
          fee: fee,
          outflow: reduction + fee,
          before: full,
          after: after,
        ),
      );
  }
}

/// Mantém as primeiras [keep] parcelas de [s] (mesmos valores) e recalcula
/// os saldos depois de antecipar [paid] (valor presente das demais).
DebtSchedule _keepFirst(DebtContract d, DebtSchedule s, int keep, Money paid) {
  final kept = s.rows.take(keep).toList();
  if (!s.interestKnown || d.monthlyRate == null) {
    return DebtSchedule(
      system: s.system,
      principal: Money.zero,
      interestKnown: false,
      rows: kept,
    );
  }
  return scheduleFromPayments(
    principal: s.principal - paid,
    monthlyRate: d.monthlyRate!,
    payments: [for (final r in kept) r.payment],
    firstDue: s.rows.first.dueDate,
    system: s.system,
    monthlyFees: d.monthlyFees,
    indexRate: d.indexMonthlyRate,
  );
}

// -----------------------------------------------------------------------------
// Comparar dívidas

enum DebtSort {
  totalSaved('Maior economia total'),
  monthlyRelief('Maior redução da parcela');

  final String label;
  const DebtSort(this.label);
}

/// Aplica o mesmo valor [cash] a cada dívida, em cada opção. Opções que o
/// contrato não permite, sem dados ou que o valor não cobre voltam como
/// [DebtEstimate] sem resultado (com o motivo). A quitação só é calculada
/// quando [cash] cobre o saldo.
List<DebtEstimate> compareDebts(
  List<DebtContract> debts,
  Money cash, {
  required DateTime asOf,
  Set<PrepayOption> options = const {
    PrepayOption.reduceTerm,
    PrepayOption.reducePayment,
    PrepayOption.lastInstallments,
    PrepayOption.payoff,
  },
}) {
  final out = <DebtEstimate>[];
  for (final d in debts.where((d) => !d.archived)) {
    for (final o in PrepayOption.values.where(options.contains)) {
      var e = estimatePrepayment(d, o, amount: cash, asOf: asOf);
      if (o == PrepayOption.payoff && e.ok && e.result!.outflow > cash) {
        e = DebtEstimate(
          debt: d,
          option: o,
          requested: cash,
          blocked:
              'O valor disponível não cobre a quitação '
              '(${e.result!.outflow.formatVisible()}).',
        );
      }
      if ((o == PrepayOption.reduceTerm || o == PrepayOption.reducePayment) &&
          !e.ok &&
          e.blocked != null &&
          e.blocked!.contains('Quitar')) {
        // O valor quita a dívida: a quitação já aparece como opção.
        continue;
      }
      out.add(e);
    }
  }
  return out;
}

/// Ordena as opções com resultado (sem resultado vão para o fim).
List<DebtEstimate> sortEstimates(List<DebtEstimate> list, DebtSort by) {
  int key(DebtEstimate e) => switch (by) {
    DebtSort.totalSaved => e.result!.totalSaved.cents,
    DebtSort.monthlyRelief => e.result!.monthlyRelief.cents,
  };
  final ok = list.where((e) => e.ok).toList()
    ..sort((a, b) {
      final c = key(b).compareTo(key(a));
      if (c != 0) return c;
      // Desempate: a outra métrica.
      return by == DebtSort.totalSaved
          ? b.result!.monthlyRelief.compareTo(a.result!.monthlyRelief)
          : b.result!.totalSaved.compareTo(a.result!.totalSaved);
    });
  return [...ok, ...list.where((e) => !e.ok)];
}

// -----------------------------------------------------------------------------
// Efeito no caixa projetado

class CashPoint {
  final YearMonth month;
  final Money before;
  final Money after;
  const CashPoint(this.month, this.before, this.after);
  Money get delta => after - before;
}

class CashImpact {
  final List<CashPoint> points;
  final Money reserve;
  const CashImpact(this.points, this.reserve);

  Money get minBefore => points.isEmpty
      ? Money.zero
      : points.map((p) => p.before).reduce((a, b) => a < b ? a : b);
  Money get minAfter => points.isEmpty
      ? Money.zero
      : points.map((p) => p.after).reduce((a, b) => a < b ? a : b);

  /// Primeiro mês abaixo da reserva mínima (depois da opção).
  YearMonth? get firstBelowReserve =>
      points.where((p) => p.after < reserve).firstOrNull?.month;
  YearMonth? get firstBelowReserveBefore =>
      points.where((p) => p.before < reserve).firstOrNull?.month;

  /// A opção faz o caixa ficar abaixo da reserva em algum mês.
  bool get breaksReserve => minAfter < reserve;

  Money get endBefore => points.isEmpty ? Money.zero : points.last.before;
  Money get endAfter => points.isEmpty ? Money.zero : points.last.after;
}

/// Saldo acumulado projetado antes e depois de aplicar [delta] (por mês),
/// nas colunas atuais e futuras da Projeção. O que cair antes da primeira
/// coluna entra nela.
CashImpact cashImpact(
  List<ProjectionColumn> columns,
  Map<YearMonth, Money> delta, {
  Money reserve = Money.zero,
}) {
  final cols = columns.where((c) => !c.isPast).toList();
  if (cols.isEmpty) return CashImpact(const [], reserve);
  var cum = Money.zero;
  for (final e in delta.entries) {
    if (e.key < cols.first.month) cum += e.value;
  }
  final points = <CashPoint>[];
  for (final c in cols) {
    cum += delta[c.month] ?? Money.zero;
    points.add(CashPoint(c.month, c.accumulated, c.accumulated + cum));
  }
  return CashImpact(points, reserve);
}
