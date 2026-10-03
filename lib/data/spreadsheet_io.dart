import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

import '../domain/engine/financial_engine.dart';
import '../domain/import/expense_import.dart';
import '../domain/models/entities.dart';

/// Leitura e geração de planilhas (.xlsx e .csv) para a importação de
/// despesas. Código Dart puro: funciona igual na web, Android e iOS.
class SpreadsheetIO {
  SpreadsheetIO._();

  static const templateFileName = 'modelo-importacao-despesas.xlsx';
  static const dataSheet = 'Despesas';
  static const listsSheet = 'Listas';

  /// Lê o arquivo e devolve as linhas da aba de despesas como valores
  /// simples (`String`, `num`, `DateTime`, `bool` ou `null`).
  ///
  /// Em .xlsx usa a aba "Despesas" ou, na falta dela, a primeira aba cujo
  /// cabeçalho seja reconhecido.
  static List<List<Object?>> readTable(Uint8List bytes, String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.csv') || name.endsWith('.txt')) {
      return parseCsv(_decodeText(bytes));
    }
    if (name.endsWith('.xls')) {
      throw const FormatException(
        'Arquivos .xls (Excel 97-2003) não são suportados. Salve como .xlsx.',
      );
    }
    final Map<String, List<List<Object?>>> sheets;
    try {
      sheets = XlsxReader.read(bytes);
    } catch (_) {
      throw const FormatException(
        'Não foi possível ler a planilha. Verifique se o arquivo é .xlsx.',
      );
    }
    final ordered = [
      if (sheets.containsKey(dataSheet)) dataSheet,
      ...sheets.keys.where((k) => k != dataSheet && k != listsSheet),
    ];
    List<List<Object?>>? first;
    for (final sheetName in ordered) {
      final rows = sheets[sheetName]!;
      first ??= rows;
      if (ExpenseSheetParser.parse(rows).fatalError == null) return rows;
    }
    return first ?? const [];
  }

  static String _decodeText(Uint8List bytes) {
    var b = bytes;
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      b = b.sublist(3);
    }
    try {
      return utf8.decode(b);
    } on FormatException {
      return latin1.decode(b); // CSV salvo pelo Excel em Windows-1252
    }
  }

  /// CSV com separador detectado automaticamente (`;`, `,` ou tab) e
  /// suporte a campos entre aspas.
  static List<List<Object?>> parseCsv(String text) {
    final firstLine = text.split(RegExp(r'\r?\n')).first;
    final sep = [';', '\t', ',']
        .map((s) => (s, s.allMatches(firstLine).length))
        .reduce((a, b) => b.$2 > a.$2 ? b : a)
        .$1;
    final rows = <List<Object?>>[];
    var row = <Object?>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == sep) {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <Object?>[];
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

  // ---------------------------------------------------------------------------
  // Modelo

  static final _headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('#FF2457D6'),
    verticalAlign: VerticalAlign.Center,
  );
  static final _optionalHeaderStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#FF1B2A4A'),
    backgroundColorHex: ExcelColor.fromHexString('#FFDCE6FB'),
    verticalAlign: VerticalAlign.Center,
  );
  static final _titleStyle = CellStyle(bold: true, fontSize: 14);
  static final _boldStyle = CellStyle(bold: true);
  static final _dateStyle = CellStyle(
    numberFormat: const CustomDateTimeNumFormat(formatCode: 'dd/mm/yyyy'),
  );
  static final _moneyStyle = CellStyle(
    numberFormat: const CustomNumericNumFormat(formatCode: '#,##0.00'),
  );

  static const _widths = [
    12.0,
    34.0,
    12.0,
    26.0,
    22.0,
    22.0,
    10.0,
    20.0,
    13.0,
    34.0,
  ];

  /// Gera o modelo de importação. As abas "Listas" e as listas suspensas
  /// trazem os cadastros do próprio usuário ([data]).
  static Uint8List buildTemplate(FinanceData data, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final book = Excel.createExcel();
    final defaultName = book.getDefaultSheet()!;
    book.rename(defaultName, dataSheet);

    // Aba Despesas: só o cabeçalho.
    final sheet = book[dataSheet];
    _writeHeader(sheet);

    // Aba Exemplo
    final ex = book['Exemplo'];
    _writeHeader(ex);
    final cats = _categoryNames(data);
    String cat(String preferred) => cats.contains(preferred)
        ? preferred
        : (cats.isNotEmpty ? cats.first : '');
    final account =
        data.accounts.where((a) => a.active).firstOrNull?.name ??
        'Conta corrente';
    final card =
        data.cards.where((c) => c.active).firstOrNull?.name ??
        'Cartão principal';
    final d = DateTime(now.year, now.month, 1);
    final examples = <List<Object?>>[
      [
        d,
        'Supermercado',
        412.37,
        cat('Alimentação > Mercado'),
        '',
        card,
        null,
        '',
        'Concluída',
        '',
      ],
      [
        d.add(const Duration(days: 4)),
        'Conta de luz',
        189.90,
        cat('Moradia > Energia'),
        account,
        '',
        null,
        '',
        'Pendente',
        'Vencimento dia 10',
      ],
      [
        d.add(const Duration(days: 9)),
        'Notebook',
        4800.00,
        cat('Compras'),
        '',
        card,
        10,
        '',
        '',
        'Valor total; o app divide em 10 parcelas',
      ],
      [
        d.add(const Duration(days: 12)),
        'Farmácia',
        56.80,
        cat('Saúde'),
        account,
        '',
        null,
        '',
        '',
        '',
      ],
    ];
    for (var r = 0; r < examples.length; r++) {
      for (var c = 0; c < examples[r].length; c++) {
        _put(ex, c, r + 1, examples[r][c]);
      }
    }

    // Aba Instruções
    final help = book['Instruções'];
    help.setColumnWidth(0, 18);
    help.setColumnWidth(1, 14);
    help.setColumnWidth(2, 90);
    var row = 0;
    void line(List<Object?> cells, [CellStyle? style]) {
      for (var c = 0; c < cells.length; c++) {
        _put(help, c, row, cells[c], style);
      }
      row++;
    }

    line(['Importação de despesas em massa'], _titleStyle);
    line([
      'Preencha a aba "Despesas" (uma despesa por linha, a partir da linha 2) '
          'e importe em Mais > Importar despesas.',
    ]);
    line([
      'Você confere tudo antes de gravar: linhas com erro são apontadas e '
          'possíveis duplicadas vêm desmarcadas.',
    ]);
    line([]);
    line(['Coluna', 'Obrigatória', 'Como preencher'], _boldStyle);
    const desc = {
      ImportColumn.date: 'Data da compra/pagamento, no formato dd/mm/aaaa. No cartão, a fatura é definida pelo fechamento do cartão.',
      ImportColumn.description: 'Texto livre. Ex.: Supermercado, Conta de luz.',
      ImportColumn.amount: 'Valor em reais, ex.: 1234,56. Negativos são aceitos (o sinal é ignorado). Se for parcelado, informe o valor TOTAL da compra.',
      ImportColumn.category: 'Nome da categoria ou "Categoria > Subcategoria" (veja a aba Listas). Se não existir, será criada (opção na tela de importação). Vazio = Outras despesas.',
      ImportColumn.account: 'Nome da conta, exatamente como cadastrada no app. Preencha Conta OU Cartão. Se ambos ficarem vazios, é usada a conta padrão escolhida na importação.',
      ImportColumn.card:
          'Nome do cartão (ou os 4 últimos dígitos), como cadastrado no app.',
      ImportColumn.installments: 'Número de parcelas (2 a 120). Vazio ou 1 = à vista. As parcelas são geradas como em uma compra parcelada.',
      ImportColumn.project: 'Nome de um projeto existente (opcional).',
      ImportColumn.status: 'Concluída, Pendente, Planejada ou Cancelada. Vazio = Concluída (ou Planejada se a data for futura, em conta).',
      ImportColumn.notes: 'Texto livre (opcional).',
    };
    for (final c in ImportColumn.values) {
      line([c.header, c.required ? 'Sim' : 'Não', desc[c]]);
    }
    line([]);
    line(['Dicas'], _boldStyle);
    line([
      'Não altere os nomes das colunas. A ordem pode mudar e colunas extras são ignoradas.',
    ]);
    line([
      'Também é possível importar um arquivo .csv com as mesmas colunas (separado por ; ou ,).',
    ]);
    line([
      'Importar o mesmo arquivo duas vezes não duplica: lançamentos iguais (data, valor e descrição) vêm desmarcados.',
    ]);

    // Aba Listas
    final lists = book[listsSheet];
    final columns = <String, List<String>>{
      'Categorias': cats,
      'Contas': [
        for (final a in data.accounts)
          if (a.active) a.name,
      ],
      'Cartões': [
        for (final c in data.cards)
          if (c.active) c.name,
      ],
      'Projetos': [
        for (final p in data.projects)
          if (!p.archived) p.name,
      ],
      'Status': [for (final s in TransactionStatus.values) s.label],
    };
    var col = 0;
    for (final e in columns.entries) {
      _put(lists, col, 0, e.key, _headerStyle);
      for (var i = 0; i < e.value.length; i++) {
        _put(lists, col, i + 1, e.value[i]);
      }
      lists.setColumnWidth(col, 30);
      col++;
    }

    book.setDefaultSheet(dataSheet);
    final bytes = Uint8List.fromList(book.encode()!);
    return _addValidations(bytes, {
      ImportColumn.category: _listRef('A', columns['Categorias']!.length),
      ImportColumn.account: _listRef('B', columns['Contas']!.length),
      ImportColumn.card: _listRef('C', columns['Cartões']!.length),
      ImportColumn.project: _listRef('D', columns['Projetos']!.length),
      ImportColumn.status: _listRef('E', columns['Status']!.length),
    });
  }

  static String? _listRef(String col, int count) =>
      count == 0 ? null : '$listsSheet!\$$col\$2:\$$col\$${count + 1}';

  /// Categorias de despesa no formato usado na planilha.
  static List<String> _categoryNames(FinanceData data) {
    final out = <String>[];
    final expense = data.categories
        .where((c) => c.kind == CategoryKind.expense)
        .toList();
    for (final parent in expense.where((c) => c.parentId == null)) {
      out.add(parent.name);
      for (final child in expense.where((c) => c.parentId == parent.id)) {
        out.add('${parent.name} > ${child.name}');
      }
    }
    // Subcategorias órfãs (pai removido ou de outro tipo).
    for (final c in expense) {
      if (c.parentId != null &&
          !expense.any((p) => p.id == c.parentId && p.parentId == null)) {
        out.add(c.name);
      }
    }
    return out;
  }

  static void _writeHeader(Sheet sheet) {
    for (final c in ImportColumn.values) {
      _put(
        sheet,
        c.index,
        0,
        c.header,
        c.required ? _headerStyle : _optionalHeaderStyle,
      );
      sheet.setColumnWidth(c.index, _widths[c.index]);
    }
    sheet.setRowHeight(0, 22);
  }

  static void _put(
    Sheet sheet,
    int col,
    int row,
    Object? value, [
    CellStyle? style,
  ]) {
    final CellValue? v = switch (value) {
      null || '' => null,
      DateTime d => DateCellValue.fromDateTime(d),
      int i => IntCellValue(i),
      double x => DoubleCellValue(x),
      _ => TextCellValue('$value'),
    };
    if (v == null && style == null) return;
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      v,
      cellStyle:
          style ??
          switch (value) {
            DateTime() => _dateStyle,
            double() => _moneyStyle,
            _ => null,
          },
    );
  }

  /// O pacote `excel` não gera validação de dados; inserimos as listas
  /// suspensas diretamente no XML da aba "Despesas".
  static Uint8List _addValidations(
    Uint8List xlsx,
    Map<ImportColumn, String?> refs,
  ) {
    try {
      final archive = ZipDecoder().decodeBytes(xlsx);
      final sheetPath = _sheetPath(archive, dataSheet);
      final file = sheetPath == null ? null : archive.findFile(sheetPath);
      if (file == null) return xlsx;
      var xml = utf8.decode(file.content as List<int>);
      if (xml.contains('<dataValidations')) return xlsx;
      final entries = refs.entries.where((e) => e.value != null).toList();
      if (entries.isEmpty) return xlsx;
      String colLetter(int i) => String.fromCharCode(65 + i);
      final dv = StringBuffer('<dataValidations count="${entries.length}">');
      for (final e in entries) {
        final l = colLetter(e.key.index);
        // Categoria aceita nomes novos (aviso); as demais exigem item da lista.
        final style = e.key == ImportColumn.category ? 'warning' : 'stop';
        dv.write(
          '<dataValidation type="list" allowBlank="1" showErrorMessage="1" '
          'errorStyle="$style" errorTitle="${e.key.header}" '
          'error="Escolha um item da aba Listas." '
          'sqref="${l}2:${l}5000"><formula1>${e.value}</formula1>'
          '</dataValidation>',
        );
      }
      dv.write('</dataValidations>');
      // Ordem do schema: dataValidations vem depois de sheetData/mergeCells/
      // conditionalFormatting e antes de hyperlinks/printOptions/pageMargins.
      final anchors = [
        '<hyperlinks',
        '<printOptions',
        '<pageMargins',
        '<pageSetup',
        '<headerFooter',
        '<drawing',
        '<legacyDrawing',
        '<tableParts',
        '<extLst',
        '</worksheet>',
      ];
      final at = anchors
          .map(xml.indexOf)
          .where((i) => i >= 0)
          .fold<int>(-1, (a, b) => a < 0 || b < a ? b : a);
      if (at < 0) return xlsx;
      xml = xml.substring(0, at) + dv.toString() + xml.substring(at);

      final out = Archive();
      for (final f in archive.files) {
        if (f.name == sheetPath) {
          final data = utf8.encode(xml);
          out.addFile(ArchiveFile(f.name, data.length, data));
        } else {
          out.addFile(f);
        }
      }
      return Uint8List.fromList(ZipEncoder().encode(out)!);
    } catch (_) {
      return xlsx; // sem listas suspensas, mas o modelo continua válido
    }
  }

  static String? _sheetPath(Archive archive, String sheetName) {
    final wb = archive.findFile('xl/workbook.xml');
    final rels = archive.findFile('xl/_rels/workbook.xml.rels');
    if (wb == null || rels == null) return null;
    final wbXml = utf8.decode(wb.content as List<int>);
    final relsXml = utf8.decode(rels.content as List<int>);
    final sheetTag = RegExp(
      '<sheet [^>]*name="${RegExp.escape(sheetName)}"[^>]*>',
    ).firstMatch(wbXml)?.group(0);
    final rid = sheetTag == null
        ? null
        : RegExp(r'r:id="([^"]+)"').firstMatch(sheetTag)?.group(1);
    if (rid == null) return null;
    final rel = RegExp('<Relationship [^>]*Id="${RegExp.escape(rid)}"[^>]*>')
        .firstMatch(relsXml)
        ?.group(0);
    final target = rel == null
        ? null
        : RegExp(r'Target="([^"]+)"').firstMatch(rel)?.group(1);
    if (target == null) return null;
    return target.startsWith('/') ? target.substring(1) : 'xl/$target';
  }
}

