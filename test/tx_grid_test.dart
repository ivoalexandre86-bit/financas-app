import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/transactions/transactions_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:financas_app/ui/widgets/tx_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  Future<FinanceController> setup(WidgetTester tester, Size size) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      final today = fc.engine.today;
      for (final (id, desc, cents) in [
        ('t1', 'Aluguel', 210000),
        ('t2', 'Mercado', 50000),
      ]) {
        final notes = id == 't1' ? 'Reajuste em janeiro' : '';
        await fc.saveTransaction(
          FinTransaction(
            id: id,
            type: TransactionType.expense,
            amount: Money(cents),
            description: desc,
            date: today,
            accountId: 'a',
            status: TransactionStatus.pending,
            notes: notes,
          ),
        );
      }
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TransactionsScreen(),
        ),
      ),
    );
    await tester.pump();
    return fc;
  }

  testWidgets('grade larga: cabeçalho, ordenação e status em lista suspensa', (
    tester,
  ) async {
    final fc = await setup(tester, const Size(1200, 800));
    expect(find.text('DATA'), findsOneWidget);
    expect(find.text('SUBCATEGORIA'), findsOneWidget);

    // Ordena por valor (maior primeiro) e depois inverte.
    await tester.tap(find.byKey(const ValueKey('grid-sort-amount')));
    await tester.pump();
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Mercado') < y('Aluguel'), isTrue); // -500 > -2100
    await tester.tap(find.byKey(const ValueKey('grid-sort-amount')));
    await tester.pump();
    expect(y('Aluguel') < y('Mercado'), isTrue);

    // O status abre uma lista com todas as opções, sem abrir os detalhes.
    await tester.tap(find.text('Pendente').first);
    await tester.pumpAndSettle();
    expect(find.text('Prevista'), findsOneWidget);
    expect(find.text('Cancelada'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Paga').last);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(
      fc.data.transactions.where(
        (t) => t.status == TransactionStatus.completed,
      ),
      hasLength(1),
    );
    expect(find.text('Paga'), findsOneWidget);

    // Escolhe outro status direto na lista: cancelada.
    await tester.tap(find.text('Paga'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Cancelada').last);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(
      fc.data.transactions.where(
        (t) => t.status == TransactionStatus.cancelled,
      ),
      hasLength(1),
    );
  });

  testWidgets('celular: linhas compactas sem cabeçalho de colunas', (
    tester,
  ) async {
    await setup(tester, const Size(620, 900));
    expect(find.text('DATA'), findsNothing);
    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('Pendente'), findsNWidgets(2));
  });

  testWidgets('coluna de observações e configuração de colunas', (
    tester,
  ) async {
    final fc = await setup(tester, const Size(1400, 800));
    expect(find.text('OBSERVAÇÕES'), findsOneWidget);
    expect(find.text('Reajuste em janeiro'), findsOneWidget);

    // Oculta Subcategoria pela folha de configuração.
    await tester.tap(find.byKey(const ValueKey('grid-configure')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('col-visible-subcategory')));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('grid-columns-save')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('SUBCATEGORIA'), findsNothing);
    final saved = GridColumnsConfig.fromJson(fc.data.settings.txGridColumns);
    expect(saved.isVisible(GridColumn.subcategory), isFalse);

    // Arrastar a borda do cabeçalho alarga a coluna Data.
    final before = tester.getSize(find.byKey(const ValueKey('grid-sort-date')));
    await tester.runAsync(() async {
      await tester.drag(
        find.byKey(const ValueKey('grid-resize-date')),
        const Offset(60, 0),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final after = tester.getSize(find.byKey(const ValueKey('grid-sort-date')));
    expect(after.width, greaterThan(before.width + 30));
    final w = GridColumnsConfig.fromJson(fc.data.settings.txGridColumns).columns
        .firstWhere((c) => c.column == GridColumn.date)
        .width;
    expect(w, greaterThan(GridColumn.date.defaultWidth + 30));
  });

  testWidgets('edição direta nas células da grade', (tester) async {
    final fc = await setup(tester, const Size(1400, 800));
    FinTransaction t1() => fc.data.transactions.firstWhere((t) => t.id == 't1');
    final key = 't1-${t1().date.toIso8601String()}';

    Future<void> edit(String col, String text) async {
      await tester.tap(find.byKey(ValueKey('tx-edit-$col-$key')));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), text);
      await tester.runAsync(() async {
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    }

    await edit('description', 'Aluguel apto');
    expect(t1().description, 'Aluguel apto');
    expect(find.text('Aluguel apto'), findsOneWidget);

    await edit('amount', '2.300,50');
    expect(t1().amount, Money(230050));
    // O total de despesas é recalculado.
    expect(find.text(Money(280050).format()), findsWidgets);

    await edit('notes', 'Contrato novo');
    expect(t1().notes, 'Contrato novo');

    // Valor inválido não é gravado e mantém o campo aberto com o erro.
    await tester.tap(find.byKey(ValueKey('tx-edit-amount-$key')));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(t1().amount, Money(230050));
    // Esc desfaz.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);

    // Categoria pelo menu da célula.
    final root = fc.data.categories.firstWhere(
      (c) => c.kind == CategoryKind.expense && c.parentId == null,
    );
    await tester.tap(find.byKey(ValueKey('tx-edit-category-$key')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text(root.name).last);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(t1().categoryId, root.id);

    // A seta da linha abre os detalhes.
    await tester.tap(find.byKey(ValueKey('tx-open-$key')));
    await tester.pumpAndSettle();
    expect(find.text('Aluguel apto'), findsWidgets);
    expect(find.byKey(ValueKey('tx-open-$key')), findsNothing);
  });

  testWidgets('celular: descrição e valor editam na própria linha', (
    tester,
  ) async {
    final fc = await setup(tester, const Size(620, 900));
    final t2 = fc.data.transactions.firstWhere((t) => t.id == 't2');
    final key = 't2-${t2.date.toIso8601String()}';
    await tester.tap(find.byKey(ValueKey('tx-edit-amount-$key')));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '612,30');
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(
      fc.data.transactions.firstWhere((t) => t.id == 't2').amount,
      Money(61230),
    );
  });

  test('preferência de colunas: JSON tolerante e reordenação', () {
    final cfg = GridColumnsConfig.fromJson([
      {'id': 'amount', 'visible': true, 'width': 5000},
      {'id': 'xyz'},
      {'id': 'date', 'visible': false, 'width': 100},
    ]);
    expect(cfg.columns.first.column, GridColumn.amount);
    expect(cfg.columns.first.width, GridColumn.maxWidth);
    expect(cfg.isVisible(GridColumn.date), isFalse);
    expect(cfg.columns, hasLength(GridColumn.values.length));
    expect(cfg.isVisible(GridColumn.notes), isTrue);

    final moved = GridColumnsConfig.standard.moved(0, 2);
    expect(moved.columns[2].column, GridColumn.date);

    var one = GridColumnsConfig.standard;
    for (final c in GridColumn.values) {
      one = one.withVisible(c, false);
    }
    expect(one.visible, hasLength(1));

    // Tela estreita: colunas de texto encolhem antes de rolar.
    final l = GridLayout.of(900, GridColumnsConfig.standard);
    expect(l.totalWidth, closeTo(900, 0.01));
  });
}
