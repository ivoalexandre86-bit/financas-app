import 'dart:typed_data';

import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/ai_snapshot.dart';
import 'package:financas_app/data/cloud/ai_api.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/screens/assistant/assistant_screen.dart';
import 'package:financas_app/ui/screens/transactions/transaction_form_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'controller_test.dart' show MemoryRepo;

class FakeAi implements AiService {
  String? question;
  String? snapshot;
  int historyLength = -1;

  @override
  Future<String> ask(String q, String snap, List<AiTurn> history) async {
    question = q;
    snapshot = snap;
    historyLength = history.length;
    return 'Seu mês está no azul.';
  }

  @override
  Future<AiReceipt> readReceipt({
    Uint8List? bytes,
    String? mimeType,
    String? text,
  }) async => throw UnimplementedError();
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
  });

  test('recibo da IA vira lançamento', () {
    final r = AiReceipt.fromJson({
      'type': 'expense',
      'amount': 4590,
      'description': 'Mercado',
      'date': '2026-10-05',
      'categoryId': 'cat_groceries',
      'accountId': null,
      'cardId': 'c1',
      'installments': 3,
      'notes': '',
    });
    expect(r.amount, const Money(4590));
    expect(r.date, DateTime(2026, 10, 5));
    expect(r.type, TransactionType.expense);
    expect(r.installments, 3);
    expect(const AiTurn(false, 'oi').toJson(), {
      'role': 'assistant',
      'text': 'oi',
    });
  });

  test('retrato traz saldos e meses sem ocultar valores', () async {
    final fc = FinanceController(MemoryRepo());
    await fc.load();
    Money.hidden = true;
    addTearDown(() => Money.hidden = false);
    final s = buildAiSnapshot(fc.engine);
    expect(s, contains('Saldo total'));
    expect(s, contains(fc.engine.currentMonth.longLabel));
    expect(s, isNot(contains('••••')));
    expect(s, contains(Dates.format(fc.engine.today)));
  });

  Future<FinanceController> pump(
    WidgetTester tester,
    Widget home,
    AiService? ai,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(fc.load);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: fc),
          Provider<AiService?>.value(value: ai),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await tester.pump();
    return fc;
  }

  testWidgets('assistente manda pergunta com o retrato e mostra resposta', (
    tester,
  ) async {
    final ai = FakeAi();
    await pump(tester, const AssistantScreen(), ai);
    await tester.tap(find.text('Como está meu mês?'));
    await tester.pump();
    await tester.pump();
    expect(ai.question, 'Como está meu mês?');
    expect(ai.snapshot, contains('Saldo total'));
    expect(ai.historyLength, 0);
    expect(find.text('Seu mês está no azul.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('assistant-input')),
      'E o mês que vem?',
    );
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await tester.pump();
    await tester.pump();
    expect(ai.historyLength, 2);
  });

  testWidgets('sem nuvem: assistente indisponível e sem ler comprovante', (
    tester,
  ) async {
    await pump(tester, const AssistantScreen(), null);
    expect(find.text('Assistente indisponível'), findsOneWidget);
    await pump(tester, const TransactionFormScreen(), null);
    expect(find.byKey(const ValueKey('read-receipt')), findsNothing);
    await pump(tester, const TransactionFormScreen(), FakeAi());
    expect(find.byKey(const ValueKey('read-receipt')), findsOneWidget);
  });
}
