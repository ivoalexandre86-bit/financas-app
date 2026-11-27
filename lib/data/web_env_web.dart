import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Fuso horário IANA do navegador (Intl.DateTimeFormat().resolvedOptions()).
String? browserTimeZone() {
  try {
    final intl = globalContext['Intl'] as JSObject;
    final ctor = intl['DateTimeFormat'] as JSFunction;
    final fmt = ctor.callAsConstructor<JSObject>();
    final opts = fmt.callMethod<JSObject>('resolvedOptions'.toJS);
    final tz = (opts['timeZone'] as JSString?)?.toDart;
    return (tz == null || tz.isEmpty) ? null : tz;
  } catch (_) {
    return null;
  }
}

/// Tira [names] da barra de endereço sem recarregar a página.
void removeQueryParams(List<String> names) {
  try {
    final uri = Uri.base;
    if (!names.any(uri.queryParameters.containsKey)) return;
    final q = Map.of(uri.queryParameters)
      ..removeWhere((k, _) => names.contains(k));
    final next = uri.replace(queryParameters: q.isEmpty ? null : q);
    var url = next.toString();
    if (q.isEmpty) url = url.replaceFirst('?', '');
    final history = globalContext['history'] as JSObject;
    history.callMethod('replaceState'.toJS, null, ''.toJS, url.toJS);
  } catch (_) {}
}
