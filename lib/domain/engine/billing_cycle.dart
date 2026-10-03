import '../../core/dates.dart';
import '../models/entities.dart';

/// Motor de ciclo de faturamento de cartão de crédito.
///
/// Cada fatura é identificada pelo **mês de fechamento** ([YearMonth]).
///
/// Regras:
/// * O fechamento ocorre no [CreditCard.closingDay] do mês, limitado ao último
///   dia (ex.: fechamento 31 em fevereiro = 28/29).
/// * Compras **antes** da data de fechamento entram na fatura que fecha naquele
///   mês; compras **na data de fechamento ou depois** entram na fatura do mês
///   seguinte (o dia do fechamento é o "melhor dia de compra", como na prática
///   dos emissores brasileiros).
///   Ex.: fechamento dia 10 → compra em 09/08 entra na fatura de agosto;
///   compra em 11/08 (ou 10/08) entra na fatura de setembro.
/// * O vencimento ocorre no [CreditCard.dueDay]. Se o dia de vencimento for
///   maior que o de fechamento, vence no mesmo mês do fechamento; caso
///   contrário, no mês seguinte (ex.: fecha 28, vence 5 do mês seguinte).
class BillingCycle {
  BillingCycle._();

  static DateTime closingDate(CreditCard card, YearMonth invoice) =>
      Dates.clampedDate(invoice.year, invoice.month, card.closingDay);

  static DateTime dueDate(CreditCard card, YearMonth invoice) {
    final dueMonth = card.dueDay > card.closingDay ? invoice : invoice.next;
    return Dates.clampedDate(dueMonth.year, dueMonth.month, card.dueDay);
  }

  /// Fatura (mês de fechamento) a que pertence uma compra feita em [purchase].
  static YearMonth invoiceFor(CreditCard card, DateTime purchase) {
    final d = Dates.dateOnly(purchase);
    final ym = YearMonth.of(d);
    final closing = closingDate(card, ym);
    return d.isBefore(closing) ? ym : ym.next;
  }

  /// Data de abertura do ciclo (dia seguinte ao fechamento anterior… na
  /// prática, o próprio dia do fechamento anterior, que já pertence a este
  /// ciclo pela regra acima).
  static DateTime cycleStart(CreditCard card, YearMonth invoice) =>
      closingDate(card, invoice.previous);

  /// Último dia de compra que ainda entra nesta fatura.
  static DateTime lastPurchaseDay(CreditCard card, YearMonth invoice) =>
      closingDate(card, invoice).subtract(const Duration(days: 1));

  /// Fatura de uma transação de cartão, considerando parcelas: a parcela N de
  /// uma compra cai N − 1 faturas após a fatura da compra.
  static YearMonth invoiceForTransaction(CreditCard card, FinTransaction tx) {
    final base = invoiceFor(card, tx.date);
    if (tx.isInstallment && (tx.installmentNumber ?? 1) > 1) {
      return base.add(tx.installmentNumber! - 1);
    }
    return base;
  }

  /// Fatura atualmente aberta (recebendo compras) na data [today].
  static YearMonth currentInvoice(CreditCard card, DateTime today) =>
      invoiceFor(card, today);
}
