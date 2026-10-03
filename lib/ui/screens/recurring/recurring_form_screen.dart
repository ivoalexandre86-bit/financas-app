import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/recurrence.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';

/// Cadastro/edição de regra recorrente, com pausa, retomada e exclusão.
class RecurringFormScreen extends StatefulWidget {
  final RecurringRule? rule;
  const RecurringFormScreen({super.key, this.rule});
  @override
  State<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends State<RecurringFormScreen> {
  final _form = GlobalKey<FormState>();
  late RecurringRule? r = widget.rule;
  late TransactionType type = r?.type ?? TransactionType.expense;
  late final amount = TextEditingController(
    text: r?.amount.formatPlain() ?? '',
  );
  late final desc = TextEditingController(text: r?.description ?? '');
  late final notes = TextEditingController(text: r?.notes ?? '');
  late final interval = TextEditingController(text: '${r?.interval ?? 1}');
  late final day = TextEditingController(
    text: r?.dayOfMonth?.toString() ?? (r == null ? '' : ''),
  );
  late String? categoryId = r?.categoryId;
  late Funding? funding = r == null
      ? null
      : Funding(accountId: r!.accountId, cardId: r!.cardId);
  late String? projectId = r?.projectId;
  late RecurrenceFrequency frequency =
      r?.frequency ?? RecurrenceFrequency.monthly;
  late RecurrenceUnit unit = r?.unit ?? RecurrenceUnit.months;
  late DateTime start = r?.startDate ?? DateTime.now();
  late DateTime? end = r?.endDate;

  bool get monthly =>
      frequency == RecurrenceFrequency.monthly ||
      frequency == RecurrenceFrequency.quarterly ||
      frequency == RecurrenceFrequency.yearly ||
      (frequency == RecurrenceFrequency.custom &&
          unit == RecurrenceUnit.months);

  RecurringRule _build() {
    final base =
        r ??
        RecurringRule(
          id: newId('rec_'),
          type: type,
          amount: Money.zero,
          description: '',
          startDate: start,
        );
    return base.copyWith(
      type: type,
      amount: Money.tryParse(amount.text)!,
      description: desc.text.trim(),
      categoryId: categoryId,
      accountId: funding?.accountId,
      cardId: funding?.cardId,
      projectId: projectId,
      frequency: frequency,
      interval: int.tryParse(interval.text) ?? 1,
      unit: unit,
      dayOfMonth: monthly ? int.tryParse(day.text) : null,
      startDate: start,
      endDate: end,
      notes: notes.text.trim(),
    );
  }

  Future<void> _save(FinanceController fc) async {
    if (!_form.currentState!.validate()) return;
    if (end != null && end!.isBefore(start)) {
      showMessage(context, 'A data final deve ser após a inicial', error: true);
      return;
    }
    final updated = _build();
    if (r == null) {
      final ok = await runAction(
        context,
        () => fc.createRule(updated),
        success: 'Recorrência criada',
      );
      if (ok && mounted) Navigator.pop(context);
      return;
    }
    final hasPlanned = fc.data.transactions.any(
      (t) =>
          t.recurringId == r!.id &&
          (t.status == TransactionStatus.planned ||
              t.status == TransactionStatus.pending),
    );
    final scope = await showDialog<RuleEditScope>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Aplicar alteração a…'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, RuleEditScope.futureOnly),
            child: const ListTile(
              title: Text('Somente ocorrências futuras'),
              subtitle: Text(
                'Lançamentos já registrados permanecem como estão.',
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, RuleEditScope.futureAndPlanned),
            child: ListTile(
              title: const Text('Futuras e planejadas existentes'),
              subtitle: Text(
                hasPlanned
                    ? 'Também atualiza ocorrências planejadas/pendentes já registradas.'
                    : 'Não há ocorrências planejadas registradas.',
              ),
            ),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;
    final ok = await runAction(
      context,
      () => fc.updateRule(r!, updated, scope),
      success: 'Recorrência atualizada. Histórico concluído preservado.',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    if (r != null) {
      r = fc.data.ruleById[r!.id] ?? r; // reflete pausa/retomada
    }
    final rule = r;
    final preview = () {
      final a = Money.tryParse(amount.text);
      if (a == null || desc.text.trim().isEmpty) return <DateTime>[];
      try {
        return Recurrence.occurrences(
          _build(),
          fc.today,
          Dates.addMonths(fc.today, 24),
        ).take(4).toList();
      } catch (_) {
        return <DateTime>[];
      }
    }();

    return Scaffold(
      appBar: AppBar(
        title: Text(rule == null ? 'Nova recorrência' : 'Editar recorrência'),
        actions: [
          if (rule != null)
            IconButton(
              tooltip: rule.isPaused ? 'Retomar' : 'Pausar',
              icon: Icon(rule.isPaused ? Icons.play_arrow : Icons.pause),
              onPressed: () => runAction(
                context,
                () => rule.isPaused ? fc.resumeRule(rule) : fc.pauseRule(rule),
                success: rule.isPaused
                    ? 'Recorrência retomada'
                    : 'Recorrência pausada',
              ),
            ),
          if (rule != null)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Excluir recorrência?',
                  message: 'Ocorrências futuras deixam de ser geradas. Lançamentos já concluídos são preservados no histórico.',
                  confirm: 'Excluir',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                final done = await runAction(
                  context,
                  () => fc.deleteRule(rule),
                  success: 'Recorrência excluída',
                );
                if (done && context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            if (rule?.isPaused == true)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.fin.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Pausada desde ${Dates.format(rule!.pauses.last.from)}. Nenhuma ocorrência é gerada enquanto pausada.',
                ),
              ),
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Despesa'),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Receita'),
                ),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() {
                type = s.first;
                categoryId = null;
              }),
            ),
            const SizedBox(height: 16),
            MoneyField(controller: amount, onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            TextFormField(
              controller: desc,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Descrição'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Informe uma descrição'
                  : null,
            ),
            const SizedBox(height: 12),
            CategoryDropdown(
              fc: fc,
              kind: type == TransactionType.income
                  ? CategoryKind.income
                  : CategoryKind.expense,
              value: categoryId,
              onChanged: (v) => setState(() => categoryId = v),
            ),
            const SizedBox(height: 12),
            FundingDropdown(
              fc: fc,
              value: funding,
              onChanged: (f) => setState(() => funding = f),
            ),
            const SizedBox(height: 12),
            ProjectDropdown(
              fc: fc,
              value: projectId,
              onChanged: (v) => setState(() => projectId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<RecurrenceFrequency>(
              initialValue: frequency,
              decoration: const InputDecoration(labelText: 'Frequência'),
              items: [
                for (final f in RecurrenceFrequency.values)
                  DropdownMenuItem(value: f, child: Text(f.label)),
              ],
              onChanged: (f) => setState(() => frequency = f!),
            ),
            if (frequency == RecurrenceFrequency.custom) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: IntField(
                      controller: interval,
                      label: 'A cada',
                      min: 1,
                      max: 365,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<RecurrenceUnit>(
                      initialValue: unit,
                      decoration: const InputDecoration(labelText: 'Unidade'),
                      items: [
                        for (final u in RecurrenceUnit.values)
                          DropdownMenuItem(value: u, child: Text(u.label)),
                      ],
                      onChanged: (u) => setState(() => unit = u!),
                    ),
                  ),
                ],
              ),
            ],
            if (monthly) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: day,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Dia do mês (opcional)',
                  helperText:
                      'Vazio = mesmo dia da data inicial (${start.day}). Dias 29–31 se ajustam ao fim do mês.',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final n = int.tryParse(v);
                  return n == null || n < 1 || n > 31 ? 'Entre 1 e 31' : null;
                },
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DateField(
                    value: start,
                    label: 'Início',
                    onChanged: (d) => setState(() => start = d ?? start),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DateField(
                    value: end,
                    label: 'Fim (opcional)',
                    clearable: true,
                    onChanged: (d) => setState(() => end = d),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Próximas ocorrências', style: context.text.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in preview) Chip(label: Text(Dates.format(d))),
                ],
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => _save(fc),
            child: const Text('Salvar'),
          ),
        ),
      ),
    );
  }
}
