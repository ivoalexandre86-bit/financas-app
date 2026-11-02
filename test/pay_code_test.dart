import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/pay_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconhece linha digitável e Pix copia e cola', () {
    expect(
      payCodeKind('34191.09123 45678.123456 78900.000000 1 12345678901234'),
      PayCodeKind.boleto,
    );
    expect(payCodeKind('8' * 48), PayCodeKind.boleto);
    expect(payCodeKind('00020126580014br.gov.bcb.pix'), PayCodeKind.pix);
    expect(payCodeKind('123'), isNull);
    expect(payCodeKind('abc ${'1' * 47}'), isNull);
  });

  test('códigos de pagamento vão e voltam no JSON', () {
    final tx = FinTransaction(
      id: 'tx_1',
      type: TransactionType.expense,
      amount: Money(18000),
      description: 'Luz',
      date: DateTime(2026, 11, 3),
      accountId: 'a',
      boletoCode: '1' * 47,
      pixCode: '000201xyz',
    );
    final back = FinTransaction.fromJson(tx.toJson());
    expect(back.boletoCode, '1' * 47);
    expect(back.pixCode, '000201xyz');
    expect(back.copyWith(boletoCode: null).boletoCode, isNull);
    expect(back.copyWith(description: 'x').pixCode, '000201xyz');
  });
}
