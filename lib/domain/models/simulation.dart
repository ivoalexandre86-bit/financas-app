import '../../core/dates.dart';
import '../../core/ids.dart';
import 'enums.dart';

/// Situação de uma simulação na lista.
enum SimulationStatus {
  active('Ativa'),
  archived('Arquivada');

  final String label;
  const SimulationStatus(this.label);
}

/// Recorrência usada para preencher os meses de uma linha.
enum SimRecurrence {
  once('Única'),
  monthly('Mensal'),
  bimonthly('Bimestral'),
  quarterly('Trimestral'),
  semiannual('Semestral'),
  yearly('Anual');

  final String label;
  const SimRecurrence(this.label);

  int get step => switch (this) {
    once => 0,
    monthly => 1,
    bimonthly => 2,
    quarterly => 3,
    semiannual => 6,
    yearly => 12,
  };
}

/// Classificação orçamentária livre de uma linha.
const simClassifications = ['Fixa', 'Variável', 'Eventual', 'Investimento'];

/// Origem de uma linha: copiada do orçamento base ou criada na simulação.
enum SimOrigin { base, added }

/// Linha da planilha de uma simulação (uma receita ou despesa ao longo dos
/// meses). Os valores ficam por mês, em centavos e sempre positivos; o tipo
/// define o sinal.
class SimItem {
  final String id;
  final TransactionType type; // income | expense
  final String description;
  final String? categoryId;
  final String? accountId;
  final String? cardId;

  /// Dia do mês em que o lançamento acontece (1–31).
  final int day;
  final SimRecurrence recurrence;
  final String classification;
  final String notes;
  final SimOrigin origin;

  /// Chave do item do orçamento oficial de onde a linha veio
  /// (`r:<regra>`, `i:<parcelamento>`, `t:<lançamento>`). Nula nas linhas
  /// criadas na simulação.
  final String? sourceKey;

  /// Lançamentos oficiais por mês (ids, inclusive ocorrências virtuais
  /// `v:...`) que formam o valor da linha no orçamento base. Usado para
  /// aplicar a simulação ao orçamento.
  final Map<String, List<String>> refs;

  /// Valor por mês (`"2027-01"` → centavos).
  final Map<String, int> values;

  const SimItem({
    required this.id,
    required this.type,
    required this.description,
    this.categoryId,
    this.accountId,
    this.cardId,
    this.day = 1,
    this.recurrence = SimRecurrence.once,
    this.classification = '',
    this.notes = '',
    this.origin = SimOrigin.added,
    this.sourceKey,
    this.refs = const {},
    this.values = const {},
  });

  bool get isIncome => type == TransactionType.income;

  int valueAt(YearMonth m) => values[m.key] ?? 0;

  int totalIn(Iterable<YearMonth> months) =>
      months.fold(0, (a, m) => a + valueAt(m));

  /// Valor com sinal (+ receita, − despesa).
  int signedAt(YearMonth m) => isIncome ? valueAt(m) : -valueAt(m);

  /// Preenche [amount] de [from] a [to] conforme a recorrência (meses fora
  /// do intervalo ficam como estavam).
  SimItem fill(int amount, YearMonth from, YearMonth to, SimRecurrence rec) {
    final v = Map<String, int>.from(values);
    var i = 0;
    for (final m in YearMonth.range(from, to)) {
      final hit = rec == SimRecurrence.once ? i == 0 : i % rec.step == 0;
      if (hit) {
        v[m.key] = amount;
      } else {
        v.remove(m.key);
      }
      i++;
    }
    v.removeWhere((_, c) => c == 0);
    return copyWith(values: v, recurrence: rec);
  }

  SimItem withValue(YearMonth m, int cents) {
    final v = Map<String, int>.from(values);
    if (cents == 0) {
      v.remove(m.key);
    } else {
      v[m.key] = cents;
    }
    return copyWith(values: v);
  }

  /// Mesmos dados de cadastro (descrição, categoria, conta…), ignorando os
  /// valores e o dia.
  bool sameFieldsAs(SimItem o) =>
      type == o.type &&
      description == o.description &&
      categoryId == o.categoryId &&
      accountId == o.accountId &&
      cardId == o.cardId;

  SimItem copyWith({
    String? id,
    TransactionType? type,
    String? description,
    Object? categoryId = _keep,
    Object? accountId = _keep,
    Object? cardId = _keep,
    int? day,
    SimRecurrence? recurrence,
    String? classification,
    String? notes,
    SimOrigin? origin,
    Object? sourceKey = _keep,
    Map<String, List<String>>? refs,
    Map<String, int>? values,
  }) => SimItem(
    id: id ?? this.id,
    type: type ?? this.type,
    description: description ?? this.description,
    categoryId: categoryId == _keep ? this.categoryId : categoryId as String?,
    accountId: accountId == _keep ? this.accountId : accountId as String?,
    cardId: cardId == _keep ? this.cardId : cardId as String?,
    day: day ?? this.day,
    recurrence: recurrence ?? this.recurrence,
    classification: classification ?? this.classification,
    notes: notes ?? this.notes,
    origin: origin ?? this.origin,
    sourceKey: sourceKey == _keep ? this.sourceKey : sourceKey as String?,
    refs: refs ?? this.refs,
    values: values ?? this.values,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'description': description,
    'categoryId': categoryId,
    'accountId': accountId,
    'cardId': cardId,
    'day': day,
    'recurrence': recurrence.name,
    'classification': classification,
    'notes': notes,
    'origin': origin.name,
    'sourceKey': sourceKey,
    'refs': refs,
    'values': values,
  };

