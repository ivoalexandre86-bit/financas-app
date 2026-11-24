import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/recurring/recurring_screen.dart';
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
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveAccount(Account(id: 'a', name: 'Conta'));
      final today = fc.today;
      for (final (id, type, desc, end) in [
        ('sal', TransactionType.income, 'Salário', null),
        ('net', TransactionType.expense, 'Internet', null),
        ('old', TransactionType.expense, 'Academia', DateTime(today.year - 1)),
      ]) {
        await fc.createRule(
          RecurringRule(
            id: id,
            type: type,
            amount: const Money(10000),
            description: desc,
            accountId: 'a',
            startDate: DateTime(today.year - 2, 1, 5),
            endDate: end,
          ),
        );
      }
    });
    return fc;
  }

  Widget app(FinanceController fc) => ChangeNotifierProvider.value(
    value: fc,
    child: MaterialApp(theme: AppTheme.dark(), home: const RecurringScreen()),
  );

  Future<void> open(WidgetTester tester, FinanceController fc) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(fc));
    await tester.pumpAndSettle();
  }

  // As linhas ficam atrás do painel de filtros aberto.
  Finder row(String id) =>
      find.byKey(ValueKey('rec-row-$id'), skipOffstage: false);
  Finder key(String k) => find.byKey(ValueKey(k));
  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(key('rec-filters'));
    await tester.pumpAndSettle();
  }

  test('modelo de filtro é salvo nas preferências', () {
    const s = AppSettings(filterStyle: FilterStyle.checklist);
    expect(AppSettings.fromJson(s.toJson()).filterStyle, FilterStyle.checklist);
    expect(AppSettings.fromJson({}).filterStyle, FilterStyle.classic);
  });

  testWidgets('botão ao lado de Filtros troca o modelo', (tester) async {
    final fc = await setup(tester);
    await open(tester, fc);
    // Botão Filtros no canto superior direito abre o painel.
    final btn = tester.getTopRight(key('rec-filters'));
    expect(btn.dx, greaterThan(1400));
    expect(btn.dy, lessThan(60));
    await openFilters(tester);
    expect(key('rec-type-checklist'), findsNothing);
    await tester.tap(key('filter-style-toggle'));
    await tester.pumpAndSettle();
    expect(fc.data.settings.filterStyle, FilterStyle.checklist);
    expect(key('rec-type-checklist'), findsOneWidget);
    await tester.tap(key('filter-style-toggle'));
    await tester.pumpAndSettle();
    expect(fc.data.settings.filterStyle, FilterStyle.classic);
    expect(key('rec-type-checklist'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lista com caixas: marca vários valores e limpa cada filtro', (
    tester,
  ) async {
    final fc = await setup(tester);
    await fc.setFilterStyle(FilterStyle.checklist);
    await open(tester, fc);
    expect(row('sal'), findsOneWidget);
    await openFilters(tester);
    expect(row('sal'), findsOneWidget);
    expect(row('net'), findsOneWidget);
    expect(row('old'), findsNothing);

    // Marca só Receitas.
    await tester.tap(key('rec-type-income'));
    await tester.pumpAndSettle();
    expect(row('sal'), findsOneWidget);
    expect(row('net'), findsNothing);
    // Marca também Despesas: as duas aparecem.
    await tester.tap(key('rec-type-expense'));
    await tester.pumpAndSettle();
    expect(row('sal'), findsOneWidget);
    expect(row('net'), findsOneWidget);
    expect(fc.gridFilter('recurring')!['type'], ['income', 'expense']);

    // Situação é de escolha única; Limpar volta ao padrão (em vigor).
    expect(key('rec-state-clear'), findsNothing);
    await tester.ensureVisible(key('rec-state-all'));
    await tester.pumpAndSettle();
    await tester.tap(key('rec-state-all'));
    await tester.pumpAndSettle();
    expect(row('old'), findsOneWidget);
    await tester.ensureVisible(key('rec-state-clear'));
    await tester.pumpAndSettle();
    await tester.tap(key('rec-state-clear'));
    await tester.pumpAndSettle();
    expect(row('old'), findsNothing);
    // O Tipo continua filtrado até limpar o próprio filtro.
    await tester.ensureVisible(key('rec-type-clear'));
    await tester.pumpAndSettle();
    expect(key('rec-type-clear'), findsOneWidget);
    await tester.tap(key('rec-type-income'));
    await tester.pumpAndSettle();
    expect(row('sal'), findsNothing);
    await tester.tap(key('rec-type-clear'));
    await tester.pumpAndSettle();
    expect(row('sal'), findsOneWidget);
    expect(row('net'), findsOneWidget);
    expect(key('rec-type-clear'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtro salvo no formato antigo (um valor) continua valendo', (
    tester,
  ) async {
    final fc = await setup(tester);
    await fc.saveGridFilter('recurring', {'type': 'income'});
    await open(tester, fc);
    expect(row('sal'), findsOneWidget);
    expect(row('net'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lista suspensa mostra "2 selecionados" após marcar vários', (
    tester,
  ) async {
    final fc = await setup(tester);
    await fc.saveGridFilter('recurring', {
      'type': ['income', 'expense'],
    });
    await open(tester, fc);
    await openFilters(tester);
    expect(find.text('2 selecionados'), findsOneWidget);
    expect(row('sal'), findsOneWidget);
    expect(row('net'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
