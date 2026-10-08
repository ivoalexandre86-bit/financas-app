import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../models/entities.dart';
import '../models/simulation.dart';
import 'financial_engine.dart';

/// Totais de um mês de um cenário (centavos).
class SimMonth {
  final YearMonth month;
  final int income;
  final int expenses;
  final int accumulated;
  const SimMonth(this.month, this.income, this.expenses, this.accumulated);
  int get net => income - expenses;

  /// Utilização do orçamento: despesas ÷ receitas (0 quando sem receita).
  double get utilization => income == 0 ? 0 : expenses / income;
}

/// Cálculos de uma lista de linhas em um período.
class SimTotals {
  final List<SimMonth> months;
  final int opening;
  const SimTotals(this.months, this.opening);

  factory SimTotals.of(
    List<SimItem> items,
    List<YearMonth> months,
    int opening,
  ) {
    var running = opening;
    final out = <SimMonth>[];
    for (final m in months) {
      var inc = 0, exp = 0;
      for (final i in items) {
        if (i.isIncome) {
          inc += i.valueAt(m);
        } else {
          exp += i.valueAt(m);
        }
      }
      running += inc - exp;
      out.add(SimMonth(m, inc, exp, running));
    }
    return SimTotals(out, opening);
  }

  /// Orçamento oficial calculado agora pelo motor (saldo de contas).
  factory SimTotals.official(FinancialEngine e, YearMonth from, YearMonth to) {
    final p = e.projection(MonthRange(from, to));
    return SimTotals([
      for (final c in p.columns)
        SimMonth(
          c.month,
          c.income.cents,
          c.expenses.cents,
          c.accumulated.cents,
        ),
    ], p.openingBalance.cents);
  }

  int get income => months.fold(0, (a, m) => a + m.income);
  int get expenses => months.fold(0, (a, m) => a + m.expenses);
  int get net => income - expenses;
  int get finalBalance => months.isEmpty ? opening : months.last.accumulated;
  int get deficitMonths => months.where((m) => m.net < 0).length;
  int get surplusMonths => months.where((m) => m.net > 0).length;

  SimMonth? at(YearMonth m) {
    for (final x in months) {
      if (x.month == m) return x;
    }
    return null;
  }
}

/// Variação percentual de [from] para [to] (null quando a base é zero).
double? pctChange(int from, int to) =>
    from == 0 ? null : (to - from) / from.abs() * 100;

/// Diferença de uma linha entre o orçamento base e a simulação.
class SimImpact {
  final SimItem? base;
  final SimItem? sim;

  /// Efeito no resultado do período (+ melhora, − piora), em centavos.
  final int effect;
  const SimImpact(this.base, this.sim, this.effect);
  SimItem get item => (sim ?? base)!;
}

class SimulationEngine {
  SimulationEngine._();

  /// Copia o orçamento oficial do período para linhas de simulação: uma
  /// linha por recorrência, por parcelamento ou por lançamento avulso,
  /// com o valor de cada mês em regime de caixa (como na Projeção).
  static ({List<SimItem> items, int opening}) snapshot(
    FinancialEngine engine,
    YearMonth from,
    YearMonth to,
  ) {
    final groups = <String, _Group>{};
    for (final e in engine.recognizedEvents(ProjectionFilter.none, to)) {
      if (e.month < from || e.signed.isZero) continue;
      final tx = e.tx;
      final income = e.signed.cents > 0;
      // Avulsos iguais (mesma descrição, categoria e conta/cartão) ficam
      // numa linha só, como numa planilha de orçamento.
      final source = tx.recurringId != null
          ? 'r:${tx.recurringId}'
          : tx.installmentGroupId != null
          ? 'i:${tx.installmentGroupId}'
          : 't:${tx.description.trim().toLowerCase()}|${tx.categoryId}|'
                '${tx.accountId}|${tx.cardId}';
      final g = groups.putIfAbsent(
        '$source|$income',
        () => _Group(source, income, tx),
      );
      g.add(e.month, e.signed.cents.abs(), tx);
    }
    final rules = {for (final r in engine.data.recurringRules) r.id: r};
    final items = <SimItem>[];
    for (final g in groups.values) {
      final tx = g.last;
      var rec = SimRecurrence.once;
      if (g.source.startsWith('i:')) rec = SimRecurrence.monthly;
      if (g.source.startsWith('r:')) {
        final r = rules[tx.recurringId];
        rec = switch (r?.frequency) {
          RecurrenceFrequency.quarterly => SimRecurrence.quarterly,
          RecurrenceFrequency.yearly => SimRecurrence.yearly,
          _ => SimRecurrence.monthly,
        };
      }
      items.add(
        SimItem(
          id: newId('si_'),
          type: g.income ? TransactionType.income : TransactionType.expense,
          description: tx.description,
          categoryId: tx.categoryId,
          accountId: tx.accountId,
          cardId: tx.cardId,
          day: tx.date.day,
          recurrence: rec,
          classification: g.source.startsWith('t:') ? 'Variável' : 'Fixa',
          origin: SimOrigin.base,
          sourceKey: g.source,
          refs: g.refs,
          values: g.values,
        ),
      );
    }
    sortItems(items);
    final opening = engine
        .projection(MonthRange(from, to))
        .openingBalance
        .cents;
    return (items: items, opening: opening);
  }

