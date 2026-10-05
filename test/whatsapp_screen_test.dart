import 'dart:convert';

import 'package:financas_app/data/cloud/api_client.dart';
import 'package:financas_app/ui/screens/settings/whatsapp_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('formatPhone', () {
    expect(formatPhone('5511999990000'), '+55 11 99999-0000');
    expect(formatPhone('551199990000'), '+55 11 9999-0000');
    expect(formatPhone('15550001234'), '+15550001234');
  });

  testWidgets('vincula, mostra o código e desvincula', (tester) async {
    String? linked;
    final calls = <String>[];
    final api = ApiClient(
      'https://api.test',
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        final body = switch ('${req.method} ${req.url.path}') {
          'GET /whatsapp/status' => {
            'enabled': true,
            'botNumber': '15550001234',
            'audio': false,
            'linkedNumber': linked,
          },
          'POST /whatsapp/link-code' => {
            'code': '123456',
            'text': 'VINCULAR 123456',
            'url': 'https://wa.me/15550001234?text=VINCULAR%20123456',
          },
          'DELETE /whatsapp/link' => null,
          _ => throw StateError('inesperado: ${req.url}'),
        };
        if (body == null) return http.Response('', 204);
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
        home: WhatsAppScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('wa-link')));
    await tester.pumpAndSettle();
    expect(find.text('VINCULAR 123456'), findsOneWidget);
    expect(find.text('para +15550001234'), findsOneWidget);
    expect(find.byKey(const ValueKey('wa-open')), findsOneWidget);

    linked = '5511999990000';
    await tester.tap(find.byKey(const ValueKey('wa-check')));
    await tester.pumpAndSettle();
    expect(find.text('Ligado ao número +55 11 99999-0000.'), findsOneWidget);

    linked = null;
    await tester.tap(find.byKey(const ValueKey('wa-unlink')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desvincular').last);
    await tester.pumpAndSettle();
    expect(calls, contains('DELETE /whatsapp/link'));
    expect(find.byKey(const ValueKey('wa-link')), findsOneWidget);
  });

  testWidgets('servidor sem WhatsApp configurado', (tester) async {
    final api = ApiClient(
      'https://api.test',
      client: MockClient(
        (req) async => http.Response(
          jsonEncode({'enabled': false, 'botNumber': null}),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: WhatsAppScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ainda não foi configurado'), findsOneWidget);
    expect(find.byKey(const ValueKey('wa-link')), findsNothing);
  });
}
