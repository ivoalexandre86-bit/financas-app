import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/month_closing.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import 'month_adjust_screen.dart';
import 'month_end_plan_screen.dart';

// Fechar o mês, ajustar o resultado manualmente e reverter (reabrir).

/// Folha de ações de um mês: fechar, ajustar, editar o ajuste ou reabrir.
///
/// "Ajustar" abre a grade [MonthAdjustScreen] com [range] (padrão: o mês e
/// os seguintes, 6 meses), com o foco no mês.
Future<void> showMonthClosingActions(
  BuildContext context,
  YearMonth month, {
  MonthRange? range,
}) {
  void openGrid() => push(
    context,
    MonthAdjustScreen(
      range: range ?? MonthRange.starting(month, 6),
      focus: month,
    ),
  );
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final fc = ctx.watch<FinanceController>();
      final closing = fc.closingOf(month);
      final now = fc.engine.computedMonthTotals(ProjectionFilter.none, month);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'Resultado de ${month.longLabel}',
                  style: ctx.text.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: closing == null
                    ? _Totals(
                        title: 'Calculado pelos lançamentos',
                        income: now.income,
                        expenses: now.expenses,
                      )
                    : ClosingSummary(closing: closing, computedNow: now),
              ),
              const Divider(height: 24),
              if (closing == null) ...[
                ListTile(
                  key: const ValueKey('closing-close'),
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Fechar mês'),
                  subtitle: const Text(
                    'Congela o resultado atual. Lançamentos feitos ou '
                    'alterados depois não mudam mais este mês.',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await runAction(
                      context,
                      () => fc.closeMonth(month),
                      success: '${month.longLabel} fechado',
                    );
                    // Último passo do fechamento: o que fazer com o dinheiro.
                    if (ok && context.mounted) {
                      push(context, MonthEndPlanScreen(month: month));
                    }
                  },
                ),
                ListTile(
                  key: const ValueKey('closing-adjust'),
                  leading: const Icon(Icons.tune),
                  title: const Text('Ajustar resultado manualmente'),
                  subtitle: const Text(
                    'Abre a grade para digitar o ajuste mês a mês.',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    openGrid();
                  },
                ),
              ] else ...[
                ListTile(
                  key: const ValueKey('closing-next-steps'),
                  leading: const Icon(Icons.lightbulb_outline),
                  title: const Text('O que fazer agora?'),
                  subtitle: Text(
                    closing.decision == null
                        ? 'Quanto está livre de verdade e o que fazer com a sobra '
                              'ou com a falta de caixa.'
                        : 'Decisão registrada: ${closing.decision!.title}',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    push(context, MonthEndPlanScreen(month: month));
                  },
                ),
                ListTile(
                  key: const ValueKey('closing-adjust'),
                  leading: const Icon(Icons.tune),
                  title: Text(
                    closing.isAdjusted
                        ? 'Editar ajuste manual'
                        : 'Ajustar resultado manualmente',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    openGrid();
                  },
                ),
                if (closing.isAdjusted)
                  ListTile(
                    key: const ValueKey('closing-recalc'),
                    leading: const Icon(Icons.restart_alt),
                    title: const Text('Desfazer só o ajuste'),
                    subtitle: Text(
                      'Mantém o mês fechado com os valores calculados agora '
                      '(resultado ${now.net.format()}).',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await runAction(
                        context,
                        () => fc.closeMonth(month, note: closing.note),
                        success: 'Ajuste desfeito',
                      );
                    },
                  ),
                ListTile(
                  key: const ValueKey('closing-reopen'),
                  leading: Icon(Icons.lock_open, color: ctx.colors.error),
                  title: const Text('Reabrir mês (reverter)'),
                  subtitle: const Text(
                    'Remove o fechamento e o ajuste: o mês volta a ser '
                    'calculado pelos lançamentos.',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await reopenMonthWithConfirm(context, month);
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Ver todos os fechamentos e ajustes'),
                onTap: () {
                  Navigator.pop(ctx);
                  push(context, const MonthClosingsScreen());
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> reopenMonthWithConfirm(
  BuildContext context,
  YearMonth month,
) async {
  final fc = context.read<FinanceController>();
  final ok = await confirmDialog(
    context,
    title: 'Reabrir ${month.longLabel}?',
    message:
        'O fechamento e o ajuste manual deste mês serão revertidos e o '
        'resultado volta a ser calculado pelos lançamentos.',
    confirm: 'Reabrir',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await runAction(
    context,
    () => fc.reopenMonth(month),
    success: '${month.longLabel} reaberto',
  );
}

/// Diálogo do ajuste manual: receitas, despesas e observação.
Future<void> showAdjustMonthDialog(BuildContext context, YearMonth month) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AdjustDialog(month: month),
  );
}

class _AdjustDialog extends StatefulWidget {
  final YearMonth month;
  const _AdjustDialog({required this.month});

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController income;
  late final TextEditingController expenses;
  late final TextEditingController note;
  late final MonthTotals computed;

  @override
  void initState() {
    super.initState();
    final fc = context.read<FinanceController>();
    computed = fc.engine.computedMonthTotals(
      ProjectionFilter.none,
      widget.month,
    );
    final c = fc.closingOf(widget.month);
    income = TextEditingController(
      text: (c?.income ?? computed.income).formatPlain(),
    );
    expenses = TextEditingController(
      text: (c?.expenses ?? computed.expenses).formatPlain(),
    );
    note = TextEditingController(text: c?.note ?? '');
  }

  @override
  void dispose() {
    income.dispose();
    expenses.dispose();
    note.dispose();
    super.dispose();
  }

  Money _v(TextEditingController c) => Money.tryEval(c.text) ?? Money.zero;

  @override
  Widget build(BuildContext context) {
    final net = _v(income) - _v(expenses);
    final diff = net - computed.net;
    return AlertDialog(
      title: Text('Ajustar ${widget.month.longLabel}'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Calculado pelos lançamentos: receitas '
                  '${computed.income.format()}, despesas '
                  '${computed.expenses.format()}, resultado '
                  '${computed.net.format()}.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
                const SizedBox(height: 12),
                MoneyField(
                  key: const ValueKey('adjust-income'),
                  controller: income,
                  label: 'Receitas do mês',
                  allowZero: true,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                MoneyField(
                  key: const ValueKey('adjust-expenses'),
                  controller: expenses,
                  label: 'Despesas do mês',
                  allowZero: true,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('adjust-note'),
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                    hintText: 'Ex.: conferido com o extrato',
                  ),
                ),
                const SizedBox(height: 16),
                InfoRow('Resultado', MoneyText(net, colorize: true)),
                InfoRow(
                  'Ajuste',
                  MoneyText(diff, colorize: true, showPlus: true),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('adjust-save'),
          onPressed: () async {
            if (!_form.currentState!.validate()) return;
            final fc = context.read<FinanceController>();
            final nav = Navigator.of(context);
            final ok = await runAction(
              context,
              () => fc.adjustMonthResult(
                widget.month,
                income: _v(income),
                expenses: _v(expenses),
                note: note.text,
              ),
              success: 'Resultado de ${widget.month.longLabel} ajustado',
            );
            if (ok) nav.pop();
          },
          child: const Text('Salvar e fechar mês'),
        ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  final String title;
  final Money income;
  final Money expenses;
  const _Totals({
    required this.title,
    required this.income,
    required this.expenses,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: context.text.labelLarge),
      InfoRow('Receitas', MoneyText(income)),
      InfoRow('Despesas', MoneyText(expenses)),
      InfoRow(
        'Resultado',
        MoneyText(
          income - expenses,
          colorize: true,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

/// Resumo de um mês fechado: valores que valem, o que os lançamentos dão
/// hoje e a diferença.
class ClosingSummary extends StatelessWidget {
  final MonthClosing closing;
  final MonthTotals computedNow;
  const ClosingSummary({
    super.key,
    required this.closing,
    required this.computedNow,
  });

  @override
  Widget build(BuildContext context) {
    final diff = closing.net - computedNow.net;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              closing.isAdjusted ? Icons.tune : Icons.lock,
              size: 16,
              color: context.colors.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                closing.isAdjusted
                    ? 'Fechado com ajuste manual em '
                          '${Dates.format(closing.updatedAt)}'
                    : 'Fechado em ${Dates.format(closing.updatedAt)}',
                style: context.text.labelLarge,
              ),
            ),
          ],
        ),
        InfoRow('Receitas', MoneyText(closing.computedIncome)),
        InfoRow('Despesas', MoneyText(closing.computedExpenses)),
        if (!closing.adjustment.isZero)
          InfoRow(
            'Ajuste manual',
            MoneyText(closing.adjustment, colorize: true, showPlus: true),
          ),
        InfoRow(
          'Resultado considerado',
          MoneyText(
            closing.net,
            colorize: true,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        InfoRow('Pelos lançamentos hoje', MoneyText(computedNow.net)),
        if (!diff.isZero)
          InfoRow('Diferença', MoneyText(diff, colorize: true, showPlus: true)),
        if (closing.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              closing.note!,
              style: context.text.bodySmall?.copyWith(
                color: context.fin.subtle,
              ),
            ),
          ),
      ],
    );
  }
}

/// Lista de todos os meses fechados/ajustados, com reverter um ou todos.
class MonthClosingsScreen extends StatelessWidget {
  const MonthClosingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final list = fc.monthClosings;
    final adjusted = list.where((c) => c.isAdjusted).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Fechamentos e ajustes')),
      body: list.isEmpty
          ? const EmptyState(
              icon: Icons.lock_clock,
              title: 'Nenhum mês fechado',
              message:
                  'Na Projeção, toque no nome de um mês para fechar o '
                  'resultado ou ajustá-lo manualmente.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Meses fechados usam os valores abaixo em Início, '
                    'Projeção, gráficos e relatórios (na visão sem filtros). '
                    'Reabrir reverte para o cálculo pelos lançamentos.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.fin.subtle,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (adjusted.isNotEmpty)
                        OutlinedButton.icon(
                          key: const ValueKey('closings-revert-adjusted'),
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: Text(
                            'Reverter ajustes manuais (${adjusted.length})',
                          ),
                          onPressed: () =>
                              _revert(context, adjusted, onlyAdjusted: true),
                        ),
                      OutlinedButton.icon(
                        key: const ValueKey('closings-revert-all'),
                        icon: const Icon(Icons.lock_open, size: 18),
                        label: Text('Reabrir todos (${list.length})'),
                        onPressed: () => _revert(context, list),
                      ),
                    ],
                  ),
                ),
                for (final c in list)
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => showMonthClosingActions(context, c.month),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              c.month.longLabel,
                              style: context.text.titleSmall,
                            ),
                            ClosingSummary(
                              closing: c,
                              computedNow: fc.engine.computedMonthTotals(
                                ProjectionFilter.none,
                                c.month,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                key: ValueKey('closing-reopen-${c.id}'),
                                icon: const Icon(Icons.lock_open, size: 18),
                                label: const Text('Reabrir'),
                                onPressed: () =>
                                    reopenMonthWithConfirm(context, c.month),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _revert(
    BuildContext context,
    List<MonthClosing> items, {
    bool onlyAdjusted = false,
  }) async {
    final fc = context.read<FinanceController>();
    final ok = await confirmDialog(
      context,
      title: onlyAdjusted
          ? 'Reverter ${items.length} ajuste(s) manual(is)?'
          : 'Reabrir ${items.length} mês(es)?',
      message: onlyAdjusted
          ? 'Os meses com ajuste manual voltam a ser calculados pelos '
                'lançamentos. Meses só fechados continuam fechados.'
          : 'Todos os fechamentos e ajustes manuais serão revertidos e os '
                'meses voltam a ser calculados pelos lançamentos.',
      confirm: 'Reverter',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await runAction(
      context,
      () => fc.reopenMonths(items.map((c) => c.month)),
      success: onlyAdjusted ? 'Ajustes revertidos' : 'Meses reabertos',
    );
  }
}
