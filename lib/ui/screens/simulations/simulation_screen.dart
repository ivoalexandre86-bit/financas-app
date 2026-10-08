import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../domain/engine/simulation_engine.dart';
import '../../../domain/models/simulation.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'scenario_compare_screen.dart';
import 'sim_grid.dart';
import 'sim_views.dart';
import 'simulations_screen.dart';

/// Uma simulação aberta: planilha, comparação com a base e painel.
///
/// As edições ficam em memória (com desfazer/refazer) até "Salvar"; nada
/// aqui altera os lançamentos oficiais, exceto "Aplicar ao orçamento", que
/// pede confirmação.
class SimulationScreen extends StatefulWidget {
  final String simulationId;
  const SimulationScreen({super.key, required this.simulationId});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

enum _Menu { edit, reset, compare, apply }

class _SimulationScreenState extends State<SimulationScreen> {
  Simulation? saved;
  List<SimItem> items = const [];
  final undo = <List<SimItem>>[];
  final redo = <List<SimItem>>[];
  bool dirty = false;

  @override
  void initState() {
    super.initState();
    saved = context.read<FinanceController>().simulationById(
      widget.simulationId,
    );
    items = saved?.items ?? const [];
  }

  Simulation get working => saved!.copyWith(items: items);

  void _change(List<SimItem> next) => setState(() {
    undo.add(items);
    if (undo.length > 200) undo.removeAt(0);
    redo.clear();
    items = next;
    dirty = true;
  });

  void _undo() {
    if (undo.isEmpty) return;
    setState(() {
      redo.add(items);
      items = undo.removeLast();
      dirty = true;
    });
  }

  void _redo() {
    if (redo.isEmpty) return;
    setState(() {
      undo.add(items);
      items = redo.removeLast();
      dirty = true;
    });
  }

  Future<bool> _save() async {
    final fc = context.read<FinanceController>();
    final ok = await runAction(
      context,
      () => fc.saveSimulation(working),
      success: 'Simulação salva',
    );
    if (ok && mounted) {
      setState(() {
        saved = fc.simulationById(widget.simulationId);
        dirty = false;
      });
    }
    return ok;
  }

  void _discard() => setState(() {
    items = saved!.items;
    undo.clear();
    redo.clear();
    dirty = false;
  });

  Future<void> _menu(_Menu m) async {
    final fc = context.read<FinanceController>();
    switch (m) {
      case _Menu.edit:
        final r = await showDialog<SimulationFormResult>(
          context: context,
          builder: (_) =>
              SimulationFormDialog(simulations: fc.simulations, editing: saved),
        );
        if (r == null || !mounted) return;
        final next = saved!.copyWith(
          name: r.name,
          description: r.description,
          color: r.color,
        );
        final ok = await runAction(context, () => fc.saveSimulation(next));
        if (ok && mounted) {
          setState(() => saved = fc.simulationById(widget.simulationId));
        }
      case _Menu.reset:
        final ok = await confirmDialog(
          context,
          title: 'Restaurar simulação?',
          message:
              'Todas as linhas voltam a ser exatamente como no orçamento base '
              '"${saved!.baseName}" de quando a simulação foi criada. Você '
              'ainda pode desfazer antes de salvar.',
          confirm: 'Restaurar',
        );
        if (ok) _change(saved!.baseItems);
      case _Menu.compare:
        await push(
          context,
          ScenarioCompareScreen(initialIds: [widget.simulationId]),
        );
      case _Menu.apply:
        await _apply(fc);
    }
  }

