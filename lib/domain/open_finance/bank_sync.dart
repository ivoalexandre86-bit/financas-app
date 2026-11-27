import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/entities.dart';

/// Transação como o provedor (Pluggy) a devolve, já no formato do app.
class ProviderTransaction {
  /// ID do provedor com prefixo (ex.: `pluggy:abc`).
  final String externalId;
  final DateTime date;

  /// Valor com sinal: positivo = entrada, negativo = saída.
  final Money signedAmount;
  final String description;

  /// Ainda não confirmado pelo banco (agendado, data futura, em
  /// processamento).
  final bool pending;

  /// Removido no banco (agendamento cancelado, lançamento desfeito).
  final bool deleted;

  const ProviderTransaction({
    required this.externalId,
    required this.date,
    required this.signedAmount,
    required this.description,
    this.pending = false,
    this.deleted = false,
  });
}

/// O que a sincronização deve gravar.
class BankSyncResult {
  final List<ExternalTransaction> externals;
  final List<FinTransaction> transactions;
  final List<String> deletedTransactionIds;

  /// Novos itens do banco nesta leitura.
  final int added;

  /// Conciliados com um lançamento já existente (manual, recorrência ou
  /// previsto).
  final int matched;

  /// Lançados sozinhos como concluídos.
  final int imported;

  /// Previstos (agendados) que entraram na projeção.
  final int scheduled;

  /// Previstos que o banco confirmou.
  final int confirmed;

  /// Removidos no banco.
  final int removed;

  const BankSyncResult({
    required this.externals,
    required this.transactions,
    required this.deletedTransactionIds,
    required this.added,
    required this.matched,
    required this.imported,
    required this.scheduled,
    required this.confirmed,
    required this.removed,
  });

  bool get isEmpty =>
      externals.isEmpty &&
      transactions.isEmpty &&
      deletedTransactionIds.isEmpty;
}

/// Conciliação da sincronização bancária, sem efeitos colaterais.
///
/// Regras:
/// - cada item do banco é identificado pelo ID do provedor: ler de novo o
///   mesmo item só atualiza o que já existe (nunca duplica);
/// - os IDs gravados são derivados do ID do provedor, então dois aparelhos
///   sincronizando ao mesmo tempo gravam os mesmos documentos;
/// - um item novo procura seu par entre os lançamentos (manuais,
///   ocorrências de recorrência e previstos pelo banco) com as regras de
///   duplicidade de sempre: mesmo sentido, mesmo valor, até
///   [toleranceDays] dias de diferença, dentro da conta/cartão vinculados;
/// - agendado no banco sem par vira lançamento **previsto** (entra na
///   projeção); quando o banco confirma, o mesmo lançamento passa a
///   concluído — conta uma vez só;
/// - se o banco confirmar com outro ID (remove o previsto e cria o
///   confirmado), o confirmado assume o lançamento previsto;
/// - agendamento cancelado no banco remove o previsto que a sincronização
///   criou; lançamento manual conciliado só perde o vínculo.
class BankSync {
  BankSync._();

  static const toleranceDays = 3;

  static String _slug(String s) => s.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');

  /// ID do documento da transação externa.
  static String externalDocId(String connectionId, String externalId) =>
      'ext_${_slug(connectionId)}_${_slug(externalId)}';

  /// ID do lançamento criado (ou materializado) pela sincronização.
  static String transactionDocId(String externalId) =>
      'tx_of_${_slug(externalId)}';

  /// Lançamento criado pela própria sincronização (não pelo usuário).
  static bool createdBySync(FinTransaction t) =>
      t.id.startsWith('tx_of_') &&
      t.recurringId == null &&
      t.installmentGroupId == null;

