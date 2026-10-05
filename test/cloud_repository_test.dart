import 'package:financas_app/data/cloud/api_client.dart';
import 'package:financas_app/data/cloud/cloud_finance_repository.dart';
import 'package:financas_app/data/finance_repository.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

/// Nuvem falsa em memória, que pode ficar "fora do ar".
class FakeRemote implements RemoteDocStore {
  final docs = <String, Map<String, Object?>>{};
  bool offline = false;
  int pushes = 0;

  @override
  Future<List<RemoteDoc>> fetchAll() async {
    if (offline) throw const OfflineException();
    return [
      for (final e in docs.entries)
        RemoteDoc(e.key.split('/').first, e.key.split('/').last, e.value),
    ];
  }

  @override
  Future<void> push(List<RemoteDoc> list) async {
    if (offline) throw const OfflineException();
    pushes++;
    for (final d in list) {
      if (d.data == null) {
        docs.remove('${d.coll}/${d.id}');
      } else {
        docs['${d.coll}/${d.id}'] = d.data!;
      }
    }
  }
}

void main() {
  late DatabaseFactory factory;
  late FakeRemote remote;

  // Um "aparelho": cópia local + fila, que sobrevivem entre aberturas.
  CloudFinanceRepository device(String name) => CloudFinanceRepository(
    'u1',
    remote,
    local: LocalFinanceRepository(
      'cloud_u1',
      opener: () => factory.openDatabase('$name-data.db'),
    ),
    openOutbox: () => factory.openDatabase('$name-outbox.db'),
  );

  WriteOp account(String id, String name) =>
      WriteOp.put(Coll.accounts, id, Account(id: id, name: name).toJson());

  setUp(() {
    factory = newDatabaseFactoryMemory();
    remote = FakeRemote();
  });

  test('gravação em um aparelho aparece no outro', () async {
    final pc = device('pc');
    final first = await pc.load();
    expect(first.accounts, isEmpty);
    expect(pc.remoteWasEmpty, isTrue);
    await pc.write([account('a', 'Nubank')]);
    await pc.flush();
    expect(remote.docs.keys, contains('accounts/a'));

    final phone = device('phone');
    final data = await phone.load();
    expect(data.accounts.map((a) => a.name), ['Nubank']);
    expect(phone.remoteWasEmpty, isFalse);

    await phone.write([const WriteOp.delete(Coll.accounts, 'a')]);
    await phone.flush();
    await pc.refresh();
    expect((await pc.load()).accounts, isEmpty);
  });

  test('sem internet: grava localmente e envia quando voltar', () async {
    final pc = device('pc');
    await pc.load();
    remote.offline = true;
    await pc.write([account('a', 'Itaú')]);
    await pc.write([account('a', 'Itaú PJ')]);
    await pc.flush();
    expect(pc.online, isFalse);
    expect(await pc.pendingCount(), 2);
    expect((await pc.load()).accounts.single.name, 'Itaú PJ');

    // Fecha e reabre o app ainda sem internet: a fila foi guardada.
    await pc.close();
    final again = device('pc');
    expect((await again.load()).accounts.single.name, 'Itaú PJ');
    expect(await again.pendingCount(), 2);

    remote.offline = false;
    await again.refresh();
    expect(again.online, isTrue);
    expect(await again.pendingCount(), 0);
    expect(remote.docs['accounts/a']?['name'], 'Itaú PJ');
    expect(remote.pushes, 1, reason: 'só a última versão sobe');
  });

  test('importar dados do aparelho substitui os da nuvem', () async {
    final pc = device('pc');
    await pc.load();
    await pc.write([account('old', 'Antiga')]);
    await pc.flush();

    final n = await pc.importAll({
      'accounts': {'a': Account(id: 'a', name: 'Conta').toJson()},
      settingsColl: {'app': const AppSettings().toJson()},
    });
    expect(n, 1);
    expect(remote.docs.keys, isNot(contains('accounts/old')));
    expect(remote.docs.keys, containsAll(['accounts/a', 'settings/app']));
    expect((await pc.load()).accounts.map((a) => a.id), ['a']);
  });
}
