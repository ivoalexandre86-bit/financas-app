import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../data/spreadsheet_io.dart';
import '../../../domain/import/expense_import.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

enum _RowFilter { all, selected, issues }

/// Importação de despesas em massa a partir de uma planilha (.xlsx/.csv):
/// baixar o modelo → selecionar o arquivo → conferir a prévia → importar.
class ExpenseImportScreen extends StatefulWidget {
  const ExpenseImportScreen({super.key});

  @override
  State<ExpenseImportScreen> createState() => _ExpenseImportScreenState();
}

class _ExpenseImportScreenState extends State<ExpenseImportScreen> {
  String? fileName;
  ExpenseSheetParseResult? parsed;
  ExpenseImportPlan? plan;
  String? defaultAccountId;
  bool createMissingCategories = true;

  /// Seleções feitas pelo usuário (linha → marcada), preservadas quando as
  /// opções mudam e a prévia é recalculada.
  final Map<int, bool> overrides = {};
  _RowFilter filter = _RowFilter.all;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final fc = context.read<FinanceController>();
    defaultAccountId = fc.activeAccounts.firstOrNull?.id;
  }

  void _replan() {
    final p = parsed;
    if (p == null || p.fatalError != null) {
      plan = null;
      return;
    }
    final fc = context.read<FinanceController>();
    final newPlan = ExpenseImportPlanner.plan(
      p.rows,
      fc.data,
      ExpenseImportOptions(
        defaultAccountId: defaultAccountId,
        createMissingCategories: createMissingCategories,
      ),
      today: fc.engine.today,
    );
    for (final i in newPlan.items) {
      final o = overrides[i.row.line];
      if (o != null && i.isValid) i.selected = o;
    }
    plan = newPlan;
  }

  Future<void> _downloadTemplate() async {
    final fc = context.read<FinanceController>();
    setState(() => busy = true);
    try {
      final bytes = SpreadsheetIO.buildTemplate(fc.data);
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Salvar modelo de importação',
        fileName: SpreadsheetIO.templateFileName,
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (mounted && uri != null) showMessage(context, 'Modelo salvo');
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          'Não foi possível salvar o modelo: $e',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickFile() async {
    setState(() => busy = true);
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Selecione a planilha de despesas',
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
      );
      if (file == null) return;
      final bytes = await file.xFile.readAsBytes();
      final rows = SpreadsheetIO.readTable(bytes, file.name);
      overrides.clear();
      filter = _RowFilter.all;
      fileName = file.name;
      parsed = ExpenseSheetParser.parse(rows);
      _replan();
    } on FormatException catch (e) {
      fileName = null;
      parsed = null;
      plan = null;
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          'Não foi possível abrir o arquivo: $e',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _import() async {
    final p = plan;
    if (p == null) return;
    final count = p.selected.length;
    final newCats = p.newCategoryNames;
    final ok = await confirmDialog(
      context,
      title: 'Importar $count ${count == 1 ? 'despesa' : 'despesas'}?',
      message:
          'Total de ${p.selectedTotal.format()}.'
          '${newCats.isEmpty ? '' : '\nCategorias novas: ${newCats.join(', ')}.'}'
          '\nVocê pode editar ou excluir os lançamentos depois.',
      confirm: 'Importar',
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    final fc = context.read<FinanceController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final batch = await fc.importExpenses(p);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${batch.rowCount} ${batch.rowCount == 1 ? 'despesa importada' : 'despesas importadas'}'
            '${batch.groups.isEmpty ? '' : ' (${batch.groups.length} parceladas)'}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showMessage(
          context,
          e is ArgumentError ? '${e.message}' : 'Falha ao importar: $e',
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = plan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar despesas'),
        actions: [
          if (parsed != null)
            IconButton(
              tooltip: 'Escolher outro arquivo',
              icon: const Icon(Icons.upload_file),
              onPressed: busy ? null : _pickFile,
            ),
        ],
        bottom: busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: p == null ? _intro(context) : _preview(context, p),
      bottomNavigationBar: p == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: busy || p.selected.isEmpty ? null : _import,
                  icon: const Icon(Icons.download_done),
                  label: Text(
                    p.selected.isEmpty
                        ? 'Nenhuma despesa selecionada'
                        : 'Importar ${p.selected.length} · ${p.selectedTotal.format()}',
                  ),
                ),
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Passo 1: instruções

  Widget _intro(BuildContext context) {
    final fatal = parsed?.fatalError;
    Widget step(int n, String title, String text, [Widget? action]) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: context.colors.primaryContainer,
            child: Text('$n', style: context.text.labelLarge),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 8), action],
              ],
            ),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (fatal != null) ...[
          _Banner(
            icon: Icons.error_outline,
            color: context.colors.error,
            text: '${fileName ?? 'Arquivo'}: $fatal',
          ),
          const SizedBox(height: 12),
        ],
        SectionCard(
          title: 'Como funciona',
          child: Column(
            children: [
              step(
                1,
                'Baixe o modelo',
                'Planilha .xlsx com listas suspensas das suas categorias, '
                    'contas, cartões e projetos, além de instruções e exemplos.',
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : _downloadTemplate,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Baixar modelo (.xlsx)'),
                  ),
                ),
              ),
              step(
                2,
                'Preencha uma despesa por linha',
                'Na aba "Despesas": Data, Descrição e Valor são obrigatórios. '
                    'Informe Conta ou Cartão; para compras parceladas, o valor '
                    'total e o número de parcelas.',
              ),
              step(
                3,
                'Selecione o arquivo e confira',
                'Aceita .xlsx ou .csv. Você revisa cada linha antes de gravar: '
                    'erros são apontados e possíveis duplicadas vêm desmarcadas.',
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: busy ? null : _pickFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Selecionar arquivo'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SectionCard(
          title: 'Colunas',
          child: Column(
            children: [
              for (final c in ImportColumn.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          c.header,
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: c.required ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _columnHint(c),
                          style: context.text.bodySmall?.copyWith(
                            color: context.fin.subtle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _columnHint(ImportColumn c) => switch (c) {
    ImportColumn.date => 'Obrigatória · dd/mm/aaaa',
    ImportColumn.description => 'Obrigatória',
    ImportColumn.amount => 'Obrigatória · ex.: 1.234,56',
    ImportColumn.category => 'Nome ou "Categoria > Subcategoria"',
    ImportColumn.account => 'Nome da conta (ou use a conta padrão)',
    ImportColumn.card => 'Nome do cartão ou 4 últimos dígitos',
    ImportColumn.installments => 'Número de parcelas (vazio = à vista)',
    ImportColumn.project => 'Nome do projeto',
    ImportColumn.status => 'Concluída, Pendente, Planejada ou Cancelada',
    ImportColumn.notes => 'Texto livre',
  };

  // ---------------------------------------------------------------------------
  // Passo 2: prévia

  Widget _preview(BuildContext context, ExpenseImportPlan p) {
    final fc = context.watch<FinanceController>();
    final invalid = p.invalid.length;
    final dups = p.duplicates.length;
    final newCats = p.newCategoryNames;
    final items = switch (filter) {
      _RowFilter.all => p.items,
      _RowFilter.selected => p.selected.toList(),
      _RowFilter.issues =>
        p.items.where((i) => !i.isValid || i.warnings.isNotEmpty).toList(),
    };
    final issues = p.items
        .where((i) => !i.isValid || i.warnings.isNotEmpty)
        .length;
    final selectable = p.valid.toList();
    final allSelected =
        selectable.isNotEmpty && selectable.every((i) => i.selected);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SectionCard(
          title: fileName,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill(
                    '${p.items.length} ${p.items.length == 1 ? 'linha' : 'linhas'}',
                    color: context.colors.primary,
                    icon: Icons.table_rows_outlined,
                  ),
                  Pill(
                    '${p.valid.length} válidas',
                    color: context.fin.positive,
                    icon: Icons.check_circle_outline,
                  ),
                  if (invalid > 0)
                    Pill(
                      '$invalid com erro',
                      color: context.colors.error,
                      icon: Icons.error_outline,
                    ),
                  if (dups > 0)
                    Pill(
                      '$dups possíveis duplicadas',
                      color: context.fin.warning,
                      icon: Icons.content_copy,
                    ),
                ],
              ),
              if (p.items.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Nenhuma despesa encontrada. Preencha a aba "Despesas" a '
                  'partir da linha 2.',
                  style: context.text.bodyMedium,
                ),
              ],
              if (parsed!.ignoredColumns.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Colunas ignoradas: ${parsed!.ignoredColumns.join(', ')}',
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: defaultAccountId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Conta padrão (linhas sem conta e sem cartão)',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Nenhuma')),
                  for (final a in fc.activeAccounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() {
                  defaultAccountId = v;
                  _replan();
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Criar categorias que não existem'),
                subtitle: Text(
                  newCats.isEmpty
                      ? 'Se desligado, essas linhas vão para "Outras despesas"'
                      : 'Serão criadas: ${newCats.join(', ')}',
                ),
                value: createMissingCategories,
                onChanged: (v) => setState(() {
                  createMissingCategories = v;
                  _replan();
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (f, label) in [
              (_RowFilter.all, 'Todas (${p.items.length})'),
              (_RowFilter.selected, 'Selecionadas (${p.selected.length})'),
              (_RowFilter.issues, 'Atenção ($issues)'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: filter == f,
                showCheckmark: false,
                onSelected: (_) => setState(() => filter = f),
              ),
            if (selectable.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  for (final i in selectable) {
                    i.selected = !allSelected;
                    overrides[i.row.line] = !allSelected;
                  }
                }),
                child: Text(allSelected ? 'Desmarcar todas' : 'Marcar todas'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (final i in items)
          _RowTile(
            item: i,
            fc: fc,
            onChanged: (v) {
              setState(() {
                i.selected = v;
                overrides[i.row.line] = v;
              });
            },
          ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  final ExpenseImportItem item;
  final FinanceController fc;
  final ValueChanged<bool> onChanged;
  const _RowTile({
    required this.item,
    required this.fc,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final r = item.row;
    final data = fc.data;
    final category = item.newCategoryName != null
        ? '${item.newCategoryName} (nova)'
        : data.categoryById[item.categoryId]?.name ?? 'Sem categoria';
    final where = item.cardId != null
        ? data.cardById[item.cardId]?.name
        : data.accountById[item.accountId]?.name;
    final meta = [
      if (r.date != null) Dates.format(r.date!),
      category,
      ?where,
      if (r.installments > 1)
        '${r.installments}x de ${r.amount == null ? '?' : r.amount!.split(r.installments).first.format()}',
      if (item.isValid) item.status.label,
    ].join(' · ');
    final invoice = item.isValid && item.cardId != null
        ? fc.invoiceHint(item.cardId, r.date!)
        : null;
    final small = context.text.bodySmall;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: item.isValid ? () => onChanged(!item.selected) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: item.isValid && item.selected,
                onChanged: item.isValid ? (v) => onChanged(v ?? false) : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.description.isEmpty
                                ? '(sem descrição)'
                                : r.description,
                            style: context.text.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (r.amount != null)
                          MoneyText(
                            r.amount!,
                            style: context.text.titleSmall,
                            color: context.fin.expense,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Linha ${r.line} · $meta',
                      style: small?.copyWith(color: context.fin.subtle),
                    ),
                    if (invoice != null)
                      Text(
                        invoice,
                        style: small?.copyWith(color: context.fin.subtle),
                      ),
                    for (final e in item.errors)
                      _Issue(e, Icons.error_outline, context.colors.error),
                    for (final w in item.warnings)
                      _Issue(
                        w,
                        Icons.warning_amber_rounded,
                        context.fin.warning,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Issue extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const _Issue(this.text, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: context.text.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Banner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
