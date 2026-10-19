import 'package:financas_app/data/auth_service.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/auth_controller.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/app_shell.dart';
import 'package:financas_app/ui/menu_layout.dart';
import 'package:financas_app/ui/screens/settings/menu_editor_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  group('MenuLayout.resolve', () {
    const defaults = [
      MenuSection('a', ['x', 'y']),
      MenuSection('b', ['z']),
    ];

    test('sem organização salva usa o padrão', () {
      expect(MenuLayout.resolve(defaults, null), same(defaults));
    });

    test('aplica ordem, nomes e seções do usuário', () {
      final r = MenuLayout.resolve(defaults, [
        {
          'id': 'b',
          'label': 'Minha',
          'items': ['y', 'z'],
        },
        {
          'id': 'custom-1',
          'label': 'Favoritos',
          'items': ['x'],
        },
        {'id': 'a', 'items': []},
      ]);
      expect([for (final s in r) s.id], ['b', 'custom-1', 'a']);
      expect(r[0].label, 'Minha');
      expect(r[0].items, ['y', 'z']);
      expect(r[1].items, ['x']);
      expect(r[2].items, isEmpty);
    });

    test('ignora itens desconhecidos/repetidos e repõe os que faltam', () {
      final r = MenuLayout.resolve(defaults, [
        {
          'id': 'b',
          'items': ['z', 'old', 'z', 'x'],
        },
        {'id': 'outra', 'items': []},
      ]);
      // 'y' (novo no app) volta para a seção padrão, que é recriada no fim.
      expect([for (final s in r) s.id], ['b', 'a']);
      expect(r[0].items, ['z', 'x']);
      expect(r[1].items, ['y']);
    });
  });

  Future<FinanceController> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(fc.load);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthController(LocalAuthService()),
          ),
          ChangeNotifierProvider.value(value: fc),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MenuEditorScreen(),
        ),
      ),
    );
    return fc;
  }

  List<MenuSection> saved(FinanceController fc) =>
      MenuLayout.resolve(defaultMenuSections, fc.data.settings.menuLayout);

  testWidgets('move item para outra seção e muda a ordem das seções', (
    tester,
  ) async {
    final fc = await pumpEditor(tester);
    expect(find.text('Organizar menu'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu-move-invoices')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contas e cartões').last);
    await tester.pumpAndSettle();
    var s = saved(fc);
    expect(s[0].items, isNot(contains('invoices')));
    expect(s[1].items.last, 'invoices');

    await tester.tap(find.byKey(const ValueKey('menu-section-up-planning')));
    await tester.pumpAndSettle();
    s = saved(fc);
    expect(
      [for (final x in s) x.id],
      ['entries', 'planning', 'wallet', 'settings-group'],
    );

    // Arrastar Faturas para o topo de Lançamentos.
    final handle = find.descendant(
      of: find.byKey(const ValueKey('menu-edit-item-invoices')),
      matching: find.byIcon(Icons.drag_handle),
    );
    final target = tester.getCenter(
      find.byKey(const ValueKey('menu-edit-item-transactions')),
    );
    final g = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 1; i <= 20; i++) {
      await g.moveTo(
        Offset.lerp(
          tester.getCenter(handle),
          target - const Offset(0, 20),
          i / 20,
        )!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    s = saved(fc);
    expect(s[0].items.first, 'invoices');
    expect(s[2].items, isNot(contains('invoices')));
  });

  testWidgets('setas sobem e descem a tela, passando entre seções', (
    tester,
  ) async {
    final fc = await pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('menu-item-up-recurring')));
    await tester.pumpAndSettle();
    expect(saved(fc)[0].items.take(2), ['recurring', 'transactions']);

    // Primeira tela da primeira seção não sobe.
    final up = tester.widget<IconButton>(
      find.byKey(const ValueKey('menu-item-up-recurring')),
    );
    expect(up.onPressed, isNull);

    // Última de Lançamentos desce para o topo de Contas e cartões.
    final lastId = saved(fc)[0].items.last;
    await tester.tap(find.byKey(ValueKey('menu-item-down-$lastId')));
    await tester.pumpAndSettle();
    expect(saved(fc)[0].items, isNot(contains(lastId)));
    expect(saved(fc)[1].items.first, lastId);

    // E sobe de volta.
    await tester.tap(find.byKey(ValueKey('menu-item-up-$lastId')));
    await tester.pumpAndSettle();
    expect(saved(fc)[0].items.last, lastId);
  });

  testWidgets('cria, renomeia, exclui seção e volta ao padrão', (tester) async {
    final fc = await pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('menu-add-section')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('menu-section-name')),
      'Favoritos',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    var s = saved(fc);
    final custom = s.last;
    expect(custom.isCustom, isTrue);
    expect(custom.label, 'Favoritos');

    await tester.tap(find.byKey(const ValueKey('menu-move-projection')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favoritos').last);
    await tester.pumpAndSettle();
    expect(saved(fc).last.items, ['projection']);

    await tester.tap(find.byKey(const ValueKey('menu-section-rename-wallet')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('menu-section-name')),
      'Bancos',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Bancos'), findsOneWidget);

    // Excluir a seção devolve Projeção para Planejamento.
    await tester.tap(find.byKey(ValueKey('menu-section-delete-${custom.id}')));
    await tester.pumpAndSettle();
    s = saved(fc);
    expect(s.any((x) => x.isCustom), isFalse);
    expect(
      s.firstWhere((x) => x.id == 'planning').items,
      contains('projection'),
    );

    await tester.tap(find.byKey(const ValueKey('menu-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voltar ao padrão').last);
    await tester.pumpAndSettle();
    expect(fc.data.settings.menuLayout, isNull);
    expect(find.text('Contas e cartões'), findsOneWidget);
  });

  testWidgets('menu lateral segue a organização salva', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final layout = MenuLayout.toJson([
      const MenuSection('planning', [
        'invoices',
        'projection',
      ], label: 'Planejar'),
      const MenuSection('entries', [
        'transactions',
        'accounts',
        'cards',
        'networth',
      ]),
      const MenuSection('wallet', []),
    ]);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthController(LocalAuthService()),
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SideMenu(
                  selected: 'home',
                  expanded: true,
                  onToggle: () {},
                  onSelect: (_) {},
                  layout: layout,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // A primeira seção (agora Planejar) começa aberta, com Faturas.
    expect(find.text('Planejar'), findsOneWidget);
    expect(find.text('Faturas'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Planejar')).dy,
      lessThan(tester.getTopLeft(find.text('Lançamentos')).dy),
    );
    // Seção vazia some do menu.
    expect(find.text('Contas e cartões'), findsNothing);
    // Itens que o usuário não posicionou voltam para a seção padrão.
    expect(find.text('Configurações'), findsOneWidget);
  });

  test('menuLayout vai e volta do JSON das preferências', () {
    final s = const AppSettings(
      menuLayout: [
        {
          'id': 'entries',
          'items': ['transactions'],
        },
      ],
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back.menuLayout, s.menuLayout);
    expect(back.copyWith(resetMenuLayout: true).menuLayout, isNull);
  });
}
