import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Código do convite pelo WhatsApp que abriu o app
/// (`…/financas-app/?cadastro=CODIGO`). Fica guardado até o cadastro, para
/// valer mesmo se a página recarregar.
abstract final class SignupInvite {
  static String? token;
  static const _k = 'signupInvite.token';

  static Future<void> init({Uri? entry}) async {
    final q =
        (entry ?? (kIsWeb ? Uri.base : null))?.queryParameters ??
        const <String, String>{};
    final fromLink = (q['cadastro'] ?? '').trim();
    if (fromLink.isNotEmpty) token = fromLink;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (fromLink.isNotEmpty) {
        await prefs.setString(_k, fromLink);
      } else {
        token ??= prefs.getString(_k);
      }
    } catch (_) {
      // Sem armazenamento local: vale só nesta abertura.
    }
  }

  /// Convite usado (ou inválido): não aparece de novo.
  static Future<void> clear() async {
    token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_k);
    } catch (_) {}
  }
}
