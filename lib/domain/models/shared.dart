import '../../core/dates.dart';
import 'other_entry.dart' show PayStatus;

export 'other_entry.dart' show PayStatus;

/// Despesas compartilhadas entre usuários do app (dados vindos do servidor).
///
/// Percentuais em pontos-base (10000 = 100%); valores em centavos.

const fullBp = 10000;

/// "60%", "33,33%".
String bpLabel(int bp) {
  final s = (bp / 100).toStringAsFixed(bp % 100 == 0 ? 0 : 2);
  return '${s.replaceAll('.', ',')}%';
}

/// Lê "60", "33,33", "33.3" → pontos-base. `null` se inválido.
int? parseBp(String text) {
  final s = text.replaceAll('%', '').replaceAll(',', '.').trim();
  if (s.isEmpty) return 0;
  final v = double.tryParse(s);
  if (v == null || v < 0 || v > 100) return null;
  return (v * 100).round();
}

DateTime? _date(Object? s) => s == null ? null : Dates.fromIso(s as String);
DateTime? _ts(Object? s) => s == null ? null : DateTime.parse(s as String);
Map<String, int> _bpMap(Object? m) => {
  for (final e in ((m as Map?) ?? const {}).entries)
    e.key as String: (e.value as num).toInt(),
};

enum ShareRole {
  owner('Dono'),
  manager('Gestor'),
  member('Participante');

  final String label;
  const ShareRole(this.label);

  static ShareRole parse(Object? s) =>
      ShareRole.values.asNameMap()[s] ?? ShareRole.member;

  bool get canManage => this != ShareRole.member;
}

enum GroupKind {
  household('Casa'),
  couple('Casal'),
  family('Família'),
  roommates('Moradores'),
  other('Outro');

  final String label;
  const GroupKind(this.label);

  static GroupKind parse(Object? s) =>
      GroupKind.values.asNameMap()[s] ?? GroupKind.household;
}

class ShareMember {
  final String userId;
  final String name;
  final String? email;
  final ShareRole role;

  /// active | invited | rejected | revoked | left | former
  final String status;
  const ShareMember({
    required this.userId,
    required this.name,
    this.email,
    this.role = ShareRole.member,
    this.status = 'active',
  });

  bool get isActive => status == 'active';
  bool get isInvited => status == 'invited';

  String get statusLabel => switch (status) {
    'active' => 'Ativo',
    'invited' => 'Convidado',
    'rejected' => 'Recusou',
    'revoked' => 'Removido',
    'left' => 'Saiu',
    _ => 'Ex-participante',
  };

  factory ShareMember.fromJson(Map<String, Object?> j) => ShareMember(
    userId: j['userId'] as String,
    name: j['name'] as String? ?? '',
    email: j['email'] as String?,
    role: ShareRole.parse(j['role']),
    status: j['status'] as String? ?? 'active',
  );
}

class ShareCategory {
  final String id;
  final String name;
  final int sort;
  final Map<String, int> percentages;
  final bool archived;
  const ShareCategory({
    required this.id,
    required this.name,
    this.sort = 0,
    this.percentages = const {},
    this.archived = false,
  });

  factory ShareCategory.fromJson(Map<String, Object?> j) => ShareCategory(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    sort: (j['sort'] as num?)?.toInt() ?? 0,
    percentages: _bpMap(j['percentages']),
    archived: j['archived'] as bool? ?? false,
  );
}

class ShareRecurrence {
  final String id;
  final String ownerId;
  final String? sourceRuleId;
  final String? categoryId;
  final String description;
  final Map<String, int>? override;
  final bool paused;
  final DateTime? createdAt;
  const ShareRecurrence({
    required this.id,
    required this.ownerId,
    this.sourceRuleId,
    this.categoryId,
    required this.description,
    this.override,
    this.paused = false,
    this.createdAt,
  });

