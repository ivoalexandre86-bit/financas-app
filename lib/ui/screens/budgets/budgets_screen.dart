import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/budget_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../domain/models/planning.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/plan_upsell.dart';

/// Orçamentos que o plano Grátis permite.
const gratisBudgetLimit = 3;

/// Limites mensais por categoria: quanto já foi gasto, o que ainda está
/// previsto no mês e os avisos de limite.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});
  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  YearMonth month = YearMonth.now();

  Future<void> _new(BuildContext context, {String? categoryId}) {
    final fc = context.read<FinanceController>();
    if (isGratisPlan(context, listen: false) &&
        fc.budgets.length >= gratisBudgetLimit) {
      return showPlanUpsell(
        context,
        feature:
            'No plano Grátis você pode ter até $gratisBudgetLimit '
            'orçamentos. Assine o Básico para criar orçamentos em todas as '
            'categorias.',
      );
    }
    return showBudgetDialog(context, categoryId: categoryId, month: month);
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final be = fc.budgetEngine;
    final statuses = be.statuses(fc.budgets, month);
    final free = be.unbudgeted(fc.budgets, month);
    var limit = Money.zero, spent = Money.zero, planned = Money.zero;
    for (final s in statuses) {
      limit += s.budget.amount;
      spent += s.spent;
      planned += s.planned;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Orçamentos')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-budget',
        onPressed: () => _new(context),
        icon: const Icon(Icons.add),
        label: const Text('Novo orçamento'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Center(
            child: MonthSwitcher(
              month: month,
              onChanged: (m) => setState(() => month = m),
            ),
          ),
          const SizedBox(height: 8),
          if (statuses.isEmpty)
            SectionCard(
              child: EmptyState(
                icon: Icons.savings_outlined,
                title: 'Nenhum orçamento',
                message:
                    'Defina quanto quer gastar por mês em cada categoria. O '
                    'app mostra quanto já foi gasto e avisa quando chegar '
                    'perto do limite.',
                actionLabel: 'Criar orçamento',
                onAction: () => _new(context),
              ),
            )
          else ...[
            _Summary(limit: limit, spent: spent, planned: planned),
            const SizedBox(height: 12),
            for (final s in statuses) ...[
              BudgetTile(
                status: s,
                onTap: () =>
                    showBudgetDialog(context, budget: s.budget, month: month),
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (free.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Gastos sem orçamento',
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  for (final f in free.take(8))
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(f.category.color)
                            .withValues(alpha: 0.15),
                        child: Icon(
                          categoryIcon(f.category.icon),
                          color: Color(f.category.color),
                          size: 20,
                        ),
                      ),
                      title: Text(f.category.name),
                      subtitle: MoneyText(f.amount),
                      trailing: TextButton(
                        onPressed: () =>
                            _new(context, categoryId: f.category.id),
                        child: const Text('Definir limite'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final Money limit, spent, planned;
  const _Summary({
    required this.limit,
    required this.spent,
    required this.planned,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = limit - spent;
    return SectionCard(
      child: Row(
        children: [
          Expanded(child: _Kv('Limite', MoneyText(limit))),
          Expanded(
            child: _Kv('Gasto', MoneyText(spent, color: context.fin.expense)),
          ),
          Expanded(child: _Kv('Previsto', MoneyText(planned))),
          Expanded(
            child: _Kv(
              remaining.isNegative ? 'Excedido' : 'Disponível',
              MoneyText(
                Money(remaining.cents.abs()),
                color: remaining.isNegative ? context.fin.negative : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha de um orçamento: barra com o gasto (cheia) e o previsto (clara).
class BudgetTile extends StatelessWidget {
  final BudgetStatus status;
  final VoidCallback? onTap;
  final bool dense;
  const BudgetTile({
    super.key,
    required this.status,
    this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final cat = fc.data.categoryById[status.budget.categoryId];
    final color = cat == null ? context.fin.subtle : Color(cat.color);
    final barColor = status.isOver
        ? context.fin.negative
        : status.isAlert || status.willExceed
        ? context.fin.warning
        : color;
    final pill = status.isOver
        ? Pill('Estourado', color: context.fin.negative)
        : status.isAlert
        ? Pill('${(status.ratio * 100).round()}%', color: context.fin.warning)
        : status.willExceed
        ? Pill('Vai passar', color: context.fin.warning)
        : null;
    final body = Padding(
      padding: EdgeInsets.all(dense ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(categoryIcon(cat?.icon), color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cat == null
                      ? 'Categoria excluída'
                      : fc.engine.categoryLabel(cat.id),
                  style: context.text.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?pill,
            ],
          ),
          const SizedBox(height: 8),
          _BudgetBar(
            spent: status.ratio,
            forecast: status.forecastRatio,
            color: barColor,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${status.spent.format()} de ${status.budget.amount.format()}',
                  style: context.text.bodySmall,
                ),
              ),
              Text(
                status.isOver
                    ? 'Passou ${Money(-status.remaining.cents).format()}'
                    : 'Restam ${status.remaining.format()}',
                style: context.text.bodySmall?.copyWith(
                  color: status.isOver
                      ? context.fin.negative
                      : context.fin.subtle,
                ),
              ),
            ],
          ),
          if (status.planned.isPositive && !dense)
            Text(
              'Previsto ainda no mês: ${status.planned.format()}',
              style: context.text.bodySmall?.copyWith(
                color: context.fin.subtle,
              ),
            ),
        ],
      ),
    );
    if (dense) return InkWell(onTap: onTap, child: body);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: body,
      ),
    );
  }
}

class _BudgetBar extends StatelessWidget {
  final double spent, forecast;
  final Color color;
  const _BudgetBar({
    required this.spent,
    required this.forecast,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: context.fin.gridLine),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: forecast.clamp(0, 1).toDouble(),
              child: ColoredBox(color: color.withValues(alpha: 0.3)),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: spent.clamp(0, 1).toDouble(),
              child: ColoredBox(color: color),
            ),
          ],
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

/// Cria ou edita um orçamento.
Future<void> showBudgetDialog(
  BuildContext context, {
  Budget? budget,
  String? categoryId,
  required YearMonth month,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _BudgetDialog(budget: budget, categoryId: categoryId, month: month),
);

class _BudgetDialog extends StatefulWidget {
  final Budget? budget;
  final String? categoryId;
  final YearMonth month;
  const _BudgetDialog({this.budget, this.categoryId, required this.month});
  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late String? categoryId = widget.budget?.categoryId ?? widget.categoryId;
  late final amount = TextEditingController(
    text: widget.budget?.amount.formatPlain() ?? '',
  );
  late double alert = (widget.budget?.alertPercent ?? 80).toDouble();
  bool _prefilled = false;

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final avg = categoryId == null
        ? null
        : fc.budgetEngine.averageSpending(categoryId!, widget.month);
    if (!_prefilled && widget.budget == null && avg != null && avg.isPositive) {
      _prefilled = true;
      amount.text = Money(((avg.cents + 999) ~/ 1000) * 1000).formatPlain();
    }
    return AlertDialog(
      title: Text(
        widget.budget == null ? 'Novo orçamento' : 'Editar orçamento',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CategoryDropdown(
                fc: fc,
                kind: CategoryKind.expense,
                value: categoryId,
                onChanged: (v) => setState(() {
                  categoryId = v;
                  _prefilled = false;
                }),
              ),
              const SizedBox(height: 12),
              MoneyField(controller: amount, label: 'Limite por mês'),
              if (avg != null && avg.isPositive)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Média dos últimos 3 meses: ${avg.format()}',
                    style: context.text.bodySmall?.copyWith(
                      color: context.fin.subtle,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Avisar ao chegar em ${alert.round()}% do limite'),
              Slider(
                value: alert,
                min: 50,
                max: 100,
                divisions: 10,
                label: '${alert.round()}%',
                onChanged: (v) => setState(() => alert = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.budget != null)
          TextButton(
            onPressed: () async {
              final ok = await runAction(
                context,
                () => fc.deleteBudget(widget.budget!),
                success: 'Orçamento excluído',
              );
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('Excluir'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            final v = Money.tryEval(amount.text);
            final b =
                widget.budget?.copyWith(
                  categoryId: categoryId,
                  amount: v,
                  alertPercent: alert.round(),
                ) ??
                Budget(
                  id: newId('bud_'),
                  categoryId: categoryId ?? '',
                  amount: v ?? Money.zero,
                  alertPercent: alert.round(),
                );
            final ok = await runAction(
              context,
              () => fc.saveBudget(b),
              success: 'Orçamento salvo',
            );
            if (ok && context.mounted) Navigator.pop(context);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
