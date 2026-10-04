import 'package:financas_app/data/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late Database db;
  late List<String> deletedData;

  LocalAuthService service() => LocalAuthService(
    open: () async => db,
    deleteUserData: (id) async => deletedData.add(id),
  );

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('auth.db');
    deletedData = [];
  });

  test(
    'primeiro cadastro vira admin; depois o cadastro aberto fecha',
    () async {
      final s = service();
      expect(await s.hasUsers(), isFalse);
      final admin = await s.register('Ivo', 'ivo@x.com', 'senha1234');
      expect(admin.isAdmin, isTrue);
      expect(await s.hasUsers(), isTrue);
      await expectLater(
        s.register('Outro', 'outro@x.com', 'senha1234'),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test('migração: usuário já existente vira administrador', () async {
    final users = StoreRef<String, Map<String, Object?>>('users');
    await users.record('demo').put(db, {
      'id': 'demo',
      'name': 'Demo',
      'email': LocalAuthService.demoEmail,
      'isDemo': true,
      'createdAt': '2026-01-01T00:00:00',
    });
    await users.record('u_old').put(db, {
      'id': 'u_old',
      'name': 'Antigo',
      'email': 'antigo@x.com',
      'isDemo': false,
      'createdAt': '2026-02-01T00:00:00',
    });
    await users.record('u_new').put(db, {
      'id': 'u_new',
      'name': 'Novo',
      'email': 'novo@x.com',
      'isDemo': false,
      'createdAt': '2026-03-01T00:00:00',
    });
    await service().hasUsers();
    expect((await users.record('u_old').get(db))!['isAdmin'], isTrue);
    expect((await users.record('u_new').get(db))!['isAdmin'], isNull);
    expect((await users.record('demo').get(db))!['isAdmin'], isNull);
  });

  test('admin cria usuário que entra com a própria senha', () async {
    final s = service();
    await s.register('Ivo', 'ivo@x.com', 'senha1234');
    final ana = await s.createUser('Ana', 'Ana@X.com ', 'abcd1234');
    expect(ana.isAdmin, isFalse);
    expect(ana.email, 'ana@x.com');
    await expectLater(
      s.createUser('Ana 2', 'ana@x.com', 'abcd1234'),
      throwsA(isA<AuthException>()),
    );
    expect((await s.listUsers()).map((u) => u.name), ['Ana', 'Ivo']);

    await s.logout();
    final logged = await s.login('ana@x.com', 'abcd1234');
    expect(logged.id, ana.id);
    // Não administrador não gerencia usuários.
    await expectLater(s.listUsers(), throwsA(isA<AuthException>()));
    await expectLater(
      s.createUser('Zé', 'ze@x.com', 'abcd1234'),
      throwsA(isA<AuthException>()),
    );
  });

  test('único administrador não pode ser rebaixado nem excluído', () async {
    final s = service();
    final ivo = await s.register('Ivo', 'ivo@x.com', 'senha1234');
    final ana = await s.createUser('Ana', 'ana@x.com', 'abcd1234');
    await expectLater(
      s.updateUser(ivo.id, name: 'Ivo', email: 'ivo@x.com', isAdmin: false),
      throwsA(isA<AuthException>()),
    );
    await expectLater(s.deleteAccount(ivo.id), throwsA(isA<AuthException>()));
    await expectLater(s.deleteUser(ivo.id), throwsA(isA<AuthException>()));

    // Promovendo a Ana, o Ivo pode deixar de ser admin.
    await s.updateUser(ana.id, name: 'Ana', email: 'ana@x.com', isAdmin: true);
    final ivo2 = await s.updateUser(
      ivo.id,
      name: 'Ivo A.',
      email: 'ivo@x.com',
      isAdmin: false,
    );
    expect(ivo2.isAdmin, isFalse);
    expect(ivo2.name, 'Ivo A.');
  });

  test('excluir usuário apaga também o orçamento dele', () async {
    final s = service();
    await s.register('Ivo', 'ivo@x.com', 'senha1234');
    final ana = await s.createUser('Ana', 'ana@x.com', 'abcd1234');
    await s.deleteUser(ana.id);
    expect(deletedData, [ana.id]);
    expect((await s.listUsers()).length, 1);
    await expectLater(
      s.login('ana@x.com', 'abcd1234'),
      throwsA(isA<AuthException>()),
    );
  });

  test('redefinir e alterar senha', () async {
    final s = service();
    await s.register('Ivo', 'ivo@x.com', 'senha1234');
    final ana = await s.createUser('Ana', 'ana@x.com', 'abcd1234');
    await s.resetPassword(ana.id, 'nova12345');
    await s.logout();
    await expectLater(
      s.login('ana@x.com', 'abcd1234'),
      throwsA(isA<AuthException>()),
    );
    await s.login('ana@x.com', 'nova12345');
    await expectLater(
      s.changePassword('errada123', 'outra1234'),
      throwsA(isA<AuthException>()),
    );
    await s.changePassword('nova12345', 'outra1234');
    await s.logout();
    expect((await s.login('ana@x.com', 'outra1234')).id, ana.id);
  });
}
