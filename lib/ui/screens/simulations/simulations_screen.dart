import 'package:flutter/material.dart' hide Simulation;
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/models/simulation.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'scenario_compare_screen.dart';
import '../../../domain/models/entities.dart';
import 'other_entries.dart';
import 'sim_common.dart';
import 'simulation_screen.dart';

/// Gestão de simulações (cenários de orçamento).
class SimulationsScreen extends StatefulWidget {
  /// 0 = cenários, 1 = outras despesas, 2 = outras receitas.
  final int initialTab;
  final YearMonth? initialMonth;
  const SimulationsScreen({super.key, this.initialTab = 0, this.initialMonth});

  @override
  State<SimulationsScreen> createState() => _SimulationsScreenState();
}

enum _Show { active, archived, all }

class _SimulationsScreenState extends State<SimulationsScreen>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab,
  )..addListener(() => setState(() {}));

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  _Show show = _Show.active;
  String query = '';
  final selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final q = query.trim().toLowerCase();
    final list = fc.simulations.where((s) {
      if (show == _Show.active && s.isArchived) return false;
      if (show == _Show.archived && !s.isArchived) return false;
      return q.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q);
    }).toList();
    selected.removeWhere((id) => fc.simulationById(id) == null);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulações'),
        bottom: TabBar(
          controller: tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Cenários'),
            Tab(key: ValueKey('tab-other-expenses'), text: 'Outras despesas'),
            Tab(key: ValueKey('tab-other-income'), text: 'Outras receitas'),
          ],
        ),
        actions: [
          if (selected.isNotEmpty && tabs.index == 0)
            TextButton.icon(
              key: const ValueKey('sim-compare-selected'),
              onPressed: () => _compare(context, selected.toList()),
              icon: const Icon(Icons.compare_arrows),
              label: Text('Comparar (${selected.length})'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: tabs.index != 0
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('sim-create'),
              onPressed: () => _create(context),
              icon: const Icon(Icons.add),
              label: const Text('Criar simulação'),
            ),
      body: TabBarView(
        controller: tabs,
        children: [
          _scenarios(context, fc, list, wide),
          OtherEntriesView(
            type: TransactionType.expense,
            initialMonth: widget.initialMonth,
          ),
          OtherEntriesView(
            type: TransactionType.income,
            initialMonth: widget.initialMonth,
          ),
        ],
      ),
    );
  }

  Widget _scenarios(
    BuildContext context,
    FinanceController fc,
    List<Simulation> list,
    bool wide,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Cenários de orçamento em sandbox: o que você muda aqui não '
            'altera seus lançamentos, até você escolher "Aplicar ao '
            'orçamento".',
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar simulação',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              SegmentedButton<_Show>(
                segments: const [
                  ButtonSegment(value: _Show.active, label: Text('Ativas')),
                  ButtonSegment(
                    value: _Show.archived,
                    label: Text('Arquivadas'),
                  ),
                  ButtonSegment(value: _Show.all, label: Text('Todas')),
                ],
                selected: {show},
                onSelectionChanged: (s) => setState(() => show = s.first),
              ),
              OutlinedButton.icon(
                onPressed: fc.simulations.isEmpty
                    ? null
                    : () => _compare(context, selected.toList()),
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Comparar cenários'),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.science_outlined,
                  title: fc.simulations.isEmpty
                      ? 'Nenhuma simulação ainda'
                      : 'Nenhuma simulação aqui',
                  message: fc.simulations.isEmpty
                      ? 'Crie um cenário a partir do seu orçamento para '
                            'testar uma compra, um aumento de salário ou '
                            'uma nova despesa sem mexer nos dados reais.'
                      : null,
                  actionLabel: fc.simulations.isEmpty
                      ? 'Criar simulação'
                      : null,
                  onAction: fc.simulations.isEmpty
                      ? () => _create(context)
                      : null,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    if (wide) const _TableHeader(),
                    for (final s in list)
                      _SimRow(
                        sim: s,
                        wide: wide,
                        selected: selected.contains(s.id),
                        onSelect: (v) => setState(
                          () => v ? selected.add(s.id) : selected.remove(s.id),
                        ),
                        onAction: (a) => _action(context, s, a),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final fc = context.read<FinanceController>();
    final r = await showDialog<SimulationFormResult>(
      context: context,
      builder: (_) => SimulationFormDialog(simulations: fc.simulations),
    );
    if (r == null || !context.mounted) return;
    Simulation? created;
    final ok = await runAction(context, () async {
      created = await fc.createSimulation(
        name: r.name,
        description: r.description,
        from: r.from,
        to: r.to,
        color: r.color,
        base: r.base,
      );
    });
    if (ok && created != null && context.mounted) {
      await push(context, SimulationScreen(simulationId: created!.id));
    }
  }

  void _compare(BuildContext context, List<String> ids) =>
      push(context, ScenarioCompareScreen(initialIds: ids));

  Future<void> _action(BuildContext context, Simulation s, _Act a) async {
    final fc = context.read<FinanceController>();
    switch (a) {
      case _Act.open:
        await push(context, SimulationScreen(simulationId: s.id));
      case _Act.edit:
        final r = await showDialog<SimulationFormResult>(
          context: context,
          builder: (_) =>
              SimulationFormDialog(simulations: fc.simulations, editing: s),
        );
        if (r == null || !context.mounted) return;
        await runAction(
          context,
          () => fc.saveSimulation(
            s.copyWith(
              name: r.name,
              description: r.description,
              color: r.color,
            ),
          ),
        );
      case _Act.rename:
        final name = await _askName(context, 'Renomear simulação', s.name);
        if (name == null || !context.mounted) return;
        await runAction(
          context,
          () => fc.saveSimulation(s.copyWith(name: name)),
        );
      case _Act.duplicate:
        final name = await _askName(
          context,
          'Duplicar simulação',
          '${s.name} (cópia)',
        );
        if (name == null || !context.mounted) return;
        await runAction(
          context,
          () => fc.duplicateSimulation(s, name),
          success: 'Simulação duplicada',
        );
      case _Act.compare:
        _compare(context, [s.id]);
      case _Act.archive:
        await runAction(
          context,
          () => fc.saveSimulation(
            s.copyWith(
              status: s.isArchived
                  ? SimulationStatus.active
                  : SimulationStatus.archived,
            ),
          ),
          success: s.isArchived
              ? 'Simulação restaurada'
              : 'Simulação arquivada',
        );
      case _Act.delete:
        final ok = await confirmDialog(
          context,
          title: 'Excluir simulação?',
          message:
              '"${s.name}" será excluída. Seu orçamento oficial não é '
              'afetado.',
          confirm: 'Excluir',
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        await runAction(
          context,
          () => fc.deleteSimulation(s),
          success: 'Simulação excluída',
        );
    }
  }
}

Future<String?> _askName(BuildContext context, String title, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Nome'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
          ),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}

