import 'dart:convert';

import 'package:financas_app/data/cloud/api_client.dart';
import 'package:financas_app/data/cloud/pluggy_open_finance.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/enums.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/open_finance/open_finance_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'controller_test.dart' show MemoryRepo;

const item = '11111111-2222-3333-4444-555555555555';

void main() {
  late List<String> calls;
  late FinanceController fc;

  setUp(() async {
    calls = [];
    final api = ApiClient(
      'https://api.test',
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}?${req.url.query}');
        final path = req.url.path;
        Object body = {};
        if (path == '/openfinance/status') body = {'configured': true};
        if (path == '/openfinance/items') {
          body = {
            'item': {'id': item, 'institution': 'MeuPluggy'},
            'accounts': [
              {'id': 'acc1', 'kind': 'bank', 'label': 'MeuPluggy · Conta'},
              {
                'id': 'card1',
                'kind': 'credit_card',
                'label': 'MeuPluggy · Cartão',
              },
            ],
          };
        }
        if (path.endsWith('/transactions')) {
          body = {
            'transactions': [
              {
                'id': 't1',
                'date': '2026-10-01',
                'amountCents': -1234,
                'description': 'MERCADO',
                'pending': false,
              },
              {
                'id': 't2',
                'date': '2026-10-02',
                'amountCents': 5000,
                'description': 'PIX',
                'pending': true,
              },
            ],
          };
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    fc = FinanceController(
      MemoryRepo(),
      openFinance: PluggyOpenFinanceProvider(api),
    );
    await fc.load();
  });

  test('conectar pelo ID cria uma conexão por conta, sem repetir', () async {
    expect(await fc.openFinance.isConfigured(), isTrue);
    expect(await fc.connectItem(' $item '), 2);
    expect(fc.connections.map((c) => c.institutionName).toSet(), {
      'MeuPluggy · Conta',
      'MeuPluggy · Cartão',
    });
    expect(
      fc.connections.every(
        (c) =>
            c.providerId == 'pluggy' &&
            c.providerItemId == item &&
            c.consentStatus == ConsentStatus.active,
      ),
      isTrue,
    );
    expect(await fc.connectItem(item), 0);
    expect(fc.connections, hasLength(2));
  });

  test('sincroniza só lançamentos confirmados e não repete', () async {
    await fc.connectItem(item);
    final conta = fc.connections.firstWhere(
      (c) => c.providerAccountId == 'acc1',
    );
    final r = await fc.syncConnection(conta);
    expect(r.added, 1);
    expect(fc.externalTransactions.single.externalId, 'pluggy:t1');
    expect(fc.externalTransactions.single.signedAmount.cents, -1234);
    expect(calls.last, 'GET /openfinance/accounts/acc1/transactions?');

    final again = fc.connections.firstWhere((c) => c.id == conta.id);
    expect((await fc.syncConnection(again)).added, 0);
    // A 2ª sincronização pede só os últimos dias.
    expect(calls.last, contains('from='));
  });

  test('revogar uma conta revoga a conexão inteira no servidor', () async {
    await fc.connectItem(item);
    await fc.revokeConnection(fc.connections.first);
    expect(calls.last, 'DELETE /openfinance/items/$item?');
    expect(
      fc.connections.every((c) => c.consentStatus == ConsentStatus.revoked),
      isTrue,
    );
  });

  testWidgets('sem conexões, a tela explica os passos e abre o guia', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fc,
        child: const MaterialApp(home: OpenFinanceScreen()),
      ),
    );
    expect(find.text('Autorize seus bancos no Meu Pluggy'), findsOneWidget);
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();
    expect(find.text('Conectar seus bancos'), findsOneWidget);
    expect(find.text('Abrir Meu Pluggy'), findsOneWidget);
  });
}
