import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/dates.dart';
import '../core/money.dart';
import '../domain/engine/budget_engine.dart';
import '../domain/engine/financial_engine.dart';
import '../domain/models/entities.dart';
import '../domain/models/planning.dart';

/// Uma linha exportada: receita ou despesa reconhecida no mês (visão de
/// caixa, a mesma da Projeção). Compras no cartão entram na data de
/// pagamento (ou vencimento) da fatura.
class ExportRow {
  final DateTime cashDate;
  final DateTime date;
  final String description;
  final String category;
  final String rootCategory;
  final String where;
  final TransactionType type;
  final TransactionStatus status;

  /// Com sinal: + receita, − despesa.
  final Money amount;
  final String notes;
  final List<String> tags;

  const ExportRow({
    required this.cashDate,
    required this.date,
    required this.description,
    required this.category,
    required this.rootCategory,
    required this.where,
    required this.type,
    required this.status,
    required this.amount,
    required this.notes,
    this.tags = const [],
  });
}

/// Relatórios para baixar: Excel (lançamentos, categorias por mês e resumo),
/// CSV (lançamentos, no padrão do Excel em português) e PDF (resumo).
class ReportExport {
  final FinancialEngine engine;
  final YearMonth from;
  final YearMonth to;
  ReportExport(this.engine, this.from, this.to);

  List<YearMonth> get months => YearMonth.range(from, to).toList();

  String get periodLabel =>
      from == to ? from.longLabel : '${from.shortLabel} a ${to.shortLabel}';

  String get fileBase =>
      'financas-${from.key}${from == to ? '' : '-a-${to.key}'}';

  late final List<ExportRow> rows = () {
    final out = <ExportRow>[];
    for (final e in engine.recognizedEvents(ProjectionFilter.none, to)) {
      if (e.month < from) continue;
      final t = e.tx;
      final root =
          engine.data.categoryById[engine.rootCategoryId(t.categoryId)];
      out.add(
        ExportRow(
          cashDate: e.date,
          date: t.date,
          description: t.description,
          category: engine.categoryLabel(t.categoryId),
          rootCategory: root?.name ?? 'Sem categoria',
          where: engine.locationLabel(t),
          type: t.type,
          status: t.status,
          amount: e.signed,
          notes: t.notes,
          tags: t.tags,
        ),
      );
    }
    out.sort((a, b) {
      final c = a.cashDate.compareTo(b.cashDate);
      return c != 0 ? c : a.description.compareTo(b.description);
    });
    return out;
  }();

  /// Totais por mês: receitas, despesas (positivas) e resultado.
  List<({YearMonth month, Money income, Money expenses})> get monthly => [
    for (final m in months)
      () {
        final t = engine.monthTotals(ProjectionFilter.none, m);
        return (month: m, income: t.income, expenses: t.expenses);
      }(),
  ];

