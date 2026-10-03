import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../engine/financial_engine.dart';
import '../engine/installments.dart';
import '../models/entities.dart';

/// Importação de despesas em massa a partir de uma planilha.
///
/// O fluxo é dividido em três etapas, todas puras (sem I/O), para que
/// possam ser testadas isoladamente:
///
/// 1. [ExpenseSheetParser.parse] recebe as linhas já lidas do arquivo
///    (valores de célula como `String`, `num`, `DateTime`, `bool` ou `null`),
///    localiza o cabeçalho e interpreta cada linha;
/// 2. [ExpenseImportPlanner.plan] resolve nomes (categoria, conta, cartão,
///    projeto) contra os cadastros do usuário, valida e marca possíveis
///    duplicidades;
/// 3. [ExpenseImportPlan.build] gera os registros a gravar (categorias
///    novas, compras parceladas e lançamentos).

/// Colunas reconhecidas. A ordem é a do modelo.
enum ImportColumn {
  date('Data', true, ['data', 'data da compra', 'data compra', 'dt']),
  description('Descrição', true, [
    'descricao',
    'historico',
    'estabelecimento',
    'lancamento',
  ]),
  amount('Valor', true, ['valor', 'valor (r\$)', 'valor r\$', 'valor total']),
  category('Categoria', false, ['categoria', 'subcategoria']),
  account('Conta', false, ['conta', 'conta bancaria']),
  card('Cartão', false, ['cartao', 'cartao de credito']),
  installments('Parcelas', false, ['parcelas', 'qtd parcelas', 'parcelado']),
  project('Projeto', false, ['projeto']),
  status('Status', false, ['status', 'situacao']),
  notes('Observações', false, ['observacoes', 'observacao', 'obs', 'notas']);

  final String header;
  final bool required;
  final List<String> aliases;
  const ImportColumn(this.header, this.required, this.aliases);
}

