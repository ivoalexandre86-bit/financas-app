import 'dart:math';

import '../core/dates.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../domain/models/entities.dart';

/// Instituição disponível no provedor.
class OFInstitution {
  final String id;
  final String name;
  const OFInstitution(this.id, this.name);
}

/// Resultado do fluxo de consentimento.
class ConsentResult {
  final ConsentStatus status;
  final DateTime? expiresAt;
  const ConsentResult(this.status, this.expiresAt);
}

/// Conta encontrada numa conexão (item) do provedor.
class OFRemoteAccount {
  final String id;
  final bool isCreditCard;
  final String label;
  const OFRemoteAccount({
    required this.id,
    required this.isCreditCard,
    required this.label,
  });
}

/// Conexão (item) registrada no provedor, com suas contas.
class OFLinkedItem {
  final String id;
  final String institution;
  final DateTime? consentExpiresAt;
  final List<OFRemoteAccount> accounts;
  const OFLinkedItem({
    required this.id,
    required this.institution,
    this.consentExpiresAt,
    required this.accounts,
  });
}

/// Contrato de um provedor Open Finance autorizado (ex.: agregadores
/// regulados pelo Banco Central). O núcleo financeiro depende apenas desta
/// interface, então trocar de provedor não exige mudanças no restante do app.
///
/// O app **nunca** solicita ou armazena senhas bancárias: a autorização é
/// feita no ambiente da instituição (redirecionamento OAuth/FAPI) e o
/// provedor devolve apenas o status do consentimento.
abstract class OpenFinanceProvider {
  const OpenFinanceProvider();

  String get id;
  String get displayName;
  bool get isSandbox;

  /// Provedores reais (ex.: Pluggy) conectam colando o ID da conexão criada
  /// no portal do provedor, em vez de escolher a instituição na lista.
  bool get connectsByItemId => false;

  /// O servidor tem as credenciais do provedor?
  Future<bool> isConfigured() async => true;

  /// Registra a conexão [itemId] para o usuário e devolve as contas dela.
  Future<OFLinkedItem> linkItem(String itemId) =>
      throw UnsupportedError('Provedor não conecta por ID');

  Future<List<OFInstitution>> institutions();
  Future<ConsentResult> requestConsent(OFInstitution institution);
  Future<List<ExternalTransaction>> fetchTransactions(
    OpenFinanceConnection connection, {
    DateTime? since,
  });
  Future<void> revokeConsent(OpenFinanceConnection connection);
}

/// Provedor de **sandbox** para demonstração: simula consentimento e devolve
/// transações fictícias. Substitua por uma implementação real (via backend)
/// antes de produção.
class SandboxOpenFinanceProvider extends OpenFinanceProvider {
  @override
  String get id => 'sandbox';
  @override
  String get displayName => 'Sandbox (dados simulados)';
  @override
  bool get isSandbox => true;

  @override
  Future<List<OFInstitution>> institutions() async => const [
    OFInstitution('itau', 'Itaú Unibanco'),
    OFInstitution('nubank', 'Nubank'),
    OFInstitution('bb', 'Banco do Brasil'),
    OFInstitution('bradesco', 'Bradesco'),
    OFInstitution('inter', 'Banco Inter'),
  ];

  @override
  Future<ConsentResult> requestConsent(OFInstitution institution) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return ConsentResult(
      ConsentStatus.active,
      DateTime.now().add(const Duration(days: 365)),
    );
  }

  @override
  Future<List<ExternalTransaction>> fetchTransactions(
    OpenFinanceConnection connection, {
    DateTime? since,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final rnd = Random(connection.id.hashCode);
    final today = Dates.today();
    const samples = [
      ('PIX RECEBIDO - CLIENTE', 85000),
      ('SUPERMERCADO PAO DE ACUCAR', -23450),
      ('UBER *TRIP', -2790),
      ('IFOOD *RESTAURANTE', -6480),
      ('POSTO SHELL', -21000),
      ('DROGASIL', -5890),
      ('NETFLIX.COM', -5590),
    ];
    return [
      for (var i = 0; i < samples.length; i++)
        ExternalTransaction(
          id: newId('ext_'),
          connectionId: connection.id,
          externalId: '${connection.id}-$i',
          date: today.subtract(Duration(days: 1 + rnd.nextInt(20))),
          signedAmount: Money(samples[i].$2),
          description: samples[i].$1,
        ),
    ];
  }

  @override
  Future<void> revokeConsent(OpenFinanceConnection connection) async {}
}

/// Detecção de duplicidade entre transações importadas e lançamentos
/// manuais: mesmo sentido, mesmo valor e datas a até [toleranceDays] dias.
class DuplicateDetector {
  static const toleranceDays = 3;

  static FinTransaction? findMatch(
    ExternalTransaction ext,
    Iterable<FinTransaction> candidates, {
    Set<String> alreadyMatched = const {},
  }) {
    final isIncome = ext.signedAmount.isPositive;
    FinTransaction? best;
    var bestDiff = 1 << 30;
    for (final t in candidates) {
      if (t.isVirtual || t.isTransfer) continue;
      if (alreadyMatched.contains(t.id)) continue;
      if (t.externalId != null) continue;
      if ((t.type == TransactionType.income) != isIncome) continue;
      if (t.amount != ext.signedAmount.abs()) continue;
      final diff = t.date.difference(ext.date).inDays.abs();
      if (diff > toleranceDays) continue;
      if (diff < bestDiff) {
        best = t;
        bestDiff = diff;
      }
    }
    return best;
  }
}
