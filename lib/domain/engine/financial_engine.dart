import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/entities.dart';
import 'billing_cycle.dart';
import 'projection_filter.dart';
import 'recurrence.dart';

export 'projection_filter.dart';

/// Foto imutável dos dados de um usuário, entrada do motor de cálculo.
class FinanceData {
  final List<Account> accounts;
  final List<CreditCard> cards;
  final List<FinCategory> categories;
  final List<Project> projects;
  final List<FinTransaction> transactions;
  final List<RecurringRule> recurringRules;
  final List<InstallmentGroup> installmentGroups;
  final List<InvoicePayment> invoicePayments;
  final AppSettings settings;

  late final Map<String, Account> accountById = {
    for (final a in accounts) a.id: a,
  };
  late final Map<String, CreditCard> cardById = {
    for (final c in cards) c.id: c,
  };
  late final Map<String, FinCategory> categoryById = {
    for (final c in categories) c.id: c,
  };
  late final Map<String, Project> projectById = {
    for (final p in projects) p.id: p,
  };
  late final Map<String, RecurringRule> ruleById = {
    for (final r in recurringRules) r.id: r,
  };
  late final Map<String, InstallmentGroup> groupById = {
    for (final g in installmentGroups) g.id: g,
  };

  FinanceData({
    this.accounts = const [],
    this.cards = const [],
    this.categories = const [],
    this.projects = const [],
    this.transactions = const [],
    this.recurringRules = const [],
    this.installmentGroups = const [],
    this.invoicePayments = const [],
    this.settings = const AppSettings(),
  });
}

/// Evento reconhecido em um mês, com valor assinado (+ receita, − despesa).
class RecognizedEvent {
  final FinTransaction tx;
  final YearMonth month;
  final EventSource source;

  /// Receita (+) ou despesa (−). Transferências não são reconhecidas.
  final Money signed;
  const RecognizedEvent(this.tx, this.month, this.source, this.signed);

  bool get isIncome => signed.cents > 0;
  bool get isExpense => signed.cents < 0;
}

class MonthTotals {
  Money income = Money.zero;
  Money expenses = Money.zero; // positivo
  Money transfersNet = Money.zero; // só quando há filtro de conta
  Money get net => income - expenses;
}

class ProjectionColumn {
  final YearMonth month;
  final Money income;
  final Money expenses;
  final Money transfersNet;
  final Money opening;
  final Money accumulated;
  final bool isPast;
  final bool isCurrent;
  const ProjectionColumn({
    required this.month,
    required this.income,
    required this.expenses,
    required this.transfersNet,
    required this.opening,
    required this.accumulated,
    required this.isPast,
    required this.isCurrent,
  });
  Money get net => income - expenses;
}

class ProjectionResult {
  final List<ProjectionColumn> columns;
  final Money openingBalance;
  final bool openingIsAccountBalance;
  final bool showsTransfers;
  const ProjectionResult(
    this.columns,
    this.openingBalance,
    this.openingIsAccountBalance,
    this.showsTransfers,
  );

  Money get totalIncome => columns.map((c) => c.income).sum();
  Money get totalExpenses => columns.map((c) => c.expenses).sum();
}

/// Fatura calculada de um cartão.
class Invoice {
  final CreditCard card;
  final YearMonth month; // mês de fechamento
  final DateTime closingDate;
  final DateTime dueDate;
  final List<FinTransaction> transactions;
  final List<InvoicePayment> payments;
  final Money total;
  final Money paid;
  final InvoiceStatus status;

  const Invoice({
    required this.card,
    required this.month,
    required this.closingDate,
    required this.dueDate,
    required this.transactions,
    required this.payments,
    required this.total,
    required this.paid,
    required this.status,
  });

  Money get remaining {
    final r = total - paid;
    return r.isNegative ? Money.zero : r;
  }

  String get key => month.key;
  bool get isSettled => status == InvoiceStatus.paid;
}

class ProjectSummary {
  final Project project;
  final Money actual; // despesas concluídas
  final Money planned; // despesas futuras previstas (não concluídas)
  final int transactionCount;
  const ProjectSummary(
    this.project,
    this.actual,
    this.planned,
    this.transactionCount,
  );
  Money get remaining => project.budget - actual;
  Money get forecastRemaining => project.budget - actual - planned;
  double get progress => project.budget.cents <= 0
      ? 0
      : (actual.cents / project.budget.cents).clamp(0, 1.5).toDouble();
}

