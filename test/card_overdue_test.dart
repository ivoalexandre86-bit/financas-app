import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compra no cartão só fica atrasada depois do vencimento da fatura.
void main() {
  // Fecha dia 15, vence dia 25: compra de 04/10 cai na fatura que vence 25/10.
  final card = CreditCard(
    id: 'bra',
    name: 'Bradesco',
    closingDay: 15,
    dueDay: 25,
  );
  final purchase = FinTransaction(
    id: 'presente',
    type: TransactionType.expense,
    amount: const Money(44030),
    description: 'Presente',
    date: DateTime(2026, 10, 4),
    cardId: 'bra',
    status: TransactionStatus.pending,
  );
  FinancialEngine engine(DateTime today) => FinancialEngine(
    FinanceData(cards: [card], transactions: [purchase]),
    today: today,
  );

  test('vence com a fatura, não na data da compra', () {
    expect(
      engine(DateTime(2026, 10, 14)).dueDateOf(purchase),
      DateTime(2026, 10, 25),
    );
  });

  test('não está atrasada antes do vencimento da fatura', () {
    expect(engine(DateTime(2026, 10, 14)).isOverdue(purchase), isFalse);
    expect(engine(DateTime(2026, 10, 25)).isOverdue(purchase), isFalse);
  });

  test('fica atrasada depois do vencimento da fatura', () {
    expect(engine(DateTime(2026, 10, 26)).isOverdue(purchase), isTrue);
  });
}
