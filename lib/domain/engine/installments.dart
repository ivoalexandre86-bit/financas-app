import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../models/entities.dart';

/// Geração das parcelas de uma compra parcelada.
class Installments {
  Installments._();

  /// Cria as [group.count] parcelas. O total é dividido em centavos exatos
  /// (sobras vão para as primeiras parcelas), então a soma das parcelas é
  /// sempre igual ao valor da compra.
  ///
  /// * Cartão: todas as parcelas guardam a data da compra; a fatura de cada
  ///   uma é derivada pelo [BillingCycle] (fatura da compra + N − 1). Assim,
  ///   se o dia de fechamento do cartão mudar, a alocação é recalculada.
  /// * Conta (carnê/boleto): a parcela N vence N − 1 meses após a compra.
  ///
  /// A primeira parcela recebe [firstStatus]; as demais ficam planejadas
  /// (ou com [firstStatus] se já vencidas, no caso de conta).
  static List<FinTransaction> build(
    InstallmentGroup group, {
    TransactionStatus firstStatus = TransactionStatus.completed,
    DateTime? today,
  }) {
    final now = Dates.dateOnly(today ?? DateTime.now());
    final parts = group.totalAmount.split(group.count);
    final isCard = group.cardId != null;
    return [
      for (var i = 0; i < group.count; i++)
        () {
          final number = i + 1;
          final date = isCard
              ? group.purchaseDate
              : Dates.addMonths(
                  group.purchaseDate,
                  i,
                  anchorDay: group.purchaseDate.day,
                );
          final TransactionStatus status;
          if (number == 1) {
            status = firstStatus;
          } else if (!isCard && !date.isAfter(now)) {
            status = firstStatus;
          } else {
            status = TransactionStatus.planned;
          }
          return FinTransaction(
            id: newId('tx_'),
            type: TransactionType.expense,
            amount: parts[i],
            description: group.description,
            categoryId: group.categoryId,
            date: date,
            accountId: group.accountId,
            cardId: group.cardId,
            projectId: group.projectId,
            notes: group.notes,
            status: status,
            installmentGroupId: group.id,
            installmentNumber: number,
            installmentCount: group.count,
          );
        }(),
    ];
  }

  /// Soma de parcelas por status, para a tela de detalhes.
  static ({Money paid, Money remaining, int paidCount, int cancelledCount})
  progress(Iterable<FinTransaction> installments) {
    var paid = Money.zero;
    var remaining = Money.zero;
    var paidCount = 0;
    var cancelled = 0;
    for (final t in installments) {
      switch (t.status) {
        case TransactionStatus.completed:
          paid += t.amount;
          paidCount++;
        case TransactionStatus.cancelled:
          cancelled++;
        default:
          remaining += t.amount;
      }
    }
    return (
      paid: paid,
      remaining: remaining,
      paidCount: paidCount,
      cancelledCount: cancelled,
    );
  }
}
