import 'dart:convert';

import 'package:financas_app/core/dates.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/report_export.dart';
import 'package:financas_app/domain/import/expense_import.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/domain/models/planning.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'controller_test.dart' show MemoryRepo;

void main() {
  late FinanceController fc;
  final month = YearMonth.now();

  setUpAll(() async {
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
  });

  setUp(() async {
    fc = FinanceController(MemoryRepo());
    await fc.load();
    await fc.saveAccount(Account(id: 'a', name: 'Conta'));
  });

  FinTransaction tx(String id, String desc, int cents, {String? cat}) =>
      FinTransaction(
        id: id,
        type: TransactionType.expense,
        amount: Money(cents),
        description: desc,
        categoryId: cat ?? 'cat_other_expense',
        date: month.firstDay,
        accountId: 'a',
      );

  test('regra casa sem acento/maiúsculas e a mais longa vence', () {
    final rules = [
      CategoryRule(id: '1', pattern: 'uber', categoryId: 'cat_transport'),
      CategoryRule(id: '2', pattern: 'Uber Eats', categoryId: 'cat_food'),
      CategoryRule(id: '3', pattern: 'farmácia', categoryId: 'cat_health'),
    ];
    expect(CategoryRule.categoryFor(rules, 'UBER *TRIP'), 'cat_transport');
    expect(CategoryRule.categoryFor(rules, 'uber eats pedido'), 'cat_food');
    expect(CategoryRule.categoryFor(rules, 'FARMACIA SAO JOAO'), 'cat_health');
    expect(CategoryRule.categoryFor(rules, 'mercado'), isNull);
  });

  test('salvar, aplicar e sugerir pela regra', () async {
    await fc.saveTransaction(tx('t1', 'IFOOD *Pedido', 4500));
    await fc.saveTransaction(tx('t2', 'Padaria', 900));
    final r = CategoryRule(id: 'r', pattern: 'ifood', categoryId: 'cat_food');
    await fc.saveCategoryRule(r);
    expect(fc.ruleCandidates(r).map((t) => t.id), ['t1']);
    expect(await fc.applyCategoryRule(r), 1);
    expect(
      fc.data.transactions.firstWhere((t) => t.id == 't1').categoryId,
      'cat_food',
    );
    expect(
      fc.ruleCategoryFor('ifood almoço', CategoryKind.expense),
      'cat_food',
    );
    expect(fc.ruleCategoryFor('ifood', CategoryKind.income), isNull);
    expect(
      () => fc.saveCategoryRule(
        CategoryRule(id: 'r2', pattern: 'IFOOD', categoryId: 'cat_food'),
      ),
      throwsArgumentError,
    );

    final again = FinanceController(fc.repo);
    await again.load();
    expect(again.categoryRules.single.pattern, 'ifood');
  });

  test('planilha sem categoria usa as regras', () {
    final rules = [
      CategoryRule(id: 'r', pattern: 'posto', categoryId: 'cat_transport'),
    ];
    final plan = ExpenseImportPlanner.plan(
      [
        ExpenseSheetRow(
          line: 2,
          date: month.firstDay,
          description: 'Posto Shell',
          amount: const Money(20000),
          account: 'Conta',
        ),
      ],
      fc.data,
      const ExpenseImportOptions(),
      rules: rules,
    );
    expect(plan.items.single.categoryId, 'cat_transport');
  });

  test('tags ficam no lançamento e entram na lista de tags', () async {
    await fc.saveTransaction(
      tx('t1', 'Hotel', 50000).copyWith(tags: ['Viagem', 'Férias']),
    );
    await fc.saveTransaction(
      tx('t2', 'Passagem', 90000).copyWith(tags: ['Viagem']),
    );
    expect(fc.allTags, ['Viagem', 'Férias']);
    final j = fc.data.transactions.firstWhere((t) => t.id == 't2').toJson();
    expect(j['tags'], ['Viagem']);
    expect(tx('x', 'x', 1).toJson().containsKey('tags'), isFalse);
  });

  test('exporta Excel, CSV e PDF do período', () async {
    await fc.saveTransaction(
      tx(
        't1',
        'Mercado; semana',
        12345,
        cat: 'cat_groceries',
      ).copyWith(tags: ['Casa']),
    );
    await fc.saveTransaction(
      FinTransaction(
        id: 's',
        type: TransactionType.income,
        amount: const Money(500000),
        description: 'Salário',
        categoryId: 'cat_salary',
        date: month.firstDay,
        accountId: 'a',
      ),
    );
    final r = ReportExport(fc.engine, month, month);
    expect(r.rows.length, 2);
    expect(r.expensesByCategory.single.category, 'Alimentação');
    expect(r.expensesByCategory.single.total, const Money(12345));

    final csvBytes = r.toCsv();
    expect(csvBytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]); // BOM
    final csv = utf8.decode(csvBytes);
    expect(csv, contains('Data no caixa;'));
    expect(csv, contains('"Mercado; semana"'));
    expect(csv, contains('-123,45'));
    expect(csv, contains('Casa'));

    final xlsx = r.toXlsx();
    expect(xlsx.sublist(0, 2), [0x50, 0x4B]); // zip

    final pdf = await r.toPdf(
      userName: 'Ivo',
      budgets: [
        Budget(id: 'b', categoryId: 'cat_food', amount: const Money(50000)),
      ],
    );
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
  });
}
