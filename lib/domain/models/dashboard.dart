/// Configuração de painéis (dashboards) personalizáveis.
///
/// Painéis guardam apenas **configuração**: os números são sempre calculados
/// a partir das transações pelo motor ([DashboardEngine]), de modo que
/// qualquer criação, edição, exclusão ou mudança de status reflete
/// imediatamente em todos os gráficos.
library;

import '../../core/dates.dart';
import 'enums.dart';

DateTime _ts(Object? s) =>
    s == null ? DateTime.now() : DateTime.parse(s as String);
DateTime? _pd(Object? s) => s == null ? null : Dates.fromIso(s as String);

Set<String> _strSet(Object? v) =>
    ((v as List?) ?? const []).map((e) => e as String).toSet();

// Período --------------------------------------------------------------------

enum PeriodKind {
  /// Mês de referência do painel (o mês selecionado no seletor).
  referenceMonth('Mês de referência'),

  /// Um mês específico.
  specificMonth('Mês específico'),

  /// Vários meses escolhidos (não precisam ser consecutivos).
  multipleMonths('Vários meses'),

  /// Janela relativa ao mês de referência (ex.: 3 meses antes até 2 depois).
  relative('Meses ao redor da referência'),

  /// Ano civil (o do mês de referência quando [PeriodSpec.year] é nulo).
  year('Ano'),

  /// Intervalo de datas personalizado.
  customRange('Intervalo personalizado');

  final String label;
  const PeriodKind(this.label);
}

/// Especificação de período, resolvida contra um mês de referência para que
/// painéis com períodos relativos continuem "vivos" com o passar do tempo.
class PeriodSpec {
  final PeriodKind kind;
  final YearMonth? month;
  final List<YearMonth> months;
  final int fromOffset;
  final int toOffset;
  final int? year;
  final DateTime? from;
  final DateTime? to;

  const PeriodSpec({
    this.kind = PeriodKind.referenceMonth,
    this.month,
    this.months = const [],
    this.fromOffset = -5,
    this.toOffset = 0,
    this.year,
    this.from,
    this.to,
  });

  const PeriodSpec.relative(int from, int to)
    : this(kind: PeriodKind.relative, fromOffset: from, toOffset: to);

  PeriodSpec copyWith({
    PeriodKind? kind,
    YearMonth? month,
    List<YearMonth>? months,
    int? fromOffset,
    int? toOffset,
    Object? year = _keep,
    DateTime? from,
    DateTime? to,
  }) => PeriodSpec(
    kind: kind ?? this.kind,
    month: month ?? this.month,
    months: months ?? this.months,
    fromOffset: fromOffset ?? this.fromOffset,
    toOffset: toOffset ?? this.toOffset,
    year: identical(year, _keep) ? this.year : year as int?,
    from: from ?? this.from,
    to: to ?? this.to,
  );

  /// Resolve o período em meses (e, para intervalos, limites de data).
  ResolvedPeriod resolve(YearMonth reference) {
    switch (kind) {
      case PeriodKind.referenceMonth:
        return ResolvedPeriod([reference], label: reference.longLabel);
      case PeriodKind.specificMonth:
        final m = month ?? reference;
        return ResolvedPeriod([m], label: m.longLabel);
      case PeriodKind.multipleMonths:
        final ms = months.isEmpty ? [reference] : ([...months]..sort());
        final unique = ms.toSet().toList()..sort();
        return ResolvedPeriod(
          unique,
          label: unique.length <= 3
              ? unique.map((m) => m.shortLabel).join(', ')
              : '${unique.length} meses',
        );
      case PeriodKind.relative:
        final a = fromOffset <= toOffset ? fromOffset : toOffset;
        final b = fromOffset <= toOffset ? toOffset : fromOffset;
        final ms = YearMonth.range(reference.add(a), reference.add(b)).toList();
        return ResolvedPeriod(
          ms,
          label: ms.length == 1
              ? ms.first.longLabel
              : '${ms.first.shortLabel} – ${ms.last.shortLabel}',
        );
      case PeriodKind.year:
        final y = year ?? reference.year;
        return ResolvedPeriod(
          YearMonth.range(YearMonth(y, 1), YearMonth(y, 12)).toList(),
          label: '$y',
        );
      case PeriodKind.customRange:
        var a = from ?? reference.firstDay;
        var b = to ?? reference.lastDay;
        if (b.isBefore(a)) (a, b) = (b, a);
        return ResolvedPeriod(
          YearMonth.range(YearMonth.of(a), YearMonth.of(b)).toList(),
          from: a,
          to: b,
          label: '${Dates.format(a)} – ${Dates.format(b)}',
        );
    }
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'month': month?.key,
    'months': months.map((m) => m.key).toList(),
    'fromOffset': fromOffset,
    'toOffset': toOffset,
    'year': year,
    'from': from == null ? null : Dates.toIso(from!),
    'to': to == null ? null : Dates.toIso(to!),
  };