  Future<void> _apply(FinanceController fc) async {
    if (dirty) {
      final ok = await confirmDialog(
        context,
        title: 'Salvar antes de aplicar?',
        message: 'A simulação tem alterações não salvas. Salve para continuar.',
        confirm: 'Salvar',
      );
      if (!ok || !mounted || !await _save()) return;
    }
    if (!mounted) return;
    final plan = fc.simulationPlan(working);
    if (plan.isEmpty) {
      showMessage(context, 'A simulação não tem diferenças em relação à base.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ApplyDialog(sim: working, plan: plan),
    );
    if (confirmed != true || !mounted) return;
    final ok = await runAction(
      context,
      () => fc.applySimulation(working),
      success: '${plan.changes.length} alterações aplicadas ao orçamento',
    );
    if (ok && mounted) {
      setState(() => saved = fc.simulationById(widget.simulationId));
    }
  }

  Future<void> _confirmLeave() async {
    final nav = Navigator.of(context);
    final leave = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alterações não salvas'),
        content: const Text('Deseja salvar a simulação antes de sair?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stay'),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Descartar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (leave == 'discard') {
      _discard();
      nav.pop();
    } else if (leave == 'save' && await _save()) {
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    if (saved == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.science_outlined,
          title: 'Simulação não encontrada',
        ),
      );
    }
    final sim = working;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (dirty) _save();
          },
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        },
        child: Focus(
          autofocus: true,
          child: DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                title: Row(
                  children: [
                    CircleAvatar(radius: 6, backgroundColor: Color(sim.color)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sim.name, overflow: TextOverflow.ellipsis),
                          Text(
                            '${sim.periodLabel} · base: ${sim.baseName}'
                            '${dirty ? ' · não salva' : ''}',
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(
                              color: context.fin.subtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Desfazer (Ctrl+Z)',
                    onPressed: undo.isEmpty ? null : _undo,
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: 'Refazer (Ctrl+Y)',
                    onPressed: redo.isEmpty ? null : _redo,
                    icon: const Icon(Icons.redo),
                  ),
                  if (dirty)
                    TextButton(
                      key: const ValueKey('sim-cancel'),
                      onPressed: _discard,
                      child: const Text('Cancelar'),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilledButton.icon(
                      key: const ValueKey('sim-save'),
                      onPressed: dirty ? _save : null,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Salvar'),
                    ),
                  ),
                  PopupMenuButton<_Menu>(
                    key: const ValueKey('sim-menu'),
                    onSelected: _menu,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _Menu.edit,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Editar nome e descrição'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _Menu.reset,
                        child: ListTile(
                          leading: Icon(Icons.restart_alt),
                          title: Text('Restaurar orçamento base'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _Menu.compare,
                        child: ListTile(
                          leading: Icon(Icons.compare_arrows),
                          title: Text('Comparar com outros cenários'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _Menu.apply,
                        child: ListTile(
                          leading: Icon(Icons.publish_outlined),
                          title: Text('Aplicar ao orçamento…'),
                        ),
                      ),
                    ],
                  ),
                ],
                bottom: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(icon: Icon(Icons.grid_on), text: 'Planilha'),
                    Tab(icon: Icon(Icons.compare), text: 'Comparação'),
                    Tab(icon: Icon(Icons.insights), text: 'Painel'),
                  ],
                ),
              ),
              body: Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: context.colors.primaryContainer.withValues(
                      alpha: 0.35,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 16,
                          color: context.colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Modo simulação: nada aqui altera seus lançamentos '
                            'reais.',
                            style: context.text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SimSummaryStrip(sim: sim),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        SimGrid(fc: fc, sim: sim, onChanged: _change),
                        SimCompareView(sim: sim),
                        SimDashboardView(fc: fc, sim: sim),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApplyDialog extends StatefulWidget {
  final Simulation sim;
  final SimApplyPlan plan;
  const _ApplyDialog({required this.sim, required this.plan});

  @override
  State<_ApplyDialog> createState() => _ApplyDialogState();
}

class _ApplyDialogState extends State<_ApplyDialog> {
  bool understood = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final groups = <SimChangeKind, List<SimChange>>{};
    for (final c in plan.changes) {
      (groups[c.kind] ??= []).add(c);
    }
    return AlertDialog(
      title: const Text('Aplicar simulação ao orçamento'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Você vai aplicar ${plan.changes.length} '
                '${plan.changes.length == 1 ? 'alteração' : 'alterações'} '
                'de "${widget.sim.name}" ao seu orçamento de '
                '${widget.sim.periodLabel}.',
                style: context.text.bodyLarge,
              ),
              const SizedBox(height: 12),
              for (final kind in SimChangeKind.values)
                if (groups[kind] != null) ...[
                  Text(
                    '${kind.label} (${groups[kind]!.length})',
                    style: context.text.titleSmall,
                  ),
                  for (final c in groups[kind]!)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '• ${c.description}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: ' — ${c.detail}'),
                          ],
                        ),
                        style: context.text.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
              Text(
                'Novas linhas viram lançamentos previstos (ou recorrências, '
                'quando o valor se repete). Valores alterados ajustam só os '
                'meses mudados. Lançamentos removidos são excluídos do '
                'período.',
                style: context.text.bodySmall?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('sim-apply-check'),
                contentPadding: EdgeInsets.zero,
                value: understood,
                onChanged: (v) => setState(() => understood = v ?? false),
                title: const Text(
                  'Entendo que estas alterações mudam meu orçamento oficial.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('sim-apply-confirm'),
          onPressed: understood ? () => Navigator.pop(context, true) : null,
          child: const Text('Aplicar alterações'),
        ),
      ],
    );
  }
}
