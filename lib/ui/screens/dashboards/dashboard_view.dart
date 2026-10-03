import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../domain/models/dashboard.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/dashboard_chart.dart';
import 'chart_editor_screen.dart';
import 'period_editor.dart';

/// Abre o painel de configuração e devolve o gráfico configurado.
Future<ChartConfig?> openChartEditor(
  BuildContext context, {
  required Dashboard dashboard,
  required YearMonth reference,
  ChartConfig? chart,
}) => push<ChartConfig>(
  context,
  ChartEditorScreen(
    initial:
        chart ?? ChartConfig(id: newId('ch_'), period: dashboard.filter.period),
    panel: dashboard.filter,
    reference: reference,
    isNew: chart == null,
  ),
);

/// Grade responsiva com os gráficos de um painel. Em modo de edição permite
/// arrastar para reordenar, redimensionar, configurar, duplicar e remover.
class DashboardGrid extends StatelessWidget {
  final Dashboard dashboard;
  final YearMonth reference;
  final bool editing;
  const DashboardGrid({
    super.key,
    required this.dashboard,
    required this.reference,
    this.editing = false,
  });

  /// Colunas da grade conforme a largura disponível.
  static int columnsFor(double w) => w < 640
      ? 1
      : w < 1024
      ? 2
      : 3;

  static int spanFor(ChartWidth width, int cols) => switch (cols) {
    1 => 6,
    2 => width.span <= 3 ? 3 : 6,
    _ => width.span,
  };

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final charts = dashboard.charts;
    if (charts.isEmpty) {
      return SectionCard(
        child: EmptyState(
          icon: Icons.add_chart,
          title: 'Painel vazio',
          message: 'Adicione gráficos para montar suas análises.',
          actionLabel: 'Adicionar gráfico',
          onAction: () => addChart(context, fc, dashboard, reference),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final cols = columnsFor(c.maxWidth);
        double widthOf(ChartWidth w) =>
            (c.maxWidth + gap) * spanFor(w, cols) / 6 - gap;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < charts.length; i++)
              SizedBox(
                key: ValueKey(charts[i].id),
                width: widthOf(charts[i].width).floorToDouble(),
                child: _ChartCard(
                  dashboard: dashboard,
                  chart: charts[i],
                  index: i,
                  reference: reference,
                  editing: editing,
                ),
              ),
          ],
        );
      },
    );
  }

  static Future<void> addChart(
    BuildContext context,
    FinanceController fc,
    Dashboard d,
    YearMonth reference,
  ) async {
    final c = await openChartEditor(
      context,
      dashboard: d,
      reference: reference,
    );
    if (c == null) return;
    final cur = fc.dashboardById(d.id) ?? d;
    await fc.saveDashboard(cur.copyWith(charts: [...cur.charts, c]));
  }
}

class _ChartCard extends StatefulWidget {
  final Dashboard dashboard;
  final ChartConfig chart;
  final int index;
  final YearMonth reference;
  final bool editing;
  const _ChartCard({
    required this.dashboard,
    required this.chart,
    required this.index,
    required this.reference,
    required this.editing,
  });
  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  bool table = false;

  ChartConfig get chart => widget.chart;

  Future<void> _update(
    FinanceController fc,
    List<ChartConfig> Function(List<ChartConfig>) f,
  ) {
    final d = fc.dashboardById(widget.dashboard.id) ?? widget.dashboard;
    return fc.saveDashboard(d.copyWith(charts: f([...d.charts])));
  }

  Future<void> _replace(FinanceController fc, ChartConfig n) =>
      _update(fc, (l) => [for (final x in l) x.id == n.id ? n : x]);

  Future<void> _move(FinanceController fc, String draggedId) =>
      _update(fc, (l) {
        final from = l.indexWhere((x) => x.id == draggedId);
        if (from < 0) return l;
        final item = l.removeAt(from);
        final to = l.indexWhere((x) => x.id == chart.id);
        l.insert(to < 0 ? l.length : (from <= to ? to + 1 : to), item);
        return l;
      });

