import 'package:financas_app/data/auth_service.dart';
import 'package:financas_app/ui/screens/subscription/subscription_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  final now = DateTime.now();

  test('acesso vindo do servidor', () {
    final a = Access.fromJson({
      'status': 'trial',
      'trialEndsAt': now.add(const Duration(days: 10, hours: 2)).toUtc().toIso8601String(),
      'paidUntil': null,
      'premium': false,
    })!;
    expect(a.trial, isTrue);
    expect(a.expired, isFalse);
    expect(a.trialDaysLeft(now), 10);
    expect(accessSummary(a), startsWith('Teste grátis: faltam 10 dias'));
    expect(Access.fromJson(null), isNull);
  });

  test('teste que acabou depois da última consulta conta como vencido', () {
    final a = Access(
      status: 'trial',
      trialEndsAt: now.subtract(const Duration(minutes: 1)),
    );
    expect(a.expired, isTrue);
    expect(a.trial, isFalse);
    // Assinatura paga ainda em dia vale mesmo com o teste acabado.
    final paid = Access(
      status: 'active',
      trialEndsAt: now.subtract(const Duration(days: 40)),
      paidUntil: now.add(const Duration(days: 3)),
    );
    expect(paid.expired, isFalse);
    expect(accessSummary(paid), startsWith('Plano básico ativo até'));
    expect(const Access(status: 'free').expired, isFalse);
    expect(const Access(status: 'admin').expired, isFalse);
  });
}
