import 'package:flutter/material.dart' hide Simulation;

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/models/entities.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/simulation.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/form_fields.dart';
import 'sim_common.dart';

enum _Mode { keep, set, percent }

/// Cadastro de uma linha da simulação (nova receita/despesa hipotética ou
/// ajuste de uma existente), com preenchimento por período.
class SimItemDialog extends StatefulWidget {
  final FinanceController fc;
  final Simulation sim;
  final SimItem? item;
  final TransactionType type;
  const SimItemDialog({
    super.key,
    required this.fc,
    required this.sim,
    this.item,
    this.type = TransactionType.expense,
  });

  @override
  State<SimItemDialog> createState() => _SimItemDialogState();
}

class _SimItemDialogState extends State<SimItemDialog> {
  late final SimItem? item = widget.item;
  late TransactionType type = item?.type ?? widget.type;
  late final desc = TextEditingController(text: item?.description ?? '');
  late final notes = TextEditingController(text: item?.notes ?? '');
  late final amount = TextEditingController(
    text: _initialAmount == 0 ? '' : Money(_initialAmount).formatPlain(),
  );
  final percent = TextEditingController(text: '10');
  late String? categoryId = item?.categoryId;
  late Funding? funding = item == null
      ? null
      : (item!.accountId != null || item!.cardId != null)
      ? Funding(accountId: item!.accountId, cardId: item!.cardId)
      : null;
  late int day = item?.day ?? 10;
  late String classification =
      item?.classification ??
      (type == TransactionType.income ? 'Fixa' : 'Variável');
  late SimRecurrence recurrence = item?.recurrence ?? SimRecurrence.monthly;
  late _Mode mode = item == null ? _Mode.set : _Mode.keep;
  late YearMonth start = _firstFilled ?? widget.sim.from;
  late YearMonth end = widget.sim.to;
  String? error;

  int get _initialAmount {
    final i = item;
    if (i == null) return 0;
    for (final m in widget.sim.months) {
      if (i.valueAt(m) != 0) return i.valueAt(m);
    }
    return 0;
  }

  YearMonth? get _firstFilled {
    final i = item;
    if (i == null) return null;
    for (final m in widget.sim.months) {
      if (i.valueAt(m) != 0) return m;
    }
    return null;
  }

  bool get isNew => item == null;
  bool get canChangeType => item == null || item!.origin == SimOrigin.added;

  void _submit() {
    final d = desc.text.trim();
    if (d.isEmpty) {
      setState(() => error = 'Informe uma descrição');
      return;
    }
    if (end < start) {
      setState(() => error = 'O mês final deve ser depois do inicial');
      return;
    }
    var out = (item ?? SimItem(id: newId('si_'), type: type, description: d))
        .copyWith(
          type: type,
          description: d,
          categoryId: categoryId,
          accountId: funding?.accountId,
          cardId: funding?.cardId,
          day: day,
          classification: classification,
          notes: notes.text.trim(),
        );
    switch (mode) {
      case _Mode.keep:
        out = out.copyWith(recurrence: recurrence);
      case _Mode.set:
        final v = amount.text.trim().isEmpty
            ? Money.zero
            : Money.tryEval(amount.text);
        if (v == null) {
          setState(() => error = 'Valor inválido');
          return;
        }
        out = out.fill(v.cents.abs(), start, end, recurrence);
      case _Mode.percent:
        final p = double.tryParse(percent.text.replaceAll(',', '.').trim());
        if (p == null) {
          setState(() => error = 'Percentual inválido');
          return;
        }
        var x = out;
        for (final m in YearMonth.range(start, end)) {
          final v = x.valueAt(m);
          if (v == 0) continue;
          final n = (v * (1 + p / 100)).round();
          x = x.withValue(m, n < 0 ? 0 : n);
        }
        out = x;
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final months = widget.sim.months;
    final kind = type == TransactionType.income
        ? CategoryKind.income
        : CategoryKind.expense;
    return AlertDialog(
      title: Text(
        isNew
            ? (type == TransactionType.income
                  ? 'Nova receita na simulação'
                  : 'Nova despesa na simulação')
            : 'Editar linha',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (canChangeType) ...[
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
                const SizedBox(height: 12),
              ],
              TextField(
                key: const ValueKey('sim-item-desc'),
                controller: desc,
                autofocus: isNew,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  hintText: 'Ex.: Financiamento do carro',
                ),
              ),
              const SizedBox(height: 10),
              CategoryDropdown(
                key: ValueKey('cat-$type'),
                fc: widget.fc,
                kind: kind,
                value: categoryId,
                onChanged: (v) => setState(() => categoryId = v),
              ),
              const SizedBox(height: 10),
              FundingDropdown(
                fc: widget.fc,
                value: funding,
                allowCards: type == TransactionType.expense,
                label: 'Forma de pagamento (conta ou cartão)',
                onChanged: (f) => setState(() => funding = f),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: day,
                      decoration: const InputDecoration(labelText: 'Dia'),
                      items: [
                        for (var d = 1; d <= 31; d++)
                          DropdownMenuItem(value: d, child: Text('$d')),
                      ],
                      onChanged: (v) => setState(() => day = v ?? day),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: simClassifications.contains(classification)
                          ? classification
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Classificação',
                      ),
                      items: [
                        for (final c in simClassifications)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) =>
                          setState(() => classification = v ?? classification),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Valores no período', style: context.text.titleSmall),
              const SizedBox(height: 8),
              if (!isNew)
                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(value: _Mode.keep, label: Text('Manter')),
                    ButtonSegment(
                      value: _Mode.set,
                      label: Text('Definir valor'),
                    ),
                    ButtonSegment(
                      value: _Mode.percent,
                      label: Text('Ajustar %'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => setState(() => mode = s.first),
                ),
              if (mode != _Mode.keep) ...[
                const SizedBox(height: 10),
                if (mode == _Mode.set)
                  MoneyField(
                    key: const ValueKey('sim-item-amount'),
                    controller: amount,
                    allowZero: true,
                    label: 'Valor (deixe 0 para remover nos meses)',
                  )
                else
                  TextField(
                    controller: percent,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Variação (%)',
                      helperText: 'Ex.: 10 para +10%, -20 para −20%',
                      suffixText: '%',
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MonthDropdown(
                        label: 'Mês inicial',
                        value: start,
                        options: months,
                        onChanged: (m) => setState(() => start = m),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MonthDropdown(
                        label: 'Mês final',
                        value: end,
                        options: months,
                        onChanged: (m) => setState(() => end = m),
                      ),
                    ),
                  ],
                ),
                if (mode == _Mode.set) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<SimRecurrence>(
                    initialValue: recurrence,
                    decoration: const InputDecoration(labelText: 'Recorrência'),
                    items: [
                      for (final r in SimRecurrence.values)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    onChanged: (v) =>
                        setState(() => recurrence = v ?? recurrence),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  mode == _Mode.set
                      ? 'Os meses de ${start.shortLabel} a ${end.shortLabel} '
                            'recebem o valor conforme a recorrência; os demais '
                            'meses não mudam.'
                      : 'Ajusta os valores existentes de ${start.shortLabel} '
                            'a ${end.shortLabel}.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
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
          key: const ValueKey('sim-item-submit'),
          onPressed: _submit,
          child: Text(isNew ? 'Adicionar' : 'Aplicar'),
        ),
      ],
    );
  }
}