enum _Act { open, edit, duplicate, compare, rename, archive, delete }

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final st = context.text.labelMedium?.copyWith(color: context.fin.subtle);
    return Padding(
      padding: const EdgeInsets.fromLTRB(70, 4, 52, 8),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('Simulação', style: st)),
          Expanded(flex: 3, child: Text('Orçamento base', style: st)),
          Expanded(flex: 2, child: Text('Período', style: st)),
          Expanded(flex: 2, child: Text('Status', style: st)),
          Expanded(flex: 2, child: Text('Atualizada', style: st)),
        ],
      ),
    );
  }
}

class _SimRow extends StatelessWidget {
  final Simulation sim;
  final bool wide;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final ValueChanged<_Act> onAction;
  const _SimRow({
    required this.sim,
    required this.wide,
    required this.selected,
    required this.onSelect,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(sim.color);
    final status = Pill(
      sim.isArchived
          ? 'Arquivada'
          : sim.appliedAt != null
          ? 'Aplicada'
          : 'Ativa',
      color: sim.isArchived ? context.fin.subtle : context.fin.positive,
    );
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sim.name,
          style: context.text.titleSmall,
          overflow: TextOverflow.ellipsis,
        ),
        if (sim.description.isNotEmpty)
          Text(
            sim.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
      ],
    );
    final menu = PopupMenuButton<_Act>(
      tooltip: 'Ações',
      onSelected: onAction,
      itemBuilder: (_) => [
        const PopupMenuItem(value: _Act.open, child: Text('Abrir')),
        const PopupMenuItem(value: _Act.edit, child: Text('Editar')),
        const PopupMenuItem(value: _Act.duplicate, child: Text('Duplicar')),
        const PopupMenuItem(value: _Act.compare, child: Text('Comparar')),
        const PopupMenuItem(value: _Act.rename, child: Text('Renomear')),
        PopupMenuItem(
          value: _Act.archive,
          child: Text(sim.isArchived ? 'Restaurar' : 'Arquivar'),
        ),
        const PopupMenuItem(value: _Act.delete, child: Text('Excluir')),
      ],
    );
    final check = Checkbox(
      value: selected,
      onChanged: (v) => onSelect(v ?? false),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onAction(_Act.open),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              check,
              Container(
                width: 6,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              if (wide) ...[
                Expanded(flex: 4, child: name),
                Expanded(flex: 3, child: Text(sim.baseName)),
                Expanded(flex: 2, child: Text(sim.periodLabel)),
                Expanded(
                  flex: 2,
                  child: Align(alignment: Alignment.centerLeft, child: status),
                ),
                Expanded(flex: 2, child: Text(fmtUpdated(sim.updatedAt))),
              ] else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      name,
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          status,
                          Text(
                            '${sim.periodLabel} · base: ${sim.baseName} · '
                            '${fmtUpdated(sim.updatedAt)}',
                            style: context.text.bodySmall?.copyWith(
                              color: context.fin.subtle,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              menu,
            ],
          ),
        ),
      ),
    );
  }
}