  Future<void> _shift(FinanceController fc, int delta) => _update(fc, (l) {
    final i = l.indexWhere((x) => x.id == chart.id);
    final j = (i + delta).clamp(0, l.length - 1);
    if (i < 0 || i == j) return l;
    final item = l.removeAt(i);
    l.insert(j, item);
    return l;
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final data = fc.dashboardEngine.build(
      chart,
      panel: widget.dashboard.filter,
      reference: widget.reference,
    );
    final editing = widget.editing;
    final count = widget.dashboard.charts.length;

    final header = Row(
      children: [
        if (editing)
          Draggable<String>(
            data: chart.id,
            feedback: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(chart.displayTitle),
              ),
            ),
            child: Tooltip(
              message: 'Arraste para reordenar',
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.drag_indicator, color: context.fin.subtle),
                ),
              ),
            ),
          ),
        Expanded(
          child: Text(
            chart.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleMedium,
          ),
        ),
        PopupMenuButton<ChartType>(
          tooltip: 'Trocar tipo de gráfico',
          icon: Icon(chartTypeIcon(chart.type), size: 20),
          onSelected: (t) => _replace(fc, chart.copyWith(type: t)),
          itemBuilder: (_) => [
            for (final t in ChartType.values)
              CheckedPopupMenuItem(
                value: t,
                checked: t == chart.type,
                child: Text(t.label),
              ),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: 'Opções do gráfico',
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                final n = await openChartEditor(
                  context,
                  dashboard: widget.dashboard,
                  reference: widget.reference,
                  chart: chart,
                );
                if (n != null) await _replace(fc, n);
              case 'table':
                setState(() => table = !table);
              case 'dup':
                await _update(fc, (l) {
                  final i = l.indexWhere((x) => x.id == chart.id);
                  l.insert(
                    i + 1,
                    chart.copyWith(
                      id: newId('ch_'),
                      title: '${chart.displayTitle} (cópia)',
                    ),
                  );
                  return l;
                });
              case 'up':
                await _shift(fc, -1);
              case 'down':
                await _shift(fc, 1);
              case 'remove':
                await _update(
                  fc,
                  (l) => l.where((x) => x.id != chart.id).toList(),
                );
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Configurar…')),
            PopupMenuItem(
              value: 'table',
              child: Text(table ? 'Ver gráfico' : 'Ver como tabela'),
            ),
            const PopupMenuItem(value: 'dup', child: Text('Duplicar')),
            if (widget.index > 0)
              const PopupMenuItem(value: 'up', child: Text('Mover para antes')),
            if (widget.index < count - 1)
              const PopupMenuItem(
                value: 'down',
                child: Text('Mover para depois'),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'remove', child: Text('Remover')),
          ],
        ),
      ],
    );

    final card = Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DashboardChartView(
                data: data,
                height: chart.height.plotHeight,
                showTable: table,
              ),
            ),
            if (editing) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _SizeChip(
                    icon: Icons.width_normal_outlined,
                    label: chart.width.label,
                    tooltip: 'Largura',
                    onTap: () => _replace(
                      fc,
                      chart.copyWith(
                        width:
                            ChartWidth.values[(chart.width.index + 1) %
                                ChartWidth.values.length],
                      ),
                    ),
                  ),
                  _SizeChip(
                    icon: Icons.height,
                    label: 'Altura ${chart.height.label.toLowerCase()}',
                    tooltip: 'Altura',
                    onTap: () => _replace(
                      fc,
                      chart.copyWith(
                        height:
                            ChartHeight.values[(chart.height.index + 1) %
                                ChartHeight.values.length],
                      ),
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.tune, size: 16),
                    label: const Text('Configurar'),
                    onPressed: () async {
                      final n = await openChartEditor(
                        context,
                        dashboard: widget.dashboard,
                        reference: widget.reference,
                        chart: chart,
                      );
                      if (n != null) await _replace(fc, n);
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (!editing) return card;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != chart.id,
      onAcceptWithDetails: (d) => _move(fc, d.data),
      builder: (context, candidate, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            width: 2,
            color: candidate.isNotEmpty
                ? context.colors.primary
                : context.colors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: card,
      ),
    );
  }
}