  factory ShareRecurrence.fromJson(Map<String, Object?> j) => ShareRecurrence(
    id: j['id'] as String,
    ownerId: j['ownerId'] as String,
    sourceRuleId: j['sourceRuleId'] as String?,
    categoryId: j['categoryId'] as String?,
    description: j['description'] as String? ?? '',
    override: j['override'] == null ? null : _bpMap(j['override']),
    paused: j['paused'] as bool? ?? false,
    createdAt: _ts(j['createdAt']),
  );
}

class ShareAllocation {
  final String userId;
  final int bp;
  final int amount;
  const ShareAllocation(this.userId, this.bp, this.amount);

  factory ShareAllocation.fromJson(Map<String, Object?> j) => ShareAllocation(
    j['userId'] as String,
    (j['bp'] as num).toInt(),
    (j['amount'] as num).toInt(),
  );
}

class SharePayment {
  final String id;
  final String userId;
  final int amount;
  final DateTime date;
  final String note;
  final String? settlementId;
  final String? recordedBy;
  const SharePayment({
    required this.id,
    required this.userId,
    required this.amount,
    required this.date,
    this.note = '',
    this.settlementId,
    this.recordedBy,
  });

  factory SharePayment.fromJson(Map<String, Object?> j) => SharePayment(
    id: j['id'] as String,
    userId: j['userId'] as String,
    amount: (j['amount'] as num).toInt(),
    date: _date(j['date'])!,
    note: j['note'] as String? ?? '',
    settlementId: j['settlementId'] as String?,
    recordedBy: j['recordedBy'] as String?,
  );
}

/// Parte de um participante numa despesa, com o que já pagou.
class ParticipantShare {
  final String userId;
  final int bp;
  final int owed;
  final int paid;

  /// Quem pagou a conta: a parte dele está quitada por definição.
  final bool isPayer;
  const ParticipantShare(
    this.userId,
    this.bp,
    this.owed,
    this.paid, {
    this.isPayer = false,
  });

  int get outstanding => isPayer ? 0 : (owed - paid).clamp(0, owed);
  int get settled => isPayer ? owed : paid;

  PayStatus get status => isPayer || paid >= owed
      ? PayStatus.paid
      : paid <= 0
      ? PayStatus.pending
      : PayStatus.partial;
}

class SharedExpense {
  final String id;
  final String groupId;
  final String ownerId;
  final String? categoryId;
  final String categoryName;
  final String description;
  final int total;
  final DateTime date;
  final DateTime? dueDate;

  /// account | card | manual | import | recurring
  final String source;
  final String? sourceKey;
  final String? recurrenceId;
  final DateTime? occurrenceDate;
  final bool overridden;
  final String notes;
  final DateTime? deletedAt;
  final List<ShareAllocation> allocations;
  final List<SharePayment> payments;

  const SharedExpense({
    required this.id,
    required this.groupId,
    required this.ownerId,
    this.categoryId,
    required this.categoryName,
    required this.description,
    required this.total,
    required this.date,
    this.dueDate,
    this.source = 'manual',
    this.sourceKey,
    this.recurrenceId,
    this.occurrenceDate,
    this.overridden = false,
    this.notes = '',
    this.deletedAt,
    this.allocations = const [],
    this.payments = const [],
  });

  bool get isDeleted => deletedAt != null;

  /// Data que vale para o orçamento (vencimento ou pagamento da fatura).
  DateTime get cashDate => dueDate ?? date;
  YearMonth get month => YearMonth.of(cashDate);

  String get sourceLabel => switch (source) {
    'card' => 'Cartão de crédito',
    'account' => 'Conta',
    'import' => 'Importada',
    'recurring' => 'Recorrente',
    _ => 'Lançamento manual',
  };

  ShareAllocation? allocationOf(String userId) =>
      allocations.where((a) => a.userId == userId).firstOrNull;

  int paidBy(String userId) =>
      payments.where((p) => p.userId == userId).fold(0, (a, p) => a + p.amount);