  /// Despesas por categoria raiz e mês, das que mais gastaram para as que
  /// menos.
  List<({String category, Map<YearMonth, Money> byMonth, Money total})>
  get expensesByCategory {
    final map = <String, Map<YearMonth, Money>>{};
    for (final r in rows) {
      if (!r.amount.isNegative) continue;
      final m = YearMonth.of(r.cashDate);
      final byMonth = map.putIfAbsent(r.rootCategory, () => {});
      byMonth[m] = (byMonth[m] ?? Money.zero) + Money(-r.amount.cents);
    }
    final out = [
      for (final e in map.entries)
        (
          category: e.key,
          byMonth: e.value,
          total: e.value.values.fold(Money.zero, (a, b) => a + b),
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  static double _reais(Money m) => m.cents / 100;

  // Excel ----------------------------------------------------------------------

  static final _header = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('#FF2457D6'),
  );
  static final _bold = CellStyle(bold: true);
  static final _date = CellStyle(
    numberFormat: const CustomDateTimeNumFormat(formatCode: 'dd/mm/yyyy'),
  );
  static final _money = CellStyle(
    numberFormat: const CustomNumericNumFormat(formatCode: '#,##0.00'),
  );
  static final _moneyBold = CellStyle(
    bold: true,
    numberFormat: const CustomNumericNumFormat(formatCode: '#,##0.00'),
  );

  static void _put(Sheet s, int col, int row, Object? v, [CellStyle? style]) {
    final CellValue? cell = switch (v) {
      null => null,
      DateTime d => DateCellValue.fromDateTime(d),
      int i => IntCellValue(i),
      double x => DoubleCellValue(x),
      Money m => DoubleCellValue(_reais(m)),
      _ => TextCellValue('$v'),
    };
    s.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      cell,
      cellStyle:
          style ??
          switch (v) {
            DateTime() => _date,
            Money() || double() => _money,
            _ => null,
          },
    );
  }

  static void _headerRow(Sheet s, List<String> titles, List<double> widths) {
    for (var i = 0; i < titles.length; i++) {
      _put(s, i, 0, titles[i], _header);
      s.setColumnWidth(i, widths[i]);
    }
  }

  static const _txHeader = [
    'Data no caixa',
    'Data',
    'Descrição',
    'Categoria',
    'Conta/cartão',
    'Tipo',
    'Status',
    'Valor (R\$)',
    'Tags',
    'Observações',
  ];

  Uint8List toXlsx() {
    final book = Excel.createExcel();
    final first = book.getDefaultSheet()!;
    book.rename(first, 'Lançamentos');

    final tx = book['Lançamentos'];
    _headerRow(tx, _txHeader, [13, 12, 36, 30, 22, 13, 12, 14, 20, 36]);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final values = <Object?>[
        r.cashDate,
        r.date,
        r.description,
        r.category,
        r.where,
        r.type.label,
        r.status.label,
        r.amount,
        r.tags.join(', '),
        r.notes,
      ];
      for (var c = 0; c < values.length; c++) {
        _put(tx, c, i + 1, values[c]);
      }
    }

    final cats = book['Por categoria'];
    final ms = months;
    _headerRow(
      cats,
      ['Categoria', for (final m in ms) m.shortLabel, 'Total'],
      [28, for (final _ in ms) 13, 14],
    );
    final byCat = expensesByCategory;
    for (var i = 0; i < byCat.length; i++) {
      final c = byCat[i];
      _put(cats, 0, i + 1, c.category);
      for (var j = 0; j < ms.length; j++) {
        _put(cats, j + 1, i + 1, c.byMonth[ms[j]] ?? Money.zero);
      }
      _put(cats, ms.length + 1, i + 1, c.total, _moneyBold);
    }

    final sum = book['Resumo mensal'];
    _headerRow(
      sum,
      ['Mês', 'Receitas', 'Despesas', 'Resultado'],
      [16, 14, 14, 14],
    );
    var row = 1;
    var inc = Money.zero, exp = Money.zero;
    for (final m in monthly) {
      _put(sum, 0, row, m.month.shortLabel);
      _put(sum, 1, row, m.income);
      _put(sum, 2, row, m.expenses);
      _put(sum, 3, row, m.income - m.expenses);
      inc += m.income;
      exp += m.expenses;
      row++;
    }
    _put(sum, 0, row, 'Total', _bold);
    _put(sum, 1, row, inc, _moneyBold);
    _put(sum, 2, row, exp, _moneyBold);
    _put(sum, 3, row, inc - exp, _moneyBold);

    book.setDefaultSheet('Lançamentos');
    return Uint8List.fromList(book.encode()!);
  }

  // CSV ------------------------------------------------------------------------

