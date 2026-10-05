/// Fora da web a janela não está disponível; o app usa o ID manual.
bool get pluggyConnectSupported => false;

Future<String?> openPluggyConnect(String connectToken, {bool dark = false}) =>
    throw UnsupportedError('Janela Pluggy disponível só na versão web');
