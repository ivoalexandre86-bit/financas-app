import 'package:flutter/material.dart';

import '../../domain/engine/other_entries_engine.dart';
import '../../domain/engine/shared_engine.dart';
import '../../domain/models/entities.dart';

/// De onde vem uma linha da grade de movimentações (coluna "Tipo").
enum EntryOrigin {
  transaction('Transação', Icons.receipt_long_outlined),
  invoice('Fatura', Icons.credit_card),
  otherExpense('Outra despesa', Icons.call_split),
  otherIncome('Outra receita', Icons.call_merge),
  shared('Compartilhada', Icons.groups_outlined);

  final String label;
  final IconData icon;
  const EntryOrigin(this.label, this.icon);

  /// Lançamentos gerados por Outras despesas/receitas (`oe_`) e por
  /// Compartilhadas (`sh_`); o resto foi lançado pelo próprio usuário.
  static EntryOrigin of(FinTransaction tx) {
    if (SharedBudgetSync.isDerived(tx.id)) return EntryOrigin.shared;
    if (OtherSync.isDerived(tx.id)) {
      return tx.type == TransactionType.income
          ? EntryOrigin.otherIncome
          : EntryOrigin.otherExpense;
    }
    return EntryOrigin.transaction;
  }
}

/// Célula "Tipo" da grade.
class EntryOriginLabel extends StatelessWidget {
  final EntryOrigin origin;
  const EntryOriginLabel(this.origin, {super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Icon(origin.icon, size: 14, color: style?.color?.withValues(alpha: .7)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            origin.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
