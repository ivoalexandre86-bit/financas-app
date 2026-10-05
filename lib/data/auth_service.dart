import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sembast/sembast.dart';

import '../core/ids.dart';
import 'db_factory.dart';

class AppUser {
  final String id;
  final String name;
  final String email;
  final bool isDemo;

  /// Administradores criam e gerenciam os demais usuários.
  final bool isAdmin;
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.isDemo = false,
    this.isAdmin = false,
  });
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Contrato de autenticação. A versão local abaixo guarda usuários no
/// dispositivo; na fase 3 será trocada por [RemoteAuthService] (JWT via API).
///
/// Cada usuário tem o próprio orçamento (banco isolado). O primeiro usuário
/// criado é o administrador; depois disso, só administradores criam contas.
abstract class AuthService {
  Future<AppUser?> restoreSession();

  /// Se ainda não há nenhum usuário real (primeiro acesso no dispositivo).
  Future<bool> hasUsers();

  /// Cadastro aberto: só permitido no primeiro acesso, e cria um admin.
  Future<AppUser> register(String name, String email, String password);
  Future<AppUser> login(String email, String password);
  Future<AppUser> demoUser();
  Future<void> logout();
  Future<void> deleteAccount(String userId);
  Future<void> changePassword(String current, String newPassword);

  // Gestão de usuários (somente administradores).
  Future<List<AppUser>> listUsers();
  Future<AppUser> createUser(
    String name,
    String email,
    String password, {
    bool isAdmin = false,
  });
  Future<AppUser> updateUser(
    String id, {
    required String name,
    required String email,
    required bool isAdmin,
  });
  Future<void> resetPassword(String id, String newPassword);
  Future<void> deleteUser(String id);
}

/// Autenticação local com senha protegida por PBKDF2-HMAC-SHA256 + salt
/// aleatório. A senha nunca é armazenada; a sessão é um token aleatório.
class LocalAuthService implements AuthService {
  static const _iterations = 20000;
  static const demoEmail = 'demo@exemplo.com.br';

  /// [open] e [deleteUserData] permitem testes com banco em memória.
  LocalAuthService({
    Future<Database> Function()? open,
    Future<void> Function(String userId)? deleteUserData,
  }) : _open = open ?? (() => openAppDatabase('financas_auth.db')),
       _deleteUserData =
           deleteUserData ??
           ((id) => deleteAppDatabase('financas_user_$id.db'));

  final Future<Database> Function() _open;
  final Future<void> Function(String userId) _deleteUserData;
  Future<Database>? _db;
  final _users = StoreRef<String, Map<String, Object?>>('users');
  final _session = StoreRef<String, Map<String, Object?>>('session');

  Future<Database> get db => _db ??= _open().then((d) async {
    await _ensureAdmin(d);
    return d;
  });

  /// Migração: bases criadas antes dos perfis não têm administrador. O
  /// usuário mais antigo passa a ser o administrador.
  static Future<void> _ensureAdmin(Database d) async {
    final real = await _realUsers(d);
    if (real.isEmpty || real.any((u) => u.value['isAdmin'] == true)) return;
    real.sort(
      (a, b) => ((a.value['createdAt'] as String?) ?? '').compareTo(
        (b.value['createdAt'] as String?) ?? '',
      ),
    );
    await _usersStore.record(real.first.key).update(d, {'isAdmin': true});
  }

  static final _usersStore = StoreRef<String, Map<String, Object?>>('users');

  static Future<List<RecordSnapshot<String, Map<String, Object?>>>> _realUsers(
    Database d,
  ) async => [
    for (final r in await _usersStore.find(d))
      if (r.value['isDemo'] != true) r,
  ];

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? validateEmail(String email) =>
      _emailRe.hasMatch(email.trim()) ? null : 'E-mail inválido';

