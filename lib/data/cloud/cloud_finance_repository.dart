import 'dart:async';

import 'package:sembast/sembast.dart';

import '../../domain/engine/financial_engine.dart';
import '../../domain/models/dashboard.dart';
import '../../domain/models/entities.dart';
import '../../domain/models/other_entry.dart';
import '../../domain/models/simulation.dart';
import '../db_factory.dart';
import '../finance_repository.dart';
import 'api_client.dart';

/// Documento remoto: um registro de uma coleção (`data == null` = excluído).
class RemoteDoc {
  final String coll;
  final String id;
  final Map<String, Object?>? data;
  const RemoteDoc(this.coll, this.id, this.data);
}

/// Armazenamento de documentos na nuvem.
abstract class RemoteDocStore {
  Future<List<RemoteDoc>> fetchAll();
  Future<void> push(List<RemoteDoc> docs);
}

class ApiDocStore implements RemoteDocStore {
  final ApiClient api;
  ApiDocStore(this.api);

  static const _batch = 500;

  @override
  Future<List<RemoteDoc>> fetchAll() async => [
    for (final d in (await api.get('docs'))['docs'] as List)
      RemoteDoc(
        d['coll'] as String,
        d['id'] as String,
        (d['data'] as Map).cast<String, Object?>(),
      ),
  ];

  @override
  Future<void> push(List<RemoteDoc> docs) async {
    for (var i = 0; i < docs.length; i += _batch) {
      final part = docs.sublist(
        i,
        i + _batch > docs.length ? docs.length : i + _batch,
      );
      await api.post('docs/batch', {
        'docs': [
          for (final d in part) {'coll': d.coll, 'id': d.id, 'data': d.data},
        ],
      });
    }
  }
}

/// Dados do usuário na nuvem, com cópia local para abrir rápido e funcionar
/// sem internet.
///
/// * Leituras vêm da cópia local ([LocalFinanceRepository]).
/// * Ao abrir ([load] pela 1ª vez ou [refresh]), as alterações pendentes são
///   enviadas e a cópia local é substituída pelo que está na nuvem.
/// * Cada gravação vai para a cópia local e para uma fila de envio
///   (persistida), que é enviada em seguida — ou quando a conexão voltar.
class CloudFinanceRepository implements FinanceRepository {
  final LocalFinanceRepository local;
  final RemoteDocStore remote;

  CloudFinanceRepository(
    String userId,
    this.remote, {
    LocalFinanceRepository? local,
    Future<Database> Function()? openOutbox,
  }) : local = local ?? LocalFinanceRepository('cloud_$userId'),
       _openOutbox =
           openOutbox ?? (() => openAppDatabase('financas_outbox_$userId.db')),
       _outboxName = 'financas_outbox_$userId.db';

  final Future<Database> Function() _openOutbox;
  final String _outboxName;
  Future<Database>? _outboxDb;
  Future<Database> get _outbox => _outboxDb ??= _openOutbox();
  final _queue = intMapStoreFactory.store('queue');

  bool _pulled = false;

  /// A última sincronização com a nuvem funcionou?
  bool online = false;

  /// A nuvem não tinha nenhum dado na última sincronização (conta nova).
  bool remoteWasEmpty = false;

  Future<void> _flushing = Future.value();

  /// Sincronização iniciada em segundo plano ao abrir com cópia local.
  Future<void>? backgroundSync;

  /// Abre na hora com a cópia local, quando existe, e sincroniza com a
  /// nuvem em segundo plano ([backgroundSync]). Sem cópia local (primeiro
  /// acesso no aparelho), espera o download.
  @override
  Future<FinanceData> load() async {
    if (!_pulled && backgroundSync == null) {
      if (await local.hasData()) {
        backgroundSync = refresh();
      } else {
        await refresh();
      }
    }
    return local.load();
  }

