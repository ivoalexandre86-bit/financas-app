import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Cópia local do SDK oficial (pluggy-connect-sdk), servida junto com o app.
const _sdkUrl = 'pluggy-connect.js';

bool get pluggyConnectSupported => true;

Future<void>? _loading;

/// Carrega o script da Pluggy uma única vez.
Future<void> _loadSdk() => _loading ??= () {
  final done = Completer<void>();
  final doc = globalContext['document'] as JSObject;
  final script = doc.callMethod<JSObject>('createElement'.toJS, 'script'.toJS);
  script['src'] = _sdkUrl.toJS;
  script['onload'] = ((JSAny? _) => done.complete()).toJS;
  script['onerror'] = ((JSAny? _) {
    _loading = null;
    done.completeError(
      StateError(
        'Não foi possível abrir a janela da Pluggy. Verifique a internet.',
      ),
    );
  }).toJS;
  (doc['head'] as JSObject).callMethod('appendChild'.toJS, script);
  return done.future;
}();

/// Abre a janela e devolve o ID da conexão criada, ou nulo se o usuário
/// fechar sem conectar.
Future<String?> openPluggyConnect(
  String connectToken, {
  bool dark = false,
}) async {
  await _loadSdk();
  final result = Completer<String?>();
  final opts = JSObject()
    ..['connectToken'] = connectToken.toJS
    ..['includeSandbox'] = false.toJS
    ..['language'] = 'pt'.toJS
    ..['theme'] = (dark ? 'dark' : 'light').toJS
    ..['onSuccess'] = ((JSObject data) {
      final item = data['item'] as JSObject?;
      final id = (item?['id'] as JSString?)?.toDart;
      if (!result.isCompleted) result.complete(id);
    }).toJS
    ..['onError'] = ((JSObject err) {
      final msg = (err['message'] as JSString?)?.toDart;
      if (!result.isCompleted) {
        result.completeError(StateError(msg ?? 'A conexão não foi concluída.'));
      }
    }).toJS
    ..['onClose'] = (() {
      if (!result.isCompleted) result.complete(null);
    }).toJS;
  final ctor = globalContext['PluggyConnect'] as JSFunction;
  final widget = ctor.callAsConstructor<JSObject>(opts);
  await widget.callMethod<JSPromise>('init'.toJS).toDart;
  return result.future;
}
