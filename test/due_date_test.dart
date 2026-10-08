import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/engine/installments.dart';
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
  test('despesa sem vencimento vence na própria data', () {
    final t = FinTransaction(
      id: 'tx_2',
      type: TransactionType.expense,
      amount: const Money(500),
      description: 'Mercado',
      date: DateTime(2026, 10, 8),
    );
    expect(t.hasOwnDueDate, isTrue);
    expect(t.shownDueDate, DateTime(2026, 10, 8));
    final income = FinTransaction(
      id: 'tx_3',
      type: TransactionType.income,
      amount: const Money(500),
      description: 'Salário',
      date: DateTime(2026, 10, 8),
    );
    expect(income.shownDueDate, isNull);
  });

  test('recorrência replica o vencimento em cada ocorrência', () {
    final rule = RecurringRule(
      id: 'r1',
      type: TransactionType.expense,
      amount: const Money(1000),
      description: 'Aluguel',
      accountId: 'a1',
      startDate: DateTime(2026, 10, 5),
      dueOffsetDays: 5,
    );
    final back = RecurringRule.fromJson(rule.toJson());
    expect(back.dueOffsetDays, 5);
    final occ = FinancialEngine.virtualOccurrence(back, DateTime(2026, 12, 5));
    expect(occ.dueDate, DateTime(2026, 12, 10));
    final noOffset = FinancialEngine.virtualOccurrence(
      rule.copyWith(dueOffsetDays: 0),
      DateTime(2026, 12, 5),
    );
    expect(noOffset.shownDueDate, DateTime(2026, 12, 5));
  });

  test('parcelas em conta replicam o vencimento', () {
    final g = InstallmentGroup(
      id: 'g1',
      description: 'Carnê',
      totalAmount: const Money(3000),
      count: 3,
      purchaseDate: DateTime(2026, 10, 1),
      accountId: 'a1',
      dueOffsetDays: 9,
    );
    expect(InstallmentGroup.fromJson(g.toJson()).dueOffsetDays, 9);
    final parts = Installments.build(g, today: DateTime(2026, 10, 1));
    expect(parts.map((p) => p.dueDate), [
      DateTime(2026, 10, 10),
      DateTime(2026, 11, 10),
      DateTime(2026, 12, 10),
    ]);
  });
}
