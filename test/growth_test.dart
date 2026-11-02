import 'package:financas_app/data/auth_service.dart';
import 'package:financas_app/data/growth.dart';
import 'package:financas_app/ui/screens/admin/business_screen.dart';
import 'package:financas_app/ui/screens/referral/referral_screen.dart';
import 'package:financas_app/ui/screens/subscription/subscription_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBusiness implements BusinessApi {
  final saved = <List<Object>>[];
  int calls = 0;
  @override
  Future<Map<String, Object?>> metrics(int days) async {
    calls++;
    return {
      'prices': {'basico': 999, 'premium': 1999},
      'kpis': {
        'mrrCents': 2998,
        'arpuCents': 1499,
        'paying': 2,
        'premium': 1,
        'basico': 1,
        'trial': 3,
        'bonus': 0,
        'gratis': 4,
        'courtesy': 1,
        'trialConversion': 50.0,
        'trialsEnded': 2,
        'churn': null,
        'cancellations': 0,
        'cacCents': 5000,
      },
      'funnel': [
        {
          'name': 'install',
          'label': 'Instalações',
          'count': 10,
          'fromPrevious': null,
        },
        {
          'name': 'signup',
          'label': 'Cadastros',
          'count': 5,
          'fromPrevious': 50.0,
        },
      ],
      'channels': [
        {
          'channel': 'instagram',
          'signups': 4,
          'paying': 1,
          'conversion': 25.0,
          'revenueCents': 999,
          'spendCents': 5000,
          'cacCents': 5000,
        },
      ],
      'months': [
        {
          'month': '2026-11',
          'signups': 5,
          'firstCharges': 1,
          'cancellations': 0,
          'revenueCents': 999,
          'spendCents': 5000,
          'cacCents': 5000,
        },
      ],
      'cohorts': [
        {
          'month': '2026-11',
          'size': 5,
          'retention': [80.0, null],
        },
      ],
      'referrals': {'pending': 1, 'rewarded': 0, 'rejected': 0},
    };
  }

  @override
  Future<void> saveSpend(String month, String channel, int cents) async =>
      saved.add([month, channel, cents]);
}

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('canal e convite do link de entrada; aparelho fixo', () async {
    SharedPreferences.setMockInitialValues({});
    await Growth.init(
      entry: Uri.parse(
        'https://x/financas-app/?utm_source=instagram&ref=abc123',
      ),
    );
    final device = Growth.deviceId;
    expect(device, hasLength(24));
    expect(Growth.signupExtras(), {
      'channel': 'instagram',
      'ref': 'ABC123',
      'deviceId': device,
    });
    // Outro link depois não troca o canal do primeiro toque.
    await Growth.init(entry: Uri.parse('https://x/?utm_source=google'));
    expect(Growth.channel, 'instagram');
    expect(Growth.deviceId, device);
    await Growth.clearRef();
    await Growth.init(entry: Uri.parse('https://x/'));
    expect(Growth.ref, isNull);
    // Sem conta na nuvem não envia nada (e não falha).
    Growth.track('first_budget');
  });

  test('Premium ganho por indicação', () {
    final until = DateTime.now().add(const Duration(days: 20));
    final a = Access.fromJson({
      'status': 'bonus',
      'plan': 'premium',
      'trialEndsAt': DateTime.now()
          .subtract(const Duration(days: 3))
          .toUtc()
          .toIso8601String(),
      'bonusUntil': until.toUtc().toIso8601String(),
      'premium': true,
    })!;
    expect(a.expired, isFalse);
    expect(a.isPremium, isTrue);
    expect(accessSummary(a), startsWith('Premium por indicação até '));
  });

  testWidgets('Indique e ganhe mostra código, regras e resultado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        ReferralScreen(
          loader: () async => ReferralInfo.fromJson({
            'code': 'K7M2QX',
            'invited': 3,
            'pending': 1,
            'rewarded': 1,
            'bonusUntil': DateTime.now()
                .add(const Duration(days: 30))
                .toUtc()
                .toIso8601String(),
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('K7M2QX'), findsOneWidget);
    expect(find.textContaining('?ref=K7M2QX'), findsOneWidget);
    expect(find.text('Copiar convite'), findsOneWidget);
    expect(
      find.textContaining('Premium por indicação vai até'),
      findsOneWidget,
    );
    expect(find.textContaining('mesmo aparelho'), findsOneWidget);
  });

  testWidgets('Painel do negócio: KPIs, funil, canais e investimento', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _FakeBusiness();
    await tester.pumpWidget(_wrap(BusinessScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('MRR'), findsOneWidget);
    expect(find.textContaining('29,98'), findsOneWidget);
    expect(find.text('Conversão do teste'), findsOneWidget);
    expect(find.text('50,0%'), findsOneWidget);
    expect(find.text('instagram'), findsOneWidget);
    expect(find.text('nov/26'), findsNWidgets(2));
    expect(find.text('80,0%'), findsOneWidget);

    await tester.tap(find.text('Investimento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Canal'), 'tiktok');
    await tester.enterText(
      find.widgetWithText(TextField, 'Valor investido'),
      '150,00',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(api.saved.single.sublist(1), ['tiktok', 15000]);
    expect(api.calls, 2);

    await tester.tap(find.text('90 dias'));
    await tester.pumpAndSettle();
    expect(api.calls, 3);
  });
}
