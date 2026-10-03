import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/dashboard.dart';
import '../models/entities.dart';
import 'financial_engine.dart';

/// Papel de uma série (usado para cores automáticas e sinal na cascata).
enum SeriesRole { income, expense, net, balance, other }

class ChartSeries {
  final String key;
  final String name;

  /// Um valor por item do eixo X (centavos, ou quantidade em [Measure.count]).
  final List<int> values;
  final SeriesRole role;

  /// Cor própria (ex.: cor da categoria), em ARGB.
  final int? color;
  final int total;

  const ChartSeries({
    required this.key,
    required this.name,
    required this.values,
    required this.role,
    required this.total,
    this.color,
  });

  /// Sinal na composição de resultado (despesas subtraem).
  int get sign => role == SeriesRole.expense ? -1 : 1;
}

/// Dados prontos para desenhar um gráfico.
class ChartDataset {
  final ChartConfig config;

  /// Tipo efetivamente desenhado (pode diferir do configurado quando a
  /// combinação exige ajustes, ex.: saldo só por mês).
  final Dimension xAxis;
  final List<String> xKeys;
  final List<String> xLabels;
  final List<int?> xColors;
  final List<ChartSeries> series;

  /// Séries do período de comparação, alinhadas a [series] (mesma ordem e
  /// mesmo eixo X). Vazio quando não há comparação.
  final List<ChartSeries> comparison;
  final ResolvedPeriod period;
  final ResolvedPeriod? comparisonPeriod;
  final bool isMoney;

  const ChartDataset({
    required this.config,
    required this.xAxis,
    required this.xKeys,
    required this.xLabels,
    required this.xColors,
    required this.series,
    required this.comparison,
    required this.period,
    required this.comparisonPeriod,
    required this.isMoney,
  });

  bool get isEmpty =>
      xKeys.isEmpty || series.every((s) => s.values.every((v) => v == 0));

  bool get hasComparison => comparison.isNotEmpty;

  /// Total geral (soma das séries com seus sinais quando é resultado).
  int get grandTotal => series.fold(0, (a, s) => a + s.total);

  /// Valor por item do eixo X somando as séries (com sinal, se [signed]).
  List<int> combined({bool signed = false}) => [
    for (var i = 0; i < xKeys.length; i++)
      series.fold(0, (a, s) => a + s.values[i] * (signed ? s.sign : 1)),
  ];

  /// Variação percentual entre dois valores (null quando não definida).
  static double? variation(int current, int previous) {
    if (previous == 0) return null;
    return (current - previous) / previous.abs() * 100;
  }
}

/// Calcula os dados dos gráficos dos painéis a partir do [FinancialEngine],
/// reaproveitando exatamente as mesmas regras de reconhecimento (mês da
/// fatura para cartões, transferências fora, recorrências virtuais…).
class DashboardEngine {
  final FinancialEngine engine;
  DashboardEngine(this.engine);

  FinanceData get data => engine.data;

  static const _maxX = 12;
  static const _maxSlices = 8;
  static const _maxSeries = 8;
  static const otherKey = '__other__';

