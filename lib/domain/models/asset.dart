import '../../core/dates.dart';
import '../../core/money.dart';

// Bens e dívidas registrados à mão para o patrimônio líquido.

enum AssetKind {
  realEstate('Imóvel'),
  vehicle('Veículo'),
  investment('Investimento'),
  other('Outro bem'),
  financing('Financiamento', liability: true),
  loan('Empréstimo', liability: true),
  otherDebt('Outra dívida', liability: true);

  final String label;
  final bool liability;
  const AssetKind(this.label, {this.liability = false});

  static List<AssetKind> of({required bool liability}) =>
      values.where((k) => k.liability == liability).toList();
}

/// Valor de um bem (ou dívida) em uma data.
class AssetValue {
  final DateTime date;
  final Money value;
  const AssetValue(this.date, this.value);

  Map<String, Object?> toJson() => {
    'date': Dates.toIso(date),
    'value': value.cents,
  };

  factory AssetValue.fromJson(Map<String, Object?> j) => AssetValue(
    Dates.fromIso(j['date'] as String),
    Money((j['value'] as int?) ?? 0),
  );
}

/// Bem (imóvel, veículo, investimento…) ou dívida fora do app (financiamento,
/// empréstimo). [value] é sempre positivo; [isLiability] diz se subtrai.
class Asset {
  final String id;
  final String name;
  final AssetKind kind;
  final Money value;
  final String notes;
  final DateTime updatedAt;

  /// Valores anteriores, em ordem de data (um por dia).
  final List<AssetValue> history;

  Asset({
    required this.id,
    required this.name,
    required this.kind,
    required this.value,
    this.notes = '',
    this.history = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isLiability => kind.liability;

  /// Valor com sinal: negativo para dívidas.
  Money get signed => isLiability ? -value : value;

  /// Último valor registrado até [date] (ou `null` se não havia).
  Money? valueAt(DateTime date) {
    Money? v;
    for (final h in history) {
      if (h.date.isAfter(date)) break;
      v = h.value;
    }
    return v;
  }

  /// Registra [v] em [date] no histórico (substitui o valor do mesmo dia).
  Asset withValue(Money v, DateTime date) {
    final d = Dates.dateOnly(date);
    final h = [
      ...history.where((x) => Dates.dateOnly(x.date) != d),
      AssetValue(d, v),
    ]..sort((a, b) => a.date.compareTo(b.date));
    // Uma data antiga só entra no histórico; o valor atual é o mais recente.
    return copyWith(value: h.last.value, history: h);
  }

  Asset copyWith({
    String? name,
    AssetKind? kind,
    Money? value,
    String? notes,
    List<AssetValue>? history,
  }) => Asset(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    value: value ?? this.value,
    notes: notes ?? this.notes,
    history: history ?? this.history,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'value': value.cents,
    'isLiability': isLiability,
    'notes': notes,
    'history': [for (final h in history) h.toJson()],
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Asset.fromJson(Map<String, Object?> j) {
    final kind = AssetKind.values.where((k) => k.name == j['kind']).firstOrNull;
    return Asset(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Bem',
      kind:
          kind ??
          ((j['isLiability'] as bool?) ?? false
              ? AssetKind.otherDebt
              : AssetKind.other),
      value: Money((j['value'] as int?) ?? 0),
      notes: (j['notes'] as String?) ?? '',
      history: [
        for (final h in (j['history'] as List?) ?? const [])
          AssetValue.fromJson(Map<String, Object?>.from(h as Map)),
      ]..sort((a, b) => a.date.compareTo(b.date)),
      updatedAt: j['updatedAt'] == null
          ? null
          : DateTime.parse(j['updatedAt'] as String),
    );
  }
}
