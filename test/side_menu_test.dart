import 'package:financas_app/data/auth_service.dart';
import 'package:financas_app/state/auth_controller.dart';
import 'package:financas_app/ui/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Future<List<String>> pumpMenu(
    WidgetTester tester, {
    required bool expanded,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <String>[];
    var selected = 'home';
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthController(LocalAuthService()),
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Row(
                children: [
                  SideMenu(
                    selected: selected,
                    expanded: expanded,
                    onToggle: () {},
                    onSelect: (id) => setState(() {
                      picked.add(id);
                      selected = id;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('menu em seções: Mais sumiu e Categorias fica em Configurações', (
    tester,
  ) async {
    final picked = await pumpMenu(tester, expanded: true);
    for (final s in [
      'Lançamentos',
      'Contas e cartões',
      'Planejamento',
      'Configurações',
    ]) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('Mais'), findsNothing);
    expect(find.text('Transações'), findsOneWidget);
    // Só Lançamentos começa aberta.
    expect(find.text('Faturas'), findsNothing);
    expect(find.text('Categorias'), findsNothing);
    // Usuários só para administradores.
    await tester.tap(
      find.byKey(const ValueKey('side-menu-group-settings-group')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Categorias'), findsOneWidget);
    expect(find.text('Preferências'), findsOneWidget);
    expect(find.text('Usuários'), findsNothing);
    await tester.tap(find.text('Categorias'));
    expect(picked, ['categories']);
    // Recolher uma seção esconde os itens.
    await tester.tap(find.byKey(const ValueKey('side-menu-group-entries')));
    await tester.pumpAndSettle();
    expect(find.text('Transações'), findsNothing);
  });

  testWidgets('recolhido: tocar na seção abre a lista dos itens', (
    tester,
  ) async {
    final picked = await pumpMenu(tester, expanded: false);
    expect(find.text('Faturas'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('side-menu-group-wallet')));
    await tester.pumpAndSettle();
    expect(find.text('Faturas'), findsOneWidget);
    await tester.tap(find.text('Faturas'));
    await tester.pumpAndSettle();
    expect(picked, ['invoices']);
  });
}
