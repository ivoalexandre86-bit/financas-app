import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/projection/projection_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:financas_app/ui/widgets/tx_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  testWidgets('projeção mostra KPIs no topo e grade no estilo de Transações', (
    tester,
  ) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      await fc.saveTransaction(
        FinTransaction(
          id: 'r',
          type: TransactionType.income,
          amount: const Money(100000),
          description: 'Salário',
          date: DateTime.now(),
          accountId: 'a',
        ),
      );
      await fc.saveTransaction(
        FinTransaction(
          id: 'd',
          type: TransactionType.expense,
          amount: const Money(150000),
          description: 'Aluguel',
          date: DateTime.now(),
          accountId: 'a',
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const ProjectionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('proj-kpi-income')), findsOneWidget);
    expect(find.byKey(const ValueKey('proj-kpi-expenses')), findsOneWidget);
    expect(find.byKey(const ValueKey('proj-kpi-net')), findsOneWidget);
    expect(find.byKey(const ValueKey('proj-kpi-balance')), findsOneWidget);
    expect(find.text('1 de 6 meses negativos'), findsOneWidget);
    expect(find.text('Resumo do período'), findsNothing);

    // KPIs acima da grade, que usa o painel neon de Transações.
    expect(find.byType(GridPanel), findsOneWidget);
    expect(find.text('INDICADOR'), findsOneWidget);
    final kpiY = tester
        .getTopLeft(find.byKey(const ValueKey('proj-kpi-net')))
        .dy;
    final gridY = tester.getTopLeft(find.byType(GridPanel)).dy;
    expect(kpiY, lessThan(gridY));
    expect(find.text('Saldo acumulado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
