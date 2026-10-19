import '../../core/dates.dart';
import '../../core/money.dart';

// Orçamento mensal por categoria e metas de economia.

DateTime _ts(Object? s) =>
    s == null ? DateTime.now() : DateTime.parse(s as String);
DateTime? _pd(Object? s) => s == null ? null : Dates.fromIso(s as String);
String? _d(DateTime? d) => d == null ? null : Dates.toIso(d);

const Object _unset = Object();

/// Limite mensal de gastos de uma categoria de despesa (inclui as
/// subcategorias). Vale para todos os meses.
class Budget {
  final String id;
  final String categoryId;
  final Money amount;

  /// Percentual do limite em que o app passa a avisar (ex.: 80).
  final int alertPercent;
  final DateTime createdAt;
  final DateTime updatedAt;

  Budget({
    required this.id,
    required this.categoryId,
    required this.amount,
    this.alertPercent = 80,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Budget copyWith({String? categoryId, Money? amount, int? alertPercent}) =>
      Budget(
        id: id,
        categoryId: categoryId ?? this.categoryId,
        amount: amount ?? this.amount,
        alertPercent: alertPercent ?? this.alertPercent,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'amount': amount.cents,
    'alertPercent': alertPercent,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Budget.fromJson(Map<String, Object?> j) => Budget(
    id: j['id'] as String,
    categoryId: j['categoryId'] as String,
    amount: Money((j['amount'] as int?) ?? 0),
    alertPercent: (j['alertPercent'] as int?) ?? 80,
    createdAt: _ts(j['createdAt']),
    updatedAt: _ts(j['updatedAt']),
  );
}

/// Valor guardado (ou retirado, se negativo) em uma meta.
class GoalContribution {
  final String id;
  final DateTime date;
  final Money amount;
  final String note;

  const GoalContribution({
    required this.id,
    required this.date,
    required this.amount,
    this.note = '',
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'date': _d(date),
    'amount': amount.cents,
    'note': note,
  };

  factory GoalContribution.fromJson(Map<String, Object?> j) => GoalContribution(
    id: j['id'] as String,
    date: _pd(j['date'])!,
    amount: Money((j['amount'] as int?) ?? 0),
    note: (j['note'] as String?) ?? '',
  );
}

/// Meta de economia ("Reserva de emergência", "Viagem"). O valor guardado é
/// o saldo da conta vinculada ([accountId]) ou a soma dos aportes.
class SavingsGoal {
  final String id;
  final String name;
  final Money target;
  final DateTime? deadline;
  final String? accountId;
  final List<GoalContribution> contributions;
  final int color;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  SavingsGoal({
    required this.id,
    required this.name,
    required this.target,
    this.deadline,
    this.accountId,
    this.contributions = const [],
    this.color = 0xFF16A34A,
    this.archived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  SavingsGoal copyWith({
    String? name,
    Money? target,
    Object? deadline = _unset,
    Object? accountId = _unset,
    List<GoalContribution>? contributions,
    int? color,
    bool? archived,
  }) => SavingsGoal(
    id: id,
    name: name ?? this.name,
    target: target ?? this.target,
    deadline: identical(deadline, _unset)
        ? this.deadline
        : deadline as DateTime?,
    accountId: identical(accountId, _unset)
        ? this.accountId
        : accountId as String?,
    contributions: contributions ?? this.contributions,
    color: color ?? this.color,
    archived: archived ?? this.archived,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'target': target.cents,
    'deadline': _d(deadline),
    'accountId': accountId,
    'contributions': [for (final c in contributions) c.toJson()],
    'color': color,
    'archived': archived,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SavingsGoal.fromJson(Map<String, Object?> j) => SavingsGoal(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? 'Meta',
    target: Money((j['target'] as int?) ?? 0),
    deadline: _pd(j['deadline']),
    accountId: j['accountId'] as String?,
    contributions: [
      for (final c in (j['contributions'] as List?) ?? const [])
        GoalContribution.fromJson(Map<String, Object?>.from(c as Map)),
    ],
    color: (j['color'] as int?) ?? 0xFF16A34A,
    archived: (j['archived'] as bool?) ?? false,
    createdAt: _ts(j['createdAt']),
    updatedAt: _ts(j['updatedAt']),
  );
}