  /// Receitas primeiro, depois despesas; por descrição.
  static void sortItems(List<SimItem> items) => items.sort((a, b) {
    if (a.isIncome != b.isIncome) return a.isIncome ? -1 : 1;
    return a.description.toLowerCase().compareTo(b.description.toLowerCase());
  });

  /// Linhas cujo efeito no período mudou, da maior para a menor diferença.
  static List<SimImpact> impacts(Simulation s) {
    final months = s.months;
    int effect(SimItem? i) =>
        i == null ? 0 : (i.isIncome ? 1 : -1) * i.totalIn(months);
    final base = {for (final i in s.baseItems) i.id: i};
    final sim = {for (final i in s.items) i.id: i};
    final out = <SimImpact>[];
    for (final id in {...base.keys, ...sim.keys}) {
      final d = effect(sim[id]) - effect(base[id]);
      if (d != 0) out.add(SimImpact(base[id], sim[id], d));
    }
    out.sort((a, b) => b.effect.abs().compareTo(a.effect.abs()));
    return out;
  }

  /// Quanto cabe a cada pessoa (id; `null` = não dividido) nas linhas do
  /// tipo pedido ([income]) nos meses informados.
  static Map<String?, int> byPerson(
    Iterable<SimItem> items,
    Iterable<YearMonth> months,
    bool income,
  ) {
    final out = <String?, int>{};
    for (final i in items) {
      if (i.isIncome != income) continue;
      for (final m in months) {
        final v = i.valueAt(m);
        if (v == 0) continue;
        i.splitCents(v).forEach((k, c) => out[k] = (out[k] ?? 0) + c);
      }
    }
    return out;
  }

  /// Total por categoria (raiz) no período: [income] = receitas.
  static Map<String?, int> byCategory(
    List<SimItem> items,
    List<YearMonth> months,
    bool income,
    String? Function(String?) rootOf,
  ) {
    final out = <String?, int>{};
    for (final i in items) {
      if (i.isIncome != income) continue;
      final k = rootOf(i.categoryId);
      out[k] = (out[k] ?? 0) + i.totalIn(months);
    }
    return out;
  }
}

class _Group {
  final String source;
  final bool income;
  FinTransaction last;
  final Map<String, int> values = {};
  final Map<String, List<String>> refs = {};
  _Group(this.source, this.income, this.last);

  void add(YearMonth m, int cents, FinTransaction tx) {
    values[m.key] = (values[m.key] ?? 0) + cents;
    final r = refs[m.key] ??= [];
    if (!r.contains(tx.id)) r.add(tx.id);
    if (!tx.date.isBefore(last.date)) last = tx;
  }
}

// -----------------------------------------------------------------------------
// Aplicar a simulação ao orçamento oficial

