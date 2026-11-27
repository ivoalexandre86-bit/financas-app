import 'api_client.dart';

/// O que uma pessoa da conta enxerga: só estes cartões e contas (e os
/// lançamentos deles). `null` em vez de um [AccessScope] = todo o orçamento.
class AccessScope {
  final List<String> cards;
  final List<String> accounts;
  const AccessScope({this.cards = const [], this.accounts = const []});

  bool get isEmpty => cards.isEmpty && accounts.isEmpty;

  static AccessScope? fromJson(Object? j) => j is Map
      ? AccessScope(
          cards: [for (final c in (j['cards'] as List? ?? const [])) '$c'],
          accounts: [
            for (final a in (j['accounts'] as List? ?? const [])) '$a',
          ],
        )
      : null;

  Map<String, Object?> toJson() => {'cards': cards, 'accounts': accounts};
}

/// Pessoa da conta: o dono, quem já entrou ou quem foi convidado.
class AccountMember {
  /// Id do vínculo (nulo para o dono).
  final String? id;
  final String? userId;
  final String? name;
  final String email;

  /// owner | active | invited.
  final String status;

  /// Acesso limitado (null = todo o orçamento).
  final AccessScope? scope;
  const AccountMember({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.status,
    this.scope,
  });

  bool get isOwner => status == 'owner';
  bool get isInvited => status == 'invited';
  String get label => name ?? email;

  factory AccountMember.fromJson(Map<String, Object?> j) => AccountMember(
    id: j['id'] as String?,
    userId: j['userId'] as String?,
    name: j['name'] as String?,
    email: j['email'] as String,
    status: j['status'] as String,
    scope: AccessScope.fromJson(j['scope']),
  );
}

/// Convite recebido para usar a conta de outra pessoa.
class AccountInvite {
  final String id;
  final String ownerName;
  final String ownerEmail;
  const AccountInvite(this.id, this.ownerName, this.ownerEmail);

  factory AccountInvite.fromJson(Map<String, Object?> j) => AccountInvite(
    j['id'] as String,
    j['ownerName'] as String,
    j['ownerEmail'] as String,
  );
}

/// Conta em uso, quem participa dela e os convites recebidos.
class AccountState {
  final String accountId;
  final String ownerName;
  final String ownerEmail;

  /// A conta em uso é a do próprio usuário.
  final bool isOwner;

  /// Meu acesso à conta de outra pessoa (null = todo o orçamento).
  final AccessScope? myScope;
  final List<AccountMember> members;
  final List<AccountInvite> invites;
  final int maxMembers;
  const AccountState({
    required this.accountId,
    required this.ownerName,
    required this.ownerEmail,
    required this.isOwner,
    required this.members,
    required this.invites,
    this.maxMembers = 5,
    this.myScope,
  });

  /// Pessoas além do dono (inclui convites pendentes).
  int get guestCount => members.where((m) => !m.isOwner).length;

  factory AccountState.fromJson(Map<String, Object?> j) {
    final a = (j['account'] as Map).cast<String, Object?>();
    return AccountState(
      accountId: a['id'] as String,
      ownerName: a['ownerName'] as String,
      ownerEmail: a['ownerEmail'] as String,
      isOwner: a['isOwner'] == true,
      myScope: AccessScope.fromJson(a['scope']),
      members: [
        for (final m in (j['members'] as List? ?? const []))
          AccountMember.fromJson((m as Map).cast<String, Object?>()),
      ],
      invites: [
        for (final i in (j['invites'] as List? ?? const []))
          AccountInvite.fromJson((i as Map).cast<String, Object?>()),
      ],
      maxMembers: (j['maxMembers'] as num?)?.toInt() ?? 5,
    );
  }
}

/// Conta com vários usuários (servidor).
abstract class AccountApi {
  Future<AccountState> state();
  Future<AccountState> invite(String email, {AccessScope? scope});

  /// Dono: muda o acesso de uma pessoa (null = todo o orçamento).
  Future<AccountState> setScope(String memberId, AccessScope? scope);
  Future<AccountState> remove(String memberId);
  Future<AccountState> leave();
  Future<AccountState> accept(String inviteId);
  Future<AccountState> reject(String inviteId);
}

class HttpAccountApi implements AccountApi {
  final ApiClient api;
  HttpAccountApi(this.api);

  AccountState _s(Map<String, Object?> j) => AccountState.fromJson(j);

  @override
  Future<AccountState> state() async => _s(await api.get('account'));
  @override
  Future<AccountState> invite(String email, {AccessScope? scope}) async =>
      _s(
        await api.post('account/members', {
          'email': email,
          if (scope != null) 'scope': scope.toJson(),
        }),
      );
  @override
  Future<AccountState> setScope(String memberId, AccessScope? scope) async =>
      _s(
        await api.patch('account/members/$memberId', {
          'scope': scope?.toJson(),
        }),
      );
  @override
  Future<AccountState> remove(String memberId) async =>
      _s(await api.delete('account/members/$memberId'));
  @override
  Future<AccountState> leave() async =>
      _s(await api.post('account/leave', const {}));
  @override
  Future<AccountState> accept(String inviteId) async =>
      _s(await api.post('account/invites/$inviteId/accept', const {}));
  @override
  Future<AccountState> reject(String inviteId) async =>
      _s(await api.post('account/invites/$inviteId/reject', const {}));
}
