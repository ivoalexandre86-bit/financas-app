import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/auth_service.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/auth_controller.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/categories/categories_screen.dart';
import 'package:financas_app/ui/screens/projects/projects_screen.dart';
import 'package:financas_app/ui/screens/simulations/simulations_screen.dart';
import 'package:financas_app/ui/screens/users/users_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

class _FakeAuth extends Fake implements AuthService {
  @override
  Future<List<AppUser>> listUsers() async => const [
    AppUser(id: 'u1', name: 'Ana', email: 'ana@x.com', isAdmin: true),
    AppUser(id: 'u2', name: 'Bruno', email: 'bruno@x.com'),
  ];
}

void main() {
  Future<FinanceController> setup(WidgetTester tester) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(() async {
      await fc.load();
      await fc.saveCategory(
        FinCategory(id: 'casa', name: 'Casa', kind: CategoryKind.expense),
      );
      await fc.saveCategory(
        FinCategory(
          id: 'luz',
          name: 'Luz',
          kind: CategoryKind.expense,
          parentId: 'casa',
        ),
      );
      await fc.saveProject(
        Project(id: 'viagem', name: 'Viagem', budget: const Money(500000)),
      );
      await fc.createSimulation(
        name: 'Carro novo',
        from: YearMonth(2026, 1),
        to: YearMonth(2026, 12),
      );
    });
    return fc;
  }

  Widget app(FinanceController fc, Widget home) => ChangeNotifierProvider(
    create: (_) => AuthController(_FakeAuth()),
    child: ChangeNotifierProvider.value(
      value: fc,
      child: MaterialApp(theme: AppTheme.dark(), home: home),
    ),
  );

  Future<void> wide(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('categorias: alterna para grade e lembra a escolha', (
    tester,
  ) async {
    final fc = await setup(tester);
    await wide(tester);
    await tester.pumpWidget(app(fc, const CategoriesScreen()));
    await tester.pump();
    expect(find.byKey(const ValueKey('categories-row-casa')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('categories-view-grid')));
    await tester.pump();
    expect(find.byKey(const ValueKey('categories-row-casa')), findsOneWidget);
    expect(find.byKey(const ValueKey('categories-row-luz')), findsOneWidget);
    expect(find.byKey(const ValueKey('categories-footer')), findsOneWidget);
    expect(fc.gridFilter('categories'), {'view': 'grid'});
    // Ordenar por lançamentos e voltar não quebra.
    await tester.tap(find.byKey(const ValueKey('categories-sort-uses')));
    await tester.pump();
    // Celular: linhas compactas.
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pump();
    expect(find.byKey(const ValueKey('categories-row-luz')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('projetos: grade com totais', (tester) async {
    final fc = await setup(tester);
    await wide(tester);
    await tester.pumpWidget(app(fc, const ProjectsScreen()));
    await tester.pump();
    expect(find.byType(ProjectCard), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('projects-view-grid')));
    await tester.pump();
    expect(find.byType(ProjectCard), findsNothing);
    expect(find.byKey(const ValueKey('projects-row-viagem')), findsOneWidget);
    expect(find.text('Total · 1 projeto'), findsOneWidget);
    expect(fc.gridFilter('projects'), {'view': 'grid'});
    // Reabrir mantém a grade.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(fc, const ProjectsScreen()));
    await tester.pump();
    expect(find.byKey(const ValueKey('projects-row-viagem')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('simulações: grade de cenários com seleção', (tester) async {
    final fc = await setup(tester);
    await wide(tester);
    await tester.pumpWidget(app(fc, const SimulationsScreen()));
    await tester.pump();
    final id = fc.simulations.single.id;
    expect(find.byKey(ValueKey('simulations-row-$id')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('simulations-view-grid')));
    await tester.pump();
    expect(find.byKey(ValueKey('simulations-row-$id')), findsOneWidget);
    expect(find.text('Total · 1 simulação'), findsOneWidget);
    expect(fc.gridFilter('simulations'), {'view': 'grid'});
    await tester.tap(find.byKey(ValueKey('simulations-select-$id')));
    await tester.pump();
    expect(find.byKey(const ValueKey('sim-compare-selected')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('usuários: alterna para grade', (tester) async {
    final fc = await setup(tester);
    await wide(tester);
    await tester.pumpWidget(app(fc, const UsersScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('user-ana@x.com')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('users-view-grid')));
    await tester.pump();
    expect(find.byKey(const ValueKey('user-ana@x.com')), findsNothing);
    expect(find.byKey(const ValueKey('users-row-ana@x.com')), findsOneWidget);
    expect(find.byKey(const ValueKey('users-row-bruno@x.com')), findsOneWidget);
    expect(find.text('1 administrador'), findsOneWidget);
    expect(fc.gridFilter('users'), {'view': 'grid'});
    expect(tester.takeException(), isNull);
  });
}
