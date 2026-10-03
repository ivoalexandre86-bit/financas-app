import 'dart:math';

import '../core/dates.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../domain/engine/billing_cycle.dart';
import '../domain/engine/installments.dart';
import '../domain/engine/recurrence.dart';
import '../domain/models/entities.dart';
import 'default_categories.dart';
import 'finance_repository.dart';

/// Gera dados de **exemplo** realistas, relativos à data atual, para a conta
/// de demonstração. Nunca é aplicado a contas reais.
List<WriteOp> buildSampleData({DateTime? today}) {
  final now = Dates.dateOnly(today ?? DateTime.now());
  final rnd = Random(42);
  final ops = <WriteOp>[];
  final txs = <FinTransaction>[];
  final cm = YearMonth.of(now);
  final start = cm.add(-5).firstDay;

  Money m(num reais) => Money((reais * 100).round());

  // Categorias
  for (final c in defaultCategories()) {
    ops.add(WriteOp.put(Coll.categories, c.id, c.toJson()));
  }

  // Contas
  final itau = Account(
    id: 'acc_itau',
    name: 'Itaú Corrente',
    institution: 'Itaú Unibanco',
    type: AccountType.checking,
    initialBalance: m(6800),
    color: 0xFFEC7000,
  );
  final nu = Account(
    id: 'acc_nubank',
    name: 'Nubank Conta',
    institution: 'Nu Pagamentos',
    type: AccountType.digital,
    initialBalance: m(2150),
    color: 0xFF820AD1,
  );
  final poup = Account(
    id: 'acc_savings',
    name: 'Poupança',
    institution: 'Itaú Unibanco',
    type: AccountType.savings,
    initialBalance: m(12000),
    color: 0xFF15803D,
  );
  final cash = Account(
    id: 'acc_cash',
    name: 'Carteira',
    type: AccountType.cash,
    initialBalance: m(250),
    color: 0xFF64748B,
  );
  for (final a in [itau, nu, poup, cash]) {
    ops.add(WriteOp.put(Coll.accounts, a.id, a.toJson()));
  }

  // Cartões
  final nuCard = CreditCard(
    id: 'card_nubank',
    name: 'Nubank Ultravioleta',
    bank: 'Nubank',
    brand: 'Mastercard',
    lastFour: '4821',
    limit: m(15000),
    closingDay: 3,
    dueDay: 10,
    paymentAccountId: nu.id,
    color: 0xFF820AD1,
  );
  final itauCard = CreditCard(
    id: 'card_itau',
    name: 'Itaú Personnalité',
    bank: 'Itaú',
    brand: 'Visa',
    lastFour: '1093',
    limit: m(9000),
    closingDay: 25,
    dueDay: 5,
    paymentAccountId: itau.id,
    color: 0xFF1B2A4A,
  );
  for (final c in [nuCard, itauCard]) {
    ops.add(WriteOp.put(Coll.cards, c.id, c.toJson()));
  }

  // Projetos
  final trip = Project(
    id: 'prj_europe',
    name: 'Viagem para Europa',
    description: 'Lisboa, Porto e Madri — 15 dias',
    budget: m(30000),
    startDate: cm.add(-2).firstDay,
    endDate: cm.add(4).lastDay,
    color: 0xFF0D9488,
  );
  final reform = Project(
    id: 'prj_reform',
    name: 'Reforma do escritório',
    description: 'Mesa, cadeira e iluminação',
    budget: m(8000),
    startDate: cm.firstDay,
    endDate: cm.add(2).lastDay,
    color: 0xFFCA8A04,
  );
  for (final p in [trip, reform]) {
    ops.add(WriteOp.put(Coll.projects, p.id, p.toJson()));
  }

  // Regras recorrentes
  RecurringRule rule(
    String id,
    TransactionType type,
    num value,
    String desc,
    String cat,
    int day, {
    String? account,
    String? card,
    RecurrenceFrequency freq = RecurrenceFrequency.monthly,
    DateTime? startAt,
  }) => RecurringRule(
    id: id,
    type: type,
    amount: m(value),
    description: desc,
    categoryId: cat,
    accountId: account,
    cardId: card,
    frequency: freq,
    dayOfMonth: day,
    startDate: startAt ?? start,
  );
  const inc = TransactionType.income;
  const exp = TransactionType.expense;
  final rules = [
    rule(
      'rec_salary',
      inc,
      12500,
      'Salário',
      'cat_salary',
      5,
      account: itau.id,
    ),
    rule(
      'rec_freela',
      inc,
      3200,
      'Projeto freelance (contrato)',
      'cat_freelance',
      20,
      account: nu.id,
      freq: RecurrenceFrequency.quarterly,
    ),
    rule('rec_rent', exp, 2800, 'Aluguel', 'cat_rent', 10, account: itau.id),
    rule(
      'rec_condo',
      exp,
      650,
      'Condomínio',
      'cat_condo',
      10,
      account: itau.id,
    ),
    rule(
      'rec_energy',
      exp,
      235,
      'Conta de energia',
      'cat_energy',
      15,
      account: itau.id,
    ),
    rule(
      'rec_internet',
      exp,
      119.90,
      'Internet fibra',
      'cat_internet',
      20,
      card: nuCard.id,
    ),
    rule(
      'rec_netflix',
      exp,
      55.90,
      'Netflix',
      'cat_subscriptions',
      10,
      card: nuCard.id,
    ),
    rule(
      'rec_spotify',
      exp,
      21.90,
      'Spotify',
      'cat_subscriptions',
      12,
      card: nuCard.id,
    ),
    rule(
      'rec_gym',
      exp,
      119.90,
      'Academia',
      'cat_health',
      7,
      card: itauCard.id,
    ),
    rule(
      'rec_course',
      exp,
      450,
      'Curso de inglês',
      'cat_education',
      8,
      account: nu.id,
    ),
    rule(
      'rec_health',
      exp,
      689,
      'Plano de saúde',
      'cat_health',
      1,
      account: itau.id,
    ),
  ];
  for (final r in rules) {
    ops.add(WriteOp.put(Coll.recurringTransactions, r.id, r.toJson()));
    // Ocorrências passadas confirmadas (materializadas como concluídas).
    for (final d in Recurrence.occurrences(
      r,
      r.startDate,
      now.subtract(const Duration(days: 1)),
    )) {
      txs.add(
        FinTransaction(
          id: newId('tx_'),
          type: r.type,
          amount: r.amount,
          description: r.description,
          categoryId: r.categoryId,
          date: d,
          accountId: r.accountId,
          cardId: r.cardId,
          status: TransactionStatus.completed,
          recurringId: r.id,
          occurrenceDate: d,
        ),
      );
    }
  }

  // Gastos variáveis dos últimos meses
  final variable = <(String, String, num, num, String?)>[
    ('Supermercado', 'cat_groceries', 280, 620, null),
    ('Restaurante', 'cat_restaurants', 60, 210, null),
    ('Uber', 'cat_rides', 18, 55, null),
    ('Posto de combustível', 'cat_fuel', 180, 260, null),
    ('Farmácia', 'cat_health', 35, 140, null),
    ('Cinema', 'cat_leisure', 40, 90, null),
    ('Padaria', 'cat_groceries', 15, 45, 'cash'),
  ];
  for (var d = start; d.isBefore(now); d = d.add(const Duration(days: 1))) {
    for (final (desc, cat, min, max, where) in variable) {
      final chance = switch (cat) {
        'cat_groceries' => where == 'cash' ? 0.12 : 0.12,
        'cat_rides' => 0.15,
        'cat_restaurants' => 0.1,
        _ => 0.05,
      };
      if (rnd.nextDouble() > chance) continue;
      final value = m(min + rnd.nextDouble() * (max - min));
      final onCard = where == null && rnd.nextDouble() < 0.75;
      txs.add(
        FinTransaction(
          id: newId('tx_'),
          type: TransactionType.expense,
          amount: Money((value.cents ~/ 10) * 10 + rnd.nextInt(10)),
          description: desc,
          categoryId: cat,
          date: d,
          accountId: onCard ? null : (where == 'cash' ? cash.id : nu.id),
          cardId: onCard ? (rnd.nextBool() ? nuCard.id : itauCard.id) : null,
          status: TransactionStatus.completed,
        ),
      );
    }
  }

  // Transferências mensais para a poupança
  for (var mm = cm.add(-5); mm < cm; mm = mm.next) {
    txs.add(
      FinTransaction(
        id: newId('tx_'),
        type: TransactionType.transfer,
        amount: m(1000),
        description: 'Reserva de emergência',
        date: Dates.clampedDate(mm.year, mm.month, 6),
        accountId: itau.id,
        destinationAccountId: poup.id,
        status: TransactionStatus.completed,
      ),
    );
  }

  // Compras parceladas
  void installments(
    String desc,
    num total,
    int count,
    DateTime date, {
    String? card,
    String? account,
    String cat = 'cat_shopping',
    String? project,
  }) {
    final g = InstallmentGroup(
      id: newId('ig_'),
      description: desc,
      totalAmount: m(total),
      count: count,
      purchaseDate: date,
      cardId: card,
      accountId: account,
      categoryId: cat,
      projectId: project,
    );
    ops.add(WriteOp.put(Coll.installmentGroups, g.id, g.toJson()));
    txs.addAll(Installments.build(g, today: now));
  }

  installments('Notebook', 3600, 12, Dates.addMonths(now, -3), card: nuCard.id);
  installments(
    'Geladeira',
    2400,
    10,
    Dates.addMonths(now, -1),
    card: itauCard.id,
  );
  installments(
    'Passagens aéreas',
    6800,
    10,
    Dates.addMonths(now, -2),
    card: nuCard.id,
    cat: 'cat_travel',
    project: trip.id,
  );
  installments(
    'Curso de especialização',
    1800,
    6,
    Dates.addMonths(now, -1),
    account: nu.id,
    cat: 'cat_education',
  );

  // Lançamentos de projetos
  txs.addAll([
    FinTransaction(
      id: newId('tx_'),
      type: TransactionType.expense,
      amount: m(480),
      description: 'Seguro viagem',
      categoryId: 'cat_travel',
      date: now.subtract(const Duration(days: 12)),
      cardId: itauCard.id,
      projectId: trip.id,
    ),
    FinTransaction(
      id: newId('tx_'),
      type: TransactionType.expense,
      amount: m(9200),
      description: 'Hospedagem (hotéis)',
      categoryId: 'cat_travel',
      date: Dates.addMonths(now, 3),
      accountId: itau.id,
      projectId: trip.id,
      status: TransactionStatus.planned,
    ),
    FinTransaction(
      id: newId('tx_'),
      type: TransactionType.expense,
      amount: m(1850),
      description: 'Cadeira ergonômica',
      categoryId: 'cat_shopping',
      date: now.subtract(const Duration(days: 2)),
      accountId: nu.id,
      projectId: reform.id,
      notes: 'Garantia de 5 anos; nota fiscal no e-mail',
    ),
    FinTransaction(
      id: newId('tx_'),
      type: TransactionType.expense,
      amount: m(2300),
      description: 'Mesa sob medida',
      categoryId: 'cat_shopping',
      date: Dates.addMonths(now, 1),
      accountId: itau.id,
      projectId: reform.id,
      status: TransactionStatus.pending,
    ),
    FinTransaction(
      id: newId('tx_'),
      type: TransactionType.income,
      amount: m(18000),
      description: '13º salário',
      categoryId: 'cat_salary',
      date: DateTime(cm.month == 12 ? cm.year + 1 : cm.year, 12, 18),
      accountId: itau.id,
      status: TransactionStatus.planned,
    ),
  ]);

  // Compras no cartão acompanham a fatura: pagas (concluídas) só quando a
  // fatura já venceu e foi paga abaixo; nas demais ficam pendentes.
  for (final (i, t) in txs.indexed) {
    final card = [nuCard, itauCard].where((c) => c.id == t.cardId).firstOrNull;
    if (card == null || t.status == TransactionStatus.planned) continue;
    final due = BillingCycle.dueDate(
      card,
      BillingCycle.invoiceForTransaction(card, t),
    );
    txs[i] = t.copyWith(
      status: due.isBefore(now)
          ? TransactionStatus.completed
          : TransactionStatus.pending,
    );
  }

  for (final t in txs) {
    ops.add(WriteOp.put(Coll.transactions, t.id, t.toJson()));
  }

  // Pagamento integral das faturas já vencidas
  for (final card in [nuCard, itauCard]) {
    final totals = <YearMonth, Money>{};
    for (final t in txs.where((t) => t.cardId == card.id)) {
      final inv = BillingCycle.invoiceForTransaction(card, t);
      totals[inv] = (totals[inv] ?? Money.zero) + t.amount;
    }
    totals.forEach((inv, total) {
      final due = BillingCycle.dueDate(card, inv);
      if (!due.isBefore(now)) return;
      final p = InvoicePayment(
        id: newId('pay_'),
        cardId: card.id,
        invoiceKey: inv.key,
        amount: total,
        date: due,
        accountId: card.paymentAccountId,
      );
      ops.add(WriteOp.put(Coll.invoicePayments, p.id, p.toJson()));
    });
  }
  return ops;
}
