import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:financas_app/core/money.dart';
import 'package:financas_app/data/default_categories.dart';
import 'package:financas_app/data/finance_repository.dart';
import 'package:financas_app/data/spreadsheet_io.dart';
import 'package:financas_app/domain/engine/financial_engine.dart';
import 'package:financas_app/domain/import/expense_import.dart';
import 'package:financas_app/domain/models/entities.dart';
import 'package:financas_app/state/finance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show MemoryRepo;

FinanceData _data({List<FinTransaction> txs = const []}) => FinanceData(
  accounts: [
    Account(id: 'acc_1', name: 'Nubank Conta'),
    Account(id: 'acc_2', name: 'Itaú', active: false),
  ],
  cards: [
    CreditCard(
      id: 'card_1',
      name: 'Visa Platinum',
      lastFour: '1234',
      closingDay: 5,
      dueDay: 12,
    ),
  ],
  categories: defaultCategories(),
  projects: [Project(id: 'prj_1', name: 'Reforma')],
  transactions: txs,
);

final _today = DateTime(2026, 10, 3);

const _header = [
  'Data',
  'Descrição',
  'Valor',
  'Categoria',
  'Conta',
  'Cartão',
  'Parcelas',
  'Projeto',
  'Status',
  'Observações',
];

void main() {
  group('ExpenseSheetParser', () {
    test('valores no padrão brasileiro e numéricos', () {
      expect(ExpenseSheetParser.parseAmount('1.234,56'), const Money(123456));
      expect(ExpenseSheetParser.parseAmount('R\$ 55,9'), const Money(5590));
      expect(ExpenseSheetParser.parseAmount('-10'), const Money(-1000));
      expect(ExpenseSheetParser.parseAmount('(10,00)'), const Money(-1000));
      expect(ExpenseSheetParser.parseAmount('1234.56'), const Money(123456));
      expect(ExpenseSheetParser.parseAmount('1,234.56'), const Money(123456));
      expect(ExpenseSheetParser.parseAmount(412.37), const Money(41237));
      expect(ExpenseSheetParser.parseAmount(0.1 + 0.2), const Money(30));
      expect(ExpenseSheetParser.parseAmount(50), const Money(5000));
      expect(ExpenseSheetParser.parseAmount('abc'), isNull);
    });

    test('datas: texto, serial do Excel e DateTime', () {
      expect(ExpenseSheetParser.parseDate('15/09/2026'), DateTime(2026, 9, 15));
      expect(ExpenseSheetParser.parseDate('5/9/26'), DateTime(2026, 9, 5));
      expect(ExpenseSheetParser.parseDate('2026-09-15'), DateTime(2026, 9, 15));
      expect(ExpenseSheetParser.parseDate(46280), DateTime(2026, 9, 15));
      expect(
        ExpenseSheetParser.parseDate(DateTime(2026, 9, 15, 13, 40)),
        DateTime(2026, 9, 15),
      );
      expect(ExpenseSheetParser.parseDate('31/02/2026'), isNull);
      expect(ExpenseSheetParser.parseDate('ontem'), isNull);
    });

    test('parcelas e status', () {
      expect(ExpenseSheetParser.parseInstallments('3x'), 3);
      expect(ExpenseSheetParser.parseInstallments(10.0), 10);
      expect(ExpenseSheetParser.parseInstallments('0'), isNull);
      expect(ExpenseSheetParser.parseInstallments(2.5), isNull);
      expect(
        ExpenseSheetParser.parseStatus('concluída'),
        TransactionStatus.completed,
      );
      expect(
        ExpenseSheetParser.parseStatus('PAGO'),
        TransactionStatus.completed,
      );
      expect(
        ExpenseSheetParser.parseStatus('Pendente'),
        TransactionStatus.pending,
      );
      expect(ExpenseSheetParser.parseStatus('talvez'), isNull);
    });

    test('localiza o cabeçalho, ignora linhas vazias e aponta erros', () {
      final r = ExpenseSheetParser.parse([
        ['Minha planilha'],
        [],
        ['Valor', 'DESCRICAO', 'data', 'Coluna extra'],
        [10.5, 'Café', '01/10/2026', 'x'],
        [null, '', null],
        ['abc', '', '32/10/2026'],
      ]);
      expect(r.fatalError, isNull);
      expect(r.ignoredColumns, ['Coluna extra']);
      expect(r.rows, hasLength(2));
      expect(r.rows[0].line, 4);
      expect(r.rows[0].amount, const Money(1050));
      expect(r.rows[0].errors, isEmpty);
      expect(r.rows[1].line, 6);
      expect(r.rows[1].errors, hasLength(3));
    });

    test('sem cabeçalho = erro fatal', () {
      expect(
        ExpenseSheetParser.parse([
          ['a', 'b'],
        ]).fatalError,
        isNotNull,
      );
    });

    test('CSV com ; e aspas', () {
      final rows = SpreadsheetIO.parseCsv(
        'Data;Descrição;Valor\r\n01/10/2026;"Padaria; pão";"1.234,50"\n',
      );
      final r = ExpenseSheetParser.parse(rows);
      expect(r.rows.single.description, 'Padaria; pão');
      expect(r.rows.single.amount, const Money(123450));
    });
  });

  group('ExpenseImportPlanner', () {
    ExpenseImportPlan plan(
      List<List<Object?>> rows, {
      FinanceData? data,
      ExpenseImportOptions options = const ExpenseImportOptions(
        defaultAccountId: 'acc_1',
      ),
    }) {
      final parsed = ExpenseSheetParser.parse([_header, ...rows]);
      return ExpenseImportPlanner.plan(
        parsed.rows,
        data ?? _data(),
        options,
        today: _today,
      );
    }

    test('vincula categoria, subcategoria, conta, cartão e projeto', () {
      final p = plan([
        [
          '01/10/2026',
          'Mercado',
          '100',
          'alimentacao > mercado',
          '',
          '1234',
          '',
          'reforma',
          '',
          '',
        ],
        [
          '01/10/2026',
          'Luz',
          '200',
          'Energia',
          'NUBANK CONTA',
          '',
          '',
          '',
          '',
          '',
        ],
        ['01/10/2026', 'Sem nada', '5', '', '', '', '', '', '', ''],
      ]);
      final [a, b, c] = p.items;
      expect(a.errors, isEmpty);
      expect(a.categoryId, 'cat_groceries');
      expect(a.cardId, 'card_1');
      expect(a.projectId, 'prj_1');
      expect(b.categoryId, 'cat_energy');
      expect(b.accountId, 'acc_1');
      expect(c.categoryId, 'cat_other_expense');
      expect(c.accountId, 'acc_1', reason: 'conta padrão');
    });

    test('erros: conta/cartão inexistente, ambos, sem conta padrão', () {
      final p = plan([
        ['01/10/2026', 'A', '1', '', 'Bradesco', '', '', '', '', ''],
        [
          '01/10/2026',
          'B',
          '1',
          '',
          'Nubank Conta',
          'Visa Platinum',
          '',
          '',
          '',
          '',
        ],
        ['01/10/2026', 'C', '1', '', '', '', '', '', '', ''],
      ], options: const ExpenseImportOptions());
      expect(p.items.every((i) => !i.isValid && !i.selected), isTrue);
      expect(p.selected, isEmpty);
    });

    test('categoria inexistente: cria ou usa Outras despesas', () {
      final rows = [
        ['01/10/2026', 'A', '1', 'Pets', '', '', '', '', '', ''],
        ['02/10/2026', 'B', '1', 'pets', '', '', '', '', '', ''],
      ];
      final create = plan(rows);
      expect(create.newCategoryNames, ['Pets']);
      final batch = create.build(today: _today);
      expect(batch.categories, hasLength(1));
      expect(batch.transactions.map((t) => t.categoryId).toSet(), {
        batch.categories.single.id,
      });

      final noCreate = plan(
        rows,
        options: const ExpenseImportOptions(
          defaultAccountId: 'acc_1',
          createMissingCategories: false,
        ),
      );
      expect(noCreate.newCategoryNames, isEmpty);
      expect(noCreate.items.first.categoryId, 'cat_other_expense');
      expect(noCreate.items.first.warnings, isNotEmpty);
    });

    test('status padrão: futura em conta = planejada; cartão = concluída', () {
      final p = plan([
        ['20/10/2026', 'Futura', '1', '', 'Nubank Conta', '', '', '', '', ''],
        ['20/10/2026', 'Cartão', '1', '', '', 'Visa Platinum', '', '', '', ''],
        ['20/10/2026', 'Explícita', '1', '', '', '', '', '', 'Pendente', ''],
      ]);
      expect(p.items.map((i) => i.status), [
        TransactionStatus.planned,
        TransactionStatus.completed,
        TransactionStatus.pending,
      ]);
    });

    test('possível duplicada vem desmarcada', () {
      final data = _data(
        txs: [
          FinTransaction(
            id: 'tx_1',
            type: TransactionType.expense,
            amount: const Money(5000),
            description: 'Padaria',
            date: DateTime(2026, 10, 1),
            accountId: 'acc_1',
          ),
        ],
      );
      final p = plan([
        ['01/10/2026', 'PADARIA', '50,00', '', '', '', '', '', '', ''],
        ['01/10/2026', 'Padaria', '51,00', '', '', '', '', '', '', ''],
      ], data: data);
      expect(p.items[0].possibleDuplicate, isTrue);
      expect(p.items[0].selected, isFalse);
      expect(p.items[1].possibleDuplicate, isFalse);
      expect(p.items[1].selected, isTrue);
    });

    test('parcelado gera grupo e parcelas com soma exata', () {
      final p = plan([
        [
          '01/10/2026',
          'Notebook',
          '1000,00',
          'Compras',
          '',
          'Visa Platinum',
          '3',
          '',
          '',
          'loja X',
        ],
      ]);
      final b = p.build(today: _today);
      expect(b.groups, hasLength(1));
      expect(b.transactions, hasLength(3));
      expect(b.transactions.map((t) => t.amount).sum(), const Money(100000));
      expect(b.transactions.first.installmentGroupId, b.groups.single.id);
      expect(b.transactions.first.notes, contains('loja X'));
    });
  });

  group('Controlador', () {
    test('importExpenses grava tudo em lote', () async {
      final repo = MemoryRepo();
      final fc = FinanceController(repo);
      await fc.load();
      await fc.saveAccount(Account(id: 'acc_1', name: 'Conta'));
      final parsed = ExpenseSheetParser.parse([
        _header,
        ['01/10/2026', 'A', '10', 'Nova categoria', '', '', '', '', '', ''],
        ['01/10/2026', 'B', '30', 'Mercado', '', '', '3', '', '', ''],
      ]);
      final p = ExpenseImportPlanner.plan(
        parsed.rows,
        fc.data,
        const ExpenseImportOptions(defaultAccountId: 'acc_1'),
      );
      final b = await fc.importExpenses(p);
      expect(b.rowCount, 2);
      expect(repo.stores[Coll.transactions], hasLength(4));
      expect(repo.stores[Coll.installmentGroups], hasLength(1));
      expect(
        fc.data.categories.where((c) => c.name == 'Nova categoria'),
        hasLength(1),
      );
      // Reimportar o mesmo arquivo: tudo vem como duplicado/desmarcado.
      final again = ExpenseImportPlanner.plan(
        parsed.rows,
        fc.data,
        const ExpenseImportOptions(defaultAccountId: 'acc_1'),
      );
      expect(again.selected, isEmpty);
    });
  });

  group('Modelo .xlsx', () {
    test('gera o modelo e o lê de volta', () {
      final data = _data();
      final bytes = SpreadsheetIO.buildTemplate(data, today: _today);
      final out = Platform.environment['TEMPLATE_OUT'];
      if (out != null) File(out).writeAsBytesSync(bytes);

      final book = Excel.decodeBytes(bytes);
      expect(
        book.tables.keys,
        containsAll(['Despesas', 'Exemplo', 'Instruções', 'Listas']),
      );
      // A aba Despesas está vazia (só cabeçalho): sem linhas a importar.
      final rows = SpreadsheetIO.readTable(bytes, 'modelo.xlsx');
      final parsed = ExpenseSheetParser.parse(rows);
      expect(parsed.fatalError, isNull);
      expect(parsed.rows, isEmpty);

      // A aba Exemplo é válida contra os cadastros.
      final exRows = [
        for (final r in book.tables['Exemplo']!.rows)
          [for (final c in r) c?.value],
      ];
      expect(exRows.length, 5);
    });

    test('lê planilha preenchida com datas e números reais', () {
      final book = Excel.createExcel();
      final s = book[book.getDefaultSheet()!];
      s.appendRow([for (final h in _header) TextCellValue(h)]);
      s.appendRow([
        DateCellValue(year: 2026, month: 9, day: 15),
        TextCellValue('Mercado'),
        DoubleCellValue(412.37),
        TextCellValue('Mercado'),
        TextCellValue('Nubank Conta'),
      ]);
      s.appendRow([
        IntCellValue(46280),
        TextCellValue('Luz'),
        IntCellValue(200),
      ]);
      final bytes = book.encode()!;
      final rows = SpreadsheetIO.readTable(Uint8List.fromList(bytes), 'x.xlsx');
      final parsed = ExpenseSheetParser.parse(rows);
      expect(parsed.rows, hasLength(2));
      expect(parsed.rows[0].date, DateTime(2026, 9, 15));
      expect(parsed.rows[0].amount, const Money(41237));
      expect(parsed.rows[1].date, DateTime(2026, 9, 15));
      expect(parsed.rows[1].amount, const Money(20000));
    });
    test('lê .xlsx de outras ferramentas (caminho absoluto, inlineStr)', () {
      ArchiveFile f(String name, String content) {
        final b = utf8.encode(content);
        return ArchiveFile(name, b.length, b);
      }

      final zip = Archive()
        ..addFile(
          f(
            'xl/workbook.xml',
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                '<sheets><sheet name="Planilha1" sheetId="1" r:id="rId1"/></sheets></workbook>',
          ),
        )
        ..addFile(
          f(
            'xl/_rels/workbook.xml.rels',
            '<Relationships><Relationship Target="/xl/worksheets/sheet1.xml" Id="rId1"/></Relationships>',
          ),
        )
        ..addFile(
          f(
            'xl/sharedStrings.xml',
            '<sst><si><t>Data</t></si><si><r><t>Descri</t></r><r><t>ção</t></r></si></sst>',
          ),
        )
        ..addFile(
          f(
            'xl/worksheets/sheet1.xml',
            '<worksheet><sheetData>'
                '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c>'
                '<c r="C1" t="inlineStr"><is><t>Valor</t></is></c></row>'
                '<row r="3"><c r="A3"><v>46280</v></c><c r="B3" t="str"><v>Café</v></c>'
                '<c r="C3"><v>12.5</v></c></row>'
                '</sheetData></worksheet>',
          ),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(zip)!);
      final parsed = ExpenseSheetParser.parse(
        SpreadsheetIO.readTable(bytes, 'a.xlsx'),
      );
      expect(parsed.fatalError, isNull);
      final r = parsed.rows.single;
      expect(r.line, 3);
      expect(r.date, DateTime(2026, 9, 15));
      expect(r.description, 'Café');
      expect(r.amount, const Money(1250));
    });
  });
}