  factory PeriodSpec.fromJson(Map<String, Object?> j) => PeriodSpec(
    kind: enumByName(
      PeriodKind.values,
      j['kind'] as String?,
      PeriodKind.referenceMonth,
    ),
    month: j['month'] == null ? null : YearMonth.parse(j['month'] as String),
    months: ((j['months'] as List?) ?? const [])
        .map((m) => YearMonth.parse(m as String))
        .toList(),
    fromOffset: (j['fromOffset'] as int?) ?? -5,
    toOffset: (j['toOffset'] as int?) ?? 0,
    year: j['year'] as int?,
    from: _pd(j['from']),
    to: _pd(j['to']),
  );
}

const Object _keep = Object();

class ResolvedPeriod {
  final List<YearMonth> months;
  final DateTime? from;
  final DateTime? to;
  final String label;
  const ResolvedPeriod(this.months, {this.from, this.to, required this.label});

  bool get hasDateBounds => from != null && to != null;

  /// Mesmo período deslocado (comparações).
  ResolvedPeriod shift(int monthsDelta, {required String label}) {
    final ms = months.map((m) => m.add(monthsDelta)).toList();
    return ResolvedPeriod(
      ms,
      from: from == null ? null : Dates.addMonths(from!, monthsDelta),
      to: to == null ? null : Dates.addMonths(to!, monthsDelta),
      label: label,
    );
  }

  /// Quantidade de meses coberta (de ponta a ponta).
  int get span =>
      months.isEmpty ? 0 : months.first.monthsUntil(months.last) + 1;
}

// Gráfico --------------------------------------------------------------------

enum ChartType {
  bar('Barras'),
  stackedBar('Barras empilhadas'),
  line('Linhas'),
  area('Área'),
  trend('Tendência'),
  waterfall('Cascata (ponte)'),
  pareto('Pareto (80/20)'),
  pie('Pizza'),
  donut('Rosca'),
  comparative('Comparativo'),
  monthlyEvolution('Evolução mensal'),
  cumulative('Acumulado');

  final String label;
  const ChartType(this.label);

  bool get isCircular => this == pie || this == donut;

  /// Tipos de colunas que podem ser desenhados com os eixos invertidos
  /// (barras horizontais).
  bool get canSwapAxes =>
      this == bar ||
      this == stackedBar ||
      this == comparative ||
      this == waterfall ||
      this == pareto;

  /// Tipos que só fazem sentido com meses no eixo X.
  bool get requiresMonthAxis =>
      this == monthlyEvolution || this == cumulative || this == trend;
}

enum DataSource {
  income('Somente receitas'),
  expenses('Somente despesas'),
  both('Receitas e despesas'),
  net('Resultado (receitas − despesas)'),
  balance('Saldo acumulado projetado');

  final String label;
  const DataSource(this.label);
}

enum StatusScope {
  all('Todos'),
  pending('Pendentes'),
  completed('Concluídos');

  final String label;
  const StatusScope(this.label);