/// Leitor mínimo de .xlsx (Office Open XML).
///
/// Lemos o XML diretamente em vez de usar o pacote `excel`, que falha com
/// arquivos válidos gerados por outras ferramentas (ex.: caminhos absolutos
/// nas relações). Devolvemos textos, números e booleanos; datas chegam como
/// número serial e são convertidas por [ExpenseSheetParser.parseDate].
class XlsxReader {
  XlsxReader._();

  static const _relNs =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  /// Abas na ordem do arquivo → linhas (preenchidas até a última coluna).
  static Map<String, List<List<Object?>>> read(Uint8List bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);
    String? text(String path) {
      final f = zip.findFile(path);
      return f == null ? null : utf8.decode(f.content as List<int>);
    }

    final wb = XmlDocument.parse(text('xl/workbook.xml')!);
    final rels = XmlDocument.parse(
      text('xl/_rels/workbook.xml.rels') ?? '<r/>',
    );
    final targets = <String, String>{
      for (final r in rels.findAllElements('Relationship'))
        r.getAttribute('Id')!: r.getAttribute('Target')!,
    };

    final shared = <String>[];
    final ss = text('xl/sharedStrings.xml');
    if (ss != null) {
      for (final si in XmlDocument.parse(ss).findAllElements('si')) {
        shared.add(_runText(si));
      }
    }

