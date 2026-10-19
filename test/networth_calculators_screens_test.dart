import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/asset.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/calculators/calculators_screen.dart';
import 'package:financas_app/ui/screens/networth/networth_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  late FinanceController fc;

  Future<void> setup(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(1200, 1000),
  }) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(
        Account(id: 'a', name: 'Conta', initialBalance: const Money(100000)),
      );
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('patrimônio mostra os blocos, cria um bem e alterna a grade', (
    tester,
  ) async {
    await setup(tester, const NetWorthScreen());
    expect(find.text('Patrimônio líquido'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('networth-line-accounts')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('networth-line-invoices')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('networth-line-installments')),
      findsOneWidget,
    );
    expect(find.text('Adicionar dívida'), findsOneWidget);

    await tester.tap(find.text('Adicionar bem'));
    await tester.pumpAndSettle();
    expect(find.text('Novo bem'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Carro');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Valor atual'),
      '50.000,00',
    );
    await tester.tap(find.text('Salvar'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(fc.assets.single.name, 'Carro');
    expect(fc.assets.single.value, const Money(5000000));
    expect(find.text('Carro'), findsOneWidget);
    expect(fc.netWorthEngine.compute(fc.assets).total, const Money(5100000));

    await tester.runAsync(
      () => fc.saveAsset(
        Asset(
          id: 'l',
          name: 'Empréstimo pessoal',
          kind: AssetKind.loan,
          value: const Money(20000),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('networth-view-grid')));
    await tester.pumpAndSettle();
    expect(find.text('Empréstimo pessoal'), findsOneWidget);
    expect(find.text('Total · 2 itens'), findsOneWidget);

    // Detalhes com o histórico.
    await tester.tap(find.text('Carro'));
    await tester.pumpAndSettle();
    expect(find.text('Histórico de valores'), findsOneWidget);
    expect(find.text('Atualizar valor'), findsOneWidget);
  });

  testWidgets('calculadoras: financiamento Price e juros compostos', (
    tester,
  ) async {
    await setup(tester, const CalculatorsScreen());
    // Juros compostos (primeira aba).
    await tester.enterText(
      find.byKey(const ValueKey('calc-compound-initial')),
      '1.000,00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('calc-compound-monthly')),
      '100,00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('calc-compound-rate')),
      '1',
    );
    await tester.tap(find.text('meses'));
    await tester.enterText(
      find.byKey(const ValueKey('calc-compound-term')),
      '12',
    );
    await tester.pumpAndSettle();
    expect(find.text(const Money(239508).format()), findsWidgets);

    await tester.tap(find.text('Financiamento'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('calc-loan-amount')),
      '100.000,00',
    );
    await tester.enterText(find.byKey(const ValueKey('calc-loan-rate')), '1');
    await tester.enterText(find.byKey(const ValueKey('calc-loan-term')), '12');
    await tester.pumpAndSettle();
    expect(find.text(const Money(888488).format()), findsWidgets);

    await tester.tap(find.text('SAC'));
    await tester.pumpAndSettle();
    expect(find.text('Resultado · ${'SAC (amortização constante)'}'), findsOne);

    await tester.tap(find.text('Quanto guardar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('calc-savings-target')),
      '12.000,00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('calc-savings-term')),
      '12',
    );
    await tester.pumpAndSettle();
    expect(find.text(const Money(100000).format()), findsWidgets);

    await tester.tap(find.text('Quitar ou investir'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calc-prepay-debt')), findsOneWidget);
  });

  testWidgets('telas cabem no celular', (tester) async {
    await setup(tester, const NetWorthScreen(), size: const Size(360, 800));
    expect(tester.takeException(), isNull);
    await setup(tester, const CalculatorsScreen(), size: const Size(360, 800));
    final tabs = DefaultTabController.of(
      tester.element(find.byType(TabBarView)),
    );
    for (var i = 1; i < 4; i++) {
      tabs.index = i;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