/// Item da lista de próximos vencimentos.
class UpcomingItem {
  final DateTime date;
  final String description;
  final Money amount;
  final bool isIncome;
  final String where;
  final String statusLabel;
  final bool overdue;
  final FinTransaction? tx;
  final Invoice? invoice;
  const UpcomingItem({
    required this.date,
    required this.description,
    required this.amount,
    required this.isIncome,
    required this.where,
    required this.statusLabel,
    required this.overdue,
    this.tx,
    this.invoice,
  });
}

/// Motor central de cálculos financeiros.
///
/// Todas as telas obtêm valores daqui, garantindo as mesmas regras:
/// * Transferências nunca são receita/despesa.
/// * Pagamento de fatura liquida o passivo do cartão e **não** é despesa.
/// * Compras no cartão são despesa uma única vez, no mês definido por
///   [CardExpenseBasis] (vencimento da fatura, por padrão).
/// * Ocorrências recorrentes são geradas virtualmente e deduplicadas contra
///   lançamentos já persistidos (chave regra + data da ocorrência).
/// * Valores em centavos inteiros (sem ponto flutuante).
class FinancialEngine {
  final FinanceData data;
  final DateTime today;

  FinancialEngine(this.data, {DateTime? today})
    : today = Dates.dateOnly(today ?? DateTime.now());

  YearMonth get currentMonth => YearMonth.of(today);

  // ---------------------------------------------------------------------------
  // Expansão de recorrências

  final Map<String, List<FinTransaction>> _expandCache = {};

  /// Transações persistidas + ocorrências virtuais de recorrências até
  /// [until] (inclusive).
  List<FinTransaction> transactionsUntil(DateTime until) {
    final key = Dates.toIso(until);
    return _expandCache.putIfAbsent(key, () {
      final persisted = data.transactions;
      final materialized = <String>{
        for (final t in persisted)
          if (t.recurringId != null && t.occurrenceDate != null)
            '${t.recurringId}|${Dates.toIso(t.occurrenceDate!)}',
      };
      final result = <FinTransaction>[...persisted];
      for (final rule in data.recurringRules) {
        for (final d in Recurrence.occurrences(rule, rule.startDate, until)) {
          final k = '${rule.id}|${Dates.toIso(d)}';
          if (materialized.contains(k)) continue;
          result.add(virtualOccurrence(rule, d));
        }
      }
      return result;
    });
  }

  static FinTransaction virtualOccurrence(RecurringRule rule, DateTime d) =>
      FinTransaction(
        id: 'v:${rule.id}:${Dates.toIso(d)}',
        type: rule.type,
        amount: rule.amount,
        description: rule.description,
        categoryId: rule.categoryId,
        date: d,
        accountId: rule.accountId,
        cardId: rule.cardId,
        projectId: rule.projectId,
        notes: rule.notes,
        status: TransactionStatus.planned,
        recurringId: rule.id,
        occurrenceDate: d,
        isVirtual: true,
        createdAt: rule.createdAt,
        updatedAt: rule.updatedAt,
      );

  // ---------------------------------------------------------------------------
  // Reconhecimento

  /// Mês em que a transação é reconhecida como receita/despesa, ou `null`
  /// para transferências e cartões inexistentes.
  YearMonth? recognitionMonth(FinTransaction tx) {
    if (tx.isTransfer) return null;
    if (tx.cardId != null) {
      final card = data.cardById[tx.cardId];
      if (card == null) return null;
      final invoice = BillingCycle.invoiceForTransaction(card, tx);
      if (data.settings.cardExpenseBasis == CardExpenseBasis.invoiceDue) {
        return YearMonth.of(BillingCycle.dueDate(card, invoice));
      }
      final offset = tx.isInstallment ? (tx.installmentNumber ?? 1) - 1 : 0;
      return YearMonth.of(tx.date).add(offset);
    }
    return YearMonth.of(tx.date);
  }

  /// Data efetiva de impacto no caixa (vencimento da fatura para cartão).
  DateTime cashDate(FinTransaction tx) {
    if (tx.cardId != null) {
      final card = data.cardById[tx.cardId];
      if (card != null) {
        return BillingCycle.dueDate(
          card,
          BillingCycle.invoiceForTransaction(card, tx),
        );
      }
    }
    return tx.date;
  }

