import '../../core/dates.dart';
import 'enums.dart';

/// Pessoa cadastrada para dividir despesas (cadastro geral do app).
/// [isMe] marca o próprio usuário: a parte dele não gera cobrança.
class Person {
  final String id;
  final String name;
  final int color;
  final bool isMe;
  const Person({
    required this.id,
    required this.name,
    this.color = 0xFF1565C0,
    this.isMe = false,
  });

  Person copyWith({String? name, int? color, bool? isMe}) => Person(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    isMe: isMe ?? this.isMe,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'isMe': isMe,
  };

  factory Person.fromJson(Map<String, Object?> j) => Person(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    color: (j['color'] as num?)?.toInt() ?? 0xFF1565C0,
    isMe: j['isMe'] as bool? ?? false,
  );
}

/// Como a parte de uma pessoa é definida.
enum AllocMode { percent, fixed }

/// Parte de uma pessoa num lançamento: percentual ou valor fixo (centavos).
class Allocation {
  final String personId;
  final AllocMode mode;

  /// Percentual (0–100) ou centavos, conforme [mode].
  final num value;
  const Allocation(this.personId, this.mode, this.value);

  Map<String, Object?> toJson() => {
    'personId': personId,
    'mode': mode.name,
    'value': value,
  };

  factory Allocation.fromJson(Map<String, Object?> j) => Allocation(
    j['personId'] as String,
    AllocMode.values.asNameMap()[j['mode']] ?? AllocMode.percent,
    (j['value'] as num?) ?? 0,
  );
}

const paymentMethods = ['Pix', 'Dinheiro', 'Transferência', 'Cartão', 'Outro'];

/// Pagamento (reembolso) feito por uma pessoa para a sua parte.
class OtherPayment {
  final String id;
  final String personId;
  final int amount; // centavos
  final DateTime date;
  final String method;
  final String note;
  const OtherPayment({
    required this.id,
    required this.personId,
    required this.amount,
    required this.date,
    this.method = 'Pix',
    this.note = '',
  });

  /// Id fixo da receita de reembolso gerada por este pagamento (evita
  /// duplicidade: o mesmo pagamento sempre grava o mesmo lançamento).
  String get incomeTxId => 'oe_pay_$id';

  OtherPayment copyWith({
    int? amount,
    DateTime? date,
    String? method,
    String? note,
  }) => OtherPayment(
    id: id,
    personId: personId,
    amount: amount ?? this.amount,
    date: date ?? this.date,
    method: method ?? this.method,
    note: note ?? this.note,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'personId': personId,
    'amount': amount,
    'date': Dates.toIso(date),
    'method': method,
    'note': note,
  };

  factory OtherPayment.fromJson(Map<String, Object?> j) => OtherPayment(
    id: j['id'] as String,
    personId: j['personId'] as String,
    amount: (j['amount'] as num).toInt(),
    date: DateTime.parse(j['date'] as String),
    method: j['method'] as String? ?? 'Pix',
    note: j['note'] as String? ?? '',
  );
}

/// Linha do histórico de um lançamento.
class HistoryEntry {
  final DateTime at;
  final String text;
  const HistoryEntry(this.at, this.text);
  Map<String, Object?> toJson() => {'at': at.toIso8601String(), 'text': text};
  factory HistoryEntry.fromJson(Map<String, Object?> j) =>
      HistoryEntry(DateTime.parse(j['at'] as String), j['text'] as String);
}

/// Situação de pagamento.
enum PayStatus {
  pending('Pendente'),
  partial('Parcial'),
  paid('Pago');

  final String label;
  const PayStatus(this.label);
}

/// Parte calculada de uma pessoa, com o que já pagou.
class PersonShare {
  final String personId;
  final double? percent;
  final int owed;
  final int paid;
  const PersonShare(this.personId, this.percent, this.owed, this.paid);
  int get balance => owed - paid;
  PayStatus get status => paid <= 0
      ? PayStatus.pending
      : paid >= owed
      ? PayStatus.paid
      : PayStatus.partial;
}

/// "Outras despesas" / "Outras receitas": lançamentos detalhados que entram
/// no orçamento como **uma linha por mês** (como a fatura do cartão).
class OtherEntry {
  final String id;
  final TransactionType type; // income | expense
  final String description;
  final int amount; // centavos, total
  final YearMonth month; // mês de referência
  final DateTime? dueDate;
  final String notes;

  /// Entra na linha consolidada do orçamento do mês.
  final bool linked;

  /// Situação do próprio lançamento: despesa paga por mim / receita recebida.
  final bool settled;
  final List<Allocation> allocations;
  final List<OtherPayment> payments;
  final List<HistoryEntry> history;