/// Normaliza textos para comparação: minúsculas, sem acentos e com espaços
/// simples.
String normalizeKey(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().trim().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Uma linha da planilha já interpretada (ainda sem vínculo com cadastros).
class ExpenseSheetRow {
  /// Número da linha no arquivo (1 = primeira linha), para mensagens.
  final int line;
  final DateTime? date;
  final String description;
  final Money? amount;
  final String category;
  final String account;
  final String card;
  final int installments;
  final String project;
  final TransactionStatus? status;
  final String notes;

  /// Problemas de formato encontrados ao ler a linha.
  final List<String> errors;

  const ExpenseSheetRow({
    required this.line,
    this.date,
    this.description = '',
    this.amount,
    this.category = '',
    this.account = '',
    this.card = '',
    this.installments = 1,
    this.project = '',
    this.status,
    this.notes = '',
    this.errors = const [],
  });
}

class ExpenseSheetParseResult {
  final List<ExpenseSheetRow> rows;

  /// Erro que impede a leitura do arquivo inteiro (ex.: sem cabeçalho).
  final String? fatalError;

  /// Colunas do arquivo que não foram reconhecidas (apenas informativo).
  final List<String> ignoredColumns;

  const ExpenseSheetParseResult({
    this.rows = const [],
    this.fatalError,
    this.ignoredColumns = const [],
  });
}

class ExpenseSheetParser {
  ExpenseSheetParser._();

  /// Linhas além deste limite são recusadas (proteção de memória/tempo).
  static const maxRows = 5000;

  static ImportColumn? _columnFor(Object? cell) {
    if (cell == null) return null;
    var key = normalizeKey('$cell').replaceAll('*', '').trim();
    if (key.isEmpty) return null;
    for (final c in ImportColumn.values) {
      if (normalizeKey(c.header) == key || c.aliases.contains(key)) return c;
    }
    return null;
  }

  static ExpenseSheetParseResult parse(List<List<Object?>> table) {
    // Cabeçalho: primeira linha (entre as 15 primeiras) que contenha as
    // colunas obrigatórias.
    int? headerIdx;
    Map<ImportColumn, int> cols = {};
    final ignored = <String>[];
    for (var i = 0; i < table.length && i < 15; i++) {
      final found = <ImportColumn, int>{};
      final unknown = <String>[];
      final row = table[i];
      for (var c = 0; c < row.length; c++) {
        final col = _columnFor(row[c]);
        if (col != null) {
          found.putIfAbsent(col, () => c);
        } else if (row[c] != null && '${row[c]}'.trim().isNotEmpty) {
          unknown.add('${row[c]}'.trim());
        }
      }
      if (ImportColumn.values
          .where((c) => c.required)
          .every(found.containsKey)) {
        headerIdx = i;
        cols = found;
        ignored.addAll(unknown);
        break;
      }
    }
    if (headerIdx == null) {
      return const ExpenseSheetParseResult(
        fatalError:
            'Não encontramos o cabeçalho com as colunas Data, Descrição e '
            'Valor. Use o modelo de importação.',
      );
    }

    final rows = <ExpenseSheetRow>[];
    for (var i = headerIdx + 1; i < table.length; i++) {
      final raw = table[i];
      Object? cell(ImportColumn c) {
        final idx = cols[c];
        if (idx == null || idx >= raw.length) return null;
        final v = raw[idx];
        if (v is String && v.trim().isEmpty) return null;
        return v;
      }

      if (cols.values.every((idx) => idx >= raw.length || _blank(raw[idx]))) {
        continue; // linha vazia
      }
      if (rows.length >= maxRows) {
        return ExpenseSheetParseResult(
          fatalError:
              'O arquivo tem mais de $maxRows linhas. Divida-o em arquivos '
              'menores.',
        );
      }
      final errors = <String>[];

      final dateCell = cell(ImportColumn.date);
      final date = parseDate(dateCell);
      if (dateCell == null) {
        errors.add('Data não informada');
      } else if (date == null) {
        errors.add('Data inválida: "$dateCell" (use dd/mm/aaaa)');
      }

      final description = _text(cell(ImportColumn.description));
      if (description.isEmpty) errors.add('Descrição não informada');

      final amountCell = cell(ImportColumn.amount);
      var amount = parseAmount(amountCell);
      if (amountCell == null) {
        errors.add('Valor não informado');
      } else if (amount == null) {
        errors.add('Valor inválido: "$amountCell"');
      } else {
        // Extratos costumam trazer despesas negativas: usamos o módulo.
        amount = amount.abs();
        if (amount.isZero) errors.add('O valor deve ser maior que zero');
      }

      var installments = 1;
      final instCell = cell(ImportColumn.installments);
      if (instCell != null) {
        final n = parseInstallments(instCell);
        if (n == null) {
          errors.add(
            'Parcelas inválidas: "$instCell" (use um número de 1 a 120)',
          );
        } else {
          installments = n;
        }
      }

      TransactionStatus? status;
      final statusCell = cell(ImportColumn.status);
      if (statusCell != null) {
        status = parseStatus(statusCell);
        if (status == null) {
          errors.add(
            'Status inválido: "$statusCell" (use Concluída, Pendente, '
            'Planejada ou Cancelada)',
          );
        }
      }

      rows.add(
        ExpenseSheetRow(
          line: i + 1,
          date: date,
          description: description,
          amount: amount,
          category: _text(cell(ImportColumn.category)),
          account: _text(cell(ImportColumn.account)),
          card: _text(cell(ImportColumn.card)),
          installments: installments,
          project: _text(cell(ImportColumn.project)),
          status: status,
          notes: _text(cell(ImportColumn.notes)),
          errors: errors,
        ),
      );
    }
    return ExpenseSheetParseResult(rows: rows, ignoredColumns: ignored);
  }

  static bool _blank(Object? v) => v == null || '$v'.trim().isEmpty;

  static String _text(Object? v) {
    if (v == null) return '';
    if (v is double && v == v.roundToDouble()) return v.toInt().toString();
    return '$v'.trim();
  }

  /// Datas: `DateTime` da célula, número serial do Excel, "dd/mm/aaaa",
  /// "dd/mm/aa", "dd-mm-aaaa" ou ISO "aaaa-mm-dd".
  static DateTime? parseDate(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return Dates.dateOnly(v);
    if (v is num) {
      // Número serial do Excel (dias desde 30/12/1899). Faixa: 1955–2119.
      if (v < 20000 || v > 80000) return null;
      return Dates.dateOnly(
        DateTime(1899, 12, 30).add(Duration(days: v.floor())),
      );
    }
    final s = '$v'.trim();
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (iso != null) {
      return _valid(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final br = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2}|\d{4})(?:\s.*)?$')
        .firstMatch(s);
    if (br != null) {
      var year = int.parse(br.group(3)!);
      if (year < 100) year += 2000;
      return _valid(year, int.parse(br.group(2)!), int.parse(br.group(1)!));
    }
    final serial = num.tryParse(s);
    return serial == null ? null : parseDate(serial);
  }

  static DateTime? _valid(int y, int m, int d) {
    if (y < 1900 || y > 2200 || m < 1 || m > 12) return null;
    if (d < 1 || d > Dates.daysInMonth(y, m)) return null;
    return DateTime(y, m, d);
  }

  /// Valores: número da célula ou texto no padrão brasileiro
  /// ("1.234,56", "R$ 55,90", "-10"). Aceita também "1234.56".
  static Money? parseAmount(Object? v) {
    if (v == null) return null;
    if (v is int) return Money(v * 100);
    if (v is double) {
      if (v.isNaN || v.isInfinite) return null;
      return Money((v * 100).round());
    }
    var s = '$v'.trim();
    // "(10,00)" = negativo em alguns extratos.
    if (s.startsWith('(') && s.endsWith(')')) {
      s = '-${s.substring(1, s.length - 1)}';
    }
    final direct = Money.tryParse(s);
    if (direct != null) return direct;
    // Formato com ponto decimal (ex.: "1234.56" ou "-R$ 1,234.56").
    final m = RegExp(
      r'^(-?)\s*(?:R\$)?\s*(-?)(\d{1,3}(?:,\d{3})+|\d+)\.(\d{1,2})$',
    ).firstMatch(s);
    if (m != null) {
      final reais = int.parse(m.group(3)!.replaceAll(',', ''));
      final cents = reais * 100 + int.parse(m.group(4)!.padRight(2, '0'));
      final neg = m.group(1)!.isNotEmpty || m.group(2)!.isNotEmpty;
      return Money(neg ? -cents : cents);
    }
    return null;
  }

  /// "3", "3x", "3 x", 3, 3.0. 1 = à vista.
  static int? parseInstallments(Object? v) {
    if (v == null) return 1;
    int? n;
    if (v is num) {
      if (v != v.roundToDouble()) return null;
      n = v.toInt();
    } else {
      final m = RegExp(r'^(\d{1,3})\s*x?$').firstMatch(normalizeKey('$v'));
      n = m == null ? null : int.parse(m.group(1)!);
    }
    if (n == null || n < 1 || n > 120) return null;
    return n;
  }

  static TransactionStatus? parseStatus(Object? v) {
    final k = normalizeKey('$v');
    switch (k) {
      case 'concluida' || 'concluido' || 'paga' || 'pago' || 'ok' || 'sim':
        return TransactionStatus.completed;
      case 'pendente' || 'a pagar' || 'em aberto' || 'aberto' || 'nao':
        return TransactionStatus.pending;
      case 'planejada' || 'planejado' || 'prevista' || 'previsto':
        return TransactionStatus.planned;
      case 'cancelada' || 'cancelado':
        return TransactionStatus.cancelled;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Planejamento (vínculo com cadastros + validação)

/// Uma linha pronta para conferência na tela de prévia.
class ExpenseImportItem {
  final ExpenseSheetRow row;
  final String? categoryId;

  /// Nome da categoria que será criada (quando não existe no cadastro).
  final String? newCategoryName;
  final String? accountId;
  final String? cardId;
  final String? projectId;
  final TransactionStatus status;
  final List<String> errors;
  final List<String> warnings;

  /// Já existe lançamento com mesma data, valor e descrição.
  final bool possibleDuplicate;

  /// Se a linha será importada (o usuário pode desmarcar).
  bool selected;

  ExpenseImportItem({
    required this.row,
    this.categoryId,
    this.newCategoryName,
    this.accountId,
    this.cardId,
    this.projectId,
    required this.status,
    this.errors = const [],
    this.warnings = const [],
    this.possibleDuplicate = false,
  }) : selected = errors.isEmpty && !possibleDuplicate;

  bool get isValid => errors.isEmpty;
  bool get isInstallment => row.installments > 1;
}

class ExpenseImportOptions {
  /// Conta usada nas linhas sem conta e sem cartão.
  final String? defaultAccountId;

  /// Cria categorias de despesa que não existem no cadastro. Se `false`,
  /// essas linhas vão para "Outras despesas".
  final bool createMissingCategories;

  const ExpenseImportOptions({
    this.defaultAccountId,
    this.createMissingCategories = true,
  });
}

class ExpenseImportPlanner {
  ExpenseImportPlanner._();

  /// Chave de categoria: "Pai > Filho", "Pai/Filho" e "Pai - Filho" são
  /// equivalentes.
  static String _catKey(String s) =>
      normalizeKey(s).replaceAll(RegExp(r'\s*[>/:]\s*|\s+-\s+'), '>');

  static const fallbackCategoryId = 'cat_other_expense';

  static ExpenseImportPlan plan(
    List<ExpenseSheetRow> rows,
    FinanceData data,
    ExpenseImportOptions options, {
    DateTime? today,
  }) {
    final now = Dates.dateOnly(today ?? DateTime.now());

    // Índices de busca por nome normalizado.
    final expenseCats = data.categories
        .where((c) => c.kind == CategoryKind.expense)
        .toList();
    final catByName = <String, FinCategory>{};
    for (final c in expenseCats) {
      final parent = data.categoryById[c.parentId];
      if (parent != null) {
        catByName.putIfAbsent(_catKey('${parent.name} > ${c.name}'), () => c);
      }
    }
    // Nome simples: categorias principais têm prioridade sobre subcategorias
    // homônimas.
    for (final c in [
      ...expenseCats.where((c) => c.parentId == null),
      ...expenseCats.where((c) => c.parentId != null),
    ]) {
      catByName.putIfAbsent(_catKey(c.name), () => c);
    }

    final accByName = {for (final a in data.accounts) normalizeKey(a.name): a};
    final cardByName = <String, CreditCard>{};
    for (final c in data.cards) {
      cardByName[normalizeKey(c.name)] = c;
      if (c.lastFour.isNotEmpty) {
        cardByName.putIfAbsent(c.lastFour, () => c);
        cardByName.putIfAbsent(
          normalizeKey('${c.name} (${c.lastFour})'),
          () => c,
        );
        cardByName.putIfAbsent(
          normalizeKey('${c.name} ${c.lastFour}'),
          () => c,
        );
      }
    }
    final projByName = {for (final p in data.projects) normalizeKey(p.name): p};

    // Chaves de duplicidade dos lançamentos existentes.
    String dupKey(DateTime d, Money m, String desc) =>
        '${Dates.toIso(d)}|${m.cents}|${normalizeKey(desc)}';
    final existing = <String>{
      for (final t in data.transactions)
        if (t.type == TransactionType.expense &&
            t.status != TransactionStatus.cancelled &&
            t.installmentGroupId == null)
          dupKey(t.date, t.amount, t.description),
      for (final g in data.installmentGroups)
        dupKey(g.purchaseDate, g.totalAmount, g.description),
    };

    final hasFallback = data.categoryById.containsKey(fallbackCategoryId);
    final defaultAccount = data.accountById[options.defaultAccountId];

    final items = <ExpenseImportItem>[];
    for (final r in rows) {
      final errors = [...r.errors];
      final warnings = <String>[];

      // Categoria
      String? categoryId;
      String? newCategoryName;
      if (r.category.isEmpty) {
        categoryId = hasFallback ? fallbackCategoryId : null;
      } else {
        final c = catByName[_catKey(r.category)];
        if (c != null) {
          categoryId = c.id;
        } else if (options.createMissingCategories) {
          newCategoryName = r.category.trim();
        } else {
          categoryId = hasFallback ? fallbackCategoryId : null;
          warnings.add(
            'Categoria "${r.category}" não existe: será usada '
            '"Outras despesas"',
          );
        }
      }

      // Conta / cartão
      String? accountId;
      String? cardId;
      if (r.account.isNotEmpty && r.card.isNotEmpty) {
        errors.add('Informe conta ou cartão, não ambos');
      } else if (r.card.isNotEmpty) {
        final c = cardByName[normalizeKey(r.card)];
        if (c == null) {
          errors.add('Cartão "${r.card}" não encontrado');
        } else {
          cardId = c.id;
          if (!c.active) warnings.add('Cartão "${c.name}" está inativo');
        }
      } else if (r.account.isNotEmpty) {
        final a = accByName[normalizeKey(r.account)];
        if (a == null) {
          errors.add('Conta "${r.account}" não encontrada');
        } else {
          accountId = a.id;
          if (!a.active) warnings.add('Conta "${a.name}" está inativa');
        }
      } else if (defaultAccount != null) {
        accountId = defaultAccount.id;
      } else {
        errors.add('Sem conta ou cartão (escolha uma conta padrão)');
      }

      // Projeto
      String? projectId;
      if (r.project.isNotEmpty) {
        projectId = projByName[normalizeKey(r.project)]?.id;
        if (projectId == null) {
          warnings.add('Projeto "${r.project}" não encontrado: ignorado');
        }
      }

      // Status: o mesmo padrão do formulário (futuro = planejada).
      final status =
          r.status ??
          (r.date != null && r.date!.isAfter(now) && cardId == null
              ? TransactionStatus.planned
              : TransactionStatus.completed);

      if (r.installments > 1 &&
          r.amount != null &&
          r.amount!.cents < r.installments) {
        errors.add('Valor insuficiente para ${r.installments} parcelas');
      }

      final dup =
          errors.isEmpty &&
          existing.contains(dupKey(r.date!, r.amount!, r.description));
      if (dup) {
        warnings.add('Possível duplicada: já existe lançamento igual');
      }

      items.add(
        ExpenseImportItem(
          row: r,
          categoryId: categoryId,
          newCategoryName: newCategoryName,
          accountId: accountId,
          cardId: cardId,
          projectId: projectId,
          status: status,
          errors: errors,
          warnings: warnings,
          possibleDuplicate: dup,
        ),
      );
    }
    return ExpenseImportPlan(items);
  }
}

/// Registros gerados por uma importação.
class ExpenseImportBatch {
  final List<FinCategory> categories;
  final List<InstallmentGroup> groups;
  final List<FinTransaction> transactions;

  /// Quantidade de linhas da planilha importadas.
  final int rowCount;

  const ExpenseImportBatch({
    this.categories = const [],
    this.groups = const [],
    this.transactions = const [],
    this.rowCount = 0,
  });
}

class ExpenseImportPlan {
  final List<ExpenseImportItem> items;
  ExpenseImportPlan(this.items);

  Iterable<ExpenseImportItem> get valid => items.where((i) => i.isValid);
  Iterable<ExpenseImportItem> get invalid => items.where((i) => !i.isValid);
  Iterable<ExpenseImportItem> get selected =>
      items.where((i) => i.isValid && i.selected);
  Iterable<ExpenseImportItem> get duplicates =>
      items.where((i) => i.possibleDuplicate);

  Money get selectedTotal => selected.map((i) => i.row.amount!).sum();

  /// Nomes das categorias que serão criadas pelas linhas selecionadas.
  List<String> get newCategoryNames {
    final seen = <String, String>{};
    for (final i in selected) {
      final n = i.newCategoryName;
      if (n != null) seen.putIfAbsent(normalizeKey(n), () => n);
    }
    return seen.values.toList();
  }

  /// Gera categorias novas, compras parceladas e lançamentos das linhas
  /// selecionadas.
  ExpenseImportBatch build({DateTime? today}) {
    final notesSuffix = 'Importado de planilha';
    final newCats = <String, FinCategory>{};
    for (final name in newCategoryNames) {
      newCats[normalizeKey(name)] = FinCategory(
        id: newId('cat_'),
        name: name,
        kind: CategoryKind.expense,
        icon: 'other',
        color: 0xFF64748B,
      );
    }
    final groups = <InstallmentGroup>[];
    final txs = <FinTransaction>[];
    var count = 0;
    for (final i in selected) {
      count++;
      final r = i.row;
      final categoryId = i.newCategoryName != null
          ? newCats[normalizeKey(i.newCategoryName!)]!.id
          : i.categoryId;
      final notes = r.notes.isEmpty ? notesSuffix : '${r.notes}\n$notesSuffix';
      if (i.isInstallment) {
        final g = InstallmentGroup(
          id: newId('ig_'),
          description: r.description,
          totalAmount: r.amount!,
          count: r.installments,
          purchaseDate: r.date!,
          accountId: i.accountId,
          cardId: i.cardId,
          categoryId: categoryId,
          projectId: i.projectId,
          notes: notes,
        );
        groups.add(g);
        txs.addAll(Installments.build(g, firstStatus: i.status, today: today));
      } else {
        txs.add(
          FinTransaction(
            id: newId('tx_'),
            type: TransactionType.expense,
            amount: r.amount!,
            description: r.description,
            categoryId: categoryId,
            date: r.date!,
            accountId: i.accountId,
            cardId: i.cardId,
            projectId: i.projectId,
            notes: notes,
            status: i.status,
          ),
        );
      }
    }
    return ExpenseImportBatch(
      categories: newCats.values.toList(),
      groups: groups,
      transactions: txs,
      rowCount: count,
    );
  }
}
