import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth_service.dart';

/// Sem conexão com o servidor (rede fora do ar, servidor indisponível…).
class OfflineException implements Exception {
  const OfflineException();
  @override
  String toString() =>
      'Sem conexão com o servidor. Verifique a internet e tente de novo.';
}

/// Cliente HTTP da API. Erros de negócio viram [AuthException] com a
/// mensagem do servidor; falhas de rede viram [OfflineException].
class ApiClient {
  final Uri base;
  final http.Client _http;

  /// Token de acesso atual (JWT).
  String? token;

  /// Chamado quando o servidor recusa o token (sessão expirada).
  void Function()? onUnauthorized;

  ApiClient(String baseUrl, {http.Client? client})
    : base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
      _http = client ?? http.Client();

  Future<Map<String, Object?>> get(String path) => _send('GET', path);
  Future<Map<String, Object?>> post(String path, [Object? body]) =>
      _send('POST', path, body);
  Future<Map<String, Object?>> patch(String path, Object? body) =>
      _send('PATCH', path, body);
  Future<Map<String, Object?>> delete(String path) => _send('DELETE', path);

  Future<Map<String, Object?>> _send(
    String method,
    String path, [
    Object? body,
  ]) async {
    final req = http.Request(method, base.resolve(path))
      ..headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 30)),
      );
    } on TimeoutException {
      throw const OfflineException();
    } on http.ClientException {
      throw const OfflineException();
    }
    Map<String, Object?> json = const {};
    if (res.body.isNotEmpty) {
      try {
        json = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)
            .cast<String, Object?>();
      } catch (_) {
        // Resposta fora do padrão (ex.: página de erro do provedor).
        if (res.statusCode >= 500) throw const OfflineException();
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    if (res.statusCode >= 500) throw const OfflineException();
    throw AuthException(
      (json['error'] as String?) ?? 'Erro ${res.statusCode} no servidor',
    );
  }
}
