import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../domain/models/entities.dart';
import '../../state/finance_controller.dart';
import 'tx_grid.dart';

// Edição direta de um lançamento numa grade (Transações e fatura do
// cartão): grava na hora e avisa se não der certo.

Future<void> saveTxInline(
  BuildContext context,
  FinanceController fc,
  FinTransaction t,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await fc.saveInline(t);
  } catch (e) {
    final msg = e is ArgumentError ? '${e.message}' : '$e';
    messenger.showSnackBar(
      SnackBar(content: Text('Não foi possível salvar: $msg')),
    );
  }
}

String? validateInlineAmount(String v) {
  final m = Money.tryEval(v);
  if (m == null) return 'Valor inválido';
  if (m.cents <= 0) return 'O valor deve ser maior que zero';
  return null;
}

Future<void> pickTxDate(
  BuildContext context,
  FinanceController fc,
  FinTransaction tx,
) async {
  final d = await showDatePicker(
    context: context,
    initialDate: tx.date,
    firstDate: DateTime(2000),
    lastDate: DateTime(fc.today.year + 30),
    locale: const Locale('pt', 'BR'),
  );
  if (d == null || !context.mounted) return;
  if (Dates.dateOnly(d) == Dates.dateOnly(tx.date)) return;
  await saveTxInline(context, fc, tx.copyWith(date: d));
}

/// Categorias do tipo do lançamento. Com a coluna Subcategoria visível,
/// a coluna Categoria lista só as principais; sem ela, mostra a árvore.
Future<void> pickTxCategory(
  BuildContext cell,
  FinanceController fc,
  FinTransaction tx, {
  required bool onlyRoots,
}) async {
  final kind = tx.type == TransactionType.income
      ? CategoryKind.income
      : CategoryKind.expense;
  List<FinCategory> sorted(bool Function(FinCategory) test) =>
      fc.data.categories.where(test).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final current = fc.data.categoryById[tx.categoryId];
  final rootId = current?.parentId ?? current?.id;
  final picked = await showCellMenu(cell, [
    for (final r in sorted((c) => c.kind == kind && c.parentId == null)) ...[
      CellMenuOption(
        r.id,
        r.name,
        color: Color(r.color),
        selected: onlyRoots ? r.id == rootId : r.id == tx.categoryId,
      ),
      if (!onlyRoots)
        for (final s in sorted((c) => c.parentId == r.id))
          CellMenuOption(
            s.id,
            s.name,
            indent: true,
            selected: s.id == tx.categoryId,
          ),
    ],
  ]);
  if (picked == null || !cell.mounted) return;
  // Mesma categoria principal: mantém a subcategoria escolhida.
  if (picked == tx.categoryId || (onlyRoots && picked == rootId)) return;
  await saveTxInline(cell, fc, tx.copyWith(categoryId: picked));
}

Future<void> pickTxSubcategory(
  BuildContext cell,
  FinanceController fc,
  FinTransaction tx,
) async {
  final current = fc.data.categoryById[tx.categoryId];
  final root = fc.data.categoryById[current?.parentId] ?? current;
  if (root == null) return;
  final subs = fc.data.categories.where((c) => c.parentId == root.id).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  if (subs.isEmpty) {
    ScaffoldMessenger.of(cell).showSnackBar(
      SnackBar(content: Text('${root.name} não tem subcategorias')),
    );
    return;
  }
  final picked = await showCellMenu(cell, [
    CellMenuOption(
      root.id,
      'Nenhuma (só ${root.name})',
      selected: tx.categoryId == root.id,
    ),
    for (final s in subs)
      CellMenuOption(s.id, s.name, selected: s.id == tx.categoryId),
  ]);
  if (picked == null || picked == tx.categoryId || !cell.mounted) return;
  await saveTxInline(cell, fc, tx.copyWith(categoryId: picked));
}