  /// Gera o conjunto de dados de um gráfico.
  ChartDataset build(
    ChartConfig c, {
    PanelFilter panel = const PanelFilter(),
    YearMonth? reference,
  }) {
    final ref = reference ?? engine.currentMonth;
    final period = (c.usePanelPeriod ? panel.period : c.period).resolve(ref);

    var xAxis = c.xAxis == Dimension.none ? Dimension.month : c.xAxis;
    var seriesBy = c.seriesBy;
    if (c.type.requiresMonthAxis &&
        xAxis != Dimension.month &&
        xAxis != Dimension.year) {
      xAxis = Dimension.month;
    }
    if (c.source == DataSource.balance) {
      xAxis = Dimension.month;
      seriesBy = Dimension.none;
    }
    if (c.source == DataSource.both &&
        seriesBy == Dimension.none &&
        xAxis != Dimension.type) {
      seriesBy = Dimension.type;
    }
    if (seriesBy == xAxis) seriesBy = Dimension.none;
    // Pizza/rosca/pareto mostram uma única distribuição.
    if (c.type.isCircular || c.type == ChartType.pareto) {
      if (xAxis == Dimension.month && seriesBy != Dimension.none) {
        xAxis = seriesBy;
      }
      seriesBy = Dimension.none;
    }

    var comparison = c.comparison;
    if (c.type == ChartType.comparative && comparison == Comparison.none) {
      comparison = Comparison.previousPeriod;
    }
    ResolvedPeriod? cmpPeriod;
    if (comparison == Comparison.previousPeriod) {
      final n = period.span;
      cmpPeriod = period.shift(-n, label: 'Período anterior');
    } else if (comparison == Comparison.previousYear) {
      cmpPeriod = period.shift(-12, label: 'Ano anterior');
    }

    if (c.source == DataSource.balance) {
      return _balance(c, period, cmpPeriod, panel);
    }

    final filter = _filter(c, panel);
    final current = _aggregate(c, filter, period, xAxis, seriesBy);

    // Eixo X ----------------------------------------------------------------
    List<String> xKeys;
    if (xAxis == Dimension.month) {
      xKeys = period.months.map((m) => m.key).toList();
    } else if (xAxis == Dimension.year) {
      xKeys = {for (final m in period.months) '${m.year}'}.toList()..sort();
    } else {
      xKeys = _rankKeys(current.xTotals, _limitX(c.type));
    }
    final foldX =
        xAxis != Dimension.month &&
        xAxis != Dimension.year &&
        xKeys.contains(otherKey);

    // Séries ----------------------------------------------------------------
    final seriesKeys = seriesBy == Dimension.none
        ? ['all']
        : _rankKeys(current.seriesTotals, _maxSeries);
    final foldS = seriesKeys.contains(otherKey);

    List<ChartSeries> makeSeries(_Agg agg, {List<int>? monthIndex}) {
      return [
        for (final sk in seriesKeys)
          () {
            final values = List<int>.filled(xKeys.length, 0);
            final sums = List<int>.filled(xKeys.length, 0);
            final counts = List<int>.filled(xKeys.length, 0);
            var tSum = 0, tCount = 0;
            agg.cells.forEach((xk, row) {
              int xi;
              if (monthIndex != null) {
                xi = agg.xOrder.indexOf(xk);
                xi = xi < 0 ? -1 : monthIndex[xi];
              } else {
                xi = xKeys.indexOf(xk);
                if (xi < 0 && foldX) xi = xKeys.indexOf(otherKey);
              }
              row.forEach((rk, cell) {
                final match =
                    rk == sk ||
                    (foldS && sk == otherKey && !seriesKeys.contains(rk));
                if (!match) return;
                tSum += cell.sum;
                tCount += cell.count;
                if (xi < 0) return;
                sums[xi] += cell.sum;
                counts[xi] += cell.count;
              });
            });
            for (var i = 0; i < values.length; i++) {
              values[i] = _measure(c.measure, sums[i], counts[i]);
            }
            return ChartSeries(
              key: sk,
              name: sk == 'all' ? _sourceLabel(c.source) : _label(seriesBy, sk),
              values: values,
              role: _role(c.source, seriesBy, sk),
              color: _color(seriesBy, sk),
              total: _measure(c.measure, tSum, tCount),
            );
          }(),
      ];
    }

    final series = makeSeries(current);
    var cmp = <ChartSeries>[];
    if (cmpPeriod != null) {
      final prev = _aggregate(c, filter, cmpPeriod, xAxis, seriesBy);
      if (xAxis == Dimension.month) {
        // Alinha por posição: 1º mês do período anterior ↔ 1º mês atual.
        final idx = [
          for (final k in prev.xOrder)
            cmpPeriod.months.indexWhere((m) => m.key == k),
        ];
        cmp = makeSeries(prev, monthIndex: idx);
      } else if (xAxis == Dimension.year) {
        final years = {for (final m in cmpPeriod.months) '${m.year}'}.toList()
          ..sort();
        final idx = [for (final k in prev.xOrder) years.indexOf(k)];
        cmp = makeSeries(prev, monthIndex: idx);
      } else {
        cmp = makeSeries(prev);
      }
    }

    return ChartDataset(
      config: c,
      xAxis: xAxis,
      xKeys: xKeys,
      xLabels: [for (final k in xKeys) _label(xAxis, k)],
      xColors: [for (final k in xKeys) _color(xAxis, k)],
      series: series,
      comparison: cmp,
      period: period,
      comparisonPeriod: cmpPeriod,
      isMoney: c.measure != Measure.count,
    );
  }

