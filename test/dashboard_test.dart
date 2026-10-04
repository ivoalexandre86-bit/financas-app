import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/domain/engine/dashboard_engine.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/models/dashboard.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:financas_app/ui/widgets/dashboard_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  final ref = YearMonth(2026, 8);
  final today = DateTime(2026, 8, 15);
  final cats = [
    FinCategory(id: 'sal', name: 'Salário', kind: CategoryKind.income),
    FinCategory(id: 'mor', name: 'Moradia', kind: CategoryKind.expense),
    FinCategory(
      id: 'alu',
      name: 'Aluguel',
      kind: CategoryKind.expense,
      parentId: 'mor',
    ),
    FinCategory(id: 'ali', name: 'Alimentação', kind: CategoryKind.expense),
    FinCategory(id: 'laz', name: 'Lazer', kind: CategoryKind.expense),
  ];
  FinTransaction tx(
    String id,
    TransactionType type,
    int reais,
    String cat,
    DateTime date, {
    TransactionStatus status = TransactionStatus.completed,
  }) => FinTransaction(
    id: id,
    type: type,
    amount: Money(reais * 100),
    description: id,
    categoryId: cat,
    date: date,
    accountId: 'a',
    status: status,
  );
  const inc = TransactionType.income, exp = TransactionType.expense;

  final data = FinanceData(
    accounts: [Account(id: 'a', name: 'Conta')],
    categories: cats,
    transactions: [
      tx('s7', inc, 5000, 'sal', DateTime(2026, 7, 5)),
      tx('s8', inc, 5000, 'sal', DateTime(2026, 8, 5)),
      tx('a7', exp, 2000, 'alu', DateTime(2026, 7, 10)),
      tx('a8', exp, 2000, 'alu', DateTime(2026, 8, 10)),
      tx('f8', exp, 1000, 'ali', DateTime(2026, 8, 12)),
      tx(
        'l8',
        exp,
        500,
        'laz',
        DateTime(2026, 8, 20),
        status: TransactionStatus.pending,
      ),
      tx(
        'x8',
        exp,
        300,
        'laz',
        DateTime(2026, 8, 21),
        status: TransactionStatus.cancelled,
      ),
    ],
  );
  final de = DashboardEngine(FinancialEngine(data, today: today));

  test('receitas e despesas por mês, com séries por tipo', () {
    final d = de.build(
      const ChartConfig(
        id: 'c',
        usePanelPeriod: false,
        period: PeriodSpec.relative(-1, 0),
      ),
      reference: ref,
    );
    expect(d.xLabels, ['Jul/26', 'Ago/26']);
    final income = d.series.firstWhere((s) => s.key == 'income');
    final expense = d.series.firstWhere((s) => s.key == 'expense');
    expect(income.values, [500000, 500000]);
    // Cancelada fica fora; pendente entra no previsto.
    expect(expense.values, [200000, 350000]);
    expect(expense.sign, -1);
  });

  test('filtro de status: pendentes x concluídos', () {
    ChartDataset b(StatusScope s) => de.build(
      ChartConfig(
        id: 'c',
        source: DataSource.expenses,
        status: s,
        usePanelPeriod: false,
        period: const PeriodSpec(),
      ),
      reference: ref,
    );
    expect(b(StatusScope.pending).grandTotal, 50000);
    expect(b(StatusScope.completed).grandTotal, 300000);
    expect(b(StatusScope.all).grandTotal, 350000);
    // O filtro do painel faz interseção com o do gráfico.
    final none = de.build(
      const ChartConfig(
        id: 'c',
        source: DataSource.expenses,
        status: StatusScope.pending,
      ),
      panel: const PanelFilter(
        period: PeriodSpec(),
        status: StatusScope.completed,
      ),
      reference: ref,
    );
    expect(none.isEmpty, isTrue);
  });

  test('categorias específicas incluem subcategorias', () {
    final d = de.build(
      const ChartConfig(
        id: 'c',
        source: DataSource.expenses,
        categoryIds: {'mor'},
        xAxis: Dimension.category,
        usePanelPeriod: false,
        period: PeriodSpec(kind: PeriodKind.year),
      ),
      reference: ref,
    );
    expect(d.xKeys, ['mor']);
    expect(d.grandTotal, 400000);
  });

  test('pareto ordena categorias por valor', () {
    final d = de.build(
      const ChartConfig(
        id: 'c',
        type: ChartType.pareto,
        source: DataSource.expenses,
        xAxis: Dimension.category,
        usePanelPeriod: false,
        period: PeriodSpec(),
      ),
      reference: ref,
    );
    expect(d.xLabels, ['Moradia', 'Alimentação', 'Lazer']);
    expect(d.combined(), [200000, 100000, 50000]);
  });

  test('realizado × previsto', () {
    final d = de.build(
      const ChartConfig(
        id: 'c',
        source: DataSource.expenses,
        seriesBy: Dimension.realization,
        usePanelPeriod: false,
        period: PeriodSpec(),
      ),
      reference: ref,
    );
    final byKey = {for (final s in d.series) s.key: s.total};
    expect(byKey['actual'], 300000);
    expect(byKey['planned'], 50000);
  });

  test('comparação mês a mês alinha pela posição', () {
    final d = de.build(
      const ChartConfig(
        id: 'c',
        source: DataSource.net,
        comparison: Comparison.previousPeriod,
        usePanelPeriod: false,
        period: PeriodSpec(),
      ),
      reference: ref,
    );
    expect(d.series.single.values, [150000]);
    expect(d.comparison.single.values, [300000]);
    expect(ChartDataset.variation(150000, 300000), -50);
  });

  test('intervalo personalizado respeita as datas', () {
    final d = de.build(
      ChartConfig(
        id: 'c',
        source: DataSource.expenses,
        usePanelPeriod: false,
        period: PeriodSpec(
          kind: PeriodKind.customRange,
          from: DateTime(2026, 8, 11),
          to: DateTime(2026, 8, 31),
        ),
      ),
      reference: ref,
    );
    expect(d.grandTotal, 150000);
  });

  test('saldo acumulado projetado', () {
    final d = de.build(
      const ChartConfig(
        id: 'c',
        source: DataSource.balance,
        usePanelPeriod: false,
        period: PeriodSpec.relative(-1, 0),
      ),
      reference: ref,
    );
    expect(d.series.single.values, [300000, 450000]);
  });

  test('configuração do painel ida e volta em JSON', () {
    final dash = Dashboard(
      id: 'd',
      name: 'Teste',
      isDefault: true,
      filter: PanelFilter(
        period: PeriodSpec(
          kind: PeriodKind.multipleMonths,
          months: [YearMonth(2026, 1), YearMonth(2026, 3)],
        ),
        status: StatusScope.pending,
        categoryIds: const {'mor'},
      ),
      charts: const [
        ChartConfig(
          id: 'c',
          title: 'X',
          type: ChartType.waterfall,
          comparison: Comparison.previousYear,
          width: ChartWidth.full,
          palette: ChartPalette.sunset,
        ),
      ],
    );
    final back = Dashboard.fromJson(dash.toJson());
    expect(back.toJson(), dash.toJson());
    expect(back.filter.period.resolve(ref).months.length, 2);
  });

  testWidgets('cor por coluna e barras horizontais', (tester) async {
    final d = de.build(
      const ChartConfig(
        id: 'g',
        source: DataSource.expenses,
        xAxis: Dimension.category,
        usePanelPeriod: false,
        period: PeriodSpec.relative(-1, 0),
        colors: {'x:mor': 0xFFE34948},
        swapAxes: true,
      ),
      panel: const PanelFilter(),
      reference: ref,
    );
    late List<({String key, String label, Color color})> items;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              items = colorableItems(context, d);
              return DashboardChartView(data: d, height: 240);
            },
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Uma série: cada coluna tem a sua cor; a escolhida prevalece.
    expect(items.every((i) => i.key.startsWith('x:')), isTrue);
    final mor = items.firstWhere((i) => i.key == 'x:mor');
    expect(mor.color, const Color(0xFFE34948));
    expect(d.config.horizontal, isTrue);
  });
}
