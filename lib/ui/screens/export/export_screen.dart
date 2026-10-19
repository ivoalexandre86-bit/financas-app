import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../data/report_export.dart';
import '../../../state/auth_controller.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/plan_upsell.dart';

enum ExportFormat {
  xlsx(
    'Excel',
    'xlsx',
    Icons.grid_on,
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),
  csv('CSV', 'csv', Icons.description_outlined, 'text/csv'),
  pdf('PDF', 'pdf', Icons.picture_as_pdf_outlined, 'application/pdf');

  final String label;
  final String ext;
  final IconData icon;
  final String mime;
  const ExportFormat(this.label, this.ext, this.icon, this.mime);
}

/// Exporta lançamentos e relatórios do período para Excel, CSV ou PDF.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  YearMonth from = YearMonth.now();
  YearMonth to = YearMonth.now();
  bool busy = false;

  Future<void> _export(ExportFormat f) async {
    if (f != ExportFormat.csv && isGratisPlan(context, listen: false)) {
      await showPlanUpsell(
        context,
        feature:
            'Relatórios em Excel e PDF fazem parte do plano Básico. No '
            'Grátis você pode exportar os lançamentos em CSV.',
      );
      return;
    }
    final fc = context.read<FinanceController>();
    final user = Provider.of<AuthController?>(context, listen: false)?.user;
    setState(() => busy = true);
    try {
      final r = ReportExport(fc.engine, from, to);
      final Uint8List bytes = switch (f) {
        ExportFormat.xlsx => r.toXlsx(),
        ExportFormat.csv => r.toCsv(),
        ExportFormat.pdf => await r.toPdf(
          userName: user?.name,
          budgets: fc.budgets,
          goals: fc.goals,
        ),
      };
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Salvar relatório',
        fileName: '${r.fileBase}.${f.ext}',
        bytes: bytes,
        mimeType: f.mime,
        type: FileType.custom,
        allowedExtensions: [f.ext],
      );
      if (mounted && uri != null) showMessage(context, 'Relatório salvo');
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Não foi possível exportar: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final r = ReportExport(fc.engine, from, to);
    final rows = r.rows.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Exportar relatórios')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Período',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 40, child: Text('De')),
                    MonthSwitcher(
                      month: from,
                      onChanged: (m) => setState(() {
                        from = m;
                        if (to < from) to = from;
                      }),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(width: 40, child: Text('Até')),
                    MonthSwitcher(
                      month: to,
                      onChanged: (m) => setState(() {
                        to = m;
                        if (to < from) from = to;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, months) in const [
                      ('Este mês', 1),
                      ('3 meses', 3),
                      ('12 meses', 12),
                    ])
                      ActionChip(
                        label: Text(label),
                        onPressed: () => setState(() {
                          to = YearMonth.now();
                          from = to.add(1 - months);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$rows ${rows == 1 ? 'lançamento' : 'lançamentos'} de '
                  '${r.periodLabel}, na visão de caixa (compras no cartão na '
                  'data da fatura).',
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final (f, text) in const [
            (
              ExportFormat.xlsx,
              'Planilha com os lançamentos, despesas por categoria em cada '
                  'mês e o resumo mensal.',
            ),
            (
              ExportFormat.pdf,
              'Relatório para imprimir ou enviar: totais, categorias, '
                  'orçamentos, metas e lançamentos.',
            ),
            (
              ExportFormat.csv,
              'Lista de lançamentos em texto (abre no Excel e no Google '
                  'Planilhas).',
            ),
          ])
            Card(
              child: ListTile(
                key: ValueKey('export-${f.ext}'),
                enabled: !busy,
                leading: Icon(f.icon),
                title: Text(f.label),
                subtitle: Text(text),
                trailing: const Icon(Icons.download),
                onTap: () => _export(f),
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
