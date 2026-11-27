import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/debt.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/debts/debt_detail_screen.dart';
import 'package:financas_app/ui/screens/debts/debts_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

// Dados fictícios.
void main() {
  late FinanceController fc;

  Future<void> setup(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(1200, 1400),
    List<DebtContract> debts = const [],
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
        Account(id: 'a', name: 'Conta', initialBalance: const Money(2000000)),
      );
      for (final d in debts) {
        await fc.saveDebt(d);
      }
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  DebtContract carro(DateTime today) => DebtContract(
    id: 'carro',
    name: 'Carro',
    system: AmortizationSystem.price,
    monthlyRate: 0.0189,
    outstanding: const Money(4200000),
    remainingMonths: 30,
    nextDueDate: DateTime(today.year, today.month + 1, 10),
  );

  testWidgets('cadastra um contrato pelo formulário', (tester) async {
    await setup(tester, const DebtsScreen());
    expect(find.text('Nenhum contrato'), findsOneWidget);
    await tester.tap(find.byKey(const Key('debt-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('debt-name')), 'Empréstimo');
    await tester.enterText(
      find.byKey(const Key('debt-outstanding')),
      '10.000,00',
    );
    await tester.enterText(find.byKey(const Key('debt-remaining')), '12');
    await tester.enterText(find.byKey(const Key('debt-rate')), '2');
    await tester.tap(find.widgetWithText(TextButton, 'Salvar'));
    await tester.pumpAndSettle();
    final d = fc.debts.single;
    expect(d.name, 'Empréstimo');
    expect(d.outstanding, const Money(1000000));
    expect(d.monthlyRate, closeTo(0.02, 1e-9));
    expect(d.remainingMonths, 12);
    // Abre o detalhe; sem sistema informado, aponta o campo que falta.
    expect(find.textContaining('Sistema de amortização'), findsWidgets);
  });

  testWidgets('detalhe simula a amortização e mostra a estimativa', (
    tester,
  ) async {
    final today = DateTime.now();
    await setup(tester, const DebtDetailScreen('carro'), debts: [carro(today)]);
    expect(find.text('Estimativa do app'), findsOneWidget);
    expect(find.text('Economia estimada'), findsOneWidget);
    expect(find.text('Caixa projetado (saldo acumulado)'), findsOneWidget);
  });

  testWidgets('novo financiamento mostra Price e SAC', (tester) async {
    await setup(tester, const DebtsScreen(initialTab: 1));
    expect(find.text('Price × SAC'), findsOneWidget);
    expect(find.text('Total de juros'), findsOneWidget);
    expect(find.text('Custo total'), findsOneWidget);
  });

  testWidgets('compara duas dívidas e aponta dados faltando', (tester) async {
    final today = DateTime.now();
    await setup(
      tester,
      const DebtsScreen(initialTab: 2),
      debts: [
        carro(today),
        DebtContract(
          id: 'cartao',
          name: 'Renegociação',
          outstanding: const Money(800000),
          remainingMonths: 10,
        ),
      ],
    );
    expect(find.text('Faltam dados para estimar'), findsOneWidget);
    expect(find.textContaining('Carro · Amortizar'), findsWidgets);
    expect(find.text('Toque para ver detalhes'), findsWidgets);
  });

  testWidgets('telas cabem no celular', (tester) async {
    final today = DateTime.now();
    for (final tab in [0, 1, 2, 3]) {
      await setup(
        tester,
        DebtsScreen(initialTab: tab),
        size: const Size(360, 740),
        debts: [carro(today)],
      );
      expect(tester.takeException(), isNull, reason: 'aba $tab');
    }
  });
}
