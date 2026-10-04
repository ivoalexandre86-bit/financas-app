import 'package:sembast/sembast.dart';

import '../auth_service.dart';
import '../db_factory.dart';
import 'api_client.dart';

/// Login pela API na nuvem: a mesma conta e os mesmos dados em qualquer
/// aparelho. A conta de demonstração continua local ([LocalAuthService]).
///
/// A sessão (token + dados do usuário) fica guardada no aparelho, então o
/// app abre mesmo sem internet com a última conta usada.
class CloudAuthService implements AuthService {
  final ApiClient api;
  final LocalAuthService local;

  CloudAuthService(
    this.api, {
    LocalAuthService? local,
    Future<Database> Function()? open,
  }) : local = local ?? LocalAuthService(),
       _open = open ?? (() => openAppDatabase('financas_cloud_session.db'));

  final Future<Database> Function() _open;
  Future<Database>? _db;
  Future<Database> get _database => _db ??= _open();
  final _session = StoreRef<String, Map<String, Object?>>('session');

  /// Usuário atual é a demonstração (local)?
  bool _demo = false;

  Future<AppUser> _start(Map<String, Object?> res) async {
    final token = res['token'] as String;
    final user = (res['user'] as Map).cast<String, Object?>();
    api.token = token;
    await _session.record('current').put(await _database, {
      'token': token,
      'user': user,
    });
    _demo = false;
    return _toUser(user);
  }

  static AppUser _toUser(Map<String, Object?> u) => AppUser(
    id: u['id'] as String,
    name: u['name'] as String,
    email: u['email'] as String,
    isAdmin: (u['isAdmin'] as bool?) ?? false,
  );

  @override
  Future<AppUser?> restoreSession() async {
    final s = await _session.record('current').get(await _database);
    if (s == null) {
      final demo = await local.restoreSession();
      _demo = demo?.isDemo ?? false;
      return _demo ? demo : null;
    }
    api.token = s['token'] as String;
    try {
      final me = await api.get('me');
      final user = (me['user'] as Map).cast<String, Object?>();
      await _session.record('current').put(await _database, {
        ...s,
        'user': user,
      });
      return _toUser(user);
    } on OfflineException {
      // Sem internet: abre com a última conta (dados do cache local).
      return _toUser((s['user'] as Map).cast<String, Object?>());
    } on AuthException {
      await logout();
      return null;
    }
  }

  @override
  Future<bool> hasUsers() async {
    try {
      return (await api.get('auth/has-users'))['hasUsers'] == true;
    } on OfflineException {
      return true;
    }
  }

  @override
  Future<AppUser> register(String name, String email, String password) async =>
      _start(
        await api.post('auth/register', {
          'name': name,
          'email': email,
          'password': password,
        }),
      );

  @override
  Future<AppUser> login(String email, String password) async => _start(
    await api.post('auth/login', {'email': email, 'password': password}),
  );

  @override
  Future<AppUser> demoUser() async {
    await _clear();
    final u = await local.demoUser();
    _demo = true;
    return u;
  }

  Future<void> _clear() async {
    api.token = null;
    await _session.record('current').delete(await _database);
  }

  @override
  Future<void> logout() async {
    if (_demo) await local.logout();
    _demo = false;
    await _clear();
  }

  @override
  Future<void> deleteAccount(String userId) async {
    await api.delete('me');
    await _clear();
  }

  @override
  Future<void> changePassword(String current, String newPassword) async {
    final err = LocalAuthService.validatePassword(newPassword);
    if (err != null) throw AuthException(err);
    await api.post('me/password', {
      'current': current,
      'password': newPassword,
    });
  }

  @override
  Future<List<AppUser>> listUsers() async => [
    for (final u in (await api.get('users'))['users'] as List)
      _toUser((u as Map).cast<String, Object?>()),
  ];

  @override
  Future<AppUser> createUser(
    String name,
    String email,
    String password, {
    bool isAdmin = false,
  }) async => _toUser(
    ((await api.post('users', {
              'name': name,
              'email': email,
              'password': password,
              'isAdmin': isAdmin,
            }))['user']
            as Map)
        .cast<String, Object?>(),
  );

  @override
  Future<AppUser> updateUser(
    String id, {
    required String name,
    required String email,
    required bool isAdmin,
  }) async {
    final u = _toUser(
      ((await api.patch('users/$id', {
                'name': name,
                'email': email,
                'isAdmin': isAdmin,
              }))['user']
              as Map)
          .cast<String, Object?>(),
    );
    final s = await _session.record('current').get(await _database);
    if (s != null && (s['user'] as Map)['id'] == id) {
      await _session.record('current').put(await _database, {
        ...s,
        'user': {
          'id': u.id,
          'name': u.name,
          'email': u.email,
          'isAdmin': u.isAdmin,
        },
      });
    }
    return u;
  }

  @override
  Future<void> resetPassword(String id, String newPassword) async {
    final err = LocalAuthService.validatePassword(newPassword);
    if (err != null) throw AuthException(err);
    await api.post('users/$id/password', {'password': newPassword});
  }

  @override
  Future<void> deleteUser(String id) async => api.delete('users/$id');
}
