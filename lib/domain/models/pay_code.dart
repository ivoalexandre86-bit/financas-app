/// Tipos de código para pagar uma conta.
enum PayCodeKind { boleto, pix }

/// Reconhece a linha digitável (boleto bancário, 47 dígitos, ou de
/// arrecadação, 48 começando com 8) ou o Pix copia e cola (BR Code).
/// A conferência completa dos dígitos fica no servidor.
PayCodeKind? payCodeKind(String text) {
  final t = text.trim();
  if (t.replaceAll(RegExp(r'\s'), '').startsWith('000201')) {
    return PayCodeKind.pix;
  }
  if (RegExp(r'[^\d\s.\-]').hasMatch(t)) return null;
  final digits = t.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 47) return PayCodeKind.boleto;
  if (digits.length == 48 && digits.startsWith('8')) return PayCodeKind.boleto;
  return null;
}