class SimulationFormResult {
  final String name;
  final String description;
  final int color;
  final Simulation? base;
  final YearMonth from;
  final YearMonth to;
  const SimulationFormResult({
    required this.name,
    required this.description,
    required this.color,
    required this.base,
    required this.from,
    required this.to,
  });
}

enum _PeriodKind { month, year, range }

/// Criação (orçamento base + período) ou edição dos dados de uma simulação.
class SimulationFormDialog extends StatefulWidget {
  final List<Simulation> simulations;
  final Simulation? editing;
  const SimulationFormDialog({
    super.key,
    required this.simulations,
    this.editing,
  });

  @override
  State<SimulationFormDialog> createState() => _SimulationFormDialogState();
}

class _SimulationFormDialogState extends State<SimulationFormDialog> {
  late final name = TextEditingController(text: widget.editing?.name ?? '');
  late final desc = TextEditingController(
    text: widget.editing?.description ?? '',
  );
  late int color =
      widget.editing?.color ??
      simColors[widget.simulations.length % simColors.length];
  String? baseId;
  _PeriodKind kind = _PeriodKind.range;
  late YearMonth month = YearMonth.now();
  late int year = YearMonth.now().year;
  late YearMonth from = YearMonth.now();
  late YearMonth to = YearMonth.now().add(11);
  String? error;

  bool get editing => widget.editing != null;
  Simulation? get base =>
      widget.simulations.where((s) => s.id == baseId).firstOrNull;

  List<YearMonth> get monthOptions {
    final b = base;
    if (b != null) return b.months;
    final now = YearMonth.now();
    return YearMonth.range(
      YearMonth(now.year - 2, 1),
      YearMonth(now.year + 3, 12),
    ).toList();
  }

  List<int> get yearOptions =>
      {for (final m in monthOptions) m.year}.toList()..sort();

  (YearMonth, YearMonth) get period => switch (kind) {
    _PeriodKind.month => (month, month),
    _PeriodKind.year => _clampToBase(YearMonth(year, 1), YearMonth(year, 12)),
    _PeriodKind.range => (from, to),
  };