  /// Data em que o lançamento aparece na lista de transações: a parcela N de
  /// uma compra no cartão aparece N − 1 meses após a compra.
  DateTime listDate(FinTransaction tx) {
    if (tx.cardId != null && tx.isInstallment) {
      return Dates.addMonths(
        tx.date,
        (tx.installmentNumber ?? 1) - 1,
        anchorDay: tx.date.day,
      );
    }
    return tx.date;
  }

  /// Lançamento já realizado: concluído, ou compra no cartão cuja fatura já
  /// fechou (parcelas faturadas contam como gasto efetivo).
  bool isRealized(FinTransaction tx) {
    if (tx.status == TransactionStatus.cancelled || tx.isVirtual) return false;
    if (tx.status == TransactionStatus.completed) return true;
    final card = data.cardById[tx.cardId];
    if (card == null) return false;
    final inv = BillingCycle.invoiceForTransaction(card, tx);
    return !BillingCycle.closingDate(card, inv).isAfter(today);
  }

  EventSource sourceOf(FinTransaction tx) {
    if (tx.isInstallment) return EventSource.installment;
    if (tx.isRecurring) return EventSource.recurring;
    if (tx.cardId != null) return EventSource.card;
    return EventSource.other;
  }

  Set<String> _expandCategories(Set<String> ids) {
    if (ids.isEmpty) return ids;
    final out = {...ids};
    for (final c in data.categories) {
      if (c.parentId != null && ids.contains(c.parentId)) out.add(c.id);
    }
    return out;
  }

  bool Function(FinTransaction) _matcher(ProjectionFilter f) {
    final cats = _expandCategories(f.categoryIds);
    return (tx) {
      if (!f.statuses.contains(tx.status)) return false;
      if (f.types.isNotEmpty && !f.types.contains(tx.type)) return false;
      if (f.hasLocationFilter) {
        final inAccount =
            f.accountIds.isNotEmpty &&
            (f.accountIds.contains(tx.accountId) ||
                f.accountIds.contains(tx.destinationAccountId));
        final inCard = f.cardIds.isNotEmpty && f.cardIds.contains(tx.cardId);
        if (!inAccount && !inCard) return false;
      }
      if (cats.isNotEmpty && !cats.contains(tx.categoryId)) return false;
      if (f.projectIds.isNotEmpty && !f.projectIds.contains(tx.projectId)) {
        return false;
      }
      if (f.sources.isNotEmpty && !f.sources.contains(sourceOf(tx))) {
        return false;
      }
      return true;
    };
  }

  /// Eventos reconhecidos (receitas e despesas) até o fim de [until],
  /// aplicando o filtro.
  Iterable<RecognizedEvent> recognizedEvents(
    ProjectionFilter filter,
    YearMonth until,
  ) sync* {
    final match = _matcher(filter);
    // Compras de cartão podem ser reconhecidas meses depois da data da
    // compra; por isso expandimos recorrências até o fim do mês desejado.
    for (final tx in transactionsUntil(until.lastDay)) {
      if (tx.isTransfer || !match(tx)) continue;
      final m = recognitionMonth(tx);
      if (m == null || m > until) continue;
      final signed = tx.type == TransactionType.income ? tx.amount : -tx.amount;
      yield RecognizedEvent(tx, m, sourceOf(tx), signed);
    }
  }

  /// Eventos de um único mês (base do drill-down).
  List<RecognizedEvent> monthEvents(ProjectionFilter filter, YearMonth month) =>
      recognizedEvents(filter, month).where((e) => e.month == month).toList()
        ..sort((a, b) => a.tx.date.compareTo(b.tx.date));

  MonthTotals monthTotals(ProjectionFilter filter, YearMonth month) {
    final t = MonthTotals();
    for (final e in monthEvents(filter, month)) {
      if (e.isIncome) {
        t.income += e.signed;
      } else {
        t.expenses += -e.signed;
      }
    }
    return t;
  }

  // ---------------------------------------------------------------------------
  // Projeção mensal (matriz)

