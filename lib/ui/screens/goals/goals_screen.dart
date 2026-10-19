import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/budget_engine.dart';
import '../../../domain/models/planning.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/plan_upsell.dart';

/// Metas que o plano Grátis permite.
const gratisGoalLimit = 1;

/// Metas de economia: quanto falta, quanto guardar por mês e aportes.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  bool showArchived = false;

  void _new(BuildContext context) {
    final fc = context.read<FinanceController>();
    final active = fc.goals.where((g) => !g.archived).length;
    if (isGratisPlan(context, listen: false) && active >= gratisGoalLimit) {
      showPlanUpsell(
        context,
        feature:
            'No plano Grátis você pode ter $gratisGoalLimit meta ativa. '
            'Assine o Básico para criar quantas metas quiser.',
      );
      return;
    }
    push(context, const GoalFormScreen());
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final goals = fc.goals.where((g) => showArchived || !g.archived).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas de economia'),
        actions: [
          IconButton(
            tooltip: showArchived ? 'Ocultar arquivadas' : 'Mostrar arquivadas',
            icon: Icon(
              showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
            ),
            onPressed: () => setState(() => showArchived = !showArchived),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-goal',
        onPressed: () => _new(context),
        icon: const Icon(Icons.add),
        label: const Text('Nova meta'),
      ),
      body: goals.isEmpty
          ? EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'Nenhuma meta',
              message:
                  'Crie metas como “Reserva de emergência” ou “Viagem”. O '
                  'app calcula quanto guardar por mês para chegar no prazo.',
              actionLabel: 'Criar meta',
              onAction: () => _new(context),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: goals.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  GoalCard(status: fc.budgetEngine.goal(goals[i])),
            ),
    );
  }
}