  /// Exclusão lógica (preserva o histórico de pagamentos).
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  OtherEntry({
    required this.id,
    required this.type,
    required this.description,
    required this.amount,
    required this.month,
    this.dueDate,
    this.notes = '',
    this.linked = true,
    this.settled = false,
    this.allocations = const [],
    this.payments = const [],
    this.history = const [],
    this.deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isIncome => type == TransactionType.income;
  bool get isDeleted => deletedAt != null;

  /// Valor de cada pessoa. Percentuais são divididos sem perder centavos;
  /// valores fixos são usados como estão.
  Map<String, int> owedByPerson() {
    final out = <String, int>{};
    final pct = <String, double>{};
    for (final a in allocations) {
      if (a.mode == AllocMode.fixed) {
        out[a.personId] = a.value.round();
      } else if (a.value > 0) {
        pct[a.personId] = a.value.toDouble();
      }
    }
    if (pct.isEmpty) return out;
    final total = pct.values.fold(0.0, (a, p) => a + p);
    var used = 0;
    final fracs = <String, double>{};
    for (final e in pct.entries) {
      final exact = amount * e.value / 100;
      out[e.key] = exact.floor();
      fracs[e.key] = exact - exact.floor();
      used += exact.floor();
    }
    final target = (amount * total.clamp(0, 100) / 100).round();
    final order = fracs.keys.toList()
      ..sort((a, b) => fracs[b]!.compareTo(fracs[a]!));
    for (var k = 0; used < target && order.isNotEmpty; k++) {
      final id = order[k % order.length];
      out[id] = out[id]! + 1;
      used++;
    }
    return out;
  }

  int get allocated => owedByPerson().values.fold(0, (a, v) => a + v);
  int get unallocated => amount - allocated;

  int paidBy(String personId) => payments
      .where((p) => p.personId == personId)
      .fold(0, (a, p) => a + p.amount);

  List<PersonShare> shares() {
    final owed = owedByPerson();
    return [
      for (final a in allocations)
        PersonShare(
          a.personId,
          a.mode == AllocMode.percent ? a.value.toDouble() : null,
          owed[a.personId] ?? 0,
          paidBy(a.personId),
        ),
    ];
  }

  /// Partes de outras pessoas (exclui quem é "eu").
  List<PersonShare> othersShares(Set<String> meIds) =>
      shares().where((s) => !meIds.contains(s.personId)).toList();

  /// Situação dos reembolsos das outras pessoas.
  PayStatus? reimbursementStatus(Set<String> meIds) {
    final o = othersShares(meIds).where((s) => s.owed > 0).toList();
    if (o.isEmpty) return null;
    if (o.every((s) => s.status == PayStatus.paid)) return PayStatus.paid;
    if (o.every((s) => s.status == PayStatus.pending)) return PayStatus.pending;
    return PayStatus.partial;
  }

  int get paidTotal => payments.fold(0, (a, p) => a + p.amount);

  /// Receita: quanto já entrou (tudo, se marcada como recebida).
  int get received => settled ? amount : paidTotal.clamp(0, amount);

  /// Situação do lançamento como um todo: despesa = reembolsos das outras
  /// pessoas; receita = recebimento.
  PayStatus? status(Set<String> meIds) {
    if (!isIncome) return reimbursementStatus(meIds);
    final r = received;
    return r <= 0
        ? PayStatus.pending
        : r >= amount
        ? PayStatus.paid
        : PayStatus.partial;
  }

  OtherEntry withHistory(String text) =>
      copyWith(history: [...history, HistoryEntry(DateTime.now(), text)]);

  OtherEntry copyWith({
    TransactionType? type,
    String? description,
    int? amount,
    YearMonth? month,
    Object? dueDate = _keep,
    String? notes,
    bool? linked,
    bool? settled,
    List<Allocation>? allocations,
    List<OtherPayment>? payments,
    List<HistoryEntry>? history,
    Object? deletedAt = _keep,
    DateTime? updatedAt,
  }) => OtherEntry(
    id: id,
    type: type ?? this.type,
    description: description ?? this.description,
    amount: amount ?? this.amount,
    month: month ?? this.month,
    dueDate: dueDate == _keep ? this.dueDate : dueDate as DateTime?,
    notes: notes ?? this.notes,
    linked: linked ?? this.linked,
    settled: settled ?? this.settled,
    allocations: allocations ?? this.allocations,
    payments: payments ?? this.payments,
    history: history ?? this.history,
    deletedAt: deletedAt == _keep ? this.deletedAt : deletedAt as DateTime?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'description': description,
    'amount': amount,
    'month': month.key,
    'dueDate': dueDate == null ? null : Dates.toIso(dueDate!),
    'notes': notes,
    'linked': linked,
    'settled': settled,
    'allocations': [for (final a in allocations) a.toJson()],
    'payments': [for (final p in payments) p.toJson()],
    'history': [for (final h in history) h.toJson()],
    'deletedAt': deletedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory OtherEntry.fromJson(Map<String, Object?> j) {
    List<T> list<T>(String k, T Function(Map<String, Object?>) f) => [
      for (final x in (j[k] as List?) ?? const [])
        f((x as Map).cast<String, Object?>()),
    ];
    DateTime? date(Object? v) => v == null ? null : DateTime.parse(v as String);
    return OtherEntry(
      id: j['id'] as String,
      type: TransactionType.values.byName(j['type'] as String),
      description: j['description'] as String? ?? '',
      amount: (j['amount'] as num?)?.toInt() ?? 0,
      month: YearMonth.parse(j['month'] as String),
      dueDate: date(j['dueDate']),
      notes: j['notes'] as String? ?? '',
      linked: j['linked'] as bool? ?? true,
      settled: j['settled'] as bool? ?? false,
      allocations: list('allocations', Allocation.fromJson),
      payments: list('payments', OtherPayment.fromJson),
      history: list('history', HistoryEntry.fromJson),
      deletedAt: date(j['deletedAt']),
      createdAt: date(j['createdAt']),
      updatedAt: date(j['updatedAt']),
    );
  }
}

const _keep = Object();
