import '../core/ids.dart';
import '../domain/models/dashboard.dart';

/// Painel criado no primeiro acesso. Reproduz os gráficos que a tela
/// inicial já tinha (Receitas × Despesas e Tendência do saldo) e adiciona
/// exemplos de análises (categorias, Pareto, realizado × previsto, cascata).
Dashboard defaultDashboard() => Dashboard(
  id: newId('dash_'),
  name: 'Visão geral',
  isDefault: true,
  filter: const PanelFilter(period: PeriodSpec.relative(-3, 2)),
  charts: [
    ChartConfig(
      id: newId('ch_'),
      title: 'Receitas × Despesas',
      type: ChartType.bar,
      source: DataSource.both,
      xAxis: Dimension.month,
    ),
    ChartConfig(
      id: newId('ch_'),
      title: 'Tendência do saldo',
      type: ChartType.area,
      source: DataSource.balance,
      usePanelPeriod: false,
      period: const PeriodSpec.relative(-2, 5),
      showTotals: false,
    ),
    ChartConfig(
      id: newId('ch_'),
      title: 'Despesas do mês por categoria',
      type: ChartType.donut,
      source: DataSource.expenses,
      xAxis: Dimension.category,
      usePanelPeriod: false,
      period: const PeriodSpec(),
      showPercentages: true,
      palette: ChartPalette.categorical,
      width: ChartWidth.third,
    ),
    ChartConfig(
      id: newId('ch_'),
      title: 'Pareto das despesas (80/20)',
      type: ChartType.pareto,
      source: DataSource.expenses,
      xAxis: Dimension.category,
      width: ChartWidth.twoThirds,
    ),
    ChartConfig(
      id: newId('ch_'),
      title: 'Despesas: realizado × previsto',
      type: ChartType.stackedBar,
      source: DataSource.expenses,
      xAxis: Dimension.month,
      seriesBy: Dimension.realization,
    ),
    ChartConfig(
      id: newId('ch_'),
      title: 'Resultado mês a mês',
      type: ChartType.waterfall,
      source: DataSource.net,
      xAxis: Dimension.month,
    ),
  ],
);

/// Painel vazio para "Novo painel".
Dashboard emptyDashboard(String name, {int order = 0}) => Dashboard(
  id: newId('dash_'),
  name: name,
  order: order,
  filter: const PanelFilter(period: PeriodSpec.relative(-5, 0)),
);
