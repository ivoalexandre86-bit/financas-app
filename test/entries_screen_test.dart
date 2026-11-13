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
  Future<FinanceController> setup(WidgetTester tester) async {
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
      for (final (id, desc) in [
        ('t1', 'Aluguel'),
        (
          'oe_expense_${today.year}-${today.month.toString().padLeft(2, '0')}',
          'Outras despesas do mês',
        ),
      ]) {
        await fc.saveTransaction(
          FinTransaction(
            id: id,
            type: TransactionType.expense,
            amount: Money(10000),
            description: desc,
            date: today,
            accountId: 'a',
            status: TransactionStatus.pending,
          ),
        );
      }
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
}
