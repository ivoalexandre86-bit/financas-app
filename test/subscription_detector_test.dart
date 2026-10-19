import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/engine/subscription_detector.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 19);
  var n = 0;
  FinTransaction tx(String desc, int cents, DateTime d, {String? rec}) =>
      FinTransaction(
        id: 't${n++}',
        type: TransactionType.expense,
        amount: Money(cents),
        description: desc,
        date: d,
        accountId: 'a',
        status: TransactionStatus.completed,
        recurringId: rec,
        occurrenceDate: rec == null ? null : d,
      );
  List<Subscription> detect(
    List<FinTransaction> txs, {
    List<RecurringRule> rules = const [],
  }) => SubscriptionDetector.detect(
    FinancialEngine(
      FinanceData(
        accounts: [Account(id: 'a', name: 'Conta')],
        transactions: txs,
        recurringRules: rules,
      ),
      today: today,
    ),
  );

  test('detecta gasto avulso repetido em 3 meses com valor parecido', () {
    final subs = detect([
      tx('Netflix', 3990, DateTime(2026, 7, 5)),
      tx('NETFLIX ', 3990, DateTime(2026, 8, 5)),
      tx('Nétflix', 4290, DateTime(2026, 9, 5)),
      tx('Netflix', 4490, DateTime(2026, 10, 5)),
    ]);
    expect(subs, hasLength(1));
    final s = subs.single;
    expect(s.source, SubscriptionSource.detected);
    expect(s.name, 'Netflix');
    expect(s.monthsSeen, 4);
    expect(s.lastDate, DateTime(2026, 10, 5));
    expect(s.monthly, const Money(4140)); // mediana de 4 meses
    expect(s.annual, const Money(4140 * 12));
    expect(s.priceIncreased, isFalse); // 42,90 → 44,90: +4,7%
  });

  test('aumento só acima de 5%', () {
    final small = detect([
      tx('Spotify', 2000, DateTime(2026, 8, 1)),
      tx('Spotify', 2000, DateTime(2026, 9, 1)),
      tx('Spotify', 2100, DateTime(2026, 10, 1)),
    ]).single;
    expect(small.priceIncreased, isFalse);
    final big = detect([
      tx('Spotify', 2000, DateTime(2026, 8, 1)),
      tx('Spotify', 2000, DateTime(2026, 9, 1)),
      tx('Spotify', 2200, DateTime(2026, 10, 1)),
    ]).single;
    expect(big.priceIncreased, isTrue);
    expect(big.increasePercent, closeTo(10, 0.01));
  });

  test('ignora poucos meses, valores muito diferentes e fora da janela', () {
    expect(
      detect([
        tx('Academia', 9900, DateTime(2026, 9, 1)),
        tx('Academia', 9900, DateTime(2026, 10, 1)),
      ]),
      isEmpty,
    );
    expect(
      detect([
        tx('Uber', 1500, DateTime(2026, 8, 1)),
        tx('Uber', 6000, DateTime(2026, 9, 1)),
        tx('Uber', 3000, DateTime(2026, 10, 1)),
      ]),
      isEmpty,
    );
    // Abril é anterior aos últimos 6 meses (mai–out).
    expect(
      detect([
        tx('Jornal', 5000, DateTime(2026, 3, 1)),
        tx('Jornal', 5000, DateTime(2026, 4, 1)),
        tx('Jornal', 5000, DateTime(2026, 10, 1)),
      ]),
      isEmpty,
    );
  });

  test('regra recorrente entra como Recorrência e não duplica', () {
    final rule = RecurringRule(
      id: 'r',
      type: TransactionType.expense,
      amount: const Money(12000),
      description: 'Internet',
      accountId: 'a',
      startDate: DateTime(2026, 1, 10),
    );
    final subs = detect(
      [
        tx('Internet', 11000, DateTime(2026, 8, 10), rec: 'r'),
        // Mesmo nome lançado à mão: não vira "Detectada".
        tx('Internet', 12000, DateTime(2026, 9, 3)),
        tx('Internet', 12000, DateTime(2026, 10, 3)),
        tx('Internet', 12000, DateTime(2026, 7, 3)),
      ],
      rules: [
        rule,
        RecurringRule(
          id: 'inc',
          type: TransactionType.income,
          amount: const Money(500000),
          description: 'Salário',
          startDate: DateTime(2026, 1, 5),
        ),
      ],
    );
    expect(subs, hasLength(1));
    final s = subs.single;
    expect(s.source, SubscriptionSource.recurring);
    expect(s.rule, same(rule));
    expect(s.monthly, const Money(12000));
    expect(s.lastDate, DateTime(2026, 10, 10));
    expect(s.monthsSeen, 6);
    // 110,00 em agosto (materializada); as duas últimas valem 120,00.
    expect(s.previousAmount, const Money(12000));
    expect(s.priceIncreased, isFalse);
  });

  test('regra anual vira equivalente mensal; totais', () {
    final subs = detect(
      const [],
      rules: [
        RecurringRule(
          id: 'y',
          type: TransactionType.expense,
          amount: const Money(120000),
          description: 'Seguro',
          frequency: RecurrenceFrequency.yearly,
          startDate: DateTime(2026, 3, 1),
        ),
      ],
    );
    expect(subs.single.monthly, const Money(10000));
    expect(subs.single.annual, const Money(120000));
    final t = SubscriptionDetector.totals(subs);
    expect(t.monthly, const Money(10000));
    expect(t.annual, const Money(120000));
  });
}