  Set<TransactionStatus> get statuses => switch (this) {
    StatusScope.all => const {
      TransactionStatus.planned,
      TransactionStatus.pending,
      TransactionStatus.completed,
    },
    StatusScope.pending => const {
      TransactionStatus.planned,
      TransactionStatus.pending,
    },
    StatusScope.completed => const {TransactionStatus.completed},
  };

  /// Interseção entre o filtro do gráfico e o filtro do painel.
  Set<TransactionStatus> intersect(StatusScope other) =>
      statuses.intersection(other.statuses);
}

/// Dimensões usadas no eixo X e no agrupamento das séries.
enum Dimension {
  none('Nenhum'),
  month('Mês'),
  year('Ano'),
  category('Categoria'),
  subcategory('Subcategoria'),
  type('Receita / despesa'),
  status('Status'),
  realization('Realizado × previsto'),
  account('Conta / cartão'),
  project('Projeto');

  final String label;
  const Dimension(this.label);

  static const xAxisOptions = [
    month,
    year,
    category,
    subcategory,
    type,
    status,
    realization,
    account,
    project,
  ];
  static const seriesOptions = [
    none,
    type,
    category,
    status,
    realization,
    account,
  ];
}

enum Measure {
  sum('Soma dos valores'),
  count('Quantidade de lançamentos'),
  average('Valor médio');

  final String label;
  const Measure(this.label);
}

enum Comparison {
  none('Sem comparação'),
  previousPeriod('Período anterior'),
  previousYear('Mesmo período do ano anterior');

  final String label;
  const Comparison(this.label);
}

enum ChartPalette {
  auto('Automática'),
  categorical('Categórica'),
  ocean('Oceano'),
  sunset('Pôr do sol'),
  forest('Floresta'),
  mono('Monocromática'),
  categories('Cores das categorias');

  final String label;
  const ChartPalette(this.label);
}

/// Largura do cartão no grid responsivo (em colunas de uma grade de 6).
enum ChartWidth {
  third('Pequeno', 2),
  half('Médio', 3),
  twoThirds('Grande', 4),
  full('Largura total', 6);

  final String label;
  final int span;
  const ChartWidth(this.label, this.span);
}

enum ChartHeight {
  compact('Baixo', 180),
  normal('Normal', 240),
  tall('Alto', 320);

  final String label;
  final double plotHeight;
  const ChartHeight(this.label, this.plotHeight);
}

class ChartConfig {
  final String id;
  final String title;
  final ChartType type;
  final DataSource source;
  final Set<String> categoryIds;
  final StatusScope status;
  final bool usePanelPeriod;
  final PeriodSpec period;
  final Dimension xAxis;
  final Dimension seriesBy;
  final Measure measure;
  final Comparison comparison;
  final bool showTotals;
  final bool showPercentages;
  final bool showVariation;
  final bool showValues;
  final bool showLegend;
  final ChartPalette palette;
  final ChartWidth width;
  final ChartHeight height;

  /// Cores escolhidas pelo usuário, por série (`s:<chave>`) ou por
  /// coluna/fatia (`x:<chave>`), em ARGB. Sobrepõem a paleta.
  final Map<String, int> colors;

  /// Eixos invertidos: categorias na vertical e valores na horizontal
  /// (barras horizontais). Vale para os tipos com [ChartType.canSwapAxes].
  final bool swapAxes;

  const ChartConfig({
    required this.id,
    this.title = '',
    this.type = ChartType.bar,
    this.source = DataSource.both,
    this.categoryIds = const {},
    this.status = StatusScope.all,
    this.usePanelPeriod = true,
    this.period = const PeriodSpec.relative(-5, 0),
    this.xAxis = Dimension.month,
    this.seriesBy = Dimension.none,
    this.measure = Measure.sum,
    this.comparison = Comparison.none,
    this.showTotals = true,
    this.showPercentages = false,
    this.showVariation = false,
    this.showValues = false,
    this.showLegend = true,
    this.palette = ChartPalette.auto,
    this.width = ChartWidth.half,
    this.height = ChartHeight.normal,
    this.colors = const {},
    this.swapAxes = false,
  });

  /// Barras horizontais efetivamente desenhadas.
  bool get horizontal => swapAxes && type.canSwapAxes;

