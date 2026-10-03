import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:financas_app/ui/widgets/form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  testWidgets('despesa: escolher a categoria lista as subcategorias', (
    tester,
  ) async {
    final fc = FinanceController(MemoryRepo());
    await tester.runAsync(fc.load);
    expect(fc.data.categories.any((c) => c.id == 'cat_rent'), isTrue);
    String? value;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CategoryDropdown(
              fc: fc,
              kind: CategoryKind.expense,
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Subcategoria'), findsNothing);

    await tester.tap(find.text('Categoria'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moradia').last);
    await tester.pumpAndSettle();
    expect(value, 'cat_housing');
    expect(find.text('Subcategoria'), findsOneWidget);

    await tester.tap(find.text('Nenhuma (só Moradia)'));
    await tester.pumpAndSettle();
    expect(find.text('Aluguel'), findsWidgets);
    expect(find.text('Condomínio'), findsWidgets);
    await tester.tap(find.text('Aluguel').last);
    await tester.pumpAndSettle();
    expect(value, 'cat_rent');
    // A categoria continua mostrando o grupo escolhido.
    expect(find.text('Moradia'), findsOneWidget);
  });
}
