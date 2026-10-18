import 'package:url_launcher/url_launcher.dart';

/// Páginas públicas exigidas pelas lojas e pela LGPD (publicadas com o site).
abstract final class LegalLinks {
  static const _base = 'https://ivoalexandre86-bit.github.io/financas-app';
  static final privacy = Uri.parse('$_base/privacidade.html');
  static final terms = Uri.parse('$_base/termos.html');

  static Future<void> open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
