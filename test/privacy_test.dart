import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/auth_service.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/auth_controller.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/app_shell.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
  });
  tearDown(() => Money.hidden = false);

  test('valores ocultos só na tela', () {
    const m = Money(123456);
    expect(m.format(), contains('1.234,56'));
    Money.hidden = true;
    expect(m.format(), 'R\$ ••••');
    expect(m.formatCompact(), '••••');
    expect(m.formatVisible(), contains('1.234,56'));
    expect(m.formatPlain(), '1.234,56');
  });

  test('PIN fica guardado com hash e confere', () async {
    final fc = FinanceController(MemoryRepo());
    await fc.load();
    expect(fc.hasPin, isFalse);
    expect(() => fc.setPin('12'), throwsArgumentError);
    await fc.setPin('4321');
    expect(fc.hasPin, isTrue);
    expect(fc.data.settings.pinLock, isNot(contains('4321')));
    expect(fc.checkPin('4321'), isTrue);
    expect(fc.checkPin('1234'), isFalse);
    final back = AppSettings.fromJson(fc.data.settings.toJson());
    expect(back.pinLock, fc.data.settings.pinLock);
    await fc.setPin(null);
    expect(fc.hasPin, isFalse);
  });

  Future<FinanceController> pumpShell(
    WidgetTester tester, {
    String? pin,
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(fc.load);
    if (pin != null) await tester.runAsync(() => fc.setPin(pin));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthController(LocalAuthService()),
          ),
          ChangeNotifierProvider.value(value: fc),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const AppShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return fc;
  }

  testWidgets('pede o PIN ao abrir e libera com o certo', (tester) async {
    await pumpShell(tester, pin: '2468');
    expect(find.text('App bloqueado'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('lock-pin')), '1111');
    await tester.tap(find.byKey(const ValueKey('lock-unlock')));
    await tester.pump();
    expect(find.text('PIN incorreto'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('lock-pin')), '2468');
    await tester.tap(find.byKey(const ValueKey('lock-unlock')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('App bloqueado'), findsNothing);
    // Bloquear de novo pelo menu.
    await tester.tap(find.byKey(const ValueKey('menu-lock')));
    await tester.pump();
    expect(find.text('App bloqueado'), findsOneWidget);
  });

  testWidgets('menu oculta e mostra os valores', (tester) async {
    final fc = await pumpShell(tester);
    expect(find.text('App bloqueado'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('menu-hide-values')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(fc.data.settings.hideValues, isTrue);
    expect(Money.hidden, isTrue);
    expect(find.textContaining('••••'), findsWidgets);
    expect(find.text('Mostrar valores'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-hide-values')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(Money.hidden, isFalse);
  });
}
