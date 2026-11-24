import 'package:flutter/widgets.dart';

/// Lugar na barra de título de uma tela "mãe" (Movimentações) onde a tela
/// embutida coloca os próprios botões (busca, modo de exibição, Filtros…).
/// Assim o botão de filtros fica sempre no canto superior direito, mesmo
/// nas telas que aparecem dentro de outra.
class HeaderActionsScope extends InheritedWidget {
  final ValueNotifier<List<Widget>> slot;
  const HeaderActionsScope({
    super.key,
    required this.slot,
    required super.child,
  });

  static HeaderActionsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeaderActionsScope>();

  /// Publica [actions] na barra da tela mãe, se houver uma. Retorna falso
  /// quando a tela não está embutida (ela mostra os botões por conta
  /// própria).
  static bool publish(BuildContext context, List<Widget> actions) {
    final scope = maybeOf(context);
    if (scope == null) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scope.slot.value = actions;
    });
    return true;
  }

  @override
  bool updateShouldNotify(HeaderActionsScope oldWidget) =>
      slot != oldWidget.slot;
}
