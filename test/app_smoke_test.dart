import 'package:financas_app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  testWidgets('app inicia', (tester) async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    await tester.pumpWidget(const FinancasApp());
    await tester.pump(const Duration(seconds: 1));
  });
}
