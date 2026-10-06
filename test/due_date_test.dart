import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/ui/widgets/tx_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vencimento é salvo, lido e removido no JSON', () {
    final t = FinTransaction(
      id: 'tx_1',
      type: TransactionType.expense,
      amount: const Money(1000),
      description: 'Aluguel',
      date: DateTime(2026, 10, 5),
      dueDate: DateTime(2026, 10, 15),
    );
    final back = FinTransaction.fromJson(t.toJson());
    expect(back.dueDate, DateTime(2026, 10, 15));
    expect(back.effectiveDueDate, DateTime(2026, 10, 15));
    final cleared = back.copyWith(dueDate: null);
    expect(cleared.dueDate, isNull);
    expect(cleared.effectiveDueDate, DateTime(2026, 10, 5));
    expect(FinTransaction.fromJson(cleared.toJson()).dueDate, isNull);
  });

  test('grade salva antes ganha a coluna Vencimento após Data', () {
    final cfg = GridColumnsConfig.fromJson([
      {'id': 'date', 'visible': true, 'width': 96},
      {'id': 'description', 'visible': true, 'width': 300},
      {'id': 'amount', 'visible': true, 'width': 136},
    ]);
    expect(cfg.columns[1].column, GridColumn.dueDate);
    expect(cfg.isVisible(GridColumn.dueDate), isTrue);
  });
}