  static String seriesColorKey(String key) => 's:$key';
  static String xColorKey(String key) => 'x:$key';

  /// Título exibido (gera um automático quando vazio).
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final what = switch (source) {
      DataSource.income => 'Receitas',
      DataSource.expenses => 'Despesas',
      DataSource.both => 'Receitas × despesas',
      DataSource.net => 'Resultado',
      DataSource.balance => 'Saldo acumulado',
    };
    final by = xAxis == Dimension.month
        ? 'por mês'
        : 'por ${xAxis.label.toLowerCase()}';
    return '$what $by';
  }

  ChartConfig copyWith({
    String? id,
    String? title,
    ChartType? type,
    DataSource? source,
    Set<String>? categoryIds,
    StatusScope? status,
    bool? usePanelPeriod,
    PeriodSpec? period,
    Dimension? xAxis,
    Dimension? seriesBy,
    Measure? measure,
    Comparison? comparison,
    bool? showTotals,
    bool? showPercentages,
    bool? showVariation,
    bool? showValues,
    bool? showLegend,
    ChartPalette? palette,
    ChartWidth? width,
    ChartHeight? height,
    Map<String, int>? colors,
    bool? swapAxes,
  }) => ChartConfig(
    id: id ?? this.id,
    title: title ?? this.title,
    type: type ?? this.type,
    source: source ?? this.source,
    categoryIds: categoryIds ?? this.categoryIds,
    status: status ?? this.status,
    usePanelPeriod: usePanelPeriod ?? this.usePanelPeriod,
    period: period ?? this.period,
    xAxis: xAxis ?? this.xAxis,
    seriesBy: seriesBy ?? this.seriesBy,
    measure: measure ?? this.measure,
    comparison: comparison ?? this.comparison,
    showTotals: showTotals ?? this.showTotals,
    showPercentages: showPercentages ?? this.showPercentages,
    showVariation: showVariation ?? this.showVariation,
    showValues: showValues ?? this.showValues,
    showLegend: showLegend ?? this.showLegend,
    palette: palette ?? this.palette,
    width: width ?? this.width,
    height: height ?? this.height,
    colors: colors ?? this.colors,
    swapAxes: swapAxes ?? this.swapAxes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'type': type.name,
    'source': source.name,
    'categoryIds': categoryIds.toList(),
    'status': status.name,
    'usePanelPeriod': usePanelPeriod,
    'period': period.toJson(),
    'xAxis': xAxis.name,
    'seriesBy': seriesBy.name,
    'measure': measure.name,
    'comparison': comparison.name,
    'showTotals': showTotals,
    'showPercentages': showPercentages,
    'showVariation': showVariation,
    'showValues': showValues,
    'showLegend': showLegend,
    'palette': palette.name,
    'width': width.name,
    'height': height.name,
    'colors': colors,
    'swapAxes': swapAxes,
  };

  factory ChartConfig.fromJson(Map<String, Object?> j) => ChartConfig(
    id: j['id'] as String,
    title: (j['title'] as String?) ?? '',
    type: enumByName(ChartType.values, j['type'] as String?, ChartType.bar),
    source: enumByName(
      DataSource.values,
      j['source'] as String?,
      DataSource.both,
    ),
    categoryIds: _strSet(j['categoryIds']),
    status: enumByName(
      StatusScope.values,
      j['status'] as String?,
      StatusScope.all,
    ),
    usePanelPeriod: (j['usePanelPeriod'] as bool?) ?? true,
    period: j['period'] == null
        ? const PeriodSpec.relative(-5, 0)
        : PeriodSpec.fromJson(Map<String, Object?>.from(j['period'] as Map)),
    xAxis: enumByName(Dimension.values, j['xAxis'] as String?, Dimension.month),
    seriesBy: enumByName(
      Dimension.values,
      j['seriesBy'] as String?,
      Dimension.none,
    ),
    measure: enumByName(Measure.values, j['measure'] as String?, Measure.sum),
    comparison: enumByName(
      Comparison.values,
      j['comparison'] as String?,
      Comparison.none,
    ),
    showTotals: (j['showTotals'] as bool?) ?? true,
    showPercentages: (j['showPercentages'] as bool?) ?? false,
    showVariation: (j['showVariation'] as bool?) ?? false,
    showValues: (j['showValues'] as bool?) ?? false,
    showLegend: (j['showLegend'] as bool?) ?? true,
    palette: enumByName(
      ChartPalette.values,
      j['palette'] as String?,
      ChartPalette.auto,
    ),
    width: enumByName(
      ChartWidth.values,
      j['width'] as String?,
      ChartWidth.half,
    ),
    height: enumByName(
      ChartHeight.values,
      j['height'] as String?,
      ChartHeight.normal,
    ),
    colors: {
      if (j['colors'] is Map)
        for (final e in (j['colors'] as Map).entries)
          if (e.value is int) '${e.key}': e.value as int,
    },
    swapAxes: (j['swapAxes'] as bool?) ?? false,
  );
}

