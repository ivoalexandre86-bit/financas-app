import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/transactions/transactions_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:financas_app/ui/widgets/tx_grid.dart';
import 'package:flutter/material.dart';
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

  testWidgets('grade larga: cabeçalho, ordenação e status com um toque', (
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

    // Status alterna sem abrir os detalhes.
    await tester.runAsync(() async {
      await tester.tap(find.text('Pendente').first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(
      fc.data.transactions.where(
        (t) => t.status == TransactionStatus.completed,
      ),
      hasLength(1),
    );
    expect(find.text('Paga'), findsOneWidget);
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