  (YearMonth, YearMonth) _clampToBase(YearMonth a, YearMonth b) {
    final s = base;
    if (s == null) return (a, b);
    return (a < s.from ? s.from : a, b > s.to ? s.to : b);
  }

  void _baseChanged(String? id) {
    setState(() {
      baseId = id;
      final b = base;
      if (b != null) {
        from = b.from;
        to = b.to;
        month = b.from;
        year = b.from.year;
        kind = _PeriodKind.range;
      }
    });
  }

  void _submit() {
    final n = name.text.trim();
    if (n.isEmpty) {
      setState(() => error = 'Informe o nome da simulação');
      return;
    }
    final (a, b) = period;
    if (b < a) {
      setState(() => error = 'O fim do período deve ser depois do início');
      return;
    }
    Navigator.pop(
      context,
      SimulationFormResult(
        name: n,
        description: desc.text.trim(),
        color: color,
        base: base,
        from: a,
        to: b,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opts = monthOptions;
    YearMonth fit(YearMonth m) => opts.contains(m) ? m : opts.first;
    return AlertDialog(
      title: Text(editing ? 'Editar simulação' : 'Criar simulação'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!editing) ...[
                DropdownButtonFormField<String?>(
                  key: const ValueKey('sim-form-base'),
                  initialValue: baseId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '1. Orçamento base',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Orçamento atual (lançamentos e previsões)'),
                    ),
                    for (final s in widget.simulations)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text('Simulação: ${s.name} (${s.periodLabel})'),
                      ),
                  ],
                  onChanged: _baseChanged,
                ),
                const SizedBox(height: 14),
                Text('2. Período a simular', style: context.text.labelLarge),
                const SizedBox(height: 6),
                SegmentedButton<_PeriodKind>(
                  segments: const [
                    ButtonSegment(value: _PeriodKind.month, label: Text('Mês')),
                    ButtonSegment(value: _PeriodKind.year, label: Text('Ano')),
                    ButtonSegment(
                      value: _PeriodKind.range,
                      label: Text('Período'),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) => setState(() => kind = s.first),
                ),
                const SizedBox(height: 10),
                switch (kind) {
                  _PeriodKind.month => MonthDropdown(
                    key: ValueKey('m-$baseId'),
                    label: 'Mês',
                    value: fit(month),
                    options: opts,
                    onChanged: (m) => setState(() => month = m),
                  ),
                  _PeriodKind.year => DropdownButtonFormField<int>(
                    key: ValueKey('y-$baseId'),
                    initialValue: yearOptions.contains(year)
                        ? year
                        : yearOptions.first,
                    decoration: const InputDecoration(labelText: 'Ano'),
                    items: [
                      for (final y in yearOptions)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (y) => setState(() => year = y ?? year),
                  ),
                  _PeriodKind.range => Row(
                    children: [
                      Expanded(
                        child: MonthDropdown(
                          key: ValueKey('f-$baseId'),
                          label: 'De',
                          value: fit(from),
                          options: opts,
                          onChanged: (m) => setState(() => from = m),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MonthDropdown(
                          key: ValueKey('t-$baseId'),
                          label: 'Até',
                          value: fit(to),
                          options: opts,
                          onChanged: (m) => setState(() => to = m),
                        ),
                      ),
                    ],
                  ),
                },
                const SizedBox(height: 14),
              ],
              TextField(
                key: const ValueKey('sim-form-name'),
                controller: name,
                autofocus: editing,
                decoration: InputDecoration(
                  labelText: editing ? 'Nome' : '3. Nome da simulação',
                  hintText: 'Ex.: Carro novo',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: desc,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: editing
                      ? 'Descrição / observações'
                      : '4. Descrição (opcional)',
                ),
              ),
              const SizedBox(height: 14),
              Text('Cor', style: context.text.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in simColors)
                    InkWell(
                      onTap: () => setState(() => color = c),
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(c),
                        child: c == color
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: TextStyle(color: context.colors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('sim-form-submit'),
          onPressed: _submit,
          child: Text(editing ? 'Salvar' : 'Criar'),
        ),
      ],
    );
  }
}
