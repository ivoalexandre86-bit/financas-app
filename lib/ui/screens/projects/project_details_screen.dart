import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../projection/drilldown_screen.dart';
import '../transactions/transaction_details_screen.dart';
import '../transactions/transaction_form_screen.dart';
import 'project_form_screen.dart';
import 'projects_screen.dart';

class ProjectDetailsScreen extends StatelessWidget {
  final String projectId;
  const ProjectDetailsScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final p = fc.data.projectById[projectId];
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.flag_outlined,
          title: 'Projeto removido',
        ),
      );
    }
    final e = fc.engine;
    final s = e.projectSummary(p);
    final txs = e.projectTransactions(p);
    final today = e.today;
    final past = txs.where((t) => !t.date.isAfter(today)).toList();
    final future = txs.where((t) => t.date.isAfter(today)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => push(context, ProjectFormScreen(project: p)),
          ),
          IconButton(
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Excluir projeto?',
                message: 'Os lançamentos serão mantidos, apenas desvinculados do projeto.',
                confirm: 'Excluir',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              final done = await runAction(
                context,
                () => fc.deleteProject(p),
                success: 'Projeto excluído',
              );
              if (done && context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-prj-tx',
        onPressed: () =>
            push(context, TransactionFormScreen(initialProjectId: p.id)),
        icon: const Icon(Icons.add),
        label: const Text('Lançar no projeto'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (p.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                p.description,
                style: context.text.bodyMedium?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
            ),
          ProjectCard(summary: s),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Planejado × realizado',
            child: Column(
              children: [
                InfoRow('Orçamento', MoneyText(p.budget)),
                InfoRow('Realizado (concluído)', MoneyText(s.actual)),
                InfoRow('Previsto (a realizar)', MoneyText(s.planned)),
                InfoRow(
                  'Saldo do orçamento',
                  MoneyText(s.remaining, colorize: true),
                ),
                InfoRow(
                  'Saldo após previstos',
                  MoneyText(s.forecastRemaining, colorize: true),
                ),
                if (p.startDate != null)
                  InfoRow.text('Início', Dates.format(p.startDate!)),
                if (p.endDate != null)
                  InfoRow.text('Fim', Dates.format(p.endDate!)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('Ver despesas do projeto no mês atual'),
              onPressed: () => push(
                context,
                DrilldownScreen(
                  month: YearMonth.now(),
                  row: DrillRow.expenses,
                  filter: ProjectionFilter(projectIds: {p.id}),
                ),
              ),
            ),
          ),
          if (future.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(
                'Próximos gastos previstos',
                style: context.text.titleMedium,
              ),
            ),
            Card(
              child: Column(
                children: [
                  for (final t in future)
                    TransactionTile(
                      tx: t,
                      engine: e,
                      onTap: () =>
                          push(context, TransactionDetailsScreen(tx: t)),
                    ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Text('Lançamentos', style: context.text.titleMedium),
          ),
          if (past.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhum lançamento realizado ainda.'),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final t in past)
                    TransactionTile(
                      tx: t,
                      engine: e,
                      onTap: () =>
                          push(context, TransactionDetailsScreen(tx: t)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