  /// Matriz de projeção.
  ///
  /// Resultado = Receitas − Despesas; Acumulado = anterior + resultado
  /// (+ transferências líquidas quando filtrado por conta).
  ///
  /// Saldo inicial: [openingOverride] se informado; senão, quando o filtro
  /// representa saldo de contas, soma dos saldos iniciais das contas + todo
  /// o resultado reconhecido antes do primeiro mês; caso contrário, zero.
  ProjectionResult projection(
    MonthRange range, {
    ProjectionFilter filter = ProjectionFilter.none,
    Money? openingOverride,
  }) {
    final buckets = <YearMonth, MonthTotals>{
      for (final m in range.months) m: MonthTotals(),
    };
    final accountScoped = filter.isBalanceScoped;
    var prior = Money.zero;

    for (final e in recognizedEvents(filter, range.to)) {
      if (e.month < range.from) {
        prior += e.signed;
        continue;
      }
      final b = buckets[e.month]!;
      if (e.isIncome) {
        b.income += e.signed;
      } else {
        b.expenses += -e.signed;
      }
    }

    // Transferências só alteram o saldo quando olhamos contas específicas.
    final showTransfers = accountScoped && filter.accountIds.isNotEmpty;
    if (showTransfers) {
      final match = _matcher(filter);
      for (final tx in transactionsUntil(range.to.lastDay)) {
        if (!tx.isTransfer || !match(tx)) continue;
        final m = YearMonth.of(tx.date);
        if (m > range.to) continue;
        var delta = Money.zero;
        if (filter.accountIds.contains(tx.destinationAccountId)) {
          delta += tx.amount;
        }
        if (filter.accountIds.contains(tx.accountId)) delta -= tx.amount;
        if (m < range.from) {
          prior += delta;
        } else {
          buckets[m]!.transfersNet += delta;
        }
      }
    }

    Money opening;
    if (openingOverride != null) {
      opening = openingOverride;
    } else if (accountScoped) {
      final accounts = filter.hasLocationFilter
          ? data.accounts.where((a) => filter.accountIds.contains(a.id))
          : data.accounts;
      opening = accounts.map((a) => a.initialBalance).sum() + prior;
    } else {
      opening = Money.zero;
    }

    final cols = <ProjectionColumn>[];
    var running = opening;
    for (final m in range.months) {
      final b = buckets[m]!;
      final start = running;
      running = running + b.net + b.transfersNet;
      cols.add(
        ProjectionColumn(
          month: m,
          income: b.income,
          expenses: b.expenses,
          transfersNet: b.transfersNet,
          opening: start,
          accumulated: running,
          isPast: m < currentMonth,
          isCurrent: m == currentMonth,
        ),
      );
    }
    return ProjectionResult(
      cols,
      opening,
      openingOverride == null && accountScoped,
      showTransfers,
    );
  }

  // ---------------------------------------------------------------------------
  // Saldos reais

  /// Saldo real da conta: saldo inicial + movimentações **concluídas**
  /// (receitas, despesas, transferências) − pagamentos de fatura.
  Money accountBalance(String accountId) {
    final acc = data.accountById[accountId];
    var bal = acc?.initialBalance ?? Money.zero;
    for (final t in data.transactions) {
      if (t.status != TransactionStatus.completed) continue;
      switch (t.type) {
        case TransactionType.income:
          if (t.accountId == accountId) bal += t.amount;
        case TransactionType.expense:
          if (t.accountId == accountId) bal -= t.amount;
        case TransactionType.transfer:
          if (t.accountId == accountId) bal -= t.amount;
          if (t.destinationAccountId == accountId) bal += t.amount;
      }
    }
    for (final p in data.invoicePayments) {
      if (p.accountId == accountId) bal -= p.amount;
    }
    return bal;
  }

  /// Saldo atual somado das contas ativas.
  Money get currentBalance => data.accounts
      .where((a) => a.active)
      .map((a) => accountBalance(a.id))
      .sum();

  /// Compromissos em aberto até o fim de [month]: despesas de conta não
  /// concluídas + saldo devedor das faturas que vencem até lá.
  Money openCommitmentsUntil(YearMonth month) {
    var total = Money.zero;
    for (final t in transactionsUntil(month.lastDay)) {
      if (t.cardId != null || t.type != TransactionType.expense) continue;
      if (t.status == TransactionStatus.completed ||
          t.status == TransactionStatus.cancelled) {
        continue;
      }
      if (YearMonth.of(t.date) <= month) total += t.amount;
    }
    for (final card in data.cards) {
      for (final inv in invoicesForCard(card)) {
        if (YearMonth.of(inv.dueDate) <= month) total += inv.remaining;
      }
    }
    return total;
  }