  factory SimItem.fromJson(Map<String, Object?> j) => SimItem(
    id: j['id'] as String,
    type: TransactionType.values.byName(j['type'] as String),
    description: j['description'] as String? ?? '',
    categoryId: j['categoryId'] as String?,
    accountId: j['accountId'] as String?,
    cardId: j['cardId'] as String?,
    day: (j['day'] as num?)?.toInt() ?? 1,
    recurrence:
        SimRecurrence.values.asNameMap()[j['recurrence']] ?? SimRecurrence.once,
    classification: j['classification'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    origin: SimOrigin.values.asNameMap()[j['origin']] ?? SimOrigin.added,
    sourceKey: j['sourceKey'] as String?,
    refs: {
      for (final e in ((j['refs'] as Map?) ?? const {}).entries)
        e.key as String: [for (final x in e.value as List) x as String],
    },
    values: {
      for (final e in ((j['values'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    },
  );
}

const _keep = Object();

/// Um cenário de orçamento: cópia independente (sandbox) de um orçamento
/// base em um período. Nada aqui altera os lançamentos oficiais.
class Simulation {
  final String id;
  final String name;
  final String description;
  final int color;
  final SimulationStatus status;

  /// Nome do orçamento de origem (ex.: "Orçamento atual" ou o nome da
  /// simulação duplicada).
  final String baseName;

  /// Simulação de origem, quando criada a partir de outra.
  final String? baseSimulationId;
  final YearMonth from;
  final YearMonth to;

  /// Saldo no início do período (contas), para o saldo acumulado.
  final int opening;

  /// Estado do orçamento base no momento da criação (para comparar e
  /// restaurar).
  final List<SimItem> baseItems;

  /// Estado atual da simulação.
  final List<SimItem> items;
  final DateTime? appliedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Simulation({
    required this.id,
    required this.name,
    this.description = '',
    this.color = 0xFF1565C0,
    this.status = SimulationStatus.active,
    required this.baseName,
    this.baseSimulationId,
    required this.from,
    required this.to,
    this.opening = 0,
    this.baseItems = const [],
    this.items = const [],
    this.appliedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  List<YearMonth> get months => YearMonth.range(from, to).toList();

  bool get isArchived => status == SimulationStatus.archived;

  String get periodLabel {
    if (from == to) return from.shortLabel;
    if (from.month == 1 && to.month == 12 && from.year == to.year) {
      return '${from.year}';
    }
    return '${from.shortLabel} – ${to.shortLabel}';
  }

  Simulation copyWith({
    String? id,
    String? name,
    String? description,
    int? color,
    SimulationStatus? status,
    String? baseName,
    Object? baseSimulationId = _keep,
    YearMonth? from,
    YearMonth? to,
    int? opening,
    List<SimItem>? baseItems,
    List<SimItem>? items,
    Object? appliedAt = _keep,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Simulation(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    color: color ?? this.color,
    status: status ?? this.status,
    baseName: baseName ?? this.baseName,
    baseSimulationId: baseSimulationId == _keep
        ? this.baseSimulationId
        : baseSimulationId as String?,
    from: from ?? this.from,
    to: to ?? this.to,
    opening: opening ?? this.opening,
    baseItems: baseItems ?? this.baseItems,
    items: items ?? this.items,
    appliedAt: appliedAt == _keep ? this.appliedAt : appliedAt as DateTime?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Cópia independente com novo id (duplicar): a base da cópia é o estado
  /// atual desta simulação.
  Simulation duplicate(String newName) {
    final now = DateTime.now();
    return copyWith(
      id: newId('sim_'),
      name: newName,
      status: SimulationStatus.active,
      baseName: name,
      baseSimulationId: id,
      baseItems: items,
      items: items,
      appliedAt: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'color': color,
    'status': status.name,
    'baseName': baseName,
    'baseSimulationId': baseSimulationId,
    'from': from.key,
    'to': to.key,
    'opening': opening,
    'baseItems': [for (final i in baseItems) i.toJson()],
    'items': [for (final i in items) i.toJson()],
    'appliedAt': appliedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Simulation.fromJson(Map<String, Object?> j) {
    List<SimItem> list(Object? v) => [
      for (final x in (v as List?) ?? const [])
        SimItem.fromJson((x as Map).cast<String, Object?>()),
    ];
    DateTime? date(Object? v) => v == null ? null : DateTime.parse(v as String);
    return Simulation(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      description: j['description'] as String? ?? '',
      color: (j['color'] as num?)?.toInt() ?? 0xFF1565C0,
      status:
          SimulationStatus.values.asNameMap()[j['status']] ??
          SimulationStatus.active,
      baseName: j['baseName'] as String? ?? '',
      baseSimulationId: j['baseSimulationId'] as String?,
      from: YearMonth.parse(j['from'] as String),
      to: YearMonth.parse(j['to'] as String),
      opening: (j['opening'] as num?)?.toInt() ?? 0,
      baseItems: list(j['baseItems']),
      items: list(j['items']),
      appliedAt: date(j['appliedAt']),
      createdAt: date(j['createdAt']),
      updatedAt: date(j['updatedAt']),
    );
  }
}