  List<ParticipantShare> get shares => [
    for (final a in allocations)
      ParticipantShare(
        a.userId,
        a.bp,
        a.amount,
        paidBy(a.userId),
        isPayer: a.userId == ownerId,
      ),
  ];

  ParticipantShare? shareOf(String userId) =>
      shares.where((s) => s.userId == userId).firstOrNull;

  /// Quanto os outros ainda devem a quem pagou.
  int get outstanding => shares.fold(0, (a, s) => a + s.outstanding);

  PayStatus get status {
    final others = shares.where((s) => !s.isPayer).toList();
    if (others.every((s) => s.status == PayStatus.paid)) return PayStatus.paid;
    if (others.every((s) => s.status == PayStatus.pending)) {
      return PayStatus.pending;
    }
    return PayStatus.partial;
  }

  factory SharedExpense.fromJson(String groupId, Map<String, Object?> j) =>
      SharedExpense(
        id: j['id'] as String,
        groupId: groupId,
        ownerId: j['ownerId'] as String,
        categoryId: j['categoryId'] as String?,
        categoryName: j['categoryName'] as String? ?? '',
        description: j['description'] as String? ?? '',
        total: (j['total'] as num).toInt(),
        date: _date(j['date'])!,
        dueDate: _date(j['dueDate']),
        source: j['source'] as String? ?? 'manual',
        sourceKey: j['sourceKey'] as String?,
        recurrenceId: j['recurrenceId'] as String?,
        occurrenceDate: _date(j['occurrenceDate']),
        overridden: j['overridden'] as bool? ?? false,
        notes: j['notes'] as String? ?? '',
        deletedAt: _ts(j['deletedAt']),
        allocations: [
          for (final a in (j['allocations'] as List? ?? const []))
            ShareAllocation.fromJson((a as Map).cast()),
        ],
        payments: [
          for (final p in (j['payments'] as List? ?? const []))
            SharePayment.fromJson((p as Map).cast()),
        ],
      );
}

class ShareSettlement {
  final String id;
  final String fromUserId;
  final String toUserId;
  final int amount;
  final DateTime date;
  final String note;
  const ShareSettlement({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.date,
    this.note = '',
  });

  factory ShareSettlement.fromJson(Map<String, Object?> j) => ShareSettlement(
    id: j['id'] as String,
    fromUserId: j['fromUserId'] as String,
    toUserId: j['toUserId'] as String,
    amount: (j['amount'] as num).toInt(),
    date: _date(j['date'])!,
    note: j['note'] as String? ?? '',
  );
}

class ShareGroup {
  final String id;
  final String name;
  final GroupKind kind;
  final String ownerId;
  final bool archived;
  final ShareRole myRole;

  /// Categoria do meu orçamento → categoria do grupo (última escolha).
  final Map<String, String> categoryMap;
  final List<ShareMember> members;
  final List<ShareCategory> categories;
  final List<ShareRecurrence> recurrences;
  final List<SharedExpense> expenses;
  final List<ShareSettlement> settlements;

  const ShareGroup({
    required this.id,
    required this.name,
    this.kind = GroupKind.household,
    required this.ownerId,
    this.archived = false,
    this.myRole = ShareRole.member,
    this.categoryMap = const {},
    this.members = const [],
    this.categories = const [],
    this.recurrences = const [],
    this.expenses = const [],
    this.settlements = const [],
  });

  List<ShareMember> get activeMembers =>
      members.where((m) => m.isActive).toList();

  /// Ids ativos, dono primeiro (mesma ordem da divisão no servidor).
  List<String> get activeIds => [for (final m in activeMembers) m.userId];

  /// Quem entra na divisão: ativos e convidados que ainda não responderam
  /// (a parte deles aparece quando aceitam), dono primeiro.
  List<String> get splitIds => [
    for (final m in members)
      if (m.isActive || m.isInvited) m.userId,
  ];

  /// Nome para a divisão, avisando quem ainda não aceitou o convite.
  String splitLabel(String userId) {
    final m = member(userId);
    if (m == null) return 'Ex-participante';
    return m.isInvited ? '${m.name} (convidado)' : m.name;
  }

