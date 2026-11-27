import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/asset.dart';
import '../models/fgts.dart';
import '../models/scenario.dart';

/// Saque do FGTS dentro de um cenário.
class FgtsWithdrawal {
  final PlanScenario scenario;
  final ScenarioFlow flow;
  const FgtsWithdrawal(this.scenario, this.flow);

  FgtsPurpose get purpose => FgtsPurpose.parse(flow.purpose);
}

/// Estimativas do FGTS (saldo futuro, saque-aniversário). São sempre
/// estimativas: a TR e a distribuição de lucros não entram.
abstract final class FgtsEngine {
  /// Saques do FGTS [fgts] em todos os cenários.
  static List<FgtsWithdrawal> withdrawals(
    Asset fgts,
    Iterable<PlanScenario> scenarios,
  ) => [
    for (final s in scenarios)
      for (final f in s.flows)
        if (f.source == ScenarioSource.fgts && f.refId == fgts.id)
          FgtsWithdrawal(s, f),
  ]..sort((a, b) => a.flow.date.compareTo(b.flow.date));

  /// Saldo previsto em [date]: parte do saldo informado na data do extrato,
  /// soma o rendimento mensal e o depósito de cada mês seguinte, e desconta
  /// os saques pendentes de [withdrawals] (os do mesmo cenário).
  static Money projectedBalance(
    Asset fgts,
    DateTime date, {
    Iterable<ScenarioFlow> withdrawals = const [],
  }) {
    final d = fgts.fgts ?? FgtsDetails(balanceDate: fgts.updatedAt);
    final start = Dates.dateOnly(d.balanceDate);
    final end = Dates.dateOnly(date);
    var balance = fgts.value.cents.toDouble();
    if (!end.isAfter(start)) return fgts.value;
    final pending =
        withdrawals
            .where((w) => !w.realized && w.date.isAfter(start))
            .where((w) => !w.date.isAfter(end))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final rate = d.monthlyRate;
    var month = YearMonth.of(start);
    final last = YearMonth.of(end);
    double take(YearMonth m) => pending
        .where((w) => YearMonth.of(w.date) == m)
        .fold(0.0, (a, w) => a + w.amount.cents);
    balance -= take(month);
    while (month < last) {
      month = month.next;
      balance = balance * (1 + rate) + d.monthlyDeposit.cents;
      balance -= take(month);
    }
    return Money(balance.round());
  }

  /// Valor do saque-aniversário para um saldo (alíquota + parcela
  /// adicional, Lei 13.932/2019).
  static Money birthdayAmount(Money balance) {
    final c = balance.cents;
    const table = [
      (50000, 50, 0),
      (100000, 40, 5000),
      (500000, 30, 15000),
      (1000000, 20, 65000),
      (1500000, 15, 115000),
      (2000000, 10, 190000),
    ];
    if (c <= 0) return Money.zero;
    for (final (limit, pct, extra) in table) {
      if (c <= limit) return Money((c * pct / 100).round() + extra);
    }
    return Money((c * 5 / 100).round() + 290000);
  }

  /// Avisos sobre um saque: valor acima do saldo previsto, data passada.
  static List<String> warnings(
    Asset fgts,
    ScenarioFlow flow, {
    Iterable<ScenarioFlow> others = const [],
    required DateTime today,
  }) {
    final out = <String>[];
    final before = projectedBalance(
      fgts,
      flow.date,
      withdrawals: others.where((o) => o.id != flow.id),
    );
    if (flow.amount > before) {
      out.add(
        'O valor passa do saldo previsto para a data '
        '(${before.formatVisible()}).',
      );
    }
    final purpose = FgtsPurpose.parse(flow.purpose);
    if (purpose == FgtsPurpose.birthday) {
      final max = birthdayAmount(before);
      if (flow.amount > max) {
        out.add(
          'No saque-aniversário, com esse saldo, o limite estimado é '
          '${max.formatVisible()}.',
        );
      }
    }
    if (!flow.realized && Dates.dateOnly(flow.date).isBefore(today)) {
      out.add('A data já passou: na Projeção o saque entra no mês atual.');
    }
    return out;
  }
}
