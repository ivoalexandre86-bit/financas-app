import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'project_details_screen.dart';
import 'project_form_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  bool showArchived = false;

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final projects =
        fc.data.projects.where((p) => showArchived || !p.archived).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projetos e metas'),
        actions: [
          IconButton(
            tooltip: showArchived ? 'Ocultar arquivados' : 'Mostrar arquivados',
            icon: Icon(
              showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
            ),
            onPressed: () => setState(() => showArchived = !showArchived),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-prj',
        onPressed: () => push(context, const ProjectFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Novo projeto'),
      ),
      body: projects.isEmpty
          ? EmptyState(
              icon: Icons.flag_outlined,
              title: 'Nenhum projeto',
              message: 'Crie projetos como “Viagem” ou “Reforma” para planejar orçamento e acompanhar gastos.',
              actionLabel: 'Criar projeto',
              onAction: () => push(context, const ProjectFormScreen()),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: projects.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  ProjectCard(summary: fc.engine.projectSummary(projects[i])),
            ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  final ProjectSummary summary;
  const ProjectCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final p = summary.project;
    final over = summary.remaining.isNegative;
    final color = Color(p.color);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => push(context, ProjectDetailsScreen(projectId: p.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.name, style: context.text.titleMedium),
                  ),
                  if (p.archived) Pill('Arquivado', color: context.fin.subtle),
                ],
              ),
              if (p.startDate != null || p.endDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${p.startDate == null ? '…' : Dates.format(p.startDate!)} – ${p.endDate == null ? '…' : Dates.format(p.endDate!)}',
                    style: context.text.bodySmall?.copyWith(
                      color: context.fin.subtle,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: summary.progress.clamp(0, 1),
                  minHeight: 8,
                  color: over ? context.fin.negative : color,
                  backgroundColor: context.fin.gridLine,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _Kv('Gasto', MoneyText(summary.actual))),
                  Expanded(child: _Kv('Orçamento', MoneyText(p.budget))),
                  Expanded(
                    child: _Kv(
                      over ? 'Excedido' : 'Restante',
                      MoneyText(
                        summary.remaining.abs(),
                        color: over ? context.fin.negative : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  final String k;
  final Widget v;
  const _Kv(this.k, this.v);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        k,
        style: context.text.labelSmall?.copyWith(color: context.fin.subtle),
      ),
      DefaultTextStyle.merge(
        style: const TextStyle(fontWeight: FontWeight.w600),
        child: v,
      ),
    ],
  );
}
