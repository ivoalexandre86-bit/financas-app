import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dates.dart';
import 'web_env.dart';

/// Fatura pedida pelo link do lembrete por e-mail
/// (`…/financas-app/?fatura=CARTAO&mes=AAAA-MM`). Fica guardada até o app
/// abrir com os dados carregados (mesmo que precise entrar antes).
abstract final class InvoiceLink {
  static ({String cardId, YearMonth month})? pending;
  static const _k = 'invoiceLink.pending';

  static ({String cardId, YearMonth month})? parse(Map<String, String> q) {
    final card = (q['fatura'] ?? '').trim();
    final mes = (q['mes'] ?? '').trim();
    if (card.isEmpty || !RegExp(r'^\d{4}-\d{2}$').hasMatch(mes)) return null;
    final m = int.parse(mes.substring(5));
    if (m < 1 || m > 12) return null;
    return (cardId: card, month: YearMonth.parse(mes));
  }

  static Future<void> init({Uri? entry}) async {
    final q =
        (entry ?? (kIsWeb ? Uri.base : null))?.queryParameters ??
        const <String, String>{};
    final fromLink = parse(q);
    if (fromLink != null) pending = fromLink;
    if (kIsWeb) removeQueryParams(const ['fatura', 'mes']);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (fromLink != null) {
        await prefs.setString(
          _k,
          '${fromLink.cardId}|${fromLink.month.year}-${fromLink.month.month.toString().padLeft(2, '0')}',
        );
      } else if (pending == null) {
        final saved = prefs.getString(_k)?.split('|');
        if (saved != null && saved.length == 2) {
          pending = parse({'fatura': saved[0], 'mes': saved[1]});
        }
      }
    } catch (_) {
      // Sem armazenamento local: vale só nesta abertura.
    }
  }

  /// Pega o pedido (uma vez) e esquece.
  static ({String cardId, YearMonth month})? take() {
    final p = pending;
    pending = null;
    SharedPreferences.getInstance().then((prefs) => prefs.remove(_k)).ignore();
    return p;
  }
}
