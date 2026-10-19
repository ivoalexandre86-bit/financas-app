import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/finance_repository.dart';
import 'package:financas_app/domain/models/asset.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  late MemoryRepo repo;
  late FinanceController fc;
  final today = Dates.today();

  setUp(() async {
    repo = MemoryRepo();
    fc = FinanceController(repo);
    await fc.load();
    await fc.saveAccount(
      Account(id: 'a', name: 'Conta', initialBalance: const Money(500000)),
    );
  });

  Asset house() => Asset(
    id: 'h',
    name: 'Apartamento',
    kind: AssetKind.realEstate,
    value: const Money(30000000),
  );

  test('bem salvo, valor atualizado com histórico e recarregado', () async {
    await fc.saveAsset(house());
    expect(repo.stores[Coll.assets]!.length, 1);
    expect(fc.assets.single.history.single.value, const Money(30000000));

    await fc.updateAssetValue(
      fc.assets.single,
      const Money(29000000),
      date: Dates.addMonths(today, -2),
    );
    // Data antiga entra no histórico sem trocar o valor atual.
    expect(fc.assets.single.value, const Money(30000000));
    expect(fc.assets.single.history.length, 2);

    await fc.updateAssetValue(fc.assets.single, const Money(31000000));
    expect(fc.assets.single.value, const Money(31000000));
    // Mesmo dia substitui.
    expect(fc.assets.single.history.length, 2);
    expect(fc.assets.single.history.last.value, const Money(31000000));

    final again = FinanceController(repo);
    await again.load();
    final a = again.assets.single;
    expect(a.name, 'Apartamento');
    expect(a.kind, AssetKind.realEstate);
    expect(a.value, const Money(31000000));
    expect(a.history.map((h) => h.value), [
      const Money(29000000),
      const Money(31000000),
    ]);

    await again.deleteAsset(a);
    expect(again.assets, isEmpty);
    expect(repo.stores[Coll.assets], isEmpty);
  });

  test('nome e valor são validados', () async {
    expect(
      () => fc.saveAsset(house().copyWith(name: ' ')),
      throwsArgumentError,
    );
    expect(
      () => fc.saveAsset(house().copyWith(value: const Money(-1))),
      throwsArgumentError,
    );
  });

  test('patrimônio soma contas e bens e desconta dívidas', () async {
    await fc.saveAsset(house());
    await fc.saveAsset(
      Asset(
        id: 'f',
        name: 'Financiamento',
        kind: AssetKind.financing,
        value: const Money(20000000),
      ),
    );
    final nw = fc.netWorthEngine.compute(fc.assets);
    expect(nw.accounts, const Money(500000));
    expect(nw.assets, const Money(30000000));
    expect(nw.liabilities, const Money(20000000));
    expect(nw.total, const Money(10500000));
    final points = fc.netWorthEngine.history(fc.assets);
    expect(points.last.value, nw.total);
  });

  test(
    'cartão: faturas abertas e parcelas futuras sem contar em dobro',
    () async {
      await fc.saveCard(
        CreditCard(id: 'c', name: 'Cartão', closingDay: 10, dueDay: 17),
      );
      await fc.createInstallmentPurchase(
        InstallmentGroup(
          id: 'g',
          description: 'Laptop',
          totalAmount: const Money(360000),
          count: 12,
          purchaseDate: Dates.addMonths(today, -3),
          cardId: 'c',
        ),
      );
      final nw = fc.netWorthEngine.compute(fc.assets);
      expect(nw.cardInvoices.isPositive, isTrue);
      expect(nw.installments.isPositive, isTrue);
      expect(nw.cardInvoices + nw.installments, const Money(360000));
      expect(nw.total, const Money(500000 - 360000));
    },
  );

  test('evolução usa o histórico dos bens nos meses anteriores', () async {
    final start = YearMonth.of(today).add(-2);
    await fc.saveAsset(
      Asset(
        id: 'car',
        name: 'Carro',
        kind: AssetKind.vehicle,
        value: const Money(5000000),
        history: [AssetValue(start.firstDay, const Money(6000000))],
      ),
    );
    final points = fc.netWorthEngine.history(fc.assets);
    expect(points.length, 3);
    expect(points.first.month, start);
    expect(points.first.value, const Money(500000 + 6000000));
    expect(points.last.value, const Money(500000 + 5000000));
  });
}
