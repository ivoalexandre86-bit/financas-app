import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/entities.dart';
import '../models/other_entry.dart';

/// Integração de "Outras despesas/receitas" com o orçamento oficial.
///
/// Os lançamentos detalhados nunca entram um a um no orçamento: cada mês
/// ganha **uma** transação consolidada por tipo (como a fatura do cartão), e
/// cada pagamento de reembolso vira uma receita na data do pagamento. Os ids
/// são fixos, então recalcular é idempotente e nunca duplica.
class OtherSync {
  static const expenseCategoryId = 'cat_other_expenses';
  static const incomeCategoryId = 'cat_other_income';
  static const reimbursementCategoryId = 'cat_reimbursements';

  static String monthTxId(TransactionType type, YearMonth m) =>
      'oe_${type == TransactionType.income ? 'income' : 'expense'}_${m.key}';

  /// Lê o id de uma linha consolidada (`oe_expense_2026-10`).
  static (TransactionType, YearMonth)? parseMonthTx(String id) {
    final m = RegExp(r'^oe_(expense|income)_(\d{4}-\d{2})$').firstMatch(id);
    if (m == null) return null;
    return (
      m[1] == 'income' ? TransactionType.income : TransactionType.expense,
      YearMonth.parse(m[2]!),
    );
  }

  /// Transação gerada por este módulo (linha do mês ou reembolso)?
  static bool isDerived(String id) => id.startsWith('oe_');

  static String typeLabel(TransactionType t) =>
      t == TransactionType.income ? 'Outras receitas' : 'Outras despesas';

  /// Categorias próprias que faltam no cadastro.
  static List<FinCategory> missingCategories(List<FinCategory> existing) {
    final ids = existing.map((c) => c.id).toSet();
    return [
      if (!ids.contains(expenseCategoryId))
        FinCategory(
          id: expenseCategoryId,
          name: 'Outras despesas',
          kind: CategoryKind.expense,
          color: 0xFF8D6E63,
        ),
      if (!ids.contains(incomeCategoryId))
        FinCategory(
          id: incomeCategoryId,
          name: 'Outras receitas',
          kind: CategoryKind.income,
          color: 0xFF26A69A,
        ),
      if (!ids.contains(reimbursementCategoryId))
        FinCategory(
          id: reimbursementCategoryId,
          name: 'Reembolsos',
          kind: CategoryKind.income,
          color: 0xFF7CB342,
        ),
    ];
  }

  /// Transações que o orçamento deve ter, calculadas do zero.
  static List<FinTransaction> desired({
    required List<OtherEntry> entries,
    required Map<String, Person> people,
    required String accountId,
  }) {
    final out = <FinTransaction>[];
    final groups = <String, List<OtherEntry>>{};
    for (final e in entries) {
      if (e.isDeleted || !e.linked || e.amount <= 0) continue;
      (groups[monthTxId(e.type, e.month)] ??= []).add(e);
    }
    for (final g in groups.entries) {
      final list = g.value;
      final first = list.first;
      final m = first.month;
      final total = list.fold(0, (a, e) => a + e.amount);
      DateTime? due;
      for (final e in list) {
        final d = e.dueDate;
        if (d != null && YearMonth.of(d) == m) {
          if (due == null || d.isAfter(due)) due = d;
        }
      }
      final date = due ?? m.lastDay;
      final income = first.isIncome;
      out.add(
        FinTransaction(
          id: g.key,
          type: first.type,
          amount: Money(total),
          description: typeLabel(first.type),
          categoryId: income ? incomeCategoryId : expenseCategoryId,
          date: date,
          dueDate: income ? null : date,
          accountId: accountId,
          notes:
              '${list.length} ${list.length == 1 ? 'lançamento' : 'lançamentos'}'
              ' de ${m.key}',
          status: list.every((e) => e.settled)
              ? TransactionStatus.completed
              : TransactionStatus.planned,
        ),
      );
    }
    // Reembolsos: só de despesas e só de outras pessoas (a parte de "eu" não
    // é cobrada). Receitas recebidas já estão na linha do mês.
    for (final e in entries) {
      if (e.isIncome) continue;
      for (final p in e.payments) {
        if (p.amount <= 0 || (people[p.personId]?.isMe ?? false)) continue;
        final name = people[p.personId]?.name ?? 'pessoa';
        out.add(
          FinTransaction(
            id: p.incomeTxId,
            type: TransactionType.income,
            amount: Money(p.amount),
            description: 'Reembolso $name – ${e.description}',
            categoryId: reimbursementCategoryId,
            date: p.date,
            accountId: accountId,
            notes: [p.method, if (p.note.isNotEmpty) p.note].join(' · '),
            status: TransactionStatus.completed,
          ),
        );
      }
    }
    return out;
  }

  static bool _same(FinTransaction a, FinTransaction b) {
    Map<String, Object?> k(FinTransaction t) => Map.of(t.toJson())
      ..remove('createdAt')
      ..remove('updatedAt');
    final ka = k(a), kb = k(b);
    return ka.keys.every((x) => ka[x] == kb[x]);
  }

  /// Diferença entre o que existe e o que deveria existir: (gravar, excluir).
  static (List<FinTransaction>, List<String>) diff({
    required List<FinTransaction> existing,
    required List<FinTransaction> desired,
  }) {
    final current = {
      for (final t in existing)
        if (isDerived(t.id)) t.id: t,
    };
    final puts = <FinTransaction>[];
    for (final t in desired) {
      final old = current.remove(t.id);
      if (old == null) {
        puts.add(t);
      } else if (!_same(old, t)) {
        puts.add(
          FinTransaction.fromJson({
            ...t.toJson(),
            'createdAt': old.createdAt.toIso8601String(),
          }),
        );
      }
    }
    return (puts, current.keys.toList());
  }
}

/// Totais do resumo da tela.
class OtherSummary {
  int total = 0; // despesas: total; receitas: previsto
  int assigned = 0; // parte das outras pessoas
  int received = 0;
  int outstanding = 0;
  int pending = 0, partial = 0, paid = 0;

  OtherSummary.of(Iterable<OtherEntry> entries, Set<String> meIds) {
    for (final e in entries) {
      total += e.amount;
      if (e.isIncome) {
        received += e.received;
        outstanding += e.amount - e.received;
      } else {
        for (final s in e.othersShares(meIds)) {
          assigned += s.owed;
          received += s.paid;
          outstanding += s.balance > 0 ? s.balance : 0;
        }
      }
      switch (e.status(meIds)) {
        case PayStatus.pending:
          pending++;
        case PayStatus.partial:
          partial++;
        case PayStatus.paid:
          paid++;
        case null:
      }
    }
  }
}
