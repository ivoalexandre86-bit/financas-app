import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/auth_service.dart';
import 'package:financas_app/domain/models/enums.dart';
import 'package:financas_app/state/auth_controller.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/onboarding/onboarding_screen.dart';
import 'package:financas_app/ui/screens/simulations/simulations_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:financas_app/ui/widgets/plan_upsell.dart';
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

AuthController _auth(Access access) => AuthController(LocalAuthService())
  ..user = AppUser(id: 'u', name: 'Eva', email: 'eva@x.com', access: access);

Future<FinanceController> _pump(
  WidgetTester tester,
  Widget home, {
  required Access access,
  FinanceController? fc,
}) async {
  Intl.defaultLocale = 'pt_BR';
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = fc ?? FinanceController(MemoryRepo());
  if (fc == null) await tester.runAsync(c.load);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: c),
        ChangeNotifierProvider.value(value: _auth(access)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  final now = DateTime.now();
  final trial = Access(
    status: 'trial',
    plan: 'premium',
    trialEndsAt: now.add(const Duration(days: 20, hours: 1)),
    premium: true,
  );

  test(
    '1º orçamento: conta, renda e gastos fixos viram recorrências',
    () async {
      final fc = FinanceController(MemoryRepo());
      await fc.load();
      expect(fc.needsOnboarding, isTrue);
      await fc.completeOnboarding(
        balance: Money.fromParts(1500),
        income: Money.fromParts(5000),
        incomeDay: 5,
        expenses: [
          (
            categoryId: 'cat_rent',
            description: 'Aluguel',
            amount: Money.fromParts(1800),
            day: 5,
          ),
          (
            categoryId: 'cat_groceries',
            description: 'Mercado',
            amount: Money.zero,
            day: 10,
          ),
        ],
        today: DateTime(2026, 11, 2),
      );
      expect(fc.needsOnboarding, isFalse);
      expect(fc.data.settings.onboardingDone, isTrue);
      expect(fc.data.accounts.single.initialBalance, Money.fromParts(1500));
      final rules = fc.data.recurringRules;
      expect(rules, hasLength(2)); // gasto em branco não entra
      final salary = rules.firstWhere((r) => r.type == TransactionType.income);
      expect(salary.categoryId, 'cat_salary');
      expect(salary.startDate, DateTime(2026, 11, 5));
      expect(salary.accountId, fc.data.accounts.single.id);
    },
  );

  test('pular não mostra de novo', () async {
    final fc = FinanceController(MemoryRepo());
    await fc.load();
    await fc.skipOnboarding();
    expect(fc.needsOnboarding, isFalse);
    expect(fc.data.accounts, isEmpty);
  });

  testWidgets('tela do 1º acesso: condições do teste e quanto sobra', (
    tester,
  ) async {
    final fc = await _pump(tester, const OnboardingScreen(), access: trial);
    expect(find.textContaining('Sem cartão de crédito'), findsOneWidget);
    expect(find.textContaining('nada é cobrado'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('ob-balance')), '1000');
    await tester.enterText(find.byKey(const ValueKey('ob-income')), '4000');
    await tester.enterText(find.widgetWithText(TextField, 'Mercado'), '900,50');
    await tester.pumpAndSettle();
    expect(find.textContaining('Sobram R'), findsOneWidget);
    expect(find.textContaining('3.099,50 por mês'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ob-finish')));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(fc.data.accounts, hasLength(1));
    expect(fc.data.recurringRules, hasLength(2));
  });

  testWidgets('aviso do teste no Início', (tester) async {
    await _pump(
      tester,
      const Scaffold(body: TrialStatusBanner()),
      access: trial,
    );
    expect(find.textContaining('faltam 20 dias'), findsOneWidget);
    expect(find.textContaining('sem cobrança automática'), findsOneWidget);
  });

  testWidgets('teste terminado: aviso de que está no Grátis', (tester) async {
    await _pump(
      tester,
      const Scaffold(body: TrialStatusBanner()),
      access: Access(
        status: 'expired',
        plan: 'gratis',
        trialEndsAt: now.subtract(const Duration(days: 2)),
      ),
    );
    expect(find.textContaining('está no plano Grátis'), findsOneWidget);
  });

  testWidgets('Grátis: 1 simulação; comparar pede assinatura', (tester) async {
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(fc.load);
    await tester.runAsync(
      () => fc.createSimulation(
        name: 'A',
        from: YearMonth.now(),
        to: YearMonth.now(),
      ),
    );
    await _pump(
      tester,
      const SimulationsScreen(),
      fc: fc,
      access: Access(
        status: 'expired',
        plan: 'gratis',
        trialEndsAt: now.subtract(const Duration(days: 40)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('sim-create')));
    await tester.pumpAndSettle();
    expect(find.textContaining('você pode ter 1 simulação'), findsOneWidget);
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comparar cenários'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Comparar cenários lado a lado'),
      findsOneWidget,
    );
  });
}