  /// Envia pendências e baixa tudo da nuvem. Sem conexão, mantém a cópia
  /// local (e tenta de novo na próxima vez).
  Future<void> refresh() async {
    try {
      await flush(throwOnError: true);
      final docs = await remote.fetchAll();
      final byColl = <String, Map<String, Map<String, Object?>>>{};
      for (final d in docs) {
        if (d.data == null) continue;
        (byColl[d.coll] ??= {})[d.id] = d.data!;
      }
      // Gravações feitas durante o download ainda estão na fila: não
      // sobrescreve a cópia local com uma versão antiga.
      if (await _queue.count(await _outbox) > 0) return;
      await local.replaceAll(byColl);
      remoteWasEmpty = docs.isEmpty;
      online = true;
      _pulled = true;
    } on OfflineException {
      online = false;
    }
  }

  @override
  Future<List<OpenFinanceConnection>> loadConnections() =>
      local.loadConnections();

  @override
  Future<List<ExternalTransaction>> loadExternalTransactions() =>
      local.loadExternalTransactions();

  @override
  Future<List<Dashboard>> loadDashboards() => local.loadDashboards();

  @override
  Future<List<Simulation>> loadSimulations() => local.loadSimulations();

  @override
  Future<List<OtherEntry>> loadOtherEntries() => local.loadOtherEntries();

  @override
  Future<List<Person>> loadPeople() => local.loadPeople();

  @override
  Future<void> write(List<WriteOp> ops) async {
    if (ops.isEmpty) return;
    await local.write(ops);
    await _enqueue([
      for (final op in ops) RemoteDoc(op.coll.name, op.id, op.json),
    ]);
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    await local.saveSettings(settings);
    await _enqueue([RemoteDoc(settingsColl, 'app', settings.toJson())]);
  }

  Future<void> _enqueue(List<RemoteDoc> docs) async {
    final db = await _outbox;
    await db.transaction((txn) async {
      for (final d in docs) {
        await _queue.add(txn, {'coll': d.coll, 'id': d.id, 'data': d.data});
      }
    });
    unawaited(flush());
  }

  /// Envia a fila (uma vez por vez). Falhas de rede deixam a fila intacta.
  Future<void> flush({bool throwOnError = false}) {
    final run = _flushing.then((_) => _flushOnce());
    _flushing = run.catchError((_) {});
    return throwOnError ? run : _flushing;
  }

  Future<void> _flushOnce() async {
    final db = await _outbox;
    final recs = await _queue.find(db);
    if (recs.isEmpty) return;
    // Só a última versão de cada registro precisa subir.
    final latest = <String, RemoteDoc>{};
    for (final r in recs) {
      final v = r.value;
      final coll = v['coll'] as String;
      final id = v['id'] as String;
      latest['$coll/$id'] = RemoteDoc(
        coll,
        id,
        (v['data'] as Map?)?.cast<String, Object?>(),
      );
    }
    try {
      await remote.push(latest.values.toList());
      online = true;
    } on OfflineException {
      online = false;
      rethrow;
    }
    await _queue.records(recs.map((r) => r.key)).delete(db);
  }

  /// Gravações ainda não enviadas à nuvem.
  Future<int> pendingCount() async => _queue.count(await _outbox);

  /// Substitui todos os dados da conta na nuvem pelos de [docs] (dados
  /// trazidos de um aparelho). Registros que não estão em [docs] são
  /// excluídos.
  Future<int> importAll(
    Map<String, Map<String, Map<String, Object?>>> docs,
  ) async {
    final current = await local.dumpDocs();
    final out = <RemoteDoc>[];
    current.forEach((coll, recs) {
      for (final id in recs.keys) {
        if (docs[coll]?.containsKey(id) != true) {
          out.add(RemoteDoc(coll, id, null));
        }
      }
    });
    var count = 0;
    docs.forEach((coll, recs) {
      recs.forEach((id, data) {
        out.add(RemoteDoc(coll, id, data));
        if (coll != settingsColl) count++;
      });
    });
    await remote.push(out);
    await local.replaceAll(docs);
    remoteWasEmpty = false;
    return count;
  }

  @override
  Future<void> close() async {
    await local.close();
    await (await _outbox).close();
    _outboxDb = null;
  }

  @override
  Future<void> destroy() async {
    await local.destroy();
    await close();
    await deleteAppDatabase(_outboxName);
  }
}
