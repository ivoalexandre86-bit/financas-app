import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud/api_client.dart';

/// Medição do funil e origem do usuário (canal e convite).
///
/// O aparelho ganha um id aleatório na 1ª abertura (evento `install`). O
/// canal vem do link que trouxe a pessoa (`?utm_source=instagram`) e o
/// convite de `?ref=CODIGO`; os dois vão junto no cadastro. Os demais
/// eventos (1º orçamento, 1ª simulação, uso do dia…) só são enviados com a
/// conta na nuvem; o servidor ignora repetidos.
abstract final class Growth {
  static ApiClient? _api;
  static String? deviceId;
  static String? channel;
  static String? ref;

  static const _kDevice = 'growth.device';
  static const _kChannel = 'growth.channel';
  static const _kRef = 'growth.ref';
  static const _kInstallSent = 'growth.installSent';

  /// Liga o envio de eventos à API (conta na nuvem).
  static void attach(ApiClient api) => _api = api;

  /// Lê (ou cria) o id do aparelho e guarda o canal/convite do link de
  /// entrada. Nunca falha: sem armazenamento, segue sem medir.
  static Future<void> init({Uri? entry}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      deviceId = prefs.getString(_kDevice);
      if (deviceId == null) {
        deviceId = _newId();
        await prefs.setString(_kDevice, deviceId!);
      }
      final q =
          (entry ?? (kIsWeb ? Uri.base : null))?.queryParameters ??
          const <String, String>{};
      final src = (q['utm_source'] ?? q['canal'] ?? '').trim();
      final code = (q['ref'] ?? q['convite'] ?? '').trim().toUpperCase();
      // Primeiro toque: o canal que trouxe a pessoa não é trocado depois.
      if (src.isNotEmpty && prefs.getString(_kChannel) == null) {
        await prefs.setString(_kChannel, src);
      }
      if (code.isNotEmpty) await prefs.setString(_kRef, code);
      channel = prefs.getString(_kChannel) ?? _platformChannel();
      ref = prefs.getString(_kRef);
      if (prefs.getBool(_kInstallSent) != true && _api != null) {
        final ok = await _post('install', const {}, anonymous: true);
        if (ok) await prefs.setBool(_kInstallSent, true);
      }
    } catch (_) {
      // Sem armazenamento local (ex.: navegação privada): não mede.
    }
  }

  /// Canal padrão quando o link não diz: a loja de onde veio o app.
  static String? _platformChannel() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'google-play',
      TargetPlatform.iOS => 'app-store',
      _ => null,
    };
  }

  static String _newId() {
    final r = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Dados que acompanham o cadastro.
  static Map<String, Object?> signupExtras() => {
    if (channel != null) 'channel': channel,
    if (ref != null) 'ref': ref,
    if (deviceId != null) 'deviceId': deviceId,
  };

  /// Convite usado no cadastro: não vale de novo para outra conta.
  static Future<void> clearRef() async {
    ref = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kRef);
    } catch (_) {}
  }

  /// Registra um evento do funil sem esperar nem falhar.
  static void track(String name, [Map<String, Object?> props = const {}]) {
    if (_api?.token == null) return;
    unawaited(_post(name, props));
  }

  static Future<bool> _post(
    String name,
    Map<String, Object?> props, {
    bool anonymous = false,
  }) async {
    final api = _api;
    if (api == null) return false;
    try {
      final body = {
        'name': name,
        if (deviceId != null) 'deviceId': deviceId,
        if (anonymous && channel != null) 'channel': channel,
        if (props.isNotEmpty) 'props': props,
      };
      await api.post('events', body, const Duration(seconds: 10));
      return true;
    } catch (_) {
      return false;
    }
  }
}