  // ---------------------------------------------------------------------------

  int _limitX(ChartType t) => t.isCircular
      ? _maxSlices
      : t == ChartType.pareto
      ? 15
      : _maxX;

  static int _measure(Measure m, int sum, int count) => switch (m) {
    Measure.sum => sum,
    Measure.count => count,
    Measure.average => count == 0 ? 0 : (sum / count).round(),
  };

  Set<String> _expand(Set<String> ids) {
    if (ids.isEmpty) return ids;
    return {
      ...ids,
      for (final c in data.categories)
        if (c.parentId != null && ids.contains(c.parentId)) c.id,
    };
  }

  ProjectionFilter _filter(ChartConfig c, PanelFilter panel) {
    final types = switch (c.source) {
      DataSource.income => {TransactionType.income},
      DataSource.expenses => {TransactionType.expense},
      _ => <TransactionType>{},
    };
    final a = _expand(c.categoryIds);
    final b = _expand(panel.categoryIds);
    Set<String> cats;
    if (a.isEmpty) {
      cats = b;
    } else if (b.isEmpty) {
      cats = a;
    } else {
      cats = a.intersection(b);
      if (cats.isEmpty) cats = {'__nenhuma__'};
    }
    return ProjectionFilter(
      types: types,
      statuses: c.status.intersect(panel.status),
      categoryIds: cats,
    );
  }

  _Agg _aggregate(
    ChartConfig c,
    ProjectionFilter filter,
    ResolvedPeriod period,
    Dimension xAxis,
    Dimension seriesBy,
  ) {
    final agg = _Agg();
    if (period.months.isEmpty || filter.statuses.isEmpty) return agg;
    if (xAxis == Dimension.month) {
      agg.xOrder.addAll(period.months.map((m) => m.key));
    } else if (xAxis == Dimension.year) {
      agg.xOrder.addAll({for (final m in period.months) '${m.year}'});
    }
    final monthSet = period.months.toSet();
    final last = period.months.reduce((a, b) => a > b ? a : b);
    for (final e in engine.recognizedEvents(filter, last)) {
      if (!monthSet.contains(e.month)) continue;
      if (period.hasDateBounds) {
        final d = engine.recognitionDate(e.tx);
        if (d.isBefore(period.from!) || d.isAfter(period.to!)) continue;
      }
      final v = c.source == DataSource.net
          ? e.signed.cents
          : e.signed.cents.abs();
      final xk = _key(xAxis, e);
      final sk = seriesBy == Dimension.none ? 'all' : _key(seriesBy, e);
      agg.add(xk, sk, v);
    }
    return agg;
  }

  ChartDataset _balance(
    ChartConfig c,
    ResolvedPeriod period,
    ResolvedPeriod? cmpPeriod,
    PanelFilter panel,
  ) {
    List<int> values(ResolvedPeriod p) {
      if (p.months.isEmpty) return const [];
      final first = p.months.reduce((a, b) => a < b ? a : b);
      final last = p.months.reduce((a, b) => a > b ? a : b);
      final res = engine.projection(MonthRange(first, last));
      final byMonth = {
        for (final col in res.columns) col.month: col.accumulated,
      };
      return [for (final m in p.months) (byMonth[m] ?? Money.zero).cents];
    }

    ChartSeries s(String name, List<int> v) => ChartSeries(
      key: 'balance',
      name: name,
      values: v,
      role: SeriesRole.balance,
      total: v.isEmpty ? 0 : v.last,
    );
    return ChartDataset(
      config: c,
      xAxis: Dimension.month,
      xKeys: period.months.map((m) => m.key).toList(),
      xLabels: period.months.map((m) => m.shortLabel).toList(),
      xColors: List.filled(period.months.length, null),
      series: [s('Saldo projetado', values(period))],
      comparison: cmpPeriod == null
          ? const []
          : [s('Saldo · ${cmpPeriod.label.toLowerCase()}', values(cmpPeriod))],
      period: period,
      comparisonPeriod: cmpPeriod,
      isMoney: true,
    );
  }