  static String _csvField(String s) =>
      s.contains(RegExp('[;"\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;

  /// Separador ";" e vírgula decimal, com BOM, para abrir direto no Excel.
  Uint8List toCsv() {
    final b = StringBuffer('﻿');
    b.writeln(_txHeader.map(_csvField).join(';'));
    for (final r in rows) {
      b.writeln(
        [
          Dates.format(r.cashDate),
          Dates.format(r.date),
          r.description,
          r.category,
          r.where,
          r.type.label,
          r.status.label,
          r.amount.formatPlain().replaceAll('.', ''),
          r.tags.join(', '),
          r.notes,
        ].map(_csvField).join(';'),
      );
    }
    return Uint8List.fromList(utf8.encode(b.toString()));
  }

  // PDF ------------------------------------------------------------------------

  /// A fonte padrão do PDF (Helvetica) só desenha Latin-1: troca o separador
  /// de subcategoria e descarta emojis e outros símbolos.
  static String pdfSafe(String s) => s
      .replaceAll('›', '>')
      .replaceAll(RegExp('[‘’]'), "'")
      .replaceAll(RegExp('[“”]'), '"')
      .replaceAll(RegExp('[–—]'), '-')
      .replaceAll('…', '...')
      .replaceAll(RegExp(r'[^\u0000-\u00FF]'), '')
      .trim();

  /// Relatório em PDF: resumo de cada mês, despesas por categoria,
  /// orçamentos e metas.
  Future<Uint8List> toPdf({
    String? userName,
    List<Budget> budgets = const [],
    List<SavingsGoal> goals = const [],
  }) async {
    final doc = pw.Document(title: 'Relatório financeiro - $periodLabel');
    final primary = PdfColor.fromInt(0xFF2457D6);
    final grey = PdfColor.fromInt(0xFF6B7280);
    String brl(Money m) => m.format().replaceAll(' ', ' ');
    final be = BudgetEngine(engine);

    pw.Widget table(
      List<String> head,
      List<List<String>> body, {
      int numericFrom = 1,
    }) => pw.TableHelper.fromTextArray(
      headers: head,
      data: [
        for (final row in body) [for (final c in row) pdfSafe(c)],
      ],
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
      ),
      headerDecoration: pw.BoxDecoration(color: primary),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignments: {
        for (var i = numericFrom; i < head.length; i++)
          i: pw.Alignment.centerRight,
      },
      border: null,
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: .5),
        ),
      ),
    );

    final totals = monthly;
    var inc = Money.zero, exp = Money.zero;
    for (final m in totals) {
      inc += m.income;
      exp += m.expenses;
    }
    final byCat = expensesByCategory;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: grey),
          ),
        ),
        build: (ctx) => [
          pw.Text(
            'Relatório financeiro',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: primary,
            ),
          ),
          pw.Text(
            [
              periodLabel,
              if (userName != null && userName.isNotEmpty) pdfSafe(userName),
              'gerado em ${Dates.format(DateTime.now())}',
            ].join(' · '),
            style: pw.TextStyle(color: grey, fontSize: 10),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              for (final kv in [
                ('Receitas', brl(inc)),
                ('Despesas', brl(exp)),
                ('Resultado', brl(inc - exp)),
              ])
                pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.only(right: 8),
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFEFF3FC),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          kv.$1,
                          style: pw.TextStyle(fontSize: 9, color: grey),
                        ),
                        pw.Text(
                          kv.$2,
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (totals.length > 1) ...[
            pw.SizedBox(height: 18),
            pw.Text('Resumo por mês', style: pw.TextStyle(fontSize: 13)),
            pw.SizedBox(height: 6),
            table(
              ['Mês', 'Receitas', 'Despesas', 'Resultado'],
              [
                for (final m in totals)
                  [
                    m.month.shortLabel,
                    brl(m.income),
                    brl(m.expenses),
                    brl(m.income - m.expenses),
                  ],
              ],
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Text('Despesas por categoria', style: pw.TextStyle(fontSize: 13)),
          pw.SizedBox(height: 6),
          if (byCat.isEmpty)
            pw.Text('Nenhuma despesa no período.')
          else
            table(
              ['Categoria', 'Total', '% das despesas'],
              [
                for (final c in byCat)
                  [
                    c.category,
                    brl(c.total),
                    exp.cents == 0
                        ? '-'
                        : '${(c.total.cents * 100 / exp.cents).toStringAsFixed(1).replaceAll('.', ',')}%',
                  ],
              ],
            ),
          if (budgets.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Orçamentos de ${to.longLabel}',
              style: pw.TextStyle(fontSize: 13),
            ),
            pw.SizedBox(height: 6),
            table(
              ['Categoria', 'Limite', 'Gasto', 'Previsto', 'Uso'],
              [
                for (final s in be.statuses(budgets, to))
                  [
                    engine.categoryLabel(s.budget.categoryId),
                    brl(s.budget.amount),
                    brl(s.spent),
                    brl(s.planned),
                    '${(s.ratio * 100).round()}%',
                  ],
              ],
            ),
          ],
          if (goals.where((g) => !g.archived).isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text('Metas de economia', style: pw.TextStyle(fontSize: 13)),
            pw.SizedBox(height: 6),
            table(
              ['Meta', 'Valor', 'Guardado', 'Prazo', 'Por mês'],
              [
                for (final g in goals.where((g) => !g.archived))
                  () {
                    final s = be.goal(g);
                    return [
                      g.name,
                      brl(g.target),
                      brl(s.saved),
                      g.deadline == null ? '-' : Dates.format(g.deadline!),
                      s.monthlyNeeded == null ? '-' : brl(s.monthlyNeeded!),
                    ];
                  }(),
              ],
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Text(
            'Lançamentos (${rows.length})',
            style: pw.TextStyle(fontSize: 13),
          ),
          pw.SizedBox(height: 6),
          table(
            ['Data', 'Descrição', 'Categoria', 'Conta/cartão', 'Valor'],
            [
              for (final r in rows)
                [
                  Dates.format(r.cashDate),
                  r.description,
                  r.category,
                  r.where,
                  brl(r.amount),
                ],
            ],
            numericFrom: 4,
          ),
        ],
      ),
    );
    return doc.save();
  }
}