  /// Saldo disponível = saldo atual − compromissos em aberto do mês corrente.
  Money get availableBalance =>
      currentBalance - openCommitmentsUntil(currentMonth);

  // ---------------------------------------------------------------------------
  // Faturas

  /// Faturas de um cartão, da primeira compra até a última parcela futura
  /// (ou até [until]). Recorrências no cartão são incluídas até [until].
  List<Invoice> invoicesForCard(CreditCard card, {YearMonth? until}) {
    final horizon = until ?? currentMonth.add(1);
    final byMonth = <YearMonth, List<FinTransaction>>{};
    for (final t in transactionsUntil(horizon.lastDay)) {
      if (t.cardId != card.id || t.isTransfer) continue;
      if (t.status == TransactionStatus.cancelled) continue;
      final m = BillingCycle.invoiceForTransaction(card, t);
      if (t.isVirtual && m > horizon) continue;
      byMonth.putIfAbsent(m, () => []).add(t);
    }
    final payments = <YearMonth, List<InvoicePayment>>{};
    for (final p in data.invoicePayments) {
      if (p.cardId != card.id) continue;
      payments.putIfAbsent(YearMonth.parse(p.invoiceKey), () => []).add(p);
    }
    final months = {
      ...byMonth.keys,
      ...payments.keys,
      BillingCycle.currentInvoice(card, today),
    }.toList()..sort();
    return [
      for (final m in months)
        buildInvoice(card, m, byMonth[m] ?? const [], payments[m] ?? const []),
    ];
  }

  Invoice invoice(CreditCard card, YearMonth month) {
    final all = invoicesForCard(
      card,
      until: month > currentMonth.add(1) ? month : null,
    );
    return all.firstWhere(
      (i) => i.month == month,
      orElse: () => buildInvoice(card, month, const [], const []),
    );
  }

  Invoice buildInvoice(
    CreditCard card,
    YearMonth m,
    List<FinTransaction> txs,
    List<InvoicePayment> pays,
  ) {
    var total = Money.zero;
    for (final t in txs) {
      total += t.type == TransactionType.income ? -t.amount : t.amount;
    }
    final paid = pays.map((p) => p.amount).sum();
    final closing = BillingCycle.closingDate(card, m);
    final due = BillingCycle.dueDate(card, m);
    final current = BillingCycle.currentInvoice(card, today);

    InvoiceStatus status;
    if (m > current) {
      status = InvoiceStatus.future;
    } else if (m == current) {
      status = (paid >= total && total.isPositive)
          ? InvoiceStatus.paid
          : InvoiceStatus.open;
    } else if (paid >= total) {
      status = InvoiceStatus.paid;
    } else if (today.isAfter(due)) {
      status = InvoiceStatus.overdue;
    } else if (paid.isPositive) {
      status = InvoiceStatus.partial;
    } else {
      status = InvoiceStatus.closed;
    }
    final sorted = [...txs]..sort((a, b) => b.date.compareTo(a.date));
    return Invoice(
      card: card,
      month: m,
      closingDate: closing,
      dueDate: due,
      transactions: sorted,
      payments: pays,
      total: total,
      paid: paid,
      status: status,
    );
  }

  /// Limite disponível = limite − saldo devedor de todas as faturas
  /// (inclui parcelas futuras já contratadas; exclui recorrências ainda não
  /// lançadas).
  Money availableLimit(CreditCard card) {
    var used = Money.zero;
    for (final t in data.transactions) {
      if (t.cardId != card.id || t.status == TransactionStatus.cancelled) {
        continue;
      }
      used += t.type == TransactionType.income ? -t.amount : t.amount;
    }
    for (final p in data.invoicePayments) {
      if (p.cardId == card.id) used -= p.amount;
    }
    return card.limit - used;
  }

  // ---------------------------------------------------------------------------
  // Próximos vencimentos

