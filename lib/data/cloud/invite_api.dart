import 'api_client.dart';

/// Convite pelo WhatsApp feito pelo administrador.
class WhatsAppInvite {
  final String id;
  final String name;
  final String phone;
  final String phoneLabel;
  final bool joinAccount;

  /// pending | accepted | expired.
  final String status;

  /// not_sent | sent | delivered | read | failed.
  final String sendStatus;
  final String? sendError;
  final String? userName;
  final String link;

  /// Abre o WhatsApp do próprio administrador com o texto do convite.
  final String shareUrl;
  final DateTime? expiresAt;

  const WhatsAppInvite({
    required this.id,
    required this.name,
    required this.phone,
    required this.phoneLabel,
    required this.joinAccount,
    required this.status,
    required this.sendStatus,
    required this.sendError,
    required this.userName,
    required this.link,
    required this.shareUrl,
    required this.expiresAt,
  });

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get sentByBot =>
      const {'sent', 'delivered', 'read'}.contains(sendStatus);

  factory WhatsAppInvite.fromJson(Map<String, Object?> j) => WhatsAppInvite(
    id: j['id'] as String,
    name: j['name'] as String,
    phone: j['phone'] as String,
    phoneLabel: (j['phoneLabel'] as String?) ?? j['phone'] as String,
    joinAccount: (j['joinAccount'] as bool?) ?? false,
    status: j['status'] as String,
    sendStatus: (j['sendStatus'] as String?) ?? 'not_sent',
    sendError: j['sendError'] as String?,
    userName: j['userName'] as String?,
    link: j['link'] as String,
    shareUrl: j['shareUrl'] as String,
    expiresAt: DateTime.tryParse('${j['expiresAt']}'),
  );
}

/// Situação do modelo da mensagem de convite na Meta.
class InviteTemplate {
  /// APPROVED | PENDING | MISSING | REJECTED | PAUSED | DISABLED | UNKNOWN | OFF.
  final String status;
  final String? rejectedReason;
  const InviteTemplate(this.status, [this.rejectedReason]);

  bool get approved => status == 'APPROVED';

  factory InviteTemplate.fromJson(Object? j) => j is Map
      ? InviteTemplate(
          (j['status'] as String?) ?? 'UNKNOWN',
          j['rejectedReason'] as String?,
        )
      : const InviteTemplate('UNKNOWN');
}

class InvitesState {
  final List<WhatsAppInvite> invites;
  final InviteTemplate template;
  const InvitesState(this.invites, this.template);
}

/// Convite visto por quem recebeu (tela de cadastro, sem login).
class InviteInfo {
  final String token;
  final String name;
  final String inviterName;
  final bool joinAccount;
  const InviteInfo({
    required this.token,
    required this.name,
    required this.inviterName,
    required this.joinAccount,
  });
}

abstract class InviteApi {
  Future<InvitesState> list();
  Future<(WhatsAppInvite, InviteTemplate)> create({
    required String name,
    required String phone,
    required bool joinAccount,
  });
  Future<(WhatsAppInvite, InviteTemplate)> resend(String id);
  Future<void> cancel(String id);
}

class HttpInviteApi implements InviteApi {
  final ApiClient api;
  HttpInviteApi(this.api);

  (WhatsAppInvite, InviteTemplate) _one(Map<String, Object?> r) => (
    WhatsAppInvite.fromJson((r['invite'] as Map).cast<String, Object?>()),
    InviteTemplate.fromJson(r['template']),
  );

  @override
  Future<InvitesState> list() async {
    final r = await api.get('invites');
    return InvitesState(
      [
        for (final i in (r['invites'] as List? ?? const []))
          WhatsAppInvite.fromJson((i as Map).cast<String, Object?>()),
      ],
      InviteTemplate.fromJson(r['template']),
    );
  }

  @override
  Future<(WhatsAppInvite, InviteTemplate)> create({
    required String name,
    required String phone,
    required bool joinAccount,
  }) async => _one(
    await api.post('invites', {
      'name': name,
      'phone': phone,
      'joinAccount': joinAccount,
    }),
  );

  @override
  Future<(WhatsAppInvite, InviteTemplate)> resend(String id) async =>
      _one(await api.post('invites/$id/resend', const {}));

  @override
  Future<void> cancel(String id) => api.delete('invites/$id');

  /// Dados do convite recebido pelo link (sem login).
  static Future<InviteInfo> lookup(ApiClient api, String token) async {
    final r = await api.get('auth/invites/${Uri.encodeComponent(token)}');
    return InviteInfo(
      token: token,
      name: (r['name'] as String?) ?? '',
      inviterName: (r['inviterName'] as String?) ?? '',
      joinAccount: (r['joinAccount'] as bool?) ?? false,
    );
  }
}
