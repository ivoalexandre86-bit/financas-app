import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/debt_engine.dart';
import 'package:financas_app/domain/engine/debt_sync.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/engine/projection_filter.dart';
import 'package:financas_app/domain/models/debt.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'controller_test.dart' show MemoryRepo;

// Contratos fictícios, datas relativas a hoje.
Future<FinanceController> _setup() async {
  final fc = FinanceController(MemoryRepo());
  await fc.load();
  await fc.saveAccount(Account(id: 'a', name: 'Conta corrente'));
  return fc;
}

DebtContract _loan(
  DateTime today, {
  DebtInstallments mode = DebtInstallments.generated,
}) => DebtContract(
  id: 'emp',
  name: 'Empréstimo pessoal',
  lender: 'Banco Exemplo',
  system: AmortizationSystem.price,
  monthlyRate: 0.02,
  outstanding: const Money(1000000),
  remainingMonths: 12,
  nextDueDate: DateTime(today.year, today.month + 1, 10),
  accountId: 'a',
  installments: mode,
);

List<FinTransaction> _gen(FinanceController fc) => fc.data.transactions
    .where((t) => DebtSync.isDerived(t.id) && !t.id.contains('_pre_'))
    .toList();

Money _expenses(FinanceController fc, YearMonth m) =>
    fc.engine.monthTotals(ProjectionFilter.none, m).expenses;

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('parcelas geradas entram na Projeção uma vez; salvar de novo não '
      'duplica', () async {
    final fc = await _setup();
    final d = _loan(fc.today);
    await fc.saveDebt(d);
    expect(_gen(fc), hasLength(12));
    final pmt = currentSchedule(d, fc.today)!.rows.first.total;
    final next = YearMonth.of(d.nextDueDate!);
    expect(_expenses(fc, next), pmt);
    await fc.saveDebt(d.copyWith(notes: 'de novo'));
    expect(_gen(fc), hasLength(12));
    expect(_expenses(fc, next), pmt);
  });

  test(
    'pagamento registrado: parcela paga não muda e o contrato avança',
    () async {
      final fc = await _setup();
      await fc.saveDebt(_loan(fc.today));
      final first = _gen(fc).reduce((a, b) => a.date.isBefore(b.date) ? a : b);
      await fc.toggleCompleted(first, true);
      final d = fc.debtById('emp')!;
      expect(fc.debtPayments(d).map((t) => t.id), [first.id]);
      expect(await fc.advanceDebtByPayments(d), 1);
      final after = fc.debtById('emp')!;
      expect(after.remainingMonths, 11);
      expect(after.outstanding! < const Money(1000000), isTrue);
      // A paga continua concluída e não há parcela duplicada no mês dela.
      final sameMonth = fc.data.transactions.where(
        (t) =>
            DebtSync.isDerived(t.id) &&
            YearMonth.of(t.date) == YearMonth.of(first.date),
      );
      expect(sameMonth, hasLength(1));
      expect(sameMonth.single.status, TransactionStatus.completed);
      expect(_gen(fc), hasLength(12));
    },
  );

  test('contrato vinculado a uma recorrência não gera parcelas; aplicar a '
      'amortização troca a recorrência pelo cronograma novo', () async {
    final fc = await _setup();
    final d0 = _loan(fc.today, mode: DebtInstallments.linked);
    final pmt = currentSchedule(d0, fc.today)!.rows.first.total;
    final rule = RecurringRule(
      id: 'r-emp',
      type: TransactionType.expense,
      amount: pmt,
      description: 'Parcela do empréstimo',
      accountId: 'a',
      startDate: DateTime(fc.today.year, fc.today.month - 2, 10),
      endDate: Dates.addMonths(d0.nextDueDate!, 11),
    );
    await fc.createRule(rule);
    final d = d0.copyWith(linkedRuleId: 'r-emp');
    await fc.saveDebt(d);
    expect(_gen(fc), isEmpty);
    final next = YearMonth.of(d.nextDueDate!);
    expect(_expenses(fc, next), pmt);

    final r = estimatePrepayment(
      d,
      PrepayOption.reducePayment,
      amount: const Money(300000),
      asOf: fc.today,
    ).result!;
    final closedBefore = _expenses(fc, YearMonth.of(fc.today).add(-1));
    await fc.applyDebtPlan(r, accountId: 'a');

    // A parcela nova substitui a antiga: conta uma vez só.
    expect(_expenses(fc, next), r.paymentAfter);
    expect(
      fc.data.ruleById['r-emp']!.endDate!.isBefore(d.nextDueDate!),
      isTrue,
    );
    expect(_gen(fc), hasLength(12));
    // Saída planejada hoje e mês passado intacto.
    final pre = fc.data.transactions.where((t) => t.id.contains('_pre_'));
    expect(pre.single.amount, const Money(300000));
    expect(pre.single.status, TransactionStatus.planned);
    expect(_expenses(fc, YearMonth.of(fc.today).add(-1)), closedBefore);
    final saved = fc.debtById('emp')!;
    expect(saved.installments, DebtInstallments.generated);
    expect(saved.outstanding, const Money(700000));
    expect(fc.debtScenarios.single.appliedAt, isNotNull);
  });

  test('quitar arquiva o contrato e tira as parcelas planejadas', () async {
    final fc = await _setup();
    await fc.saveDebt(_loan(fc.today));
    final d = fc.debtById('emp')!;
    final r = estimatePrepayment(
      d,
      PrepayOption.payoff,
      asOf: fc.today,
    ).result!;
    await fc.applyDebtPlan(r, accountId: 'a');
    expect(_gen(fc), isEmpty);
    expect(fc.debtById('emp')!.archived, isTrue);
    expect(
      fc.data.transactions.where((t) => t.id.contains('_pre_')).single.amount,
      const Money(1000000),
    );
  });

  test('excluir o contrato remove as parcelas planejadas', () async {
    final fc = await _setup();
    await fc.saveDebt(_loan(fc.today));
    await fc.deleteDebt(fc.debtById('emp')!);
    expect(_gen(fc), isEmpty);
    expect(fc.debts, isEmpty);
  });
}