  List<ShareCategory> get activeCategories =>
      categories.where((c) => !c.archived).toList();

  ShareMember? member(String userId) =>
      members.where((m) => m.userId == userId).firstOrNull;

  String nameOf(String userId) => member(userId)?.name ?? 'Ex-participante';

  ShareCategory? category(String? id) =>
      id == null ? null : categories.where((c) => c.id == id).firstOrNull;

  ShareRecurrence? recurrence(String? id) =>
      id == null ? null : recurrences.where((r) => r.id == id).firstOrNull;

  List<SharedExpense> get liveExpenses =>
      expenses.where((e) => !e.isDeleted).toList();

  factory ShareGroup.fromJson(Map<String, Object?> j) {
    final id = j['id'] as String;
    List<Map<String, Object?>> list(String k) => [
      for (final x in (j[k] as List? ?? const [])) (x as Map).cast(),
    ];
    return ShareGroup(
      id: id,
      name: j['name'] as String? ?? '',
      kind: GroupKind.parse(j['kind']),
      ownerId: j['ownerId'] as String,
      archived: j['archived'] as bool? ?? false,
      myRole: ShareRole.parse(j['myRole']),
      categoryMap: {
        for (final e in ((j['categoryMap'] as Map?) ?? const {}).entries)
          e.key as String: e.value as String,
      },
      members: list('members').map(ShareMember.fromJson).toList(),
      categories: list('categories').map(ShareCategory.fromJson).toList(),
      recurrences: list('recurrences').map(ShareRecurrence.fromJson).toList(),
      expenses: [
        for (final e in list('expenses')) SharedExpense.fromJson(id, e),
      ],
      settlements: list('settlements').map(ShareSettlement.fromJson).toList(),
    );
  }
}

class ShareInvite {
  final String groupId;
  final String groupName;
  final String ownerName;
  final String? invitedBy;
  const ShareInvite(
    this.groupId,
    this.groupName,
    this.ownerName,
    this.invitedBy,
  );

  factory ShareInvite.fromJson(Map<String, Object?> j) => ShareInvite(
    j['groupId'] as String,
    j['groupName'] as String? ?? '',
    j['ownerName'] as String? ?? '',
    j['invitedBy'] as String?,
  );
}

/// Tudo o que o usuário enxerga das despesas compartilhadas.
class SharedState {
  final String userId;
  final List<ShareInvite> invites;
  final List<ShareGroup> groups;
  const SharedState({
    required this.userId,
    this.invites = const [],
    this.groups = const [],
  });

  static const empty = SharedState(userId: '');

  ShareGroup? group(String? id) =>
      id == null ? null : groups.where((g) => g.id == id).firstOrNull;

  Iterable<SharedExpense> get allExpenses => groups.expand((g) => g.expenses);

  SharedExpense? expense(String id) =>
      allExpenses.where((e) => e.id == id).firstOrNull;

  factory SharedState.fromJson(Map<String, Object?> j) => SharedState(
    userId: j['userId'] as String? ?? '',
    invites: [
      for (final i in (j['invites'] as List? ?? const []))
        ShareInvite.fromJson((i as Map).cast()),
    ],
    groups: [
      for (final g in (j['groups'] as List? ?? const []))
        ShareGroup.fromJson((g as Map).cast()),
    ],
  );
}

/// Entrada de histórico (auditoria) do grupo.
class ShareAuditEntry {
  final String action;
  final Map<String, Object?> details;
  final DateTime at;
  final String? actorName;
  const ShareAuditEntry(this.action, this.details, this.at, this.actorName);

  factory ShareAuditEntry.fromJson(Map<String, Object?> j) => ShareAuditEntry(
    j['action'] as String,
    ((j['details'] as Map?) ?? const {}).cast(),
    DateTime.parse(j['at'] as String).toLocal(),
    j['actorName'] as String?,
  );
}
