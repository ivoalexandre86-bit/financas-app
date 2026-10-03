import 'package:flutter/foundation.dart';

import '../data/auth_service.dart';

/// Estado de autenticação do app.
class AuthController extends ChangeNotifier {
  final AuthService service;
  AuthController(this.service);

  AppUser? user;
  bool initializing = true;
  bool busy = false;
  String? error;

  Future<void> init() async {
    try {
      user = await service.restoreSession();
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

  Future<void> logout() async {
    await service.logout();
    user = null;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final u = user;
    if (u == null) return;
    await service.deleteAccount(u.id);
    user = null;
    notifyListeners();
  }
}
