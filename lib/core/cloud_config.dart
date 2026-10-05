/// Endereço da API na nuvem, definido na compilação:
/// `flutter build web --dart-define=API_URL=https://...`.
///
/// Sem ele, o app funciona só no aparelho (usuários e dados locais).
class CloudConfig {
  CloudConfig._();

  static const apiUrl = String.fromEnvironment('API_URL');
  static bool get enabled => apiUrl.isNotEmpty;
}