  static String? validatePassword(String p) {
    if (p.length < 8) return 'A senha deve ter ao menos 8 caracteres';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
      return 'Use letras e números';
    }
    return null;
  }

  @override
  Future<AppUser?> restoreSession() async {
    final s = await _session.record('current').get(await db);
    if (s == null) return null;
    final expires = DateTime.tryParse(s['expiresAt'] as String? ?? '');
    if (expires == null || expires.isBefore(DateTime.now())) {
      await logout();
      return null;
    }
    final u = await _users.record(s['userId'] as String).get(await db);
    return u == null ? null : _toUser(u);
  }

  @override
  Future<bool> hasUsers() async => (await _realUsers(await db)).isNotEmpty;

  @override
  Future<AppUser> register(String name, String email, String password) async {
    if (await hasUsers()) {
      throw const AuthException(
        'Novas contas são criadas pelo administrador, em Usuários.',
      );
    }
    final u = await _insert(name, email, password, isAdmin: true);
    await _startSession(u.id);
    return u;
  }

  Future<AppUser> _insert(
    String name,
    String email,
    String password, {
    required bool isAdmin,
  }) async {
    final normalized = email.trim().toLowerCase();
    final emailErr = validateEmail(normalized);
    if (emailErr != null) throw AuthException(emailErr);
    final pwErr = validatePassword(password);
    if (pwErr != null) throw AuthException(pwErr);
    if (name.trim().isEmpty) throw const AuthException('Informe o nome');
    final d = await db;
    await _checkEmailFree(d, normalized);
    final id = newId('u_');
    final record = {
      'id': id,
      'name': name.trim(),
      'email': normalized,
      ..._passwordFields(password),
      'isDemo': false,
      'isAdmin': isAdmin,
      'createdAt': DateTime.now().toIso8601String(),
    };
    await _users.record(id).put(d, record);
    return _toUser(record);
  }

  Future<void> _checkEmailFree(
    Database d,
    String email, {
    String? except,
  }) async {
    final existing = await _users.findFirst(
      d,
      finder: Finder(filter: Filter.equals('email', email)),
    );
    if (existing != null && existing.key != except) {
      throw const AuthException('Já existe uma conta com este e-mail');
    }
  }

  static Map<String, Object?> _passwordFields(String password) {
    final salt = _randomBytes(16);
    return {
      'salt': base64Encode(salt),
      'iterations': _iterations,
      'hash': base64Encode(_pbkdf2(password, salt, _iterations)),
    };
  }

  static bool _checkPassword(Map<String, Object?> u, String password) {
    if (u['hash'] == null) return false;
    final hash = _pbkdf2(
      password,
      base64Decode(u['salt'] as String),
      u['iterations'] as int,
    );
    return _constantTimeEquals(hash, base64Decode(u['hash'] as String));
  }

  @override
  Future<AppUser> login(String email, String password) async {
    final d = await db;
    final rec = await _users.findFirst(
      d,
      finder: Finder(
        filter: Filter.equals('email', email.trim().toLowerCase()),
      ),
    );
    const invalid = AuthException('E-mail ou senha incorretos');
    if (rec == null || rec.value['isDemo'] == true) throw invalid;
    final u = rec.value;
    if (!_checkPassword(u, password)) throw invalid;
    await _startSession(u['id'] as String);
    return _toUser(u);
  }

  /// Confere e-mail e senha de uma conta deste aparelho sem entrar nela.
  /// Usado para levar os dados do aparelho para a nuvem.
  Future<AppUser> verify(String email, String password) async {
    final rec = await _users.findFirst(
      await db,
      finder: Finder(
        filter: Filter.equals('email', email.trim().toLowerCase()),
      ),
    );
    if (rec == null ||
        rec.value['isDemo'] == true ||
        !_checkPassword(rec.value, password)) {
      throw const AuthException('E-mail ou senha incorretos');
    }
    return _toUser(rec.value);
  }

  /// Usuário de demonstração, separado dos usuários reais (dados de exemplo
  /// ficam em um banco próprio).
  @override
  Future<AppUser> demoUser() async {
    final d = await db;
    const id = 'demo';
    var u = await _users.record(id).get(d);
    if (u == null) {
      u = {
        'id': id,
        'name': 'Conta de demonstração',
        'email': demoEmail,
        'isDemo': true,
        'createdAt': DateTime.now().toIso8601String(),
      };
      await _users.record(id).put(d, u);
    }
    await _startSession(id);
    return _toUser(u);
  }

  @override
  Future<void> logout() async => _session.record('current').delete(await db);

  @override
  Future<void> deleteAccount(String userId) async {
    final d = await db;
    await _checkNotLastAdmin(d, userId);
    await _users.record(userId).delete(d);
    await logout();
  }

  @override
  Future<void> changePassword(String current, String newPassword) async {
    final d = await db;
    final me = await _currentRecord(d);
    if (me == null || me['isDemo'] == true) {
      throw const AuthException('Sessão inválida');
    }
    if (!_checkPassword(me, current)) {
      throw const AuthException('Senha atual incorreta');
    }
    final pwErr = validatePassword(newPassword);
    if (pwErr != null) throw AuthException(pwErr);
    await _users
        .record(me['id'] as String)
        .update(d, _passwordFields(newPassword));
  }

  @override
  Future<List<AppUser>> listUsers() async {
    final d = await _requireAdmin();
    final list = [for (final r in await _realUsers(d)) _toUser(r.value)];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<AppUser> createUser(
    String name,
    String email,
    String password, {
    bool isAdmin = false,
  }) async {
    await _requireAdmin();
    return _insert(name, email, password, isAdmin: isAdmin);
  }

  @override
  Future<AppUser> updateUser(
    String id, {
    required String name,
    required String email,
    required bool isAdmin,
  }) async {
    final d = await _requireAdmin();
    final rec = await _users.record(id).get(d);
    if (rec == null || rec['isDemo'] == true) {
      throw const AuthException('Usuário não encontrado');
    }
    if (name.trim().isEmpty) throw const AuthException('Informe o nome');
    final normalized = email.trim().toLowerCase();
    final emailErr = validateEmail(normalized);
    if (emailErr != null) throw AuthException(emailErr);
    await _checkEmailFree(d, normalized, except: id);
    if (!isAdmin) await _checkNotLastAdmin(d, id);
    final updated = await _users.record(id).update(d, {
      'name': name.trim(),
      'email': normalized,
      'isAdmin': isAdmin,
    });
    return _toUser(updated!);
  }

  @override
  Future<void> resetPassword(String id, String newPassword) async {
    final d = await _requireAdmin();
    final pwErr = validatePassword(newPassword);
    if (pwErr != null) throw AuthException(pwErr);
    final rec = await _users.record(id).get(d);
    if (rec == null || rec['isDemo'] == true) {
      throw const AuthException('Usuário não encontrado');
    }
    await _users.record(id).update(d, _passwordFields(newPassword));
  }

  @override
  Future<void> deleteUser(String id) async {
    final d = await _requireAdmin();
    final me = await _currentRecord(d);
    if (me?['id'] == id) {
      throw const AuthException(
        'Para excluir a própria conta, use Configurações.',
      );
    }
    await _checkNotLastAdmin(d, id);
    await _users.record(id).delete(d);
    await _deleteUserData(id);
  }

  /// Impede que o dispositivo fique sem administrador enquanto houver
  /// outros usuários.
  Future<void> _checkNotLastAdmin(Database d, String id) async {
    final real = await _realUsers(d);
    final admins = real.where((r) => r.value['isAdmin'] == true).toList();
    if (admins.length == 1 && admins.first.key == id && real.length > 1) {
      throw const AuthException(
        'Este é o único administrador. Torne outro usuário administrador antes.',
      );
    }
  }

  Future<Map<String, Object?>?> _currentRecord(Database d) async {
    final s = await _session.record('current').get(d);
    if (s == null) return null;
    return _users.record(s['userId'] as String).get(d);
  }

  Future<Database> _requireAdmin() async {
    final d = await db;
    final me = await _currentRecord(d);
    if (me == null || me['isAdmin'] != true) {
      throw const AuthException('Somente administradores gerenciam usuários');
    }
    return d;
  }

  Future<void> _startSession(String userId) async {
    await _session.record('current').put(await db, {
      'userId': userId,
      'token': base64UrlEncode(_randomBytes(32)),
      'expiresAt': DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String(),
    });
  }

  AppUser _toUser(Map<String, Object?> u) => AppUser(
    id: u['id'] as String,
    name: u['name'] as String,
    email: u['email'] as String,
    isDemo: (u['isDemo'] as bool?) ?? false,
    isAdmin: (u['isAdmin'] as bool?) ?? false,
  );

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018), 32 bytes de saída.
  static List<int> _pbkdf2(String password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final block = [...salt, 0, 0, 0, 1];
    var u = hmac.convert(block).bytes;
    final out = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
