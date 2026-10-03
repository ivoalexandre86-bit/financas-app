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
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.isDemo = false,
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
abstract class AuthService {
  Future<AppUser?> restoreSession();
  Future<AppUser> register(String name, String email, String password);
  Future<AppUser> login(String email, String password);
  Future<AppUser> demoUser();
  Future<void> logout();
  Future<void> deleteAccount(String userId);
}

/// Autenticação local com senha protegida por PBKDF2-HMAC-SHA256 + salt
/// aleatório. A senha nunca é armazenada; a sessão é um token aleatório.
class LocalAuthService implements AuthService {
  static const _iterations = 20000;
  static const demoEmail = 'demo@exemplo.com.br';

  Database? _db;
  final _users = StoreRef<String, Map<String, Object?>>('users');
  final _session = StoreRef<String, Map<String, Object?>>('session');

  Future<Database> get db async =>
      _db ??= await openAppDatabase('financas_auth.db');

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
  Future<AppUser> register(String name, String email, String password) async {
    final normalized = email.trim().toLowerCase();
    final emailErr = validateEmail(normalized);
    if (emailErr != null) throw AuthException(emailErr);
    final pwErr = validatePassword(password);
    if (pwErr != null) throw AuthException(pwErr);
    if (name.trim().isEmpty) throw const AuthException('Informe seu nome');
    final d = await db;
    final existing = await _users.findFirst(
      d,
      finder: Finder(filter: Filter.equals('email', normalized)),
    );
    if (existing != null) {
      throw const AuthException('Já existe uma conta com este e-mail');
    }
    final salt = _randomBytes(16);
    final id = newId('u_');
    final record = {
      'id': id,
      'name': name.trim(),
      'email': normalized,
      'salt': base64Encode(salt),
      'iterations': _iterations,
      'hash': base64Encode(_pbkdf2(password, salt, _iterations)),
      'isDemo': false,
      'createdAt': DateTime.now().toIso8601String(),
    };
    await _users.record(id).put(d, record);
    await _startSession(id);
    return _toUser(record);
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
    final hash = _pbkdf2(
      password,
      base64Decode(u['salt'] as String),
      u['iterations'] as int,
    );
    if (!_constantTimeEquals(hash, base64Decode(u['hash'] as String))) {
      throw invalid;
    }
    await _startSession(u['id'] as String);
    return _toUser(u);
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
    await _users.record(userId).delete(d);
    await logout();
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
