import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/scenario.dart';
import 'financial_engine.dart';

/// Sobrepõe os fluxos de um cenário à Projeção, sem tocar no orçamento.
class ScenarioEngine {
  final FinancialEngine engine;
  const ScenarioEngine(this.engine);

  /// Mês em que um fluxo pendente entra: o da data, mas nunca um mês já
  /// passado nem um mês fechado (esses ficam intactos). Um fluxo atrasado
  /// cai no mês atual ou no próximo mês aberto.
  YearMonth monthOf(ScenarioFlow f) {
    var m = YearMonth.of(f.date);
    if (m < engine.currentMonth) m = engine.currentMonth;
    final closed = engine.data.closingByMonth;
    while (closed.containsKey(m)) {
      m = m.next;
    }
    return m;
  }

  /// Resultado da Projeção com os fluxos pendentes de [flows] somados.
  ///
  /// Entradas viram receita e saídas viram despesa no mês do fluxo; fluxos
  /// antes do primeiro mês mudam o saldo inicial; depois do último, são
  /// ignorados. O acumulado é recalculado a partir daí.
  ProjectionResult apply(ProjectionResult base, Iterable<ScenarioFlow> flows) {
    if (base.columns.isEmpty) return base;
    final first = base.columns.first.month;
    final last = base.columns.last.month;
    final income = <YearMonth, Money>{};
    final expenses = <YearMonth, Money>{};
    var prior = Money.zero;
    for (final f in flows) {
      if (f.realized || f.amount.isZero) continue;
      final m = monthOf(f);
      if (m > last) continue;
      if (m < first) {
        prior += f.amount;
      } else if (f.amount.cents > 0) {
        income[m] = (income[m] ?? Money.zero) + f.amount;
      } else {
        expenses[m] = (expenses[m] ?? Money.zero) - f.amount;
      }
    }
    final opening = base.openingBalance + prior;
    var running = opening;
    final cols = <ProjectionColumn>[];
    for (final c in base.columns) {
      final inc = c.income + (income[c.month] ?? Money.zero);
      final exp = c.expenses + (expenses[c.month] ?? Money.zero);
      final start = running;
      running = running + inc - exp + c.transfersNet;
      cols.add(
        ProjectionColumn(
          month: c.month,
          income: inc,
          expenses: exp,
          transfersNet: c.transfersNet,
          opening: start,
          accumulated: running,
          isPast: c.isPast,
          isCurrent: c.isCurrent,
        ),
      );
    }
    return ProjectionResult(
      cols,
      opening,
      base.openingIsAccountBalance,
      base.showsTransfers,
    );
  }

  /// Total pendente do cenário por mês (para mostrar o "antes e depois").
  Map<YearMonth, Money> netByMonth(Iterable<ScenarioFlow> flows) {
    final out = <YearMonth, Money>{};
    for (final f in flows) {
      if (f.realized) continue;
      final m = monthOf(f);
      out[m] = (out[m] ?? Money.zero) + f.amount;
    }
    return out;
  }
}