  /// Ordena por magnitude e agrupa o excedente em "Outros".
  static List<String> _rankKeys(Map<String, int> totals, int limit) {
    final keys = totals.keys.toList()
      ..sort((a, b) => totals[b]!.abs().compareTo(totals[a]!.abs()));
    if (keys.length <= limit) return keys;
    return [...keys.take(limit - 1), otherKey];
  }

  String _key(Dimension d, RecognizedEvent e) {
    final t = e.tx;
    return switch (d) {
      Dimension.none => 'all',
      Dimension.month => e.month.key,
      Dimension.year => '${e.month.year}',
      Dimension.category => engine.rootCategoryId(t.categoryId),
      Dimension.subcategory => t.categoryId ?? '',
      Dimension.type => t.type.name,
      Dimension.status =>
        t.status == TransactionStatus.completed ? 'completed' : 'pending',
      Dimension.realization => engine.isRealized(t) ? 'actual' : 'planned',
      Dimension.account =>
        t.cardId != null ? 'c:${t.cardId}' : 'a:${t.accountId ?? ''}',
      Dimension.project => t.projectId ?? '',
    };
  }

  String _label(Dimension d, String key) {
    if (key == otherKey) return 'Outros';
    switch (d) {
      case Dimension.month:
        return YearMonth.parse(key).shortLabel;
      case Dimension.category:
      case Dimension.subcategory:
        if (key.isEmpty) return 'Sem categoria';
        return d == Dimension.category
            ? (data.categoryById[key]?.name ?? 'Sem categoria')
            : engine.categoryLabel(key);
      case Dimension.type:
        return key == 'income' ? 'Receitas' : 'Despesas';
      case Dimension.status:
        return key == 'completed' ? 'Concluídos' : 'Pendentes';
      case Dimension.realization:
        return key == 'actual' ? 'Realizado' : 'Previsto';
      case Dimension.account:
        final id = key.substring(2);
        if (key.startsWith('c:')) return data.cardById[id]?.name ?? 'Cartão';
        return data.accountById[id]?.name ?? 'Sem conta';
      case Dimension.project:
        return key.isEmpty
            ? 'Sem projeto'
            : (data.projectById[key]?.name ?? 'Projeto');
      case Dimension.none:
      case Dimension.year:
        return key;
    }
  }

  int? _color(Dimension d, String key) {
    if (d == Dimension.category || d == Dimension.subcategory) {
      return data.categoryById[key]?.color;
    }
    return null;
  }

  static String _sourceLabel(DataSource s) => switch (s) {
    DataSource.income => 'Receitas',
    DataSource.expenses => 'Despesas',
    DataSource.both => 'Valores',
    DataSource.net => 'Resultado',
    DataSource.balance => 'Saldo',
  };

  SeriesRole _role(DataSource s, Dimension seriesBy, String key) {
    if (seriesBy == Dimension.type) {
      return key == 'income' ? SeriesRole.income : SeriesRole.expense;
    }
    if (seriesBy == Dimension.category || seriesBy == Dimension.none) {
      if (s == DataSource.income) return SeriesRole.income;
      if (s == DataSource.expenses) return SeriesRole.expense;
      if (seriesBy == Dimension.category) {
        final kind = data.categoryById[key]?.kind;
        if (kind == CategoryKind.expense) return SeriesRole.expense;
        if (kind == CategoryKind.income) return SeriesRole.income;
      }
    }
    return switch (s) {
      DataSource.income => SeriesRole.income,
      DataSource.expenses => SeriesRole.expense,
      DataSource.net => SeriesRole.net,
      DataSource.balance => SeriesRole.balance,
      DataSource.both => SeriesRole.other,
    };
  }
}

class _Cell {
  int sum = 0;
  int count = 0;
}

class _Agg {
  /// xKey → seriesKey → célula.
  final cells = <String, Map<String, _Cell>>{};
  final xOrder = <String>[];
  final xTotals = <String, int>{};
  final seriesTotals = <String, int>{};

  void add(String xk, String sk, int v) {
    final cell = cells.putIfAbsent(xk, () => {}).putIfAbsent(sk, _Cell.new);
    cell.sum += v;
    cell.count++;
    xTotals[xk] = (xTotals[xk] ?? 0) + v;
    seriesTotals[sk] = (seriesTotals[sk] ?? 0) + v;
  }
}
