import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/simulations/other_entries.dart';
import 'package:financas_app/ui/screens/transactions/entries_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  Future<FinanceController> setup(
    WidgetTester tester, {
    Map<String, Object?>? txFilter,
  }) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      final today = fc.engine.today;
      for (final (id, desc, type) in [
        ('t1', 'Aluguel', TransactionType.expense),
        ('t2', 'Salário', TransactionType.income),
        (
          'oe_expense_${today.year}-${today.month.toString().padLeft(2, '0')}',
          'Outras despesas do mês',
          TransactionType.expense,
        ),
      ]) {
        await fc.saveTransaction(
          FinTransaction(
            id: id,
            type: type,
            amount: Money(10000),
            description: desc,
            date: today,
            accountId: 'a',
            status: TransactionStatus.pending,
          ),
        );
      }
      if (txFilter != null) await fc.saveGridFilter('transactions', txFilter);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const EntriesScreen(),
        ),
      ),
    );
    await tester.pump();
    return fc;
  }

  testWidgets('uma tela com botões: Todos, Transações e Outras despesas', (
    tester,
  ) async {
    final fc = await setup(tester);
    expect(find.text('Movimentações'), findsOneWidget);
    expect(find.byKey(const ValueKey('entries-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('entries-own')), findsOneWidget);
    expect(find.byKey(const ValueKey('entries-other')), findsOneWidget);
    // Sem nuvem não há compartilhadas; sem outras receitas, sem o botão.
    expect(find.byKey(const ValueKey('entries-shared')), findsNothing);
    expect(find.byKey(const ValueKey('entries-otherIncome')), findsNothing);

    // Todos: inclui a linha gerada por Outras despesas.
    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('Outras despesas do mês'), findsOneWidget);

    // Transações: só as lançadas pelo usuário.
    await tester.tap(find.byKey(const ValueKey('entries-own')));
    await tester.pump();
    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('Outras despesas do mês'), findsNothing);

    // Outras despesas: a grade de outras despesas, e a escolha é lembrada.
    await tester.tap(find.byKey(const ValueKey('entries-other')));
    await tester.pump();
    expect(find.byType(OtherEntriesView), findsOneWidget);
    expect(fc.gridFilter('entries'), {'view': 'other'});

    // Atalho de menu antigo abre direto no botão.
    EntriesScreen.requested.value = EntriesView.own;
    await tester.pump();
    expect(fc.gridFilter('entries'), {'view': 'own'});
    expect(EntriesScreen.requested.value, isNull);
  });

  testWidgets(
    'filtro escondido no painel vira botão removível; receitas voltam',
    (tester) async {
      // Filtro de tipo "Despesa" esquecido no painel (lembrado entre visitas).
      final fc = await setup(
        tester,
        txFilter: {
          'types': ['expense'],
        },
      );
      expect(find.text('Salário'), findsNothing);
      final chip = find.byKey(const ValueKey('f-types'));
      expect(chip, findsOneWidget);
      expect(find.text('Tipo: Despesa'), findsOneWidget);

      // Remover o filtro traz a receita de volta.
      await tester.tap(find.byTooltip('Remover filtro'));
      await tester.pump();
      expect(find.text('Salário'), findsOneWidget);
      expect(find.byKey(const ValueKey('f-types')), findsNothing);
      expect(fc.gridFilter('transactions')!['types'], isEmpty);
    },
  );

  testWidgets('coluna Tipo e botões dinâmicos por tipo e categoria', (
    tester,
  ) async {
    final fc = await setup(tester);
    // Coluna Tipo: transações do usuário e linha de Outras despesas.
    expect(find.text('TIPO'), findsOneWidget);
    expect(find.text('Transação'), findsNWidgets(2));
    expect(find.text('Outra despesa'), findsOneWidget);

    // Botões gerados a partir das linhas do mês, com a quantidade.
    expect(find.byKey(const ValueKey('qo-transaction')), findsOneWidget);
    expect(find.byKey(const ValueKey('qo-otherExpense')), findsOneWidget);
    expect(find.byKey(const ValueKey('qo-shared')), findsNothing);
    expect(find.text('Transação 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('qo-otherExpense')));
    await tester.pump();
    expect(find.text('Aluguel'), findsNothing);
    expect(find.text('Salário'), findsNothing);
    expect(find.text('Outras despesas do mês'), findsOneWidget);
    expect(fc.gridFilter('transactions')!['origins'], ['otherExpense']);

    // Desmarcar volta tudo.
    await tester.tap(find.byKey(const ValueKey('qo-otherExpense')));
    await tester.pump();
    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('Salário'), findsOneWidget);
  });
}
