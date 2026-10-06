import '../../core/dates.dart';
import '../../core/money.dart';
import 'enums.dart';

export 'enums.dart';

// Helpers de serialização ---------------------------------------------------

String? _d(DateTime? d) => d == null ? null : Dates.toIso(d);
DateTime? _pd(Object? s) => s == null ? null : Dates.fromIso(s as String);
DateTime _ts(Object? s) =>
    s == null ? DateTime.now() : DateTime.parse(s as String);

/// Sentinela para `copyWith` permitir atribuir `null` explicitamente.
const Object _unset = Object();

// Conta ----------------------------------------------------------------------

class Account {
  final String id;
  final String name;
  final String institution;
  final AccountType type;
  final Money initialBalance;
  final bool active;
  final int color;
  final DateTime createdAt;
  final DateTime updatedAt;

  Account({
    required this.id,
    required this.name,
    this.institution = '',
    this.type = AccountType.checking,
    this.initialBalance = Money.zero,
    this.active = true,
    this.color = 0xFF2457D6,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Account copyWith({
    String? name,
    String? institution,
    AccountType? type,
    Money? initialBalance,
    bool? active,
    int? color,
  }) => Account(
    id: id,
    name: name ?? this.name,
    institution: institution ?? this.institution,
    type: type ?? this.type,
    initialBalance: initialBalance ?? this.initialBalance,
    active: active ?? this.active,
    color: color ?? this.color,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'institution': institution,
    'type': type.name,
    'initialBalance': initialBalance.cents,
    'active': active,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Account.fromJson(Map<String, Object?> j) => Account(
    id: j['id'] as String,
    name: j['name'] as String,
    institution: (j['institution'] as String?) ?? '',
    type: enumByName(
      AccountType.values,
      j['type'] as String?,
      AccountType.checking,
    ),
    initialBalance: Money((j['initialBalance'] as int?) ?? 0),
    active: (j['active'] as bool?) ?? true,
    color: (j['color'] as int?) ?? 0xFF2457D6,
    createdAt: _ts(j['createdAt']),
    updatedAt: _ts(j['updatedAt']),
  );
}

// Cartão de crédito -----------------------------------------------------------

class CreditCard {
  final String id;
  final String name;
  final String bank;
  final String brand;
  final String lastFour;
  final Money limit;

  /// Dia de fechamento da fatura (1–31; limitado ao fim do mês).
  final int closingDay;

  /// Dia de vencimento da fatura (1–31; limitado ao fim do mês).
  final int dueDay;
  final bool active;
  final String? paymentAccountId;
  final int color;
  final DateTime createdAt;
  final DateTime updatedAt;

  CreditCard({
    required this.id,
    required this.name,
    this.bank = '',
    this.brand = '',
    this.lastFour = '',
    this.limit = Money.zero,
    required this.closingDay,
    required this.dueDay,
    this.active = true,
    this.paymentAccountId,
    this.color = 0xFF1B2A4A,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  CreditCard copyWith({
    String? name,
    String? bank,
    String? brand,
    String? lastFour,
    Money? limit,
    int? closingDay,
    int? dueDay,
    bool? active,
    Object? paymentAccountId = _unset,
    int? color,
  }) => CreditCard(
    id: id,
    name: name ?? this.name,
    bank: bank ?? this.bank,
    brand: brand ?? this.brand,
    lastFour: lastFour ?? this.lastFour,
    limit: limit ?? this.limit,
    closingDay: closingDay ?? this.closingDay,
    dueDay: dueDay ?? this.dueDay,
    active: active ?? this.active,
    paymentAccountId: identical(paymentAccountId, _unset)
        ? this.paymentAccountId
        : paymentAccountId as String?,
    color: color ?? this.color,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'bank': bank,
    'brand': brand,
    'lastFour': lastFour,
    'limit': limit.cents,
    'closingDay': closingDay,
    'dueDay': dueDay,
    'active': active,
    'paymentAccountId': paymentAccountId,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CreditCard.fromJson(Map<String, Object?> j) => CreditCard(
    id: j['id'] as String,
    name: j['name'] as String,
    bank: (j['bank'] as String?) ?? '',
    brand: (j['brand'] as String?) ?? '',
    lastFour: (j['lastFour'] as String?) ?? '',
    limit: Money((j['limit'] as int?) ?? 0),
    closingDay: j['closingDay'] as int,
    dueDay: j['dueDay'] as int,
    active: (j['active'] as bool?) ?? true,
    paymentAccountId: j['paymentAccountId'] as String?,
    color: (j['color'] as int?) ?? 0xFF1B2A4A,
    createdAt: _ts(j['createdAt']),
    updatedAt: _ts(j['updatedAt']),
  );
}

// Categoria -----------------------------------------------------------------

class FinCategory {
  final String id;
  final String name;
  final CategoryKind kind;
  final String? parentId;
  final String icon; // chave do ícone (ver ui/widgets/category_icons.dart)
  final int color;
  final DateTime createdAt;
  final DateTime updatedAt;

  FinCategory({
    required this.id,
    required this.name,
    required this.kind,
    this.parentId,
    this.icon = 'other',
    this.color = 0xFF6B7280,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  FinCategory copyWith({
    String? name,
    CategoryKind? kind,
    Object? parentId = _unset,
    String? icon,
    int? color,
  }) => FinCategory(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    parentId: identical(parentId, _unset) ? this.parentId : parentId as String?,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'parentId': parentId,
    'icon': icon,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory FinCategory.fromJson(Map<String, Object?> j) => FinCategory(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: enumByName(
      CategoryKind.values,
      j['kind'] as String?,
      CategoryKind.expense,
    ),
    parentId: j['parentId'] as String?,
    icon: (j['icon'] as String?) ?? 'other',
    color: (j['color'] as int?) ?? 0xFF6B7280,
    createdAt: _ts(j['createdAt']),
    updatedAt: _ts(j['updatedAt']),
  );
}

// Projeto -------------------------------------------------------------------

class Project {
  final String id;
  final String name;
  final String description;
  final Money budget;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool archived;
  final int color;
  final DateTime createdAt;
  final DateTime updatedAt;

  Project({
    required this.id,
    required this.name,
    this.description = '',
    this.budget = Money.zero,
    this.startDate,
    this.endDate,
    this.archived = false,
    this.color = 0xFF2457D6,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Project copyWith({
    String? name,
    String? description,
    Money? budget,
    Object? startDate = _unset,
    Object? endDate = _unset,
    bool? archived,
    int? color,
  }) => Project(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    budget: budget ?? this.budget,
    startDate: identical(startDate, _unset)
        ? this.startDate
        : startDate as DateTime?,
    endDate: identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
    archived: archived ?? this.archived,
    color: color ?? this.color,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'budget': budget.cents,
    'startDate': _d(startDate),
    'endDate': _d(endDate),
    'archived': archived,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Project.fromJson(Map<String, Object?> j) => Project(
    id: j['id'] as String,
    name: j['name'] as String,
    description: (j['description'] as String?) ?? '',
    budget: Money((j['budget'] as int?) ?? 0),
    startDate: _pd(j['startDate']),
    endDate: _pd(j['endDate']),
    archived: (j['archived'] as bool?) ?? false,
    color: (j['color'] as int?) ?? 0xFF2457D6,
    createdAt: _ts(j['createdAt']),
    updatedAt: _ts(j['updatedAt']),
  );
}

// Transação -----------------------------------------------------------------

/// Lançamento financeiro. O valor ([amount]) é sempre positivo; o sentido é
/// dado por [type].
///
/// Regras de vínculo:
/// * Receita/Despesa: exatamente um de [accountId] ou [cardId].
/// * Transferência: [accountId] (origem) e [destinationAccountId] (destino).
/// * Parcela: [installmentGroupId] + [installmentNumber]/[installmentCount].
///   Em cartão, [date] é a data da compra e a parcela N cai na fatura
///   (ciclo da compra + N − 1). Em conta, [date] já é o vencimento da parcela.
/// * Ocorrência de recorrência: [recurringId] + [occurrenceDate] (chave de
///   deduplicação contra as ocorrências virtuais geradas pela regra).
class FinTransaction {
  final String id;
  final TransactionType type;
  final Money amount;
  final String description;
  final String? categoryId;
  final DateTime date;
  final String? accountId;
  final String? cardId;
  final String? destinationAccountId;
  final String? projectId;
  final String notes;
  final TransactionStatus status;
  final String? recurringId;
  final DateTime? occurrenceDate;
  final String? installmentGroupId;
  final int? installmentNumber;
  final int? installmentCount;
  final String? externalId;

  /// Data de vencimento informada pelo usuário (opcional). Quando presente,
  /// é ela que define se o lançamento pendente está atrasado.
  final DateTime? dueDate;

  /// `true` para ocorrências geradas pelo motor a partir de uma regra
  /// recorrente e ainda não persistidas.
  final bool isVirtual;
  final DateTime createdAt;
  final DateTime updatedAt;

  FinTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    this.categoryId,
    required this.date,
    this.accountId,
    this.cardId,
    this.destinationAccountId,
    this.projectId,
    this.notes = '',
    this.status = TransactionStatus.completed,
    this.recurringId,
    this.occurrenceDate,
    this.installmentGroupId,
    this.installmentNumber,
    this.installmentCount,
    this.externalId,
    this.dueDate,
    this.isVirtual = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Data usada para saber se o lançamento está atrasado: o vencimento,
  /// se informado; senão, a própria data.
  DateTime get effectiveDueDate => dueDate ?? date;

  bool get isInstallment => installmentGroupId != null;
  bool get isRecurring => recurringId != null;
  bool get isCardTransaction => cardId != null;
  bool get isTransfer => type == TransactionType.transfer;

  String get installmentLabel =>
      isInstallment ? '$installmentNumber/$installmentCount' : '';

  FinTransaction copyWith({
    String? id,
    TransactionType? type,
    Money? amount,
    String? description,
    Object? categoryId = _unset,
    DateTime? date,
    Object? accountId = _unset,
    Object? cardId = _unset,
    Object? destinationAccountId = _unset,
    Object? projectId = _unset,
    String? notes,
    TransactionStatus? status,
    Object? recurringId = _unset,
    Object? occurrenceDate = _unset,
    Object? installmentGroupId = _unset,
    Object? installmentNumber = _unset,
    Object? installmentCount = _unset,
    Object? externalId = _unset,
    Object? dueDate = _unset,
    bool? isVirtual,
  }) => FinTransaction(
    id: id ?? this.id,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    description: description ?? this.description,
    categoryId: identical(categoryId, _unset)
        ? this.categoryId
        : categoryId as String?,
    date: date ?? this.date,
    accountId: identical(accountId, _unset)
        ? this.accountId
        : accountId as String?,
    cardId: identical(cardId, _unset) ? this.cardId : cardId as String?,
    destinationAccountId: identical(destinationAccountId, _unset)
        ? this.destinationAccountId
        : destinationAccountId as String?,
    projectId: identical(projectId, _unset)
        ? this.projectId
        : projectId as String?,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    recurringId: identical(recurringId, _unset)
        ? this.recurringId
        : recurringId as String?,
    occurrenceDate: identical(occurrenceDate, _unset)
        ? this.occurrenceDate
        : occurrenceDate as DateTime?,
    installmentGroupId: identical(installmentGroupId, _unset)
        ? this.installmentGroupId
        : installmentGroupId as String?,
    installmentNumber: identical(installmentNumber, _unset)
        ? this.installmentNumber
        : installmentNumber as int?,
    installmentCount: identical(installmentCount, _unset)
        ? this.installmentCount
        : installmentCount as int?,
    externalId: identical(externalId, _unset)
        ? this.externalId
        : externalId as String?,
    dueDate: identical(dueDate, _unset) ? this.dueDate : dueDate as DateTime?,
    isVirtual: isVirtual ?? this.isVirtual,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'amount': amount.cents,
    'description': description,
    'categoryId': categoryId,
    'date': Dates.toIso(date),
    'accountId': accountId,
    'cardId': cardId,
    'destinationAccountId': destinationAccountId,
    'projectId': projectId,
    'notes': notes,
    'status': status.name,
    'recurringId': recurringId,
    'occurrenceDate': _d(occurrenceDate),
    'installmentGroupId': installmentGroupId,
    'installmentNumber': installmentNumber,
    'installmentCount': installmentCount,
    'externalId': externalId,
    'dueDate': _d(dueDate),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory FinTransaction.fromJson(Map<String, Object?> j) => FinTransaction(
    id: j['id'] as String,
    type: enumByName(
      TransactionType.values,
      j['type'] as String?,
      TransactionType.expense,
    ),
    amount: Money(j['amount'] as int),
    description: (j['description'] as String?) ?? '',
    categoryId: j['categoryId'] as String?,
    date: Dates.fromIso(j['date'] as String),
    accountId: j['accountId'] as String?,
    cardId: j['cardId'] as String?,
    destinationAccountId: j['destinationAccountId'] as String?,
    projectId: j['projectId'] as String?,
    notes: (j['notes'] as String?) ?? '',
    status: enumByName(
      TransactionStatus.values,
      j['status'] as String?,
      TransactionStatus.completed,
    ),
    recurringId: j['recurringId'] as String?,
    occurrenceDate: _pd(j['occurrenceDate']),
    installmentGroupId: j['installmentGroupId'] as String?,
    installmentNumber: j['installmentNumber'] as int?,
    installmentCount: j['installmentCount'] as int?,
    externalId: j['externalId'] as String?,
    dueDate: _pd(j['dueDate']),
    createdAt: _ts(j['createdAt']),
    updatedAt: _ts(j['updatedAt']),
  );
}

// Recorrência ---------------------------------------------------------------

class PausePeriod {
  final DateTime from;
  final DateTime? to; // null = ainda pausada
  const PausePeriod(this.from, [this.to]);

  bool covers(DateTime d) =>
      !d.isBefore(from) && (to == null || d.isBefore(to!));

  Map<String, Object?> toJson() => {'from': _d(from), 'to': _d(to)};
  factory PausePeriod.fromJson(Map<String, Object?> j) =>
      PausePeriod(_pd(j['from'])!, _pd(j['to']));
}

class RecurringRule {
  final String id;
  final TransactionType type; // receita ou despesa
  final Money amount;
  final String description;
  final String? categoryId;
  final String? accountId;
  final String? cardId;
  final String? projectId;
  final RecurrenceFrequency frequency;

  /// Intervalo para frequência personalizada (ex.: a cada 2 meses).
  final int interval;
  final RecurrenceUnit unit;

  /// Dia do mês desejado (frequências mensais); `null` usa o dia de início.
  final int? dayOfMonth;
  final DateTime startDate;
  final DateTime? endDate;
  final List<PausePeriod> pauses;
  final String notes;

  /// Regra anterior quando esta foi criada por uma edição "somente futuras".
  final String? previousRuleId;
  final DateTime createdAt;
  final DateTime updatedAt;

  RecurringRule({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    this.categoryId,
    this.accountId,
    this.cardId,
    this.projectId,
    this.frequency = RecurrenceFrequency.monthly,
    this.interval = 1,
    this.unit = RecurrenceUnit.months,
    this.dayOfMonth,
    required this.startDate,
    this.endDate,
    this.pauses = const [],
    this.notes = '',
    this.previousRuleId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isPaused => pauses.any((p) => p.to == null);
  bool isEndedBy(DateTime d) => endDate != null && endDate!.isBefore(d);

  RecurringRule copyWith({
    String? id,
    TransactionType? type,
    Money? amount,
    String? description,
    Object? categoryId = _unset,
    Object? accountId = _unset,
    Object? cardId = _unset,
    Object? projectId = _unset,
    RecurrenceFrequency? frequency,
    int? interval,
    RecurrenceUnit? unit,
    Object? dayOfMonth = _unset,
    DateTime? startDate,
    Object? endDate = _unset,
    List<PausePeriod>? pauses,
    String? notes,
    Object? previousRuleId = _unset,
  }) => RecurringRule(
    id: id ?? this.id,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    description: description ?? this.description,
    categoryId: identical(categoryId, _unset)
        ? this.categoryId
        : categoryId as String?,
    accountId: identical(accountId, _unset)
        ? this.accountId
        : accountId as String?,
    cardId: identical(cardId, _unset) ? this.cardId : cardId as String?,
    projectId: identical(projectId, _unset)
        ? this.projectId
        : projectId as String?,
    frequency: frequency ?? this.frequency,
    interval: interval ?? this.interval,
    unit: unit ?? this.unit,
    dayOfMonth: identical(dayOfMonth, _unset)
        ? this.dayOfMonth
        : dayOfMonth as int?,
    startDate: startDate ?? this.startDate,
    endDate: identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
    pauses: pauses ?? this.pauses,
    notes: notes ?? this.notes,
    previousRuleId: identical(previousRuleId, _unset)
        ? this.previousRuleId
        : previousRuleId as String?,
    createdAt: id == null ? createdAt : DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'amount': amount.cents,
    'description': description,
    'categoryId': categoryId,
    'accountId': accountId,
    'cardId': cardId,
    'projectId': projectId,
    'frequency': frequency.name,
    'interval': interval,
    'unit': unit.name,
    'dayOfMonth': dayOfMonth,
    'startDate': _d(startDate),
    'endDate': _d(endDate),
    'pauses': pauses.map((p) => p.toJson()).toList(),
    'notes': notes,
    'previousRuleId': previousRuleId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory RecurringRule.fromJson(Map<String, Object?> j) => RecurringRule(
    id: j['id'] as String,
    type: enumByName(
      TransactionType.values,
      j['type'] as String?,
      TransactionType.expense,
    ),
    amount: Money(j['amount'] as int),
    description: (j['description'] as String?) ?? '',
    categoryId: j['categoryId'] as String?,
    accountId: j['accountId'] as String?,
    cardId: j['cardId'] as String?,
    projectId: j['projectId'] as String?,
    frequency: enumByName(
      RecurrenceFrequency.values,
      j['frequency'] as String?,
      RecurrenceFrequency.monthly,
    ),
    interval: (j['interval'] as int?) ?? 1,
    unit: enumByName(
      RecurrenceUnit.values,
      j['unit'] as String?,
      RecurrenceUnit.months,
    ),
    dayOfMonth: j['dayOfMonth'] as int?,
    startDate: _pd(j['startDate'])!,
    endDate: _pd(j['endDate']),
    pauses: ((j['pauses'] as List?) ?? const [])
        .map((p) => PausePeriod.fromJson(Map<String, Object?>.from(p as Map)))
        .toList(),
    notes: (j['notes'] as String?) ?? '',
    previousRuleId: j['previousRuleId'] as String?,
    createdAt: _ts(j['createdAt']),
    updatedAt: _ts(j['updatedAt']),
  );
}

// Compra parcelada ------------------------------------------------------------

class InstallmentGroup {
  final String id;
  final String description;
  final Money totalAmount;
  final int count;
  final DateTime purchaseDate;
  final String? accountId;
  final String? cardId;
  final String? categoryId;
  final String? projectId;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  InstallmentGroup({
    required this.id,
    required this.description,
    required this.totalAmount,
    required this.count,
    required this.purchaseDate,
    this.accountId,
    this.cardId,
    this.categoryId,
    this.projectId,
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'totalAmount': totalAmount.cents,
    'count': count,
    'purchaseDate': _d(purchaseDate),
    'accountId': accountId,
    'cardId': cardId,
    'categoryId': categoryId,
    'projectId': projectId,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory InstallmentGroup.fromJson(Map<String, Object?> j) => InstallmentGroup(
    id: j['id'] as String,
    description: (j['description'] as String?) ?? '',
    totalAmount: Money(j['totalAmount'] as int),
    count: j['count'] as int,
    purchaseDate: _pd(j['purchaseDate'])!,
    accountId: j['accountId'] as String?,
    cardId: j['cardId'] as String?,
    categoryId: j['categoryId'] as String?,
    projectId: j['projectId'] as String?,
    notes: (j['notes'] as String?) ?? '',
    createdAt: _ts(j['createdAt']),
    updatedAt: _ts(j['updatedAt']),
  );
}

// Pagamento de fatura -----------------------------------------------------------

/// Pagamento (total ou parcial) de uma fatura. É uma liquidação do passivo do
/// cartão — **não** é uma despesa nova (evita contagem dupla).
class InvoicePayment {
  final String id;
  final String cardId;

  /// Mês de fechamento da fatura ("2026-08").
  final String invoiceKey;
  final Money amount;
  final DateTime date;
  final String? accountId;
  final DateTime createdAt;

  InvoicePayment({
    required this.id,
    required this.cardId,
    required this.invoiceKey,
    required this.amount,
    required this.date,
    this.accountId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, Object?> toJson() => {
    'id': id,
    'cardId': cardId,
    'invoiceKey': invoiceKey,
    'amount': amount.cents,
    'date': _d(date),
    'accountId': accountId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory InvoicePayment.fromJson(Map<String, Object?> j) => InvoicePayment(
    id: j['id'] as String,
    cardId: j['cardId'] as String,
    invoiceKey: j['invoiceKey'] as String,
    amount: Money(j['amount'] as int),
    date: _pd(j['date'])!,
    accountId: j['accountId'] as String?,
    createdAt: _ts(j['createdAt']),
  );
}

// Open Finance --------------------------------------------------------------

class OpenFinanceConnection {
  final String id;
  final String providerId;
  final String institutionName;
  final ConsentStatus consentStatus;
  final DateTime? consentExpiresAt;
  final DateTime? lastSyncAt;
  final String? lastError;
  final String? linkedAccountId;
  final String? linkedCardId;

  /// Conexão (item) e conta no provedor real; nulos no sandbox.
  final String? providerItemId;
  final String? providerAccountId;
  final DateTime createdAt;

  OpenFinanceConnection({
    required this.id,
    required this.providerId,
    required this.institutionName,
    this.consentStatus = ConsentStatus.pending,
    this.consentExpiresAt,
    this.lastSyncAt,
    this.lastError,
    this.linkedAccountId,
    this.linkedCardId,
    this.providerItemId,
    this.providerAccountId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  OpenFinanceConnection copyWith({
    ConsentStatus? consentStatus,
    Object? consentExpiresAt = _unset,
    Object? lastSyncAt = _unset,
    Object? lastError = _unset,
    Object? linkedAccountId = _unset,
    Object? linkedCardId = _unset,
  }) => OpenFinanceConnection(
    id: id,
    providerId: providerId,
    institutionName: institutionName,
    consentStatus: consentStatus ?? this.consentStatus,
    consentExpiresAt: identical(consentExpiresAt, _unset)
        ? this.consentExpiresAt
        : consentExpiresAt as DateTime?,
    lastSyncAt: identical(lastSyncAt, _unset)
        ? this.lastSyncAt
        : lastSyncAt as DateTime?,
    lastError: identical(lastError, _unset)
        ? this.lastError
        : lastError as String?,
    linkedAccountId: identical(linkedAccountId, _unset)
        ? this.linkedAccountId
        : linkedAccountId as String?,
    linkedCardId: identical(linkedCardId, _unset)
        ? this.linkedCardId
        : linkedCardId as String?,
    providerItemId: providerItemId,
    providerAccountId: providerAccountId,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'providerId': providerId,
    'institutionName': institutionName,
    'consentStatus': consentStatus.name,
    'consentExpiresAt': consentExpiresAt?.toIso8601String(),
    'lastSyncAt': lastSyncAt?.toIso8601String(),
    'lastError': lastError,
    'linkedAccountId': linkedAccountId,
    'linkedCardId': linkedCardId,
    'providerItemId': providerItemId,
    'providerAccountId': providerAccountId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory OpenFinanceConnection.fromJson(Map<String, Object?> j) =>
      OpenFinanceConnection(
        id: j['id'] as String,
        providerId: j['providerId'] as String,
        institutionName: j['institutionName'] as String,
        consentStatus: enumByName(
          ConsentStatus.values,
          j['consentStatus'] as String?,
          ConsentStatus.pending,
        ),
        consentExpiresAt: j['consentExpiresAt'] == null
            ? null
            : DateTime.parse(j['consentExpiresAt'] as String),
        lastSyncAt: j['lastSyncAt'] == null
            ? null
            : DateTime.parse(j['lastSyncAt'] as String),
        lastError: j['lastError'] as String?,
        linkedAccountId: j['linkedAccountId'] as String?,
        linkedCardId: j['linkedCardId'] as String?,
        providerItemId: j['providerItemId'] as String?,
        providerAccountId: j['providerAccountId'] as String?,
        createdAt: _ts(j['createdAt']),
      );
}

/// Transação recebida do provedor Open Finance, antes da conciliação.
class ExternalTransaction {
  final String id;
  final String connectionId;
  final String externalId;
  final DateTime date;

  /// Valor com sinal: positivo = entrada, negativo = saída.
  final Money signedAmount;
  final String description;
  final ExternalTxStatus status;
  final String? matchedTransactionId;

  ExternalTransaction({
    required this.id,
    required this.connectionId,
    required this.externalId,
    required this.date,
    required this.signedAmount,
    required this.description,
    this.status = ExternalTxStatus.pending,
    this.matchedTransactionId,
  });

  ExternalTransaction copyWith({
    ExternalTxStatus? status,
    Object? matchedTransactionId = _unset,
  }) => ExternalTransaction(
    id: id,
    connectionId: connectionId,
    externalId: externalId,
    date: date,
    signedAmount: signedAmount,
    description: description,
    status: status ?? this.status,
    matchedTransactionId: identical(matchedTransactionId, _unset)
        ? this.matchedTransactionId
        : matchedTransactionId as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'connectionId': connectionId,
    'externalId': externalId,
    'date': _d(date),
    'signedAmount': signedAmount.cents,
    'description': description,
    'status': status.name,
    'matchedTransactionId': matchedTransactionId,
  };

  factory ExternalTransaction.fromJson(Map<String, Object?> j) =>
      ExternalTransaction(
        id: j['id'] as String,
        connectionId: j['connectionId'] as String,
        externalId: j['externalId'] as String,
        date: _pd(j['date'])!,
        signedAmount: Money(j['signedAmount'] as int),
        description: (j['description'] as String?) ?? '',
        status: enumByName(
          ExternalTxStatus.values,
          j['status'] as String?,
          ExternalTxStatus.pending,
        ),
        matchedTransactionId: j['matchedTransactionId'] as String?,
      );
}

// Preferências --------------------------------------------------------------

class AppSettings {
  final String themeMode; // system | light | dark
  final CardExpenseBasis cardExpenseBasis;
  final bool isSampleData;

  /// Lista de transações: agrupa as compras do cartão em uma linha por
  /// fatura (padrão) ou mostra as compras individualmente.
  final bool groupCardInvoices;

  /// Colunas da grade de transações (ordem, visibilidade e largura), no
  /// formato JSON de `GridColumnsConfig`. Nulo = padrão.
  final List<Object?>? txGridColumns;

  const AppSettings({
    this.themeMode = 'system',
    this.cardExpenseBasis = CardExpenseBasis.invoiceDue,
    this.isSampleData = false,
    this.groupCardInvoices = true,
    this.txGridColumns,
  });

  AppSettings copyWith({
    String? themeMode,
    CardExpenseBasis? cardExpenseBasis,
    bool? isSampleData,
    bool? groupCardInvoices,
    List<Object?>? txGridColumns,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    cardExpenseBasis: cardExpenseBasis ?? this.cardExpenseBasis,
    isSampleData: isSampleData ?? this.isSampleData,
    groupCardInvoices: groupCardInvoices ?? this.groupCardInvoices,
    txGridColumns: txGridColumns ?? this.txGridColumns,
  );

  Map<String, Object?> toJson() => {
    'themeMode': themeMode,
    'cardExpenseBasis': cardExpenseBasis.name,
    'isSampleData': isSampleData,
    'groupCardInvoices': groupCardInvoices,
    'txGridColumns': txGridColumns,
  };

  factory AppSettings.fromJson(Map<String, Object?> j) => AppSettings(
    themeMode: (j['themeMode'] as String?) ?? 'system',
    cardExpenseBasis: enumByName(
      CardExpenseBasis.values,
      j['cardExpenseBasis'] as String?,
      CardExpenseBasis.invoiceDue,
    ),
    isSampleData: (j['isSampleData'] as bool?) ?? false,
    groupCardInvoices: (j['groupCardInvoices'] as bool?) ?? true,
    txGridColumns: j['txGridColumns'] as List<Object?>?,
  );
}
