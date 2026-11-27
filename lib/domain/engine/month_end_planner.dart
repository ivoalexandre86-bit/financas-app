import 'dart:math' as math;

import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/debt.dart';
import '../models/entities.dart';
import '../models/planning.dart';
import 'budget_engine.dart';
import 'debt_engine.dart';
import 'financial_engine.dart';

// "O que fazer agora?" — passo final do fechamento do mês.
//
// Parte do resultado fechado, do saldo atual em contas, das faturas em
// aberto, dos próximos compromissos e da reserva mínima para dizer quanto
// dinheiro está realmente livre e comparar o que fazer com ele. Tudo aqui é
// cálculo puro: nada é gravado. As opções escolhidas só mudam o
// planejamento futuro (ver FinanceController.applyMonthEndOption) e nunca
// tocam em meses fechados.

/// Situação encontrada no fechamento.
enum MonthEndScenario {
  /// Sobra dinheiro depois dos compromissos e da reserva.
  surplus('Sobra disponível'),

  /// O mês fechou positivo, mas o caixa já está comprometido.
  committed('Resultado positivo, caixa comprometido'),

  /// O mês fechou negativo ou a projeção mostra falta de caixa.
  shortfall('Déficit ou falta de caixa prevista');

  final String label;
  const MonthEndScenario(this.label);
}

/// Tipo de opção sugerida.
enum MonthEndOptionKind {
  keepCash('Manter em caixa'),
  reserve('Reforçar a reserva'),
  goal('Guardar para uma meta'),
  debtPrepay('Amortizar dívida'),
  cutDiscretionary('Reduzir gastos variáveis'),
  postpone('Mudar data de pagamento'),
  renegotiate('Refinanciar ou renegociar');

  final String label;
  const MonthEndOptionKind(this.label);
}

/// Compromisso que precisa sair do caixa até o fim da janela.
class PlannedObligation {
  final DateTime date;
  final String description;
  final Money amount;
  final bool overdue;
  final bool isInvoice;
  final FinTransaction? tx;
  final Invoice? invoice;
  const PlannedObligation({
    required this.date,
    required this.description,
    required this.amount,
    required this.overdue,
    required this.isInvoice,
    this.tx,
    this.invoice,
  });
}

/// O que mais pesa nas despesas de um mês.
class ShortfallContributor {
  final String description;
  final Money amount;
  final bool fixed; // recorrente ou parcela
  const ShortfallContributor(this.description, this.amount, this.fixed);
}

/// Mês em que o saldo projetado fica abaixo da reserva mínima.
class ShortfallMonth {
  final YearMonth month;
  final Money projected; // saldo acumulado no fim do mês
  final Money gap; // quanto falta para a reserva mínima
  final List<ShortfallContributor> contributors;
  const ShortfallMonth(this.month, this.projected, this.gap, this.contributors);
}

/// Proposta de refinanciamento/renegociação informada pelo usuário.
class RenegotiationOffer {
  final String name;
  final Money currentInstallment;
  final int currentRemainingMonths;
  final Money newInstallment;
  final int newMonths;
  final Money upfrontCost; // entrada, tarifas, IOF
  final bool isLenderQuote;
  const RenegotiationOffer({
    required this.name,
    required this.currentInstallment,
    required this.currentRemainingMonths,
    required this.newInstallment,
    required this.newMonths,
    this.upfrontCost = Money.zero,
    this.isLenderQuote = true,
  });

  Money get currentTotal => currentInstallment * currentRemainingMonths;
  Money get newTotal => newInstallment * newMonths + upfrontCost;
  Money get monthlyRelief => currentInstallment - newInstallment;

  /// Positivo = a proposta custa mais no total.
  Money get extraCost => newTotal - currentTotal;
}

/// Uma opção comparável para o dinheiro do fim do mês.
class MonthEndOption {
  final MonthEndOptionKind kind;
  final String title;

  /// Por que a opção aparece.
  final String why;

  /// Saída de caixa agora (0 = nenhuma).
  final Money upfront;

  /// Mudança no caixa de cada mês (+ entra, − sai) em relação à projeção.
  final Map<YearMonth, Money> deltas;
  final Money? interestSavings;
  final Money? monthlyRelief;