enum SimChangeKind {
  newExpense('Novas despesas'),
  removedExpense('Despesas removidas'),
  modifiedExpense('Despesas alteradas'),
  newIncome('Novas receitas'),
  modifiedIncome('Receitas alteradas'),
  removedIncome('Receitas removidas');

  final String label;
  const SimChangeKind(this.label);
}

class SimChange {
  final SimChangeKind kind;
  final String description;
  final String detail;
  const SimChange(this.kind, this.description, this.detail);
}

/// Alterações que a simulação faria no orçamento oficial.
class SimApplyPlan {
  final List<SimChange> changes;
  final List<FinTransaction> puts;

  /// Lançamentos persistidos a excluir.
  final List<String> deletes;
  final List<RecurringRule> rules;
  const SimApplyPlan(this.changes, this.puts, this.deletes, this.rules);

  bool get isEmpty => changes.isEmpty;

  /// Monta o plano comparando as linhas atuais com as do orçamento base.
  ///
  /// * Linhas novas viram uma recorrência (valores iguais em intervalos
  ///   regulares) ou lançamentos previstos, um por mês.
  /// * Meses alterados ajustam o lançamento oficial daquele mês (ocorrências
  ///   de recorrência são materializadas só para aquele mês); meses zerados
  ///   cancelam/excluem o lançamento.
  /// * Linhas excluídas removem os lançamentos do período.
  factory SimApplyPlan.build(
    FinancialEngine engine,
    Simulation sim, {
    String? fallbackAccountId,
  }) {
    final months = sim.months;
    final txById = {
      for (final t in engine.transactionsUntil(sim.to.lastDay)) t.id: t,
    };
    final edited = <String, FinTransaction>{}; // id → versão nova
    final deleted = <String>{};
    final created = <FinTransaction>[];
    final rules = <RecurringRule>[];
    final changes = <SimChange>[];

    FinTransaction current(String id) => edited[id] ?? txById[id]!;

    void remove(String id) {
      final t = txById[id];
      if (t == null) return;
      edited.remove(id);
      if (t.isVirtual) {
        edited[id] = t.copyWith(status: TransactionStatus.cancelled);
      } else {
        deleted.add(id);
      }
    }

    void edit(String id, FinTransaction Function(FinTransaction) f) {
      if (deleted.contains(id) || !txById.containsKey(id)) return;
      edited[id] = f(current(id));
    }

    ({String? accountId, String? cardId}) funding(SimItem i) =>
        i.accountId == null && i.cardId == null
        ? (accountId: fallbackAccountId, cardId: null)
        : (accountId: i.accountId, cardId: i.cardId);

    FinTransaction newTx(SimItem i, YearMonth m, int cents) {
      final f = funding(i);
      return FinTransaction(
        id: newId('tx_'),
        type: i.type,
        amount: Money(cents),
        description: i.description,
        categoryId: i.categoryId,
        date: Dates.clampedDate(m.year, m.month, i.day),
        accountId: f.accountId,
        cardId: f.cardId,
        notes: i.notes.isEmpty ? 'Simulação: ${sim.name}' : i.notes,
        status: TransactionStatus.planned,
      );
    }

    String fmt(int c) => Money(c).format();
    String monthsLabel(List<YearMonth> ms) {
      if (ms.isEmpty) return '';
      if (ms.length == 1) return ms.first.shortLabel;
      return '${ms.first.shortLabel}–${ms.last.shortLabel} (${ms.length} meses)';
    }

    final simById = {for (final i in sim.items) i.id: i};
    for (final b in sim.baseItems) {
      final s = simById[b.id];
      final income = b.isIncome;
      if (s == null) {
        if (b.totalIn(months) == 0) continue;
        for (final ids in b.refs.values) {
          ids.forEach(remove);
        }
        changes.add(
          SimChange(
            income ? SimChangeKind.removedIncome : SimChangeKind.removedExpense,
            b.description,
            '${fmt(b.totalIn(months))} no período',
          ),
        );
        continue;
      }
      final changedMonths = [
        for (final m in months)
          if (s.valueAt(m) != b.valueAt(m)) m,
      ];
      final fieldsChanged = !s.sameFieldsAs(b);
      if (changedMonths.isEmpty && !fieldsChanged) continue;
      for (final m in changedMonths) {
        final nv = s.valueAt(m), ov = b.valueAt(m);
        final refs = b.refs[m.key] ?? const <String>[];
        final live = refs.where(txById.containsKey).toList();
        if (nv == 0) {
          live.forEach(remove);
        } else if (live.isEmpty) {
          created.add(newTx(s, m, nv));
        } else {
          final first = live.first;
          final amount = current(first).amount.cents + (nv - ov);
          if (amount > 0) {
            edit(first, (t) => t.copyWith(amount: Money(amount)));
          } else {
            live.forEach(remove);
            created.add(newTx(s, m, nv));
          }
        }
      }
      if (fieldsChanged) {
        final f = funding(s);
        for (final m in months) {
          if (s.valueAt(m) == 0) continue;
          for (final id in b.refs[m.key] ?? const <String>[]) {
            edit(
              id,
              (t) => t.copyWith(
                description: s.description,
                categoryId: s.categoryId,
                accountId: f.accountId,
                cardId: f.cardId,
              ),
            );
          }
        }
      }
      final diff = s.totalIn(months) - b.totalIn(months);
      final parts = <String>[
        if (changedMonths.isNotEmpty)
          '${diff >= 0 ? '+' : '−'}${fmt(diff.abs())} em ${monthsLabel(changedMonths)}',
        if (fieldsChanged) 'dados do lançamento alterados',
      ];
      changes.add(
        SimChange(
          income ? SimChangeKind.modifiedIncome : SimChangeKind.modifiedExpense,
          s.description,
          parts.join(' · '),
        ),
      );
    }

    for (final s in sim.items) {
      if (s.origin == SimOrigin.base &&
          sim.baseItems.any((b) => b.id == s.id)) {
        continue;
      }
      final filled = [
        for (final m in months)
          if (s.valueAt(m) != 0) m,
      ];
      if (filled.isEmpty) continue;
      final f = funding(s);
      final amounts = {for (final m in filled) s.valueAt(m)};
      final step = filled.length > 1 ? filled.first.monthsUntil(filled[1]) : 0;
      final regular =
          filled.length > 1 &&
          amounts.length == 1 &&
          step > 0 &&
          [
            for (var k = 1; k < filled.length; k++)
              filled[k - 1].monthsUntil(filled[k]),
          ].every((d) => d == step);
      if (regular) {
        final (freq, interval) = switch (step) {
          1 => (RecurrenceFrequency.monthly, 1),
          3 => (RecurrenceFrequency.quarterly, 1),
          12 => (RecurrenceFrequency.yearly, 1),
          _ => (RecurrenceFrequency.custom, step),
        };
        rules.add(
          RecurringRule(
            id: newId('rule_'),
            type: s.type,
            amount: Money(amounts.first),
            description: s.description,
            categoryId: s.categoryId,
            accountId: f.accountId,
            cardId: f.cardId,
            frequency: freq,
            interval: interval,
            unit: RecurrenceUnit.months,
            dayOfMonth: s.day,
            startDate: Dates.clampedDate(
              filled.first.year,
              filled.first.month,
              s.day,
            ),
            endDate: Dates.clampedDate(
              filled.last.year,
              filled.last.month,
              s.day,
            ),
            notes: s.notes.isEmpty ? 'Simulação: ${sim.name}' : s.notes,
          ),
        );
      } else {
        for (final m in filled) {
          created.add(newTx(s, m, s.valueAt(m)));
        }
      }
      changes.add(
        SimChange(
          s.isIncome ? SimChangeKind.newIncome : SimChangeKind.newExpense,
          s.description,
          regular
              ? '${fmt(amounts.first)} · ${monthsLabel(filled)}'
              : '${fmt(s.totalIn(months))} em ${monthsLabel(filled)}',
        ),
      );
    }

    final puts = <FinTransaction>[
      for (final t in edited.values)
        t.isVirtual ? t.copyWith(id: newId('tx_'), isVirtual: false) : t,
      ...created,
    ];
    changes.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return SimApplyPlan(changes, puts, deleted.toList(), rules);
  }
}
