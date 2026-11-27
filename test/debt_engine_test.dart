import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/calculators.dart' show loan;
import 'package:financas_app/domain/engine/debt_engine.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/models/debt.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

// Dados fictícios.
final asOf = DateTime(2026, 11, 27);
final firstDue = DateTime(2026, 12, 10);

DebtContract carro() => DebtContract(
  id: 'd-carro',
  name: 'Financiamento do carro',
  lender: 'Banco Exemplo',
  kind: DebtKind.vehicle,
  system: AmortizationSystem.price,
  monthlyRate: 0.0189,
  outstanding: const Money(4200000), // 42.000,00
  remainingMonths: 30,
  nextDueDate: firstDue,
  reduceTerm: OptionSupport.allowed,
  reducePayment: OptionSupport.allowed,
  payoff: OptionSupport.allowed,
);

DebtContract casa() => DebtContract(
  id: 'd-casa',
  name: 'Financiamento do apartamento',
  lender: 'Caixa Fictícia',
  kind: DebtKind.realEstate,
  system: AmortizationSystem.sac,
  monthlyRate: 0.0085,
  outstanding: const Money(18000000), // 180.000,00
  remainingMonths: 240,
  nextDueDate: firstDue,
  fees: const [DebtFee('Seguro MIP/DFI', Money(4500))],
);

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('Critério 2: Price e SAC com os mesmos termos', () {
    late final FinancingComparison c;
    setUpAll(
      () => c = compareFinancing(
        principal: const Money(10000000), // 100.000,00
        monthlyRate: 0.01,
        months: 12,
        firstDue: DateTime(2027, 1, 5),
        calculatedAt: asOf,
      ),
    );

    test('cronogramas separados que fecham ao centavo', () {
      for (final s in [c.price.schedule, c.sac.schedule]) {
        expect(s.months, 12);
        expect(s.reconciles, isTrue, reason: '${s.system}');
        expect(s.totalAmortization, const Money(10000000));
        expect(s.rows.last.balance, Money.zero);
        expect(s.totalPayments, s.totalInterest + s.totalAmortization);
        for (final r in s.rows) {
          expect(r.payment, r.interest + r.amortization);
        }
      }
    });

    test('Price: parcela fixa de 8.884,88', () {
      final s = c.price.schedule;
      expect(s.rows.first.payment, const Money(888488));
      expect(s.rows.first.interest, const Money(100000));
      expect(s.rows.first.amortization, const Money(788488));
      for (final r in s.rows.take(11)) {
        expect(r.payment, const Money(888488));
      }
      // Mesmo resultado da calculadora existente.
      final old = loan(
        principal: const Money(10000000),
        rate: 0.01,
        months: 12,
      );
      expect(s.totalInterest, old.totalInterest);
      expect(s.lastPayment, old.lastPayment);
    });

    test('SAC: amortização constante, juros 6.500,00', () {
      final s = c.sac.schedule;
      for (final r in s.rows) {
        expect(
          r.amortization,
          const Money(833334) - Money(r.number > 4 ? 1 : 0),
        );
      }
      expect(s.firstPayment, const Money(933334)); // 8.333,34 + 1.000,00
      expect(s.totalInterest, const Money(650000));
      expect(
        c.sacInterestSavings,
        c.price.schedule.totalInterest - const Money(650000),
      );
      expect(c.sacInterestSavings.isPositive, isTrue);
    });

    test('datas mensais a partir do início e resumo', () {
      final s = c.price.schedule;
      expect(s.rows[0].dueDate, DateTime(2027, 1, 5));
      expect(s.rows[11].dueDate, DateTime(2027, 12, 5));
      expect(s.totalCost, s.totalPaid);
      expect(c.price.cetMonthly, closeTo(0.01, 1e-6));
    });

    test('encargos e custos de contratação entram no custo total e no CET', () {
      final f = compareFinancing(
        principal: const Money(10000000),
        monthlyRate: 0.01,
        months: 12,
        firstDue: DateTime(2027, 1, 5),
        monthlyFees: const Money(2500),
        upfrontCharges: const Money(150000),
      );
      final s = f.price.schedule;
      expect(s.reconciles, isTrue);
      expect(s.firstPayment, const Money(888488 + 2500));
      expect(s.totalFees, const Money(30000));
      expect(s.totalCost, s.totalPayments + const Money(30000 + 150000));
      expect(f.price.cetMonthly!, greaterThan(0.01));
      expect(f.assumptions.join(' '), contains('Custos na contratação'));
    });

    test('indexador corrige o saldo e o cronograma continua fechando', () {
      final s = buildSchedule(
        principal: const Money(10000000),
        monthlyRate: 0.008,
        months: 120,
        system: AmortizationSystem.sac,
        firstDue: firstDue,
        indexRate: 0.001,
      );
      expect(s.reconciles, isTrue);
      expect(s.totalCorrection.isPositive, isTrue);
      expect(s.totalAmortization, const Money(10000000) + s.totalCorrection);
    });
  });

  group('Contratos existentes', () {
    test('cronograma restante a partir do saldo atual', () {
      final s = currentSchedule(carro(), asOf)!;
      expect(s.months, 30);
      expect(s.rows.first.dueDate, firstDue);
      expect(s.reconciles, isTrue);
    });

    test('reduzir o prazo mantém a parcela; economia = juros a menos', () {
      final e = estimatePrepayment(
        carro(),
        PrepayOption.reduceTerm,
        amount: const Money(1000000),
        asOf: asOf,
      );
      final r = e.result!;
      expect(r.source, EstimateSource.app);
      expect(r.outflow, const Money(1000000));
      expect(r.after.reconciles, isTrue);
      expect(r.monthsAfter, lessThan(r.monthsBefore));
      expect(r.after.rows.first.payment, r.before.rows.first.payment);
      expect(r.totalSaved, r.interestSaved);
      expect(r.totalSaved.isPositive, isTrue);
    });

    test('reduzir a parcela mantém o prazo', () {
      final r = estimatePrepayment(
        carro(),
        PrepayOption.reducePayment,
        amount: const Money(1000000),
        asOf: asOf,
      ).result!;
      expect(r.monthsAfter, r.monthsBefore);
      expect(r.monthlyRelief.isPositive, isTrue);
      expect(r.after.reconciles, isTrue);
      expect(r.totalSaved, r.interestSaved);
    });

    test('antecipar as últimas parcelas pelo valor presente', () {
      final d = carro().copyWith(lastInstallments: OptionSupport.allowed);
      final r = estimatePrepayment(
        d,
        PrepayOption.lastInstallments,
        installments: 5,
        asOf: asOf,
      ).result!;
      expect(r.installmentsCovered, 5);
      expect(r.monthsAfter, 25);
      // As parcelas que ficam não mudam (só centavos na última).
      final pmt = r.before.rows.first.payment;
      for (final x in r.after.rows.take(24)) {
        expect(x.payment, pmt);
      }
      expect((r.after.rows.last.payment - pmt).cents.abs(), lessThan(50));
      expect(r.outflow < pmt * 5, isTrue); // desconto dos juros
      expect(r.totalSaved.isPositive, isTrue);
      expect(r.after.reconciles, isTrue);
    });

    test('quitação: sai o saldo, economiza todos os juros', () {
      final r = estimatePrepayment(
        carro(),
        PrepayOption.payoff,
        asOf: asOf,
      ).result!;
      expect(r.outflow, const Money(4200000));
      expect(r.after.isEmpty, isTrue);
      expect(r.totalSaved, r.before.totalInterest);
      expect(r.monthlyRelief, r.before.firstPayment);
    });

    test('tarifa de antecipação sai do valor disponível', () {
      final d = carro().copyWith(prepaymentFeeRate: 0.02);
      final r = estimatePrepayment(
        d,
        PrepayOption.reduceTerm,
        amount: const Money(1020000),
        asOf: asOf,
      ).result!;
      expect(r.principalReduction, const Money(1000000));
      expect(r.fee, const Money(20000));
      expect(r.outflow, const Money(1020000));
    });

    test('contrato que não permite a opção', () {
      final d = carro().copyWith(reducePayment: OptionSupport.notAllowed);
      final e = estimatePrepayment(
        d,
        PrepayOption.reducePayment,
        amount: const Money(100000),
        asOf: asOf,
      );
      expect(e.ok, isFalse);
      expect(e.blocked, contains('não permite'));
    });

    test('efeito no caixa: saída agora, parcelas a menos depois', () {
      final r = estimatePrepayment(
        carro(),
        PrepayOption.reducePayment,
        amount: const Money(1000000),
        asOf: asOf,
      ).result!;
      final delta = r.cashDelta();
      expect(delta[YearMonth(2026, 11)], const Money(-1000000));
      expect(delta[YearMonth(2026, 12)], r.monthlyRelief);
      final sum = delta.values.fold(Money.zero, (a, b) => a + b);
      expect(sum, r.totalSaved);
    });
  });

  group('Critério 3: duas dívidas, mesmo valor', () {
    const cash = Money(1500000); // 15.000,00

    test('compara economia total, alívio mensal e ordena', () {
      final list = compareDebts([carro(), casa()], cash, asOf: asOf);
      final ok = list.where((e) => e.ok).toList();
      expect(ok.map((e) => e.debt.id).toSet(), {'d-carro', 'd-casa'});
      for (final e in ok) {
        expect(e.result!.outflow <= cash, isTrue);
      }
      final bySaved = sortEstimates(list, DebtSort.totalSaved);
      final byRelief = sortEstimates(list, DebtSort.monthlyRelief);
      for (var i = 1; i < ok.length; i++) {
        expect(
          bySaved[i - 1].result!.totalSaved >= bySaved[i].result!.totalSaved,
          isTrue,
        );
        expect(
          byRelief[i - 1].result!.monthlyRelief >=
              byRelief[i].result!.monthlyRelief,
          isTrue,
        );
      }
      // Quitação não cabe em 15.000 nas duas dívidas.
      final payoff = list.where((e) => e.option == PrepayOption.payoff);
      expect(payoff.every((e) => !e.ok && e.blocked != null), isTrue);
      // A dívida longa (apartamento, 240 parcelas) economiza mais juros ao
      // reduzir o prazo, mesmo com taxa menor; o carro alivia mais a parcela.
      Money saved(String id) => list
          .firstWhere(
            (e) => e.debt.id == id && e.option == PrepayOption.reduceTerm,
          )
          .result!
          .totalSaved;
      expect(saved('d-casa') > saved('d-carro'), isTrue);
    });

    test('caixa projetado antes e depois e reserva mínima', () {
      final r = estimatePrepayment(
        carro(),
        PrepayOption.reducePayment,
        amount: cash,
        asOf: asOf,
      ).result!;
      final cols = [
        for (var i = 0; i < 6; i++)
          ProjectionColumn(
            month: YearMonth(2026, 11).add(i),
            income: Money.zero,
            expenses: Money.zero,
            transfersNet: Money.zero,
            opening: Money.zero,
            accumulated: const Money(2000000),
            isPast: false,
            isCurrent: i == 0,
          ),
      ];
      final impact = cashImpact(
        cols,
        r.cashDelta(),
        reserve: const Money(1000000),
      );
      expect(impact.points.first.after, const Money(500000));
      expect(impact.breaksReserve, isTrue);
      expect(impact.firstBelowReserve, YearMonth(2026, 11));
      expect(impact.points[1].after, const Money(500000) + r.monthlyRelief);
    });

    test('dados faltando são apontados antes de estimar', () {
      final semTaxa = carro().copyWith(monthlyRate: null, system: null);
      final list = compareDebts([semTaxa, casa()], cash, asOf: asOf);
      final e = list.firstWhere(
        (e) => e.debt.id == 'd-carro' && e.option == PrepayOption.reduceTerm,
      );
      expect(e.ok, isFalse);
      expect(e.missing, containsAll([DebtField.rate, DebtField.system]));
    });

    test('cotação do credor supre a taxa que falta e é identificada', () {
      final d = carro().copyWith(
        monthlyRate: null,
        currentPayment: const Money(190000),
        quotes: [
          LenderQuote(
            id: 'q1',
            kind: QuoteKind.payoff,
            date: asOf,
            amount: const Money(4150000),
            validUntil: DateTime(2026, 12, 5),
          ),
        ],
      );
      final e = estimatePrepayment(d, PrepayOption.payoff, asOf: asOf);
      expect(e.ok, isTrue);
      expect(e.result!.isLenderQuote, isTrue);
      expect(e.result!.outflow, const Money(4150000));
      expect(e.result!.totalSaved, const Money(190000 * 30 - 4150000));
      expect(e.result!.interestSaved, isNull);
      // Vencida, a cotação não vale mais e volta a faltar a taxa.
      final later = estimatePrepayment(
        d,
        PrepayOption.payoff,
        asOf: DateTime(2026, 12, 6),
      );
      expect(later.ok, isFalse);
      expect(later.missing, contains(DebtField.rate));
    });
  });

  test('JSON do contrato e do cenário ida e volta', () {
    final d = casa().copyWith(
      quotes: [
        LenderQuote(
          id: 'q',
          kind: QuoteKind.prepayment,
          date: asOf,
          amount: const Money(100),
          newPayment: const Money(50),
        ),
      ],
      linkedTxIds: ['t1'],
      installments: DebtInstallments.generated,
    );
    final back = DebtContract.fromJson(d.toJson());
    expect(back.toJson(), d.toJson());
    final s = DebtScenario(
      id: 's',
      name: 'Teste',
      kind: ScenarioKind.comparison,
      calculatedAt: asOf,
      inputs: {'cash': 100},
      summary: [
        {'debtId': 'd', 'totalSaved': 10},
      ],
    );
    expect(DebtScenario.fromJson(s.toJson()).toJson(), s.toJson());
    const st = AppSettings(minimumReserve: Money(123));
    expect(AppSettings.fromJson(st.toJson()).minimumReserve, const Money(123));
  });
}