  /// Para renegociação: positivo = custa mais no total.
  final Money? totalCostChange;

  /// Campos que faltam para calcular (estimativa não mostrada).
  final List<String> missingFields;
  final List<String> assumptions;
  final bool isLenderQuote;

  /// Meta, dívida ou lançamento alvo.
  final String? targetId;

  /// Estimativa do motor de dívidas usada na opção (prazo menor, ou a
  /// primeira que o contrato permite).
  final DebtEstimate? debtEstimate;
  final RenegotiationOffer? offer;
  final List<FinTransaction> postponed;

  /// Datas novas dos lançamentos adiados (mesma ordem de [postponed]).
  final List<DateTime> postponedTo;

  const MonthEndOption({
    required this.kind,
    required this.title,
    required this.why,
    this.upfront = Money.zero,
    this.deltas = const {},
    this.interestSavings,
    this.monthlyRelief,
    this.totalCostChange,
    this.missingFields = const [],
    this.assumptions = const [],
    this.isLenderQuote = false,
    this.targetId,
    this.debtEstimate,
    this.offer,
    this.postponed = const [],
    this.postponedTo = const [],
  });

  String get id => '${kind.name}:${targetId ?? ''}';
  bool get isComplete => missingFields.isEmpty;
}

/// Linha do antes e depois da projeção.
class CashCompare {
  final YearMonth month;
  final Money before;
  final Money after;
  const CashCompare(this.month, this.before, this.after);
  Money get change => after - before;
}

/// Análise completa do fim do mês.
class MonthEndAnalysis {
  final YearMonth closedMonth;
  final bool isClosed;
  final Money income;
  final Money expenses;
  final Money cash;
  final Money minimumReserve;
  final DateTime windowEnd;
  final List<PlannedObligation> obligations;
  final Money expectedIncome; // receitas a receber na janela (não contam)
  final List<ProjectionColumn> projection;
  final List<ShortfallMonth> shortfalls;
  final MonthEndScenario scenario;
  final List<MonthEndOption> options;
  final DateTime calculatedAt;

  const MonthEndAnalysis({
    required this.closedMonth,
    required this.isClosed,
    required this.income,
    required this.expenses,
    required this.cash,
    required this.minimumReserve,
    required this.windowEnd,
    required this.obligations,
    required this.expectedIncome,
    required this.projection,
    required this.shortfalls,
    required this.scenario,
    required this.options,
    required this.calculatedAt,
  });

  Money get result => income - expenses;
  Money get committed => obligations.map((o) => o.amount).sum();

  /// Dinheiro realmente livre: saldo − compromissos − reserva mínima.
  Money get available => cash - committed - minimumReserve;
  Money get freeToUse => available.isNegative ? Money.zero : available;

  /// Quanto precisa ficar separado para os compromissos.
  Money get setAside => committed;

  /// Primeiro mês da projeção (o mês seguinte ao planejamento).
  YearMonth get nextMonth => projection.first.month;

  /// Antes e depois da projeção para uma opção.
  List<CashCompare> compare(MonthEndOption o) {
    var acc = Money.zero;
    return [
      for (final c in projection)
        () {
          acc += o.deltas[c.month] ?? Money.zero;
          return CashCompare(c.month, c.accumulated, c.accumulated + acc);
        }(),
    ];
  }

  /// Caixa no fim do mês seguinte depois da opção.
  Money cashNextMonthAfter(MonthEndOption o) => compare(o).first.after;

  /// Meses abaixo da reserva depois da opção.
  int shortfallMonthsAfter(MonthEndOption o) =>
      compare(o).where((c) => c.after < minimumReserve).length;
}

class MonthEndPlanner {
  final FinancialEngine engine;
  MonthEndPlanner(this.engine);

  DateTime get today => engine.today;

  /// Primeiro mês em que o plano pode mexer: o atual ou o próximo aberto.
  YearMonth firstOpenMonth() {
    var m = engine.currentMonth;
    while (engine.data.closingByMonth.containsKey(m)) {
      m = m.next;
    }
    return m;
  }

