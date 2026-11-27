import '../../core/dates.dart';
import '../../core/money.dart';

// Cenários de planejamento: um conjunto de fluxos de caixa previstos que só
// entram na Projeção quando o cenário é escolhido. O orçamento oficial (base)
// nunca é alterado por um cenário.
//
// Modelo comum para FGTS (saques simulados), dívidas (amortizações,
// quitações) e o "O que fazer agora?" do fechamento do mês. Cada módulo usa
// [ScenarioFlow.source] e [ScenarioFlow.refId] para achar os seus fluxos.

/// Origem de um cenário ou fluxo.
abstract final class ScenarioSource {
  static const fgts = 'fgts';
  static const debt = 'debt';
  static const monthEnd = 'monthEnd';
  static const manual = 'manual';
}

/// Fluxo de caixa previsto de um cenário.
class ScenarioFlow {
  final String id;
  final DateTime date;

  /// Valor com sinal: positivo entra no caixa, negativo sai.
  final Money amount;
  final String description;

  /// Quem criou o fluxo (ver [ScenarioSource]).
  final String source;

  /// Registro de origem (ex.: id do FGTS ou do contrato).
  final String? refId;

  /// Finalidade (ex.: motivo do saque do FGTS).
  final String purpose;

  /// O valor foi confirmado (extrato, comprovante, proposta) ou é estimativa.
  final bool amountConfirmed;

  /// A data foi confirmada ou é estimativa.
  final bool dateConfirmed;

  /// Já aconteceu e foi lançado no orçamento: sai da sobreposição para não
  /// contar duas vezes.
  final bool realized;

  /// Lançamento real que registrou o fluxo, quando [realized].
  final String? transactionId;
  final String notes;

  const ScenarioFlow({
    required this.id,
    required this.date,
    required this.amount,
    required this.description,
    this.source = ScenarioSource.manual,
    this.refId,
    this.purpose = '',
    this.amountConfirmed = false,
    this.dateConfirmed = false,
    this.realized = false,
    this.transactionId,
    this.notes = '',
  });

  bool get isEstimate => !amountConfirmed || !dateConfirmed;

  ScenarioFlow copyWith({
    DateTime? date,
    Money? amount,
    String? description,
    String? purpose,
    bool? amountConfirmed,
    bool? dateConfirmed,
    bool? realized,
    String? transactionId,
    bool clearTransaction = false,
    String? notes,
  }) => ScenarioFlow(
    id: id,
    date: date ?? this.date,
    amount: amount ?? this.amount,
    description: description ?? this.description,
    source: source,
    refId: refId,
    purpose: purpose ?? this.purpose,
    amountConfirmed: amountConfirmed ?? this.amountConfirmed,
    dateConfirmed: dateConfirmed ?? this.dateConfirmed,
    realized: realized ?? this.realized,
    transactionId: clearTransaction
        ? null
        : (transactionId ?? this.transactionId),
    notes: notes ?? this.notes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'date': Dates.toIso(date),
    'amount': amount.cents,
    'description': description,
    'source': source,
    if (refId != null) 'refId': refId,
    if (purpose.isNotEmpty) 'purpose': purpose,
    'amountConfirmed': amountConfirmed,
    'dateConfirmed': dateConfirmed,
    if (realized) 'realized': true,
    if (transactionId != null) 'transactionId': transactionId,
    if (notes.isNotEmpty) 'notes': notes,
  };

  factory ScenarioFlow.fromJson(Map<String, Object?> j) => ScenarioFlow(
    id: j['id'] as String,
    date: Dates.fromIso(j['date'] as String),
    amount: Money((j['amount'] as num?)?.toInt() ?? 0),
    description: (j['description'] as String?) ?? '',
    source: (j['source'] as String?) ?? ScenarioSource.manual,
    refId: j['refId'] as String?,
    purpose: (j['purpose'] as String?) ?? '',
    amountConfirmed: (j['amountConfirmed'] as bool?) ?? false,
    dateConfirmed: (j['dateConfirmed'] as bool?) ?? false,
    realized: (j['realized'] as bool?) ?? false,
    transactionId: j['transactionId'] as String?,
    notes: (j['notes'] as String?) ?? '',
  );
}

/// Cenário de planejamento (coleção `scenarios`).
class PlanScenario {
  final String id;
  final String name;

  /// Módulo que criou o cenário (ver [ScenarioSource]).
  final String kind;
  final List<ScenarioFlow> flows;
  final String notes;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  PlanScenario({
    required this.id,
    required this.name,
    this.kind = ScenarioSource.manual,
    this.flows = const [],
    this.notes = '',
    this.archived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Fluxos que ainda mudam a projeção (os realizados já estão no orçamento).
  Iterable<ScenarioFlow> get pendingFlows => flows.where((f) => !f.realized);

  PlanScenario copyWith({
    String? name,
    List<ScenarioFlow>? flows,
    String? notes,
    bool? archived,
  }) => PlanScenario(
    id: id,
    name: name ?? this.name,
    kind: kind,
    flows: flows ?? this.flows,
    notes: notes ?? this.notes,
    archived: archived ?? this.archived,
    createdAt: createdAt,
  );

  /// Inclui ou substitui (pelo id) um fluxo.
  PlanScenario withFlow(ScenarioFlow f) => copyWith(
    flows: [...flows.where((x) => x.id != f.id), f]
      ..sort((a, b) => a.date.compareTo(b.date)),
  );

  PlanScenario withoutFlow(String flowId) =>
      copyWith(flows: flows.where((x) => x.id != flowId).toList());

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'flows': [for (final f in flows) f.toJson()],
    if (notes.isNotEmpty) 'notes': notes,
    if (archived) 'archived': true,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PlanScenario.fromJson(Map<String, Object?> j) => PlanScenario(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? 'Cenário',
    kind: (j['kind'] as String?) ?? ScenarioSource.manual,
    flows: [
      for (final f in (j['flows'] as List?) ?? const [])
        ScenarioFlow.fromJson(Map<String, Object?>.from(f as Map)),
    ]..sort((a, b) => a.date.compareTo(b.date)),
    notes: (j['notes'] as String?) ?? '',
    archived: (j['archived'] as bool?) ?? false,
    createdAt: j['createdAt'] == null
        ? null
        : DateTime.parse(j['createdAt'] as String),
    updatedAt: j['updatedAt'] == null
        ? null
        : DateTime.parse(j['updatedAt'] as String),
  );
}
