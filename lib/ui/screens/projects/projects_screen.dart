import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/remembered_filters.dart';
import '../../widgets/sort_grid.dart';
import '../../widgets/tx_grid.dart';
import '../../widgets/view_mode.dart';
import 'project_details_screen.dart';
import 'project_form_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen>
    with RememberedFilters {
  bool showArchived = false;
  ViewMode view = ViewMode.cards;

  @override
  String get filterKey => 'projects';

  @override
  Map<String, Object?> filtersToJson() => {'view': view.name};

  @override
  void restoreFilters(Map<String, Object?> saved, FinanceController fc) =>
      view = FilterJson.enumOrNull(ViewMode.values, saved['view']) ?? view;

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
          ViewModeToggle(
            keyPrefix: 'projects',
            mode: view,
            onChanged: (v) => setFilters(() => view = v),
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
          : view == ViewMode.grid
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                ProjectsGrid(
                  summaries: [
                    for (final p in projects) fc.engine.projectSummary(p),
                  ],
                ),
              ],
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

/// Projetos no padrão de grade de Faturas: ordenável, com totais.
class ProjectsGrid extends StatelessWidget {
  final List<ProjectSummary> summaries;
  const ProjectsGrid({super.key, required this.summaries});

  @override
  Widget build(BuildContext context) {
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final strong = context.text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
    );
    int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    String period(ProjectSummary s) {
      final p = s.project;
      if (p.startDate == null && p.endDate == null) return '';
      return '${p.startDate == null ? '…' : Dates.format(p.startDate!)} – '
          '${p.endDate == null ? '…' : Dates.format(p.endDate!)}';
    }

    int date(DateTime? a, DateTime? b) =>
        a == null ? (b == null ? 0 : 1) : (b == null ? -1 : a.compareTo(b));
    Widget money(Money v, {TextStyle? style}) => Text(
      v.format(),
      style: style?.copyWith(color: v.cents < 0 ? context.fin.negative : null),
    );
    Money sum(List<ProjectSummary> l, Money Function(ProjectSummary) f) =>
        l.map(f).sum();
    Widget status(ProjectSummary s) => NeonStatus(
      label: s.project.archived
          ? 'Arquivado'
          : s.remaining.isNegative
          ? 'Excedido'
          : 'Ativo',
      color: s.project.archived
          ? context.fin.subtle
          : s.remaining.isNegative
          ? context.fin.negative
          : context.fin.positive,
      done: s.project.archived,
    );
    Widget progress(ProjectSummary s) {
      final over = s.remaining.isNegative;
      return Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: s.progress.clamp(0, 1),
                minHeight: 6,
                color: over ? context.fin.negative : Color(s.project.color),
                backgroundColor: context.fin.gridLine,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '${(s.progress * 100).round()}%',
              textAlign: TextAlign.right,
              style: context.text.bodySmall,
            ),
          ),
        ],
      );
    }

    Widget dot(ProjectSummary s) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: Color(s.project.color),
        shape: BoxShape.circle,
      ),
    );

    return SortGrid<ProjectSummary>(
      keyPrefix: 'projects',
      rows: summaries,
      rowId: (s) => s.project.id,
      accent: (context, s) => Color(s.project.color),
      dimmed: (s) => s.project.archived,
      onOpen: (s) =>
          push(context, ProjectDetailsScreen(projectId: s.project.id)),
      initialSort: 'name',
      tieBreak: (a, b) => text(a.project.name, b.project.name),
      columns: [
        SortCol(
          id: 'name',
          label: 'Projeto',
          width: 200,
          minWidth: 130,
          flexible: true,
          fill: true,
          compare: (a, b) => text(a.project.name, b.project.name),
          cell: (context, s) => GridCell(
            child: Row(
              children: [
                dot(s),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SortCol(
          id: 'period',
          label: 'Período',
          width: 200,
          minWidth: 120,
          flexible: true,
          compare: (a, b) {
            final c = date(a.project.startDate, b.project.startDate);
            return c != 0 ? c : date(a.project.endDate, b.project.endDate);
          },
          cell: (context, s) => GridCell(
            child: Text(
              period(s).isEmpty ? '—' : period(s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtle,
            ),
          ),
        ),
        SortCol(
          id: 'budget',
          label: 'Orçamento',
          width: 124,
          right: true,
          compare: (a, b) => a.project.budget.compareTo(b.project.budget),
          cell: (context, s) => GridCell(
            right: true,
            child: money(s.project.budget, style: context.text.bodySmall),
          ),
          footer: (context, l) => money(
            sum(l, (s) => s.project.budget),
            style: context.text.bodySmall,
          ),
        ),
        SortCol(
          id: 'actual',
          label: 'Gasto',
          width: 128,
          right: true,
          highlight: true,
          compare: (a, b) => a.actual.compareTo(b.actual),
          cell: (context, s) =>
              GridCell(right: true, child: money(s.actual, style: strong)),
          footer: (context, l) => money(sum(l, (s) => s.actual), style: strong),
        ),
        SortCol(
          id: 'remaining',
          label: 'Restante',
          width: 124,
          right: true,
          compare: (a, b) => a.remaining.compareTo(b.remaining),
          cell: (context, s) => GridCell(
            right: true,
            child: money(s.remaining, style: context.text.bodySmall),
          ),
          footer: (context, l) =>
              money(sum(l, (s) => s.remaining), style: context.text.bodySmall),
        ),
        SortCol(
          id: 'progress',
          label: 'Progresso',
          width: 150,
          compare: (a, b) => a.progress.compareTo(b.progress),
          cell: (context, s) => GridCell(child: progress(s)),
        ),
        SortCol(
          id: 'status',
          label: 'Situação',
          width: 116,
          compare: (a, b) => (a.project.archived ? 1 : 0).compareTo(
            b.project.archived ? 1 : 0,
          ),
          cell: (context, s) => GridCell(child: status(s)),
        ),
      ],
      compactRow: (context, s) => Row(
        children: [
          dot(s),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    'de ${s.project.budget.format()}',
                    '${(s.progress * 100).round()}%',
                    if (s.project.archived) 'Arquivado',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          money(s.actual, style: strong),
        ],
      ),
      footerLabel: (context, l) => Text(
        'Total · ${l.length} ${l.length == 1 ? 'projeto' : 'projetos'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: gridFooterLabelStyle(context),
      ),
      compactFooter: (context, l) =>
          money(sum(l, (s) => s.actual), style: strong),
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
