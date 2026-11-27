import 'dart:convert';

import 'package:financas_app/data/cloud/api_client.dart';
import 'package:financas_app/data/invoice_link.dart';
import 'package:financas_app/ui/screens/settings/email_reminders_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('link do e-mail abre a fatura do cartão e mês', () async {
    SharedPreferences.setMockInitialValues({});
    expect(InvoiceLink.parse({'fatura': 'nubank', 'mes': '2026-13'}), isNull);
    expect(InvoiceLink.parse({'mes': '2026-12'}), isNull);
    await InvoiceLink.init(
      entry: Uri.parse('https://app.exemplo/?fatura=nubank&mes=2026-12'),
    );
    final p = InvoiceLink.take()!;
    expect(p.cardId, 'nubank');
    expect((p.month.year, p.month.month), (2026, 12));
    expect(InvoiceLink.take(), isNull);
  });

  test('fuso do aparelho pelo deslocamento', () {
    expect(deviceTimeZone(DateTime.utc(2026)), 'America/Sao_Paulo');
  });

  testWidgets('confirma o e-mail e liga o lembrete com antecedência', (
    tester,
  ) async {
    var verified = false;
    var prefs = <String, Object?>{
      'enabled': false,
      'daysBefore': 3,
      'overdue': true,
      'timeZone': 'America/Sao_Paulo',
      'sendHour': 8,
    };
    final calls = <String>[];
    Map<String, Object?> state() => {
      'available': true,
      'sandbox': true,
      'email': 'ivo@exemplo.test',
      'verified': verified,
      'prefs': prefs,
      'recent': [
        if (verified)
          {
            'cardId': 'nubank',
            'invoiceKey': '2026-12',
            'due': '2026-12-10',
            'phase': 'antes',
            'sentAt': '2026-12-07T11:05:00Z',
            'amount': 83456,
          },
      ],
    };
    final api = ApiClient(
      'https://api.test',
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        final Object body = switch ('${req.method} ${req.url.path}') {
          'GET /email/reminders' => state(),
          'POST /email/verify/send' => {'sent': true, 'sandbox': true},
          'PATCH /email/reminders' => () {
            prefs = {
              ...prefs,
              ...(jsonDecode(req.body) as Map).cast<String, Object?>(),
            };
            return state();
          }(),
          _ => throw StateError('inesperado: ${req.url}'),
        };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: EmailRemindersScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ivo@exemplo.test'), findsOneWidget);
    expect(find.textContaining('modo de teste'), findsOneWidget);
    // Sem confirmar, o lembrete não liga.
    final sw = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('email-enabled')),
    );
    expect(sw.onChanged, isNull);

    await tester.tap(find.byKey(const ValueKey('email-verify')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /email/verify/send'));
    expect(find.textContaining('Enviamos o link'), findsOneWidget);

    verified = true;
    await tester.tap(find.byTooltip('Atualizar'));
    await tester.pumpAndSettle();
    expect(find.text('E-mail confirmado.'), findsOneWidget);
    await tester.dragUntilVisible(
      find.textContaining('834,56'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.textContaining('Vence 10/12/2026'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('email-enabled')));
    await tester.pumpAndSettle();
    expect(prefs['enabled'], true);

    await tester.tap(find.byKey(const ValueKey('email-days')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 dias antes').last);
    await tester.pumpAndSettle();
    expect(prefs['daysBefore'], 5);

    await tester.tap(find.byKey(const ValueKey('email-overdue')));
    await tester.pumpAndSettle();
    expect(prefs['overdue'], false);
  });
}
