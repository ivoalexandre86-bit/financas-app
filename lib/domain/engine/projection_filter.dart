import '../../core/dates.dart';
import '../models/entities.dart';

/// Origem de um evento financeiro (usada em filtros e no drill-down).
enum EventSource {
  installment('Parcelamentos'),
  recurring('Recorrentes'),
  card('Cartões de crédito'),
  other('Outras');

  final String label;
  const EventSource(this.label);
}

/// Filtros combináveis aplicados igualmente à matriz de projeção, ao
/// drill-down e aos indicadores. Conjuntos vazios significam "todos".
class ProjectionFilter {
  final Set<String> accountIds;
  final Set<String> cardIds;
  final Set<String> categoryIds;
  final Set<String> projectIds;
  final Set<TransactionType> types;
  final Set<TransactionStatus> statuses;
  final Set<EventSource> sources;

  static const defaultStatuses = {
    TransactionStatus.planned,
    TransactionStatus.pending,
    TransactionStatus.completed,
  };

  const ProjectionFilter({
    this.accountIds = const {},
    this.cardIds = const {},
    this.categoryIds = const {},
    this.projectIds = const {},
    this.types = const {},
    this.statuses = defaultStatuses,
    this.sources = const {},
  });

  static const none = ProjectionFilter();

  ProjectionFilter copyWith({
    Set<String>? accountIds,
    Set<String>? cardIds,
    Set<String>? categoryIds,
    Set<String>? projectIds,
    Set<TransactionType>? types,
    Set<TransactionStatus>? statuses,
    Set<EventSource>? sources,
  }) => ProjectionFilter(
    accountIds: accountIds ?? this.accountIds,
    cardIds: cardIds ?? this.cardIds,
    categoryIds: categoryIds ?? this.categoryIds,
    projectIds: projectIds ?? this.projectIds,
    types: types ?? this.types,
    statuses: statuses ?? this.statuses,
    sources: sources ?? this.sources,
  );

  bool get hasLocationFilter => accountIds.isNotEmpty || cardIds.isNotEmpty;

  /// Quando há filtros de categoria/projeto/tipo/origem/status, o saldo
  /// acumulado deixa de representar o saldo das contas e passa a ser o
  /// acumulado do recorte no período (começando em zero).
  bool get isBalanceScoped =>
      categoryIds.isEmpty &&
      projectIds.isEmpty &&
      types.isEmpty &&
      sources.isEmpty &&
      statuses.length == defaultStatuses.length &&
      statuses.containsAll(defaultStatuses);

  int get activeCount =>
      (accountIds.isNotEmpty ? 1 : 0) +
      (cardIds.isNotEmpty ? 1 : 0) +
      (categoryIds.isNotEmpty ? 1 : 0) +
      (projectIds.isNotEmpty ? 1 : 0) +
      (types.isNotEmpty ? 1 : 0) +
      (sources.isNotEmpty ? 1 : 0) +
      (hasCustomStatuses ? 1 : 0);

  bool get hasCustomStatuses =>
      statuses.length != defaultStatuses.length ||
      !statuses.containsAll(defaultStatuses);

  bool get isEmpty => activeCount == 0;
}

/// Intervalo de meses exibido na projeção.
class MonthRange {
  final YearMonth from;
  final YearMonth to;
  const MonthRange(this.from, this.to);

  factory MonthRange.starting(YearMonth from, int months) =>
      MonthRange(from, from.add(months - 1));

  int get length => from.monthsUntil(to) + 1;
  List<YearMonth> get months => YearMonth.range(from, to).toList();
}