// Painel ---------------------------------------------------------------------

/// Filtros do painel, aplicados a todos os gráficos ao mesmo tempo.
class PanelFilter {
  /// Período usado pelos gráficos que seguem o período do painel.
  final PeriodSpec period;

  /// Restringe o status em todos os gráficos (interseção com o do gráfico).
  final StatusScope status;

  /// Restringe as categorias em todos os gráficos (vazio = todas).
  final Set<String> categoryIds;

  const PanelFilter({
    this.period = const PeriodSpec.relative(-5, 0),
    this.status = StatusScope.all,
    this.categoryIds = const {},
  });

  PanelFilter copyWith({
    PeriodSpec? period,
    StatusScope? status,
    Set<String>? categoryIds,
  }) => PanelFilter(
    period: period ?? this.period,
    status: status ?? this.status,
    categoryIds: categoryIds ?? this.categoryIds,
  );

  Map<String, Object?> toJson() => {
    'period': period.toJson(),
    'status': status.name,
    'categoryIds': categoryIds.toList(),
  };

  factory PanelFilter.fromJson(Map<String, Object?> j) => PanelFilter(
    period: j['period'] == null
        ? const PeriodSpec.relative(-5, 0)
        : PeriodSpec.fromJson(Map<String, Object?>.from(j['period'] as Map)),
    status: enumByName(
      StatusScope.values,
      j['status'] as String?,
      StatusScope.all,
    ),
    categoryIds: _strSet(j['categoryIds']),
  );
}

class Dashboard {
  final String id;
  final String name;
  final bool isDefault;
  final int order;
  final PanelFilter filter;
  final List<ChartConfig> charts;
  final DateTime createdAt;
  final DateTime updatedAt;

  Dashboard({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.order = 0,
    this.filter = const PanelFilter(),
    this.charts = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Dashboard copyWith({
    String? id,
    String? name,
    bool? isDefault,
    int? order,
    PanelFilter? filter,
    List<ChartConfig>? charts,
  }) => Dashboard(
    id: id ?? this.id,
    name: name ?? this.name,
    isDefault: isDefault ?? this.isDefault,
    order: order ?? this.order,
    filter: filter ?? this.filter,
    charts: charts ?? this.charts,
    createdAt: id == null ? createdAt : DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'isDefault': isDefault,
    'order': order,
    'filter': filter.toJson(),
    'charts': charts.map((c) => c.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Dashboard.fromJson(Map<String, Object?> j) => Dashboard(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? 'Painel',
    isDefault: (j['isDefault'] as bool?) ?? false,
    order: (j['order'] as int?) ?? 0,
    filter: j['filter'] == null
        ? const PanelFilter()
        : PanelFilter.fromJson(Map<String, Object?>.from(j['filter'] as Map)),
    charts: ((j['charts'] as List?) ?? const [])
        .map((c) => ChartConfig.fromJson(Map<String, Object?>.from(c as Map)))
        .toList(),
    createdAt: _ts(j['createdAt']),
    updatedAt: _ts(j['updatedAt']),
  );
}
