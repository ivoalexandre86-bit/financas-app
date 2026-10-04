import 'package:flutter/foundation.dart';

import '../data/auth_service.dart';

/// Estado de autenticação do app.
class AuthController extends ChangeNotifier {
  final AuthService service;
  AuthController(this.service);

  AppUser? user;

  /// Primeiro acesso no dispositivo: o cadastro aberto cria o administrador.
  bool canRegister = false;
  bool initializing = true;
  bool busy = false;
  String? error;

  Future<void> init() async {
    try {
      user = await service.restoreSession();
      canRegister = !await service.hasUsers();
    } catch (e) {
      error = 'Não foi possível restaurar a sessão';
    }
    initializing = false;
    notifyListeners();
  }

  Future<bool> _run(Future<AppUser> Function() op) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      user = await op();
      canRegister = false;
      return true;
    } on AuthException catch (e) {
      error = e.message;
      return false;
    } catch (e) {
      error = 'Erro inesperado: $e';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) =>
      _run(() => service.login(email, password));

  Future<bool> register(String name, String email, String password) =>
      _run(() => service.register(name, email, password));

  Future<bool> enterDemo() => _run(service.demoUser);

  bool get isAdmin => user?.isAdmin ?? false;

  Future<void> logout() async {
    await service.logout();
    user = null;
    error = null;
    canRegister = !await service.hasUsers();
    notifyListeners();
  }

  /// Lança [AuthException] se a conta não puder ser excluída (por exemplo,
  /// único administrador com outros usuários cadastrados).
  Future<void> deleteAccount() async {
    final u = user;
    if (u == null) return;
    await service.deleteAccount(u.id);
    user = null;
    canRegister = !await service.hasUsers();
    notifyListeners();
  }

  Future<void> changePassword(String current, String newPassword) =>
      service.changePassword(current, newPassword);

  // Gestão de usuários (somente administradores).

  Future<List<AppUser>> listUsers() => service.listUsers();

  Future<AppUser> createUser(
    String name,
    String email,
    String password, {
    bool isAdmin = false,
  }) => service.createUser(name, email, password, isAdmin: isAdmin);

  Future<AppUser> updateUser(
    String id, {
    required String name,
    required String email,
    required bool isAdmin,
  }) async {
    final u = await service.updateUser(
      id,
      name: name,
      email: email,
      isAdmin: isAdmin,
    );
    if (u.id == user?.id) {
      user = u;
      notifyListeners();
    }
    return u;
  }

  Future<void> resetPassword(String id, String newPassword) =>
      service.resetPassword(id, newPassword);

  Future<void> deleteUser(String id) => service.deleteUser(id);
}
