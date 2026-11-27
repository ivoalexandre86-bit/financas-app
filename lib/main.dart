import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/invoice_link.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  // Link do lembrete de fatura por e-mail (?fatura=…&mes=…).
  await InvoiceLink.init();
  runApp(const FinancasApp());
}
