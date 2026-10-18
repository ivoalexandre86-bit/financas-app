import 'package:financas_app/core/dates.dart';
import 'package:financas_app/data/auth_service.dart';
import 'package:financas_app/domain/engine/projection_filter.dart';
import 'package:financas_app/state/auth_controller.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/import/expense_import_screen.dart';
import 'package:financas_app/ui/screens/open_finance/open_finance_screen.dart';
import 'package:financas_app/ui/screens/projection/projection_screen.dart';
import 'package:financas_app/ui/screens/subscription/subscription_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  final now = DateTime.now();
  final later = now.add(const Duration(days: 10, hours: 2));
  final before = now.subtract(const Duration(days: 40));

  test('acesso vindo do servidor', () {
    final a = Access.fromJson({
      'status': 'trial',
      'plan': 'premium',
      'trialEndsAt': later.toUtc().toIso8601String(),
      'paidUntil': null,
      'premium': true,
    })!;
    expect(a.trial, isTrue);
    expect(a.expired, isFalse);
    expect(a.isPremium, isTrue);
    expect(a.trialDaysLeft(now), 10);
    expect(
      accessSummary(a),
      startsWith('Teste do Premium: faltam 10 dias (até '),
    );
    expect(Access.fromJson(null), isNull);
  });

  test('plano lido do servidor ou deduzido (servidor antigo)', () {
    String plan(Map<String, Object?> j) => Access.fromJson(j)!.plan;
    expect(plan({'status': 'expired', 'plan': 'gratis'}), 'gratis');
    expect(plan({'status': 'active', 'plan': 'basico'}), 'basico');
    // Sem `plan`: vencido → Grátis; teste, cortesia e admin → Premium.
    expect(plan({'status': 'expired'}), 'gratis');
    expect(plan({'status': 'trial'}), 'premium');
    expect(plan({'status': 'free'}), 'premium');
    expect(plan({'status': 'admin'}), 'premium');
    expect(plan({'status': 'active', 'premium': true}), 'premium');
    expect(plan({'status': 'active', 'premium': false}), 'basico');
    expect(plan({'status': 'active', 'plan': 'outro'}), 'basico');
  });

  test('teste que acabou depois da última consulta vira Grátis', () {
    final a = Access(
      status: 'trial',
      plan: 'premium',
      trialEndsAt: now.subtract(const Duration(minutes: 1)),
    );
    expect(a.expired, isTrue);
    expect(a.trial, isFalse);
    expect(a.isGratis, isTrue);
    expect(a.isPremium, isFalse);
    expect(accessSummary(a), 'Plano Grátis');
    // Assinatura paga ainda em dia vale mesmo com o teste acabado.
    final paid = Access(
      status: 'active',
      trialEndsAt: before,
      paidUntil: now.add(const Duration(days: 3)),
    );
    expect(paid.expired, isFalse);
    expect(paid.isGratis, isFalse);
    expect(accessSummary(paid), startsWith('Plano básico ativo até'));
    // Premium que venceu também vira Grátis.
    final ended = Access(
      status: 'active',
      plan: 'premium',
      premium: true,
      trialEndsAt: before,
      paidUntil: now.subtract(const Duration(hours: 1)),
    );
    expect(ended.isGratis, isTrue);
    expect(const Access(status: 'free', plan: 'premium').expired, isFalse);
    expect(const Access(status: 'admin', plan: 'premium').isPremium, isTrue);
    expect(accessSummary(const Access(status: 'free')), 'Conta sem cobrança');
  });

  test('projeção do Grátis vai até 3 meses a partir do mês atual', () {
    final m = YearMonth.now();
    MonthRange limit(MonthRange r) =>
        ProjectionScreen.limitRange(r, gratis: true);
    final twelve = MonthRange.starting(m, 12);
    expect(
      identical(ProjectionScreen.limitRange(twelve, gratis: false), twelve),
      isTrue,
    );
    final r = limit(twelve);
    expect([r.from, r.to], [m, m.add(2)]);
    final past = limit(MonthRange(m.add(-12), m.add(-1)));
    expect([past.from, past.to], [m.add(-3), m.add(-1)]);
    final ahead = limit(MonthRange(m.add(5), m.add(8)));
    expect([ahead.from, ahead.to], [m.add(2), m.add(2)]);
    final three = MonthRange.starting(m, 3);
    expect(identical(limit(three), three), isTrue);
  });

  group('telas no plano Grátis', () {
    AuthController gratis() => AuthController(LocalAuthService())
      ..user = AppUser(
        id: 'u',
        name: 'Eva',
        email: 'eva@x.com',
        access: Access(status: 'expired', plan: 'gratis', trialEndsAt: before),
      );

    Future<void> pump(WidgetTester tester, Widget home) async {
      Intl.defaultLocale = 'pt_BR';
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fc = FinanceController(MemoryRepo());
      await tester.runAsync(fc.load);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: fc),
            ChangeNotifierProvider.value(value: gratis()),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: home),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('projeção mostra o aviso e oferece assinar no 12 meses', (
      tester,
    ) async {
      await pump(tester, const ProjectionScreen());
      expect(
        find.text(
          'No plano Grátis a projeção mostra 3 meses. Assine para ver 12.',
        ),
        findsOneWidget,
      );
      final m = YearMonth.now();
      expect(
        find.text('${m.shortLabel} – ${m.add(2).shortLabel}'),
        findsOneWidget,
      );
      await tester.tap(find.text('12 meses'));
      await tester.pumpAndSettle();
      expect(find.text('Recurso do plano Básico'), findsOneWidget);
      await tester.tap(find.text('Ver planos').last);
      await tester.pumpAndSettle();
      expect(find.text('Assinatura'), findsOneWidget);
      expect(find.text('Plano Grátis'), findsOneWidget);
      expect(find.text('Seu plano'), findsOneWidget);
    });

    testWidgets('importar planilha mostra o plano Básico', (tester) async {
      await pump(tester, const ExpenseImportScreen());
      expect(find.text('Importar planilha é do plano Básico'), findsOneWidget);
    });

    testWidgets('Open Finance mostra a demonstração', (tester) async {
      await pump(tester, const OpenFinanceScreen());
      expect(find.text('Banco Exemplo'), findsOneWidget);
      expect(find.text('Demonstração · dados fictícios'), findsOneWidget);
      expect(find.text('Conectar banco'), findsNothing);
      // Conta local: não há servidor para registrar o aviso.
      await tester.tap(find.byKey(const ValueKey('of-interest')));
      await tester.pump();
      expect(find.text('Disponível nas contas na nuvem.'), findsOneWidget);
    });
  });
}