  /// Data em que uma saída planejada cai: hoje, ou o dia 1º do primeiro
  /// mês aberto quando o mês atual já está fechado.
  DateTime firstOpenDate() {
    final m = firstOpenMonth();
    return m == engine.currentMonth ? today : m.firstDay;
  }

  bool isClosed(YearMonth m) => engine.data.closingByMonth.containsKey(m);

  /// Compromissos não pagos (inclusive atrasados) que vencem até [end]:
  /// despesas de conta pendentes e saldo restante das faturas.
  List<PlannedObligation> obligationsUntil(DateTime end) {
    final out = <PlannedObligation>[];
    for (final t in engine.transactionsUntil(end)) {
      if (t.cardId != null || t.type != TransactionType.expense) continue;
      if (t.status == TransactionStatus.completed ||
          t.status == TransactionStatus.cancelled) {
        continue;
      }
      if (t.date.isAfter(end)) continue;
      out.add(
        PlannedObligation(
          date: t.effectiveDueDate,
          description: t.description,
          amount: t.amount,
          overdue: t.effectiveDueDate.isBefore(today),
          isInvoice: false,
          tx: t,
        ),
      );
    }
    for (final card in engine.data.cards) {
      for (final inv in engine.invoicesForCard(card)) {
        if (inv.remaining.cents <= 0 || inv.dueDate.isAfter(end)) continue;
        out.add(
          PlannedObligation(
            date: inv.dueDate,
            description: 'Fatura ${card.name} (${inv.month.shortLabel})',
            amount: inv.remaining,
            overdue: inv.dueDate.isBefore(today),
            isInvoice: true,
            invoice: inv,
          ),
        );
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  Money _expectedIncomeUntil(DateTime end) {
    var total = Money.zero;
    for (final t in engine.transactionsUntil(end)) {
      if (t.type != TransactionType.income) continue;
      if (t.status == TransactionStatus.completed ||
          t.status == TransactionStatus.cancelled) {
        continue;
      }
      if (t.date.isAfter(end) || t.date.isBefore(today)) continue;
      total += t.amount;
    }
    return total;
  }

  static bool _isFixed(FinTransaction t) =>
      t.recurringId != null || t.installmentGroupId != null;

  /// Maiores despesas do mês, agrupadas por descrição.
  List<ShortfallContributor> contributors(YearMonth m, {int limit = 3}) {
    final by = <String, (Money, bool)>{};
    for (final e in engine.monthEvents(ProjectionFilter.none, m)) {
      if (!e.isExpense) continue;
      final key = e.tx.cardId != null && !_isFixed(e.tx)
          ? 'Compras no cartão ${engine.data.cardById[e.tx.cardId]?.name ?? ''}'
                .trim()
          : e.tx.description;
      final old = by[key];
      by[key] = (
        (old?.$1 ?? Money.zero) + (-e.signed),
        (old?.$2 ?? false) || _isFixed(e.tx),
      );
    }
    final list = [
      for (final MapEntry(:key, :value) in by.entries)
        ShortfallContributor(key, value.$1, value.$2),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    return list.take(limit).toList();
  }

  /// Gastos variáveis (sem recorrência nem parcelamento) previstos no mês.
  Money discretionaryIn(YearMonth m) {
    var total = Money.zero;
    for (final e in engine.monthEvents(ProjectionFilter.none, m)) {
      if (!e.isExpense || _isFixed(e.tx)) continue;
      total += -e.signed;
    }
    return total;
  }

  /// Analisa o fim de [closedMonth].
  ///
  /// [amount] limita quanto aplicar nas opções de sobra (padrão: tudo o
  /// que está livre). [cutPercent] é o corte dos gastos variáveis
  /// sugerido no déficit.
  MonthEndAnalysis analyze(
    YearMonth closedMonth, {
    Money minimumReserve = Money.zero,
    List<SavingsGoal> goals = const [],
    List<DebtContract> debts = const [],
    List<RenegotiationOffer> offers = const [],
    Money? amount,
    int cutPercent = 10,
    int horizon = 6,
  }) {
    final totals = engine.monthTotals(ProjectionFilter.none, closedMonth);
    final first = firstOpenMonth();
    final planMonth = closedMonth.next > first ? closedMonth.next : first;
    final windowEnd = planMonth.lastDay;
    final obligations = obligationsUntil(windowEnd);
    final cash = engine.currentBalance;
    final committed = obligations.map((o) => o.amount).sum();
    final available = cash - committed - minimumReserve;
    final range = MonthRange(first, first.add(horizon - 1));
    final projection = engine.projection(range).columns;

    final shortfalls = <ShortfallMonth>[
      for (final c in projection)
        if (c.accumulated < minimumReserve)
          ShortfallMonth(
            c.month,
            c.accumulated,
            minimumReserve - c.accumulated,
            contributors(c.month),
          ),
    ];

    final scenario = totals.net.isNegative || shortfalls.isNotEmpty
        ? MonthEndScenario.shortfall
        : available.isPositive
        ? MonthEndScenario.surplus
        : MonthEndScenario.committed;

    final free = available.isNegative ? Money.zero : available;
    var use = amount == null ? free : Money(math.min(amount.cents, free.cents));
    if (use.isNegative) use = Money.zero;

    final options = <MonthEndOption>[];
    final now = first;
    final reserveNote = minimumReserve.isZero
        ? 'Reserva mínima não definida: tudo acima dos compromissos conta como livre.'
        : 'Reserva mínima de ${minimumReserve.formatVisible()} já descontada.';

    // ----- Manter em caixa: sempre aparece, é a referência.
    options.add(
      MonthEndOption(
        kind: MonthEndOptionKind.keepCash,
        title: 'Manter o dinheiro em conta',
        why: scenario == MonthEndScenario.surplus
            ? 'Deixa ${use.formatVisible()} livres para imprevistos no mês seguinte. É a base para comparar as outras opções.'
            : 'Não mexe em nada: os compromissos já usam o caixa. É a base para comparar as outras opções.',
        assumptions: [reserveNote],
      ),
    );

    if (scenario != MonthEndScenario.shortfall && use.isPositive) {
      final be = BudgetEngine(engine);
      final active = goals.where((g) => !g.archived).toList();
      bool isReserve(SavingsGoal g) => g.name.toLowerCase().contains('reserva');
      // ----- Reserva.
      final reserveGoal = active.where(isReserve).firstOrNull;
      final reserveLeft = reserveGoal == null
          ? null
          : be.goal(reserveGoal).remaining;
      if (reserveGoal == null || reserveLeft!.isPositive) {
        final v = reserveLeft == null
            ? use
            : Money(math.min(use.cents, reserveLeft.cents));
        options.add(
          MonthEndOption(
            kind: MonthEndOptionKind.reserve,
            title: reserveGoal == null
                ? 'Começar uma reserva de emergência'
                : 'Reforçar ${reserveGoal.name}',
            why: reserveGoal == null
                ? 'Você ainda não tem uma meta de reserva. Separar ${v.formatVisible()} protege o caixa de imprevistos.'
                : 'Faltam ${reserveLeft!.formatVisible()} para completar a reserva.',
            upfront: v,
            deltas: {now: -v},
            targetId: reserveGoal?.id,
            assumptions: [
              'O valor sai do caixa livre e fica guardado na meta.',
              reserveNote,
            ],
          ),
        );
      }
      // ----- Metas.
      for (final g in active.where((g) => !isReserve(g))) {
        final st = be.goal(g);
        if (st.reached || st.remaining.cents <= 0) continue;
        final v = Money(math.min(use.cents, st.remaining.cents));
        final needed = st.monthlyNeeded;
        options.add(
          MonthEndOption(
            kind: MonthEndOptionKind.goal,
            title: 'Guardar para ${g.name}',
            why:
                'Faltam ${st.remaining.formatVisible()} para a meta'
                '${needed == null ? '' : ' (${needed.formatVisible()} por mês até o prazo)'}.',
            upfront: v,
            deltas: {now: -v},
            targetId: g.id,
            assumptions: [
              'O valor sai do caixa livre e fica guardado na meta.',
            ],
          ),
        );
      }
    }

    // ----- Dívidas: na sobra e no caixa comprometido (com o que sobrar).
    if (scenario != MonthEndScenario.shortfall) {
      for (final d in debts) {
        options.add(_debtOption(d, use, now, range, scenario));
      }
    }

    // ----- Déficit / falta de caixa.
    if (scenario == MonthEndScenario.shortfall) {
      final months = range.months.toList();
      // Cortar gastos variáveis.
      final cut = <YearMonth, Money>{};
      for (final m in months) {
        final d = discretionaryIn(m);
        final v = Money((d.cents * cutPercent / 100).round());
        if (v.isPositive) cut[m] = v;
      }
      if (cut.isNotEmpty) {
        final monthly = cut.values.map((v) => v).sum();
        options.add(
          MonthEndOption(
            kind: MonthEndOptionKind.cutDiscretionary,
            title: 'Cortar $cutPercent% dos gastos variáveis',
            why:
                'Compras avulsas e no cartão (sem recorrência nem parcela) somam '
                '${Money((monthly.cents * 100 / cutPercent).round()).formatVisible()} '
                'nos próximos $horizon meses. Cortar $cutPercent% libera '
                '${monthly.formatVisible()} no período.',
            deltas: cut,
            monthlyRelief: Money((monthly.cents / cut.length).round()),
            assumptions: [
              'Estimativa: o corte vale para os gastos variáveis já previstos.',
              'Nada é alterado nos lançamentos; o plano fica registrado.',
            ],
          ),
        );
      }
      // Mudar data de pagamento: maiores pendências de conta no primeiro
      // mês com falta, que ainda não venceram e podem ir para o mês seguinte.
      final firstShort = shortfalls.isEmpty ? null : shortfalls.first.month;
      if (firstShort != null) {
        final cands =
            engine
                .transactionsUntil(firstShort.lastDay)
                .where(
                  (t) =>
                      t.type == TransactionType.expense &&
                      t.cardId == null &&
                      t.installmentGroupId == null &&
                      t.status == TransactionStatus.pending &&
                      YearMonth.of(t.date) == firstShort &&
                      !t.date.isBefore(today) &&
                      !isClosed(firstShort.next),
                )
                .toList()
              ..sort((a, b) => b.amount.compareTo(a.amount));
        for (final t in cands.take(2)) {
          final to = Dates.clampedDate(
            firstShort.next.year,
            firstShort.next.month,
            t.date.day,
          );
          options.add(
            MonthEndOption(
              kind: MonthEndOptionKind.postpone,
              title: 'Passar “${t.description}” para ${Dates.format(to)}',
              why:
                  '${firstShort.longLabel} fica abaixo da reserva. Pagar ${t.amount.formatVisible()} '
                  'no mês seguinte alivia esse mês (combine a nova data com quem recebe).',
              deltas: {firstShort: t.amount, firstShort.next: -t.amount},
              targetId: t.id,
              postponed: [t],
              postponedTo: [to],
              assumptions: [
                'Só vale se o credor aceitar a nova data, sem multa.',
              ],
            ),
          );
        }
      }
      // Renegociação.
      for (final o in offers) {
        final d = <YearMonth, Money>{};
        for (var k = 0; k < months.length; k++) {
          final oldPays = k < o.currentRemainingMonths;
          final newPays = k < o.newMonths;
          var v = Money.zero;
          if (oldPays) v += o.currentInstallment;
          if (newPays) v -= o.newInstallment;
          if (k == 0) v -= o.upfrontCost;
          if (!v.isZero) d[months[k]] = v;
        }
        options.add(
          MonthEndOption(
            kind: MonthEndOptionKind.renegotiate,
            title: 'Renegociar ${o.name}',
            why: o.extraCost.isPositive
                ? 'A parcela cai ${o.monthlyRelief.formatVisible()}, mas o total sobe ${o.extraCost.formatVisible()}.'
                : 'A parcela cai ${o.monthlyRelief.formatVisible()} e o total cai ${(-o.extraCost).formatVisible()}.',
            upfront: o.upfrontCost,
            deltas: d,
            monthlyRelief: o.monthlyRelief,
            totalCostChange: o.extraCost,
            isLenderQuote: o.isLenderQuote,
            offer: o,
            assumptions: [
              'Total atual: ${o.currentInstallment.formatVisible()} × ${o.currentRemainingMonths} = ${o.currentTotal.formatVisible()}.',
              'Proposta: ${o.newInstallment.formatVisible()} × ${o.newMonths}'
                  '${o.upfrontCost.isZero ? '' : ' + ${o.upfrontCost.formatVisible()} de custos'}'
                  ' = ${o.newTotal.formatVisible()}.',
            ],
          ),
        );
      }
    }

    return MonthEndAnalysis(
      closedMonth: closedMonth,
      isClosed: isClosed(closedMonth),
      income: totals.income,
      expenses: totals.expenses,
      cash: cash,
      minimumReserve: minimumReserve,
      windowEnd: windowEnd,
      obligations: obligations,
      expectedIncome: _expectedIncomeUntil(windowEnd),
      projection: projection,
      shortfalls: shortfalls,
      scenario: scenario,
      options: options,
      calculatedAt: today,
    );
  }

  MonthEndOption _debtOption(
    DebtContract d,
    Money use,
    YearMonth now,
    MonthRange range,
    MonthEndScenario scenario,
  ) {
    // Mesmo valor nas opções do contrato, pelo motor de dívidas.
    final all = compareDebts([d], use, asOf: today);
    DebtEstimate? of(PrepayOption o) =>
        all.where((e) => e.option == o && e.ok).firstOrNull;
    final term = of(PrepayOption.reduceTerm);
    final pay = of(PrepayOption.reducePayment);
    final best =
        term ??
        pay ??
        of(PrepayOption.payoff) ??
        of(PrepayOption.lastInstallments);
    if (best == null || use.isZero) {
      final missing = {for (final e in all) ...e.missing.map((f) => f.label)}
          .toList();
      final blocked = all.map((e) => e.blocked).nonNulls.firstOrNull;
      return MonthEndOption(
        kind: MonthEndOptionKind.debtPrepay,
        title: 'Amortizar ${d.name}',
        why: use.isZero
            ? 'Não há sobra livre para antecipar agora.'
            : missing.isNotEmpty
            ? 'Faltam dados do contrato para estimar: ${missing.join(', ')}. '
                  'Complete em Dívidas e contratos ou informe a cotação do credor.'
            : blocked ?? 'O contrato não permite antecipar.',
        missingFields: use.isZero
            ? const ['valor livre para amortizar']
            : missing.isEmpty
            ? [blocked ?? 'contrato não permite antecipar']
            : missing,
        targetId: d.id,
      );
    }
    final r = best.result!;
    // Efeito no caixa: saída agora e parcelas que mudam. Nada cai em mês
    // fechado: o que seria antes do primeiro mês aberto vai para ele.
    final deltas = <YearMonth, Money>{};
    r.cashDelta().forEach((m, v) {
      final k = m < now ? now : m;
      if (k > range.to) return;
      deltas[k] = (deltas[k] ?? Money.zero) + v;
    });
    final source = r.isLenderQuote ? 'cotação do credor' : 'estimativa do app';
    final lower = pay?.result;
    return MonthEndOption(
      kind: MonthEndOptionKind.debtPrepay,
      title: 'Amortizar ${d.name}',
      why:
          '${scenario == MonthEndScenario.committed ? 'Com o que sobra depois dos compromissos, ' : ''}'
          '${best.option.label.toLowerCase()} com ${r.outflow.formatVisible()}: '
          '${r.monthsBefore} → ${r.monthsAfter} parcelas, economia de '
          '${r.totalSaved.formatVisible()} ($source).'
          '${lower == null || identical(lower, r) ? '' : ' Se preferir parcela menor: ${lower.paymentAfter.formatVisible()} (−${lower.monthlyRelief.formatVisible()}/mês).'}',
      upfront: r.outflow,
      deltas: deltas,
      interestSavings: r.totalSaved,
      monthlyRelief: lower?.monthlyRelief ?? r.monthlyRelief,
      targetId: d.id,
      isLenderQuote: r.isLenderQuote,
      debtEstimate: best,
      assumptions: [
        ...r.assumptions,
        ...r.warnings,
        'Só planejamento: nenhum pagamento é feito e o contrato não muda.',
      ],
    );
  }
}
