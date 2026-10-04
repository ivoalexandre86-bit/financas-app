import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/dashboard_engine.dart';
import '../../../domain/models/dashboard.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/dashboard_chart.dart';
import 'period_editor.dart';

/// Painel de configuração de um gráfico, com pré-visualização ao vivo.
class ChartEditorScreen extends StatefulWidget {
  final ChartConfig initial;
  final PanelFilter panel;
  final YearMonth reference;
  final bool isNew;
  const ChartEditorScreen({
    super.key,
    required this.initial,
    required this.panel,
    required this.reference,
    this.isNew = false,
  });

  @override
  State<ChartEditorScreen> createState() => _ChartEditorScreenState();
}

class _ChartEditorScreenState extends State<ChartEditorScreen> {
  late ChartConfig c = widget.initial;
  late final titleCtrl = TextEditingController(text: widget.initial.title);

  @override
  void dispose() {
    titleCtrl.dispose();
    super.dispose();
  }

  void set(ChartConfig n) => setState(() => c = n);

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final preview = fc.dashboardEngine.build(
      c,
      panel: widget.panel,
      reference: widget.reference,
    );
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final previewCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(c.displayTitle, style: context.text.titleMedium),
            const SizedBox(height: 4),
            DashboardChartView(data: preview, height: c.height.plotHeight),
          ],
        ),
      ),
    );

    final form = _form(context, fc, preview);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Adicionar gráfico' : 'Configurar gráfico'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, c),
              child: Text(widget.isNew ? 'Adicionar' : 'Salvar'),
            ),
          ),
        ],
      ),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: previewCard,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 16, 16, 32),
                    children: form,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: previewCard,
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: form,
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _form(
    BuildContext context,
    FinanceController fc,
    ChartDataset preview,
  ) {
    Widget section(String t) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(t, style: context.text.titleSmall),
    );
    Widget chips<T>(
      List<T> values,
      T selected,
      String Function(T) label,
      ValueChanged<T> onTap,
    ) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == selected,
            onSelected: (_) => onTap(v),
          ),
      ],
    );

    final isBalance = c.source == DataSource.balance;
    final kind = switch (c.source) {
      DataSource.income => CategoryKind.income,
      DataSource.expenses => CategoryKind.expense,
      _ => null,
    };
    final cats =
        fc.data.categories.where((x) => kind == null || x.kind == kind).toList()
          ..sort(
            (a, b) => fc.engine
                .categoryLabel(a.id)
                .compareTo(fc.engine.categoryLabel(b.id)),
          );

    return [
      TextField(
        controller: titleCtrl,
        decoration: InputDecoration(
          labelText: 'Título do gráfico',
          hintText: c.copyWith(title: '').displayTitle,
        ),
        onChanged: (v) => set(c.copyWith(title: v)),
      ),
      section('Tipo de gráfico'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in ChartType.values)
            ChoiceChip(
              avatar: Icon(chartTypeIcon(t), size: 16),
              label: Text(t.label),
              selected: c.type == t,
              onSelected: (_) => set(c.copyWith(type: t)),
            ),
        ],
      ),
      if (c.type.requiresMonthAxis)
        _note(context, 'Este tipo usa meses no eixo X.'),
      if (c.type.canSwapAxes)
        SwitchListTile(
          key: const ValueKey('swap-axes'),
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            c.swapAxes ? Icons.align_horizontal_left : Icons.bar_chart,
          ),
          title: const Text('Inverter eixos'),
          subtitle: const Text(
            'Barras horizontais: categorias na vertical e valores na horizontal',
          ),
          value: c.swapAxes,
          onChanged: (v) => set(c.copyWith(swapAxes: v)),
        ),
      section('Fonte de dados'),
      chips(
        DataSource.values,
        c.source,
        (v) => v.label,
        (v) => set(
          c.copyWith(
            source: v,
            // Categorias de outro tipo deixam de fazer sentido.
            categoryIds: v == DataSource.income || v == DataSource.expenses
                ? c.categoryIds
                      .where(
                        (id) =>
                            fc.data.categoryById[id]?.kind ==
                            (v == DataSource.income
                                ? CategoryKind.income
                                : CategoryKind.expense),
                      )
                      .toSet()
                : c.categoryIds,
          ),
        ),
      ),
      if (isBalance)
        _note(
          context,
          'O saldo projetado considera todas as contas, lançamentos, '
          'recorrências, parcelas e faturas (como na Projeção).',
        ),
      if (!isBalance) ...[
        section('Status dos lançamentos'),
        chips(
          StatusScope.values,
          c.status,
          (v) => v.label,
          (v) => set(c.copyWith(status: v)),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Realizado × previsto'),
          subtitle: const Text(
            'Separa o que já foi realizado do que ainda está previsto',
          ),
          value: c.seriesBy == Dimension.realization,
          onChanged: (v) => set(
            c.copyWith(seriesBy: v ? Dimension.realization : Dimension.none),
          ),
        ),
        section('Categorias'),
        Row(
          children: [
            Expanded(
              child: Text(
                c.categoryIds.isEmpty
                    ? 'Todas as categorias'
                    : '${c.categoryIds.length} selecionada(s)',
                style: context.text.bodySmall,
              ),
            ),
            if (c.categoryIds.isNotEmpty)
              TextButton(
                onPressed: () => set(c.copyWith(categoryIds: {})),
                child: const Text('Limpar'),
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final cat in cats)
              FilterChip(
                label: Text(fc.engine.categoryLabel(cat.id)),
                selected: c.categoryIds.contains(cat.id),
                avatar: CircleAvatar(
                  backgroundColor: Color(cat.color),
                  radius: 5,
                ),
                onSelected: (v) {
                  final s = {...c.categoryIds};
                  v ? s.add(cat.id) : s.remove(cat.id);
                  set(c.copyWith(categoryIds: s));
                },
              ),
          ],
        ),
      ],
      section('Período'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Usar o período do painel'),
        subtitle: Text(
          'Período do painel: ${widget.panel.period.resolve(widget.reference).label}',
        ),
        value: c.usePanelPeriod,
        onChanged: (v) => set(c.copyWith(usePanelPeriod: v)),
      ),
      if (!c.usePanelPeriod)
        PeriodEditor(
          value: c.period,
          reference: widget.reference,
          onChanged: (p) => set(c.copyWith(period: p)),
        ),
      const SizedBox(height: 12),
      DropdownButtonFormField<Comparison>(
        initialValue: c.comparison,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Comparar com'),
        items: [
          for (final v in Comparison.values)
            DropdownMenuItem(value: v, child: Text(v.label)),
        ],
        onChanged: (v) => set(c.copyWith(comparison: v)),
      ),
      if (!isBalance) ...[
        section('Eixos e agrupamento'),
        DropdownButtonFormField<Dimension>(
          initialValue: Dimension.xAxisOptions.contains(c.xAxis)
              ? c.xAxis
              : Dimension.month,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Eixo X (agrupar por)'),
          items: [
            for (final v in Dimension.xAxisOptions)
              DropdownMenuItem(value: v, child: Text(v.label)),
          ],
          onChanged: (v) => set(c.copyWith(xAxis: v)),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Measure>(
          initialValue: c.measure,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Eixo Y (valor)'),
          items: [
            for (final v in Measure.values)
              DropdownMenuItem(value: v, child: Text(v.label)),
          ],
          onChanged: (v) => set(c.copyWith(measure: v)),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Dimension>(
          key: ValueKey('series-${c.seriesBy.name}'),
          initialValue: c.seriesBy,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Séries (dividir cada barra/linha por)',
          ),
          items: [
            for (final v in Dimension.seriesOptions)
              DropdownMenuItem(value: v, child: Text(v.label)),
          ],
          onChanged: (v) => set(c.copyWith(seriesBy: v)),
        ),
      ],
      section('Exibição'),
      _switch('Totais', c.showTotals, (v) => set(c.copyWith(showTotals: v))),
      _switch(
        'Percentuais',
        c.showPercentages,
        (v) => set(c.copyWith(showPercentages: v)),
      ),
      _switch(
        'Variações',
        c.showVariation,
        (v) => set(c.copyWith(showVariation: v)),
      ),
      _switch(
        'Valores sobre o gráfico',
        c.showValues,
        (v) => set(c.copyWith(showValues: v)),
      ),
      _switch('Legenda', c.showLegend, (v) => set(c.copyWith(showLegend: v))),
      section('Cores'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in ChartPalette.values)
            ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p != ChartPalette.auto && p != ChartPalette.categories)
                    for (final col in paletteColors(context, p).take(4))
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: col,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  if (p != ChartPalette.auto && p != ChartPalette.categories)
                    const SizedBox(width: 4),
                  Text(p.label),
                ],
              ),
              selected: c.palette == p,
              onSelected: (_) => set(c.copyWith(palette: p)),
            ),
        ],
      ),
      ..._customColors(context, preview),
      section('Tamanho'),
      chips(
        ChartWidth.values,
        c.width,
        (v) => v.label,
        (v) => set(c.copyWith(width: v)),
      ),
      const SizedBox(height: 8),
      chips(
        ChartHeight.values,
        c.height,
        (v) => 'Altura: ${v.label.toLowerCase()}',
        (v) => set(c.copyWith(height: v)),
      ),
    ];
  }

  /// Cor de cada coluna (ou série), escolhida pelo usuário.
  List<Widget> _customColors(BuildContext context, ChartDataset preview) {
    if (preview.isEmpty) return const [];
    final items = colorableItems(context, preview);
    if (items.isEmpty) return const [];
    final perX = items.first.key.startsWith('x:');
    return [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                perX ? 'Cor de cada coluna' : 'Cor de cada série',
                style: context.text.labelLarge,
              ),
            ),
            if (c.colors.isNotEmpty)
              TextButton(
                onPressed: () => set(c.copyWith(colors: {})),
                child: const Text('Restaurar'),
              ),
          ],
        ),
      ),
      _note(context, 'Toque em um item para escolher a cor.'),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final it in items.take(40))
            ActionChip(
              key: ValueKey('color-${it.key}'),
              avatar: CircleAvatar(backgroundColor: it.color, radius: 8),
              label: Text(it.label),
              onPressed: () async {
                final picked = await pickChartColor(
                  context,
                  title: 'Cor de “${it.label}”',
                  current: it.color,
                  custom: c.colors.containsKey(it.key),
                );
                if (picked == null) return;
                final m = {...c.colors};
                picked == -1 ? m.remove(it.key) : m[it.key] = picked;
                set(c.copyWith(colors: m));
              },
            ),
        ],
      ),
    ];
  }

  Widget _switch(String t, bool v, ValueChanged<bool> f) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(t),
    value: v,
    onChanged: f,
  );

  Widget _note(BuildContext context, String s) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      s,
      style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
    ),
  );
}

IconData chartTypeIcon(ChartType t) => switch (t) {
  ChartType.bar => Icons.bar_chart,
  ChartType.stackedBar => Icons.stacked_bar_chart,
  ChartType.line => Icons.show_chart,
  ChartType.area => Icons.area_chart,
  ChartType.trend => Icons.trending_up,
  ChartType.waterfall => Icons.waterfall_chart,
  ChartType.pareto => Icons.align_horizontal_left,
  ChartType.pie => Icons.pie_chart,
  ChartType.donut => Icons.donut_large,
  ChartType.comparative => Icons.compare_arrows,
  ChartType.monthlyEvolution => Icons.timeline,
  ChartType.cumulative => Icons.stacked_line_chart,
};