class GoalCard extends StatelessWidget {
  final GoalStatus status;
  const GoalCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final g = status.goal;
    final color = Color(g.color);
    final fc = context.read<FinanceController>();
    final account = fc.data.accountById[g.accountId];
    final needed = status.monthlyNeeded;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => push(context, GoalDetailsScreen(goalId: g.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.emoji_events_outlined, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(g.name, style: context.text.titleMedium),
                  ),
                  if (status.reached)
                    Pill('Concluída', color: context.fin.positive)
                  else if (status.overdue)
                    Pill('Prazo vencido', color: context.fin.negative)
                  else if (g.archived)
                    Pill('Arquivada', color: context.fin.subtle),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: status.progress,
                  minHeight: 8,
                  color: status.reached ? context.fin.positive : color,
                  backgroundColor: context.fin.gridLine,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${status.saved.format()} de ${g.target.format()} '
                '(${(status.progress * 100).round()}%)',
                style: context.text.bodyMedium,
              ),
              if (!status.reached)
                Text(
                  [
                    'Faltam ${status.remaining.format()}',
                    if (g.deadline != null) 'até ${Dates.format(g.deadline!)}',
                    if (needed != null) '· guarde ${needed.format()} por mês',
                  ].join(' '),
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
              if (account != null)
                Text(
                  'Saldo da conta ${account.name}',
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GoalDetailsScreen extends StatelessWidget {
  final String goalId;
  const GoalDetailsScreen({super.key, required this.goalId});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final g = fc.goals.where((x) => x.id == goalId).firstOrNull;
    if (g == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Meta excluída')),
      );
    }
    final status = fc.budgetEngine.goal(g);
    final linked = g.accountId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(g.name),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => push(context, GoalFormScreen(goal: g)),
          ),
          IconButton(
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirmDialog(
                context,
                title: 'Excluir meta?',
                message: 'A meta e os aportes registrados nela serão apagados.',
              )) {
                return;
              }
              if (!context.mounted) return;
              final ok = await runAction(context, () => fc.deleteGoal(g));
              if (ok && context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      floatingActionButton: linked
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab-goal-add',
              onPressed: () => _contributionDialog(context, g),
              icon: const Icon(Icons.add),
              label: const Text('Guardar dinheiro'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          GoalCard(status: status),
          const SizedBox(height: 12),
          if (linked)
            SectionCard(
              child: Text(
                'O valor guardado é o saldo atual da conta vinculada. Para '
                'guardar mais, transfira dinheiro para essa conta.',
                style: context.text.bodyMedium,
              ),
            )
          else
            SectionCard(
              title: 'Aportes',
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: g.contributions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Nenhum aporte ainda.'),
                    )
                  : Column(
                      children: [
                        for (final c in g.contributions.reversed)
                          ListTile(
                            leading: Icon(
                              c.amount.isNegative
                                  ? Icons.remove_circle_outline
                                  : Icons.add_circle_outline,
                              color: c.amount.isNegative
                                  ? context.fin.negative
                                  : context.fin.positive,
                            ),
                            title: MoneyText(c.amount, colorize: true),
                            subtitle: Text(
                              [
                                Dates.format(c.date),
                                if (c.note.isNotEmpty) c.note,
                              ].join(' · '),
                            ),
                            trailing: IconButton(
                              tooltip: 'Excluir aporte',
                              icon: const Icon(Icons.close),
                              onPressed: () => runAction(
                                context,
                                () => fc.deleteGoalContribution(g, c),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

Future<void> _contributionDialog(BuildContext context, SavingsGoal g) async {
  final fc = context.read<FinanceController>();
  final amount = TextEditingController();
  final note = TextEditingController();
  var withdraw = false;
  var date = fc.today;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Movimentar meta'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Guardar')),
                  ButtonSegment(value: true, label: Text('Retirar')),
                ],
                selected: {withdraw},
                onSelectionChanged: (s) => setState(() => withdraw = s.first),
              ),
              const SizedBox(height: 12),
              MoneyField(controller: amount, autofocus: true),
              const SizedBox(height: 12),
              DateField(
                value: date,
                onChanged: (d) => setState(() => date = d ?? date),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Observação'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final v = Money.tryEval(amount.text) ?? Money.zero;
              final ok = await runAction(
                ctx,
                () => fc.addGoalContribution(
                  g,
                  GoalContribution(
                    id: newId('gc_'),
                    date: date,
                    amount: withdraw ? -v : v,
                    note: note.text.trim(),
                  ),
                ),
                success: withdraw ? 'Retirada registrada' : 'Aporte registrado',
              );
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

class GoalFormScreen extends StatefulWidget {
  final SavingsGoal? goal;
  const GoalFormScreen({super.key, this.goal});
  @override
  State<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends State<GoalFormScreen> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.goal?.name ?? '');
  late final target = TextEditingController(
    text: widget.goal?.target.formatPlain() ?? '',
  );
  late final initial = TextEditingController();
  late DateTime? deadline = widget.goal?.deadline;
  late String? accountId = widget.goal?.accountId;
  late int color = widget.goal?.color ?? palette[2];
  late bool archived = widget.goal?.archived ?? false;

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final isNew = widget.goal == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'Nova meta' : 'Editar meta')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 12),
            MoneyField(controller: target, label: 'Valor da meta'),
            const SizedBox(height: 12),
            DateField(
              value: deadline,
              label: 'Prazo (opcional)',
              clearable: true,
              onChanged: (d) => setState(() => deadline = d),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: accountId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Onde o dinheiro fica',
                helperText:
                    'Com uma conta vinculada, o valor guardado é o saldo dela.',
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Registrar aportes manualmente'),
                ),
                for (final a in fc.activeAccounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => accountId = v),
            ),
            if (isNew && accountId == null) ...[
              const SizedBox(height: 12),
              MoneyField(
                controller: initial,
                label: 'Já guardado (opcional)',
                allowZero: true,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in palette)
                  GestureDetector(
                    onTap: () => setState(() => color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: color == c
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            if (!isNew)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Arquivada'),
                value: archived,
                onChanged: (v) => setState(() => archived = v),
              ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                final t = Money.tryEval(target.text) ?? Money.zero;
                final start = Money.tryEval(initial.text) ?? Money.zero;
                final g =
                    (widget.goal ??
                            SavingsGoal(
                              id: newId('goal_'),
                              name: name.text.trim(),
                              target: t,
                              contributions: [
                                if (start.isPositive)
                                  GoalContribution(
                                    id: newId('gc_'),
                                    date: fc.today,
                                    amount: start,
                                    note: 'Valor inicial',
                                  ),
                              ],
                            ))
                        .copyWith(
                          name: name.text.trim(),
                          target: t,
                          deadline: deadline,
                          accountId: accountId,
                          color: color,
                          archived: archived,
                        );
                final ok = await runAction(
                  context,
                  () => fc.saveGoal(g),
                  success: 'Meta salva',
                );
                if (ok && context.mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