    final out = <String, List<List<Object?>>>{};
    for (final sheet in wb.findAllElements('sheet')) {
      final name = sheet.getAttribute('name') ?? 'Planilha';
      final rid =
          sheet.getAttribute('id', namespace: _relNs) ??
          sheet.getAttribute('r:id');
      var target = targets[rid];
      if (target == null) continue;
      target = target.startsWith('/')
          ? target.substring(1)
          : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
      final xml = text(target);
      if (xml == null) continue;
      out[name] = _rows(XmlDocument.parse(xml), shared);
    }
    return out;
  }

  static String _runText(XmlElement e) =>
      e.findAllElements('t').map((t) => t.innerText).join();

  static List<List<Object?>> _rows(XmlDocument doc, List<String> shared) {
    final rows = <List<Object?>>[];
    var nextRow = 0;
    for (final row in doc.findAllElements('row')) {
      final r = int.tryParse(row.getAttribute('r') ?? '');
      final rowIdx = r != null ? r - 1 : nextRow;
      nextRow = rowIdx + 1;
      if (rowIdx >= 20000) break;
      while (rows.length <= rowIdx) {
        rows.add([]);
      }
      final cells = rows[rowIdx];
      var nextCol = 0;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? nextCol : _colIndex(ref);
        nextCol = col + 1;
        if (col > 200) continue;
        final value = _cellValue(c, shared);
        if (value == null) continue;
        while (cells.length <= col) {
          cells.add(null);
        }
        cells[col] = value;
      }
    }
    return rows;
  }

  static int _colIndex(String ref) {
    var n = 0;
    for (final ch in ref.codeUnits) {
      if (ch < 65 || ch > 90) break; // até o primeiro dígito
      n = n * 26 + (ch - 64);
    }
    return n - 1;
  }

  static Object? _cellValue(XmlElement c, List<String> shared) {
    final type = c.getAttribute('t');
    final v = c.getElement('v')?.innerText;
    switch (type) {
      case 's':
        final i = int.tryParse(v ?? '');
        return i != null && i < shared.length ? shared[i] : null;
      case 'inlineStr':
        final isEl = c.getElement('is');
        return isEl == null ? null : _runText(isEl);
      case 'str':
        return v;
      case 'b':
        return v == '1';
      case 'e':
        return null;
      case 'd':
        return v == null ? null : DateTime.tryParse(v);
      default:
        if (v == null || v.isEmpty) return null;
        final n = num.tryParse(v);
        if (n == null) return v;
        return n is double && n == n.roundToDouble() && n.abs() < 1e15
            ? n.toInt()
            : n;
    }
  }
}
