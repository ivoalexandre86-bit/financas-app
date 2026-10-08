import '../../core/ids.dart';
import '../../core/money.dart';
import '../../domain/models/entities.dart';
import '../open_finance.dart';
import 'api_client.dart';

/// Open Finance real via Pluggy, sempre pelo servidor do app (as credenciais
/// da Pluggy ficam só no servidor). O usuário autoriza os bancos no Meu
/// Pluggy e cola aqui o ID da conexão; cada conta vira uma conexão do app.
class PluggyOpenFinanceProvider extends OpenFinanceProvider {
  final ApiClient api;
  PluggyOpenFinanceProvider(this.api);

  @override
  String get id => 'pluggy';
  @override
  String get displayName => 'Pluggy (Open Finance)';
  @override
  bool get isSandbox => false;
  @override
  bool get connectsByItemId => true;

  @override
  Future<bool> isConfigured() async =>
      (await api.get('openfinance/status'))['configured'] == true;

  @override
  Future<String> connectToken() async =>
      (await api.post('openfinance/connect-token'))['connectToken'] as String;

  @override
  Future<OFLinkedItem> linkItem(String itemId) async {
    final r = await api.post('openfinance/items', {'itemId': itemId.trim()});
    final item = (r['item'] as Map).cast<String, Object?>();
    final expires = item['consentExpiresAt'] as String?;
    return OFLinkedItem(
      id: item['id'] as String,
      institution: item['institution'] as String,
      consentExpiresAt: expires == null ? null : DateTime.parse(expires),
      accounts: [
        for (final a in (r['accounts'] as List).cast<Map>())
          OFRemoteAccount(
            id: a['id'] as String,
            isCreditCard: a['kind'] == 'credit_card',
            label: a['label'] as String,
          ),
      ],
    );
  }

  @override
  Future<List<OFInstitution>> institutions() async => const [];

  @override
  Future<ConsentResult> requestConsent(OFInstitution institution) =>
      throw UnsupportedError('Conecte pelo ID da conexão do Meu Pluggy');

  @override
  Future<List<ExternalTransaction>> fetchTransactions(
    OpenFinanceConnection connection, {
    DateTime? since,
  }) async {
    final account = connection.providerAccountId;
    if (account == null) throw StateError('Conexão sem conta do provedor');
    final from = since == null
        ? ''
        : '?from=${since.toIso8601String().substring(0, 10)}';
    final r = await api.get(
      'openfinance/accounts/${Uri.encodeComponent(account)}/transactions$from',
    );
    return [
      for (final t in (r['transactions'] as List).cast<Map>())
        // Lançamentos ainda pendentes no banco mudam de ID ao serem
        // confirmados; esperamos a confirmação para não duplicar.
        if (t['pending'] != true)
          ExternalTransaction(
            id: newId('ext_'),
            connectionId: connection.id,
            externalId: 'pluggy:${t['id']}',
            date: DateTime.parse(t['date'] as String),
            signedAmount: Money(t['amountCents'] as int),
            description: t['description'] as String,
          ),
    ];
  }

  @override
  Future<void> revokeConsent(OpenFinanceConnection connection) async {
    final item = connection.providerItemId;
    if (item != null) {
      await api.delete('openfinance/items/${Uri.encodeComponent(item)}');
    }
  }
}
