import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/debt.dart';
import '../models/entities.dart';
import '../models/enums.dart';
import 'debt_engine.dart';

/// Parcelas de contratos na Projeção.
///
/// Contratos com [DebtInstallments.generated] ganham uma despesa planejada
/// por parcela restante, com id fixo `debt_<contrato>_<AAAAMM>`, recalculada
/// a cada alteração do contrato. Parcelas já concluídas (pagas) nunca são
/// alteradas nem excluídas. Com [DebtInstallments.linked] o compromisso já
/// lançado (recorrência ou parcelamento) representa as parcelas e nada é
/// gerado, para cada pagamento contar uma vez só.
class DebtSync {
  static const prefix = 'debt_';

  static bool isDerived(String id) => id.startsWith(prefix);
  static String installmentId(String debtId, DateTime due) =>
      '$prefix${debtId}_${due.year}${due.month.toString().padLeft(2, '0')}';
  static String prepaymentId(String debtId, String scenarioId) =>
      '$prefix${debtId}_pre_$scenarioId';

  /// Contrato dono de um lançamento gerado (ou `null`).
  static String? debtIdOf(String txId, Iterable<DebtContract> debts) {
    if (!isDerived(txId)) return null;
    for (final d in debts) {
      if (txId.startsWith('$prefix${d.id}_')) return d.id;
    }
    return null;
  }

  /// Parcelas desejadas para [d] a partir de [asOf].
  static List<FinTransaction> desired(DebtContract d, DateTime asOf) {
    if (d.archived ||
        d.installments != DebtInstallments.generated ||
        d.accountId == null) {
      return const [];
    }
    final s = remainingSchedule(d, asOf);
    if (s == null) return const [];
    return [
      for (final r in s.rows)
        FinTransaction(
          id: installmentId(d.id, r.dueDate),
          type: TransactionType.expense,
          amount: r.total,
          description:
              '${d.name} – parcela ${r.number}/${s.months}'
              '${d.lender.isEmpty ? '' : ' (${d.lender})'}',
          categoryId: d.categoryId,
          date: r.dueDate,
          dueDate: r.dueDate,
          accountId: d.accountId,
          notes: s.interestKnown
              ? 'Juros ${r.interest.formatVisible()} · amortização '
                    '${r.amortization.formatVisible()}'
                    '${r.fees.isPositive ? ' · encargos ${r.fees.formatVisible()}' : ''}'
                    ' · saldo ${r.balance.formatVisible()}'
              : 'Parcela do contrato',
          status: TransactionStatus.planned,
        ),
    ];
  }

  /// Diferenças entre o que existe e o desejado para os contratos [debts]
  /// (só parcelas `debt_<id>_AAAAMM`; antecipações e pagas ficam).
  static (List<FinTransaction>, List<String>) diff({
    required List<FinTransaction> existing,
    required List<DebtContract> debts,
    required DateTime asOf,
    Set<String> removedDebtIds = const {},
  }) {
    final ids = {for (final d in debts) d.id, ...removedDebtIds};
    final current = <String, FinTransaction>{};
    for (final t in existing) {
      if (!isDerived(t.id) || t.id.contains('_pre_')) continue;
      final owner = ids.where((id) => t.id.startsWith('$prefix${id}_'));
      if (owner.isEmpty) continue;
      current[t.id] = t;
    }
    final puts = <FinTransaction>[];
    for (final d in debts) {
      for (final t in desired(d, asOf)) {
        final old = current.remove(t.id);
        if (old == null) {
          puts.add(t);
        } else if (old.status == TransactionStatus.completed ||
            old.status == TransactionStatus.cancelled) {
          continue; // paga (ou cancelada à mão): não mexe
        } else if (!_same(old, t)) {
          puts.add(
            FinTransaction.fromJson({
              ...t.toJson(),
              'status': old.status.name,
              'createdAt': old.createdAt.toIso8601String(),
            }),
          );
        }
      }
    }
    final deletes = [
      for (final t in current.values)
        if (t.status != TransactionStatus.completed) t.id,
    ];
    return (puts, deletes);
  }

  static bool _same(FinTransaction a, FinTransaction b) =>
      a.amount == b.amount &&
      a.description == b.description &&
      a.categoryId == b.categoryId &&
      a.accountId == b.accountId &&
      Dates.dateOnly(a.date) == Dates.dateOnly(b.date) &&
      a.notes == b.notes;

  /// Pagamentos registrados do contrato: parcelas geradas concluídas,
  /// ocorrências concluídas do compromisso vinculado e lançamentos
  /// vinculados à mão.
  static List<FinTransaction> payments(
    DebtContract d,
    List<FinTransaction> txs,
  ) {
    final linked = d.linkedTxIds.toSet();
    return txs.where((t) {
      if (t.status != TransactionStatus.completed) return false;
      if (linked.contains(t.id)) return true;
      if (t.id.startsWith('$prefix${d.id}_')) return true;
      if (d.installments == DebtInstallments.linked) {
        if (d.linkedRuleId != null && t.recurringId == d.linkedRuleId) {
          return true;
        }
        if (d.linkedGroupId != null &&
            t.installmentGroupId == d.linkedGroupId) {
          return true;
        }
      }
      return false;
    }).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Parcelas do cronograma atual já pagas (pagamentos com data a partir
  /// do vencimento anterior à próxima parcela, um por mês).
  static int paidSinceNextDue(
    DebtContract d,
    List<FinTransaction> payments,
    DateTime asOf,
  ) {
    final next = d.nextDueDate;
    if (next == null) return 0;
    final from = Dates.addDays(next, -20);
    final months = {
      for (final p in payments)
        if (!p.date.isBefore(from) && !p.id.contains('_pre_'))
          YearMonth.of(p.date),
    };
    return months.length.clamp(0, d.remainingMonths ?? 0);
  }

  /// Avança o contrato [paid] parcelas no cronograma atual: novo saldo,
  /// parcelas restantes, próximo vencimento e parcela atual.
  static DebtContract advance(DebtContract d, int paid, DateTime asOf) {
    if (paid <= 0) return d;
    final s = remainingSchedule(d, asOf);
    if (s == null || s.isEmpty) return d;
    final k = paid.clamp(1, s.months);
    final last = s.rows[k - 1];
    final next = k < s.months ? s.rows[k] : null;
    return d.copyWith(
      outstanding: s.interestKnown ? last.balance : d.outstanding,
      balanceDate: last.dueDate,
      remainingMonths: s.months - k,
      nextDueDate: next?.dueDate,
      currentPayment: next?.payment ?? Money.zero,
      archived: next == null ? true : null,
    );
  }
}