  List<UpcomingItem> upcoming({int days = 30, int limit = 10}) {
    final end = today.add(Duration(days: days));
    final items = <UpcomingItem>[];
    for (final t in transactionsUntil(end)) {
      if (t.cardId != null) continue; // entram pela fatura
      if (t.status == TransactionStatus.completed ||
          t.status == TransactionStatus.cancelled) {
        continue;
      }
      if (t.date.isAfter(end)) continue;
      // Pendências antigas aparecem como atrasadas (até 60 dias).
      if (t.date.isBefore(today.subtract(const Duration(days: 60)))) continue;
      items.add(
        UpcomingItem(
          date: t.date,
          description: t.description,
          amount: t.amount,
          isIncome: t.type == TransactionType.income,
          where: locationLabel(t),
          statusLabel: t.status.label,
          overdue: t.date.isBefore(today),
          tx: t,
        ),
      );
    }
    for (final card in data.cards.where((c) => c.active)) {
      for (final inv in invoicesForCard(card)) {
        if (inv.remaining.isZero || inv.dueDate.isAfter(end)) continue;
        if (inv.dueDate.isBefore(today.subtract(const Duration(days: 60)))) {
          continue;
        }
        items.add(
          UpcomingItem(
            date: inv.dueDate,
            description: 'Fatura ${card.name} (${inv.month.shortLabel})',
            amount: inv.remaining,
            isIncome: false,
            where: card.name,
            statusLabel: inv.status.label,
            overdue: inv.dueDate.isBefore(today),
            invoice: inv,
          ),
        );
      }
    }
    items.sort((a, b) => a.date.compareTo(b.date));
    return items.take(limit).toList();
  }

  // ---------------------------------------------------------------------------
  // Indicadores

  /// Total previsto de despesas recorrentes reconhecidas no mês.
  Money recurringExpensesIn(YearMonth month) => monthEvents(
    const ProjectionFilter(
      types: {TransactionType.expense},
      sources: {EventSource.recurring},
    ),
    month,
  ).map((e) => -e.signed).sum();

  /// Parcelas ainda não pagas/faturadas (compromissos futuros).
  ({Money total, int count}) futureInstallments() {
    var total = Money.zero;
    var count = 0;
    for (final t in data.transactions) {
      if (!t.isInstallment || t.status == TransactionStatus.cancelled) continue;
      if (t.status == TransactionStatus.completed && t.cardId == null) continue;
      final cash = cashDate(t);
      if (cash.isAfter(today)) {
        total += t.amount;
        count++;
      }
    }
    return (total: total, count: count);
  }

  // ---------------------------------------------------------------------------
  // Projetos

  ProjectSummary projectSummary(Project p) {
    var actual = Money.zero;
    var planned = Money.zero;
    var count = 0;
    final horizon = p.endDate ?? Dates.addMonths(today, 12);
    for (final t in transactionsUntil(horizon)) {
      if (t.projectId != p.id || t.type != TransactionType.expense) continue;
      if (t.status == TransactionStatus.cancelled) continue;
      count++;
      if (isRealized(t)) {
        actual += t.amount;
      } else {
        planned += t.amount;
      }
    }
    return ProjectSummary(p, actual, planned, count);
  }

  List<FinTransaction> projectTransactions(Project p) {
    final horizon = p.endDate ?? Dates.addMonths(today, 12);
    return transactionsUntil(horizon).where((t) => t.projectId == p.id).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // ---------------------------------------------------------------------------
  // Rótulos

  String locationLabel(FinTransaction t) {
    if (t.cardId != null) return data.cardById[t.cardId]?.name ?? 'Cartão';
    if (t.isTransfer) {
      final from = data.accountById[t.accountId]?.name ?? '?';
      final to = data.accountById[t.destinationAccountId]?.name ?? '?';
      return '$from → $to';
    }
    return data.accountById[t.accountId]?.name ?? 'Sem conta';
  }

  String categoryLabel(String? id) {
    final c = data.categoryById[id];
    if (c == null) return 'Sem categoria';
    final parent = data.categoryById[c.parentId];
    return parent == null ? c.name : '${parent.name} › ${c.name}';
  }

  /// Categoria raiz (para agrupamentos).
  String rootCategoryId(String? id) {
    final c = data.categoryById[id];
    if (c == null) return '';
    return c.parentId ?? c.id;
  }
}