  static BankSyncResult plan({
    required OpenFinanceConnection connection,
    required List<ProviderTransaction> fetched,
    required List<ExternalTransaction> existing,
    required List<FinTransaction> candidates,
    required String? Function(String description, bool income) categoryFor,
  }) {
    final exts = <String, ExternalTransaction>{
      for (final e in existing)
        if (e.connectionId == connection.id) e.externalId: e,
    };
    final txs = <String, FinTransaction>{
      for (final t in candidates)
        if (!t.isVirtual) t.id: t,
    };
    final virtuals = [
      for (final t in candidates)
        if (t.isVirtual) t,
    ];
    final usedVirtual = <String>{};
    final extOut = <String, ExternalTransaction>{};
    final txOut = <String, FinTransaction>{};
    final orphans = <String>{};
    var added = 0, matched = 0, imported = 0, scheduled = 0;
    var confirmed = 0, removed = 0;

    void putExt(ExternalTransaction e) {
      exts[e.externalId] = e;
      extOut[e.id] = e;
    }

    void putTx(FinTransaction t) {
      txs[t.id] = t;
      txOut[t.id] = t;
    }

    FinTransaction? linked(ExternalTransaction e) {
      final id = e.matchedTransactionId;
      if (id == null) return null;
      final t = txs[id];
      return t != null && t.externalId == e.externalId ? t : null;
    }

    bool inScope(FinTransaction t) =>
        (connection.linkedAccountId == null ||
            t.accountId == connection.linkedAccountId) &&
        (connection.linkedCardId == null ||
            t.cardId == connection.linkedCardId);

    /// Lançamento que acompanha a confirmação do banco.
    FinTransaction settle(FinTransaction t, ProviderTransaction f) {
      var u = t;
      if (createdBySync(t)) {
        u = u.copyWith(
          date: Dates.dateOnly(f.date),
          amount: f.signedAmount.abs(),
        );
      }
      if (!f.pending &&
          t.cardId == null &&
          t.status != TransactionStatus.cancelled) {
        u = u.copyWith(status: TransactionStatus.completed);
      }
      return u;
    }

    final byId = <String, ProviderTransaction>{
      for (final f in fetched) f.externalId: f,
    };

    // 1. Removidos no banco.
    for (final f in byId.values.where((f) => f.deleted)) {
      final e = exts[f.externalId];
      if (e == null ||
          e.status == ExternalTxStatus.removed ||
          e.status == ExternalTxStatus.superseded) {
        continue;
      }
      final t = linked(e);
      if (t != null) {
        final released = t.copyWith(externalId: null);
        if (createdBySync(t)) {
          // Pode ser assumido pelo confirmado (outro ID) logo abaixo.
          txs[t.id] = released;
          orphans.add(t.id);
        } else {
          putTx(released);
        }
      }
      putExt(
        e.copyWith(
          status: ExternalTxStatus.removed,
          matchedTransactionId: null,
        ),
      );
      removed++;
    }

    // 2. Já conhecidos: só o que mudou (ex.: previsto → confirmado).
    final fresh = <ProviderTransaction>[];
    for (final f in byId.values.where((f) => !f.deleted)) {
      final e = exts[f.externalId];
      if (e == null || e.status == ExternalTxStatus.removed) {
        fresh.add(f);
        continue;
      }
      if (e.status == ExternalTxStatus.superseded) continue;
      final day = Dates.dateOnly(f.date);
      final changed =
          e.providerPending != f.pending ||
          e.date != day ||
          e.signedAmount != f.signedAmount;
      if (!changed) continue;
      final t = linked(e);
      if (t != null) {
        if (e.providerPending && !f.pending) confirmed++;
        putTx(settle(t, f));
      }
      putExt(
        e.copyWith(
          date: day,
          signedAmount: f.signedAmount,
          description: f.description,
          providerPending: f.pending,
        ),
      );
    }

    // 3. Novos: procura o par; sem par, previsto ou lançado sozinho.
    fresh.sort((a, b) => a.date.compareTo(b.date));
    for (final f in fresh) {
      added++;
      final income = f.signedAmount.isPositive;
      final amount = f.signedAmount.abs();
      final day = Dates.dateOnly(f.date);
      bool fits(FinTransaction t) =>
          !t.isTransfer &&
          t.status != TransactionStatus.cancelled &&
          (t.type == TransactionType.income) == income &&
          t.amount == amount &&
          inScope(t) &&
          Dates.daysBetween(t.date, day).abs() <= toleranceDays;

      FinTransaction? best;
      ExternalTransaction? supersede;
      var bestDiff = 1 << 30;
      void consider(FinTransaction t, int rank, [ExternalTransaction? s]) {
        final diff = Dates.daysBetween(t.date, day).abs() * 4 + rank;
        if (diff < bestDiff) {
          best = t;
          bestDiff = diff;
          supersede = s;
        }
      }

      for (final t in txs.values) {
        if (!fits(t)) continue;
        if (t.externalId == null) {
          consider(t, orphans.contains(t.id) ? 0 : 1);
        } else if (!f.pending) {
          // Previsto do banco ainda aberto com outro ID: o confirmado o
          // substitui (a remoção do previsto pode chegar depois).
          final e = exts[t.externalId];
          if (e != null &&
              e.providerPending &&
              e.status != ExternalTxStatus.removed &&
              !byId.containsKey(e.externalId)) {
            consider(t, 3, e);
          }
        }
      }
      for (final v in virtuals) {
        if (usedVirtual.contains(v.id) || !fits(v)) continue;
        consider(v, 2);
      }

      final docId = externalDocId(connection.id, f.externalId);
      final ext = ExternalTransaction(
        id: docId,
        connectionId: connection.id,
        externalId: f.externalId,
        date: day,
        signedAmount: f.signedAmount,
        description: f.description,
        providerPending: f.pending,
      );
      final match = best;
      if (match != null) {
        var t = match;
        if (t.isVirtual) {
          usedVirtual.add(t.id);
          t = t.copyWith(id: transactionDocId(f.externalId), isVirtual: false);
        }
        orphans.remove(t.id);
        final s = supersede;
        if (s != null) {
          putExt(
            s.copyWith(
              status: ExternalTxStatus.superseded,
              matchedTransactionId: null,
            ),
          );
        }
        putTx(settle(t.copyWith(externalId: f.externalId), f));
        putExt(
          ext.copyWith(
            status: ExternalTxStatus.matched,
            matchedTransactionId: t.id,
          ),
        );
        matched++;
        continue;
      }
      final canCreate =
          connection.linkedAccountId != null || connection.linkedCardId != null;
      if (canCreate && (f.pending || connection.autoImport)) {
        final t = FinTransaction(
          id: transactionDocId(f.externalId),
          type: income ? TransactionType.income : TransactionType.expense,
          amount: amount,
          description: f.description,
          categoryId:
              categoryFor(f.description, income) ??
              (income ? 'cat_other_income' : 'cat_other_expense'),
          date: day,
          accountId: connection.linkedCardId == null
              ? connection.linkedAccountId
              : null,
          cardId: connection.linkedCardId,
          status: f.pending
              ? TransactionStatus.planned
              : TransactionStatus.completed,
          externalId: f.externalId,
          notes: f.pending
              ? 'Previsto pelo banco (${connection.institutionName})'
              : 'Importado via Open Finance (${connection.institutionName})',
        );
        putTx(t);
        putExt(
          ext.copyWith(
            status: ExternalTxStatus.imported,
            matchedTransactionId: t.id,
          ),
        );
        f.pending ? scheduled++ : imported++;
      } else {
        putExt(ext);
      }
    }

    return BankSyncResult(
      externals: extOut.values.toList(),
      transactions: [
        for (final t in txOut.values)
          if (!orphans.contains(t.id)) t,
      ],
      deletedTransactionIds: orphans.toList(),
      added: added,
      matched: matched,
      imported: imported,
      scheduled: scheduled,
      confirmed: confirmed,
      removed: removed,
    );
  }
}
