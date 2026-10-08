import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconhece instituições digitadas livremente', () {
    expect(matchBank('Itaú')?.code, '341');
    expect(matchBank('Itaú Unibanco S.A.')?.code, '341');
    expect(matchBank('Nu Pagamentos')?.code, '260');
    expect(matchBank('nubank')?.code, '260');
    expect(matchBank('341 - Itau')?.code, '341');
    expect(matchBank('1')?.code, '001');
    expect(matchBank('Caixa')?.code, '104');
    expect(matchBank('Conta Inter')?.code, '077');
    expect(matchBank('Banco do Brasil')?.code, '001');
    expect(matchBank('Minha cooperativa local'), isNull);
    expect(matchBank(''), isNull);
  });

  test('busca por código ou nome', () {
    expect(searchBanks('341').single.name, 'Itaú Unibanco');
    expect(searchBanks('brades').map((b) => b.code), ['237']);
    expect(searchBanks('').length, brazilianBanks.length);
  });

  test('códigos são únicos e com 3 dígitos', () {
    final codes = brazilianBanks.map((b) => b.code).toList();
    expect(codes.toSet().length, codes.length);
    expect(codes.every((c) => RegExp(r'^\d{3}$').hasMatch(c)), isTrue);
  });

  test('padroniza contas e cartões existentes', () {
    final d = FinanceData(
      accounts: [
        Account(id: 'a1', name: 'Corrente', institution: 'itau'),
        Account(id: 'a2', name: 'Coop', institution: 'Coop XYZ'),
        Account(
          id: 'a3',
          name: 'Já ok',
          institution: 'Nubank',
          institutionCode: '260',
        ),
      ],
      cards: [
        CreditCard(
          id: 'c1',
          name: 'Roxo',
          bank: 'Nu',
          closingDay: 1,
          dueDay: 8,
        ),
      ],
    );
    final ops = FinanceController.institutionFixes(d);
    expect(ops.length, 2);
    final acc = Account.fromJson(ops[0].json!);
    expect((acc.institutionCode, acc.institution), ('341', 'Itaú Unibanco'));
    final card = CreditCard.fromJson(ops[1].json!);
    expect((card.bankCode, card.bank), ('260', 'Nubank'));
  });

  test('JSON antigo sem código continua válido', () {
    final a = Account.fromJson({'id': 'x', 'name': 'n', 'institution': 'BB'});
    expect(a.institutionCode, '');
    expect(Account.fromJson(a.toJson()).institution, 'BB');
  });
}