class _SizeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  const _SizeChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$tooltip (toque para alternar)',
    child: ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
    ),
  );
}

/// Filtros aplicados a todos os gráficos do painel.
class PanelFilterBar extends StatelessWidget {
  final Dashboard dashboard;
  final YearMonth reference;
  final ValueChanged<YearMonth> onReference;
  const PanelFilterBar({
    super.key,
    required this.dashboard,
    required this.reference,
    required this.onReference,
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final f = dashboard.filter;
    Future<void> save(PanelFilter nf) =>
        fc.saveDashboard(dashboard.copyWith(filter: nf));

    final catLabel = f.categoryIds.isEmpty
        ? 'Todas as categorias'
        : f.categoryIds.length == 1
        ? fc.engine.categoryLabel(f.categoryIds.first)
        : '${f.categoryIds.length} categorias';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MonthSwitcher(month: reference, onChanged: onReference),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(f.period.resolve(reference).label),
          tooltip: 'Período do painel',
          onPressed: () async {
            final p = await showModalBottomSheet<PeriodSpec>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) =>
                  _PeriodSheet(initial: f.period, reference: reference),
            );
            if (p != null) await save(f.copyWith(period: p));
          },
        ),
        SegmentedButton<StatusScope>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            for (final s in StatusScope.values)
              ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {f.status},
          onSelectionChanged: (s) => save(f.copyWith(status: s.first)),
        ),
        ActionChip(
          avatar: const Icon(Icons.category_outlined, size: 18),
          label: Text(catLabel),
          tooltip: 'Categorias (todos os gráficos)',
          onPressed: () async {
            final s = await showModalBottomSheet<Set<String>>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _CategorySheet(fc: fc, initial: f.categoryIds),
            );
            if (s != null) await save(f.copyWith(categoryIds: s));
          },
        ),
      ],
    );
  }
}

class _PeriodSheet extends StatefulWidget {
  final PeriodSpec initial;
  final YearMonth reference;
  const _PeriodSheet({required this.initial, required this.reference});
  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late PeriodSpec p = widget.initial;

  @override
  Widget build(BuildContext context) {
    Widget preset(String label, PeriodSpec spec) => ActionChip(
      label: Text(label),
      onPressed: () => Navigator.pop(context, spec),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Período do painel', style: context.text.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                preset('Mês de referência', const PeriodSpec()),
                preset('Últimos 3 meses', const PeriodSpec.relative(-2, 0)),
                preset('Últimos 6 meses', const PeriodSpec.relative(-5, 0)),
                preset('Últimos 12 meses', const PeriodSpec.relative(-11, 0)),
                preset('Próximos 6 meses', const PeriodSpec.relative(0, 5)),
                preset('Ano', const PeriodSpec(kind: PeriodKind.year)),
              ],
            ),
            const Divider(height: 32),
            PeriodEditor(
              value: p,
              reference: widget.reference,
              onChanged: (v) => setState(() => p = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, p),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  final FinanceController fc;
  final Set<String> initial;
  const _CategorySheet({required this.fc, required this.initial});
  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final sel = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final e = widget.fc.engine;
    final cats = [...widget.fc.data.categories]
      ..sort((a, b) {
        final k = a.kind.index.compareTo(b.kind.index);
        return k != 0
            ? k
            : e.categoryLabel(a.id).compareTo(e.categoryLabel(b.id));
      });
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Categorias do painel', style: context.text.titleLarge),
          Text(
            'Aplica-se a todos os gráficos deste painel.',
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in cats)
                    FilterChip(
                      avatar: CircleAvatar(
                        backgroundColor: Color(c.color),
                        radius: 5,
                      ),
                      label: Text('${e.categoryLabel(c.id)} · ${c.kind.label}'),
                      selected: sel.contains(c.id),
                      onSelected: (v) =>
                          setState(() => v ? sel.add(c.id) : sel.remove(c.id)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, <String>{}),
                child: const Text('Todas'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(context, sel),
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
