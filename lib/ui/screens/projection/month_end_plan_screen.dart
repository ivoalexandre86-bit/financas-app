import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/debt_engine.dart';
import '../../../domain/engine/month_end_planner.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';

/// "O que fazer agora?": último passo do fechamento do mês. Mostra quanto
/// está livre de verdade e compara opções, com a projeção antes e depois.
/// Aplicar uma opção só mexe no planejamento futuro.
class MonthEndPlanScreen extends StatefulWidget {
  final YearMonth month;
  const MonthEndPlanScreen({super.key, required this.month});

  @override
  State<MonthEndPlanScreen> createState() => _MonthEndPlanScreenState();
}

class _MonthEndPlanScreenState extends State<MonthEndPlanScreen> {
  final offers = <RenegotiationOffer>[];
  final amountCtrl = TextEditingController();
  Money? amount;
  int cutPercent = 10;
  DebtSort sort = DebtSort.totalSaved;
  String? selected;

  @override
  void dispose() {
    amountCtrl.dispose();
    super.dispose();
  }

  List<MonthEndOption> _sorted(List<MonthEndOption> all) {
    final debtOpts = all
        .where((o) => o.kind == MonthEndOptionKind.debtPrepay)
        .toList();
    int key(MonthEndOption o) => switch (sort) {
      DebtSort.totalSaved => o.interestSavings?.cents ?? -1,
      DebtSort.monthlyRelief => o.monthlyRelief?.cents ?? -1,
    };
    debtOpts.sort((a, b) => key(b).compareTo(key(a)));
    return [
      ...all.where((o) => o.kind != MonthEndOptionKind.debtPrepay),
      ...debtOpts,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final debts = fc.activeDebts;
    final a = fc.monthEndAnalysis(
      widget.month,
      offers: offers,
      amount: amount,
      cutPercent: cutPercent,
    );
    final options = _sorted(a.options);
    final sel = options.where((o) => o.id == selected).firstOrNull;
    final decision = fc.closingOf(widget.month)?.decision;
    return Scaffold(
      appBar: AppBar(title: const Text('O que fazer agora?')),
      body: ListView(
        key: const ValueKey('month-end-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (!a.isClosed)
            _Banner(
              icon: Icons.lock_open,
              color: context.fin.warning,
              text:
                  '${widget.month.longLabel} ainda está aberto. Feche o mês '
                  'para registrar uma decisão.',
            ),
          if (decision != null)
            _Banner(
              key: const ValueKey('month-end-decision'),
              icon: Icons.check_circle_outline,
              color: context.fin.positive,
              text:
                  'Decisão registrada em ${Dates.format(decision.decidedAt)}: '
                  '${decision.title}.\n${decision.changes.join('\n')}',
            ),
          _AvailableCard(analysis: a),
          _ScenarioCard(analysis: a),
          _ObligationsCard(analysis: a),
          if (a.shortfalls.isNotEmpty) _ShortfallCard(analysis: a),
          const SizedBox(height: 8),
          Text('Opções', style: context.text.titleMedium),
          const SizedBox(height: 8),
          _controls(context, a, debts.length),
          for (final o in options)
            _OptionCard(
              key: ValueKey('month-end-option-${o.id}'),
              analysis: a,
              option: o,
              selected: o.id == selected,
              onSelect: () => setState(() => selected = o.id),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const ValueKey('month-end-apply'),
            icon: const Icon(Icons.event_available),
            label: Text(
              sel == null
                  ? 'Escolha uma opção'
                  : 'Aplicar ao planejamento: ${sel.kind.label}',
            ),
            onPressed: sel == null || !sel.isComplete || !a.isClosed
                ? null
                : () => _apply(fc, a, sel),
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, MonthEndAnalysis a, int debtCount) {
    final children = <Widget>[];
    if (a.scenario != MonthEndScenario.shortfall && a.freeToUse.isPositive) {
      children.add(
        TextField(
          key: const ValueKey('month-end-amount'),
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quanto usar (até ${a.freeToUse.format()})',
            helperText: 'Vazio = todo o valor livre',
            prefixText: 'R\$ ',
          ),
          onChanged: (v) => setState(() => amount = Money.tryEval(v)),
        ),
      );
    }
    if (a.scenario != MonthEndScenario.shortfall) {
      children.add(
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (debtCount == 0)
              Text(
                'Cadastre seus empréstimos e financiamentos em Dívidas e '
                'contratos para comparar amortizações aqui.',
                key: const ValueKey('month-end-no-debts'),
                style: context.text.bodySmall?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
            if (debtCount > 1)
              for (final v in DebtSort.values)
                ChoiceChip(
                  key: ValueKey('month-end-sort-${v.name}'),
                  label: Text(v.label),
                  selected: sort == v,
                  onSelected: (_) => setState(() => sort = v),
                ),
          ],
        ),
      );
    } else {
      children.add(
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Corte nos gastos variáveis:'),
            for (final p in const [5, 10, 20])
              ChoiceChip(
                label: Text('$p%'),
                selected: cutPercent == p,
                onSelected: (_) => setState(() => cutPercent = p),
              ),
            OutlinedButton.icon(
              key: const ValueKey('month-end-add-offer'),
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('Informar proposta de renegociação'),
              onPressed: _addOffer,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in children)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: c),
        ],
      ),
    );
  }

  Future<void> _addOffer() async {
    final r = await showDialog<RenegotiationOffer>(
      context: context,
      builder: (_) => const _OfferDialog(),
    );
    if (r != null) setState(() => offers.add(r));
  }

  Future<void> _apply(
    FinanceController fc,
    MonthEndAnalysis a,
    MonthEndOption o,
  ) async {
    final date = Dates.format(fc.monthEndPlanDate());
    final what = switch (o.kind) {
      MonthEndOptionKind.reserve || MonthEndOptionKind.goal =>
        'Registra um aporte de ${o.upfront.format()} na meta em $date.',
      MonthEndOptionKind.debtPrepay =>
        'Cria uma saída prevista (pendente) de ${o.upfront.format()} em $date. '
            'O app não faz o pagamento nem altera o contrato: as parcelas só '
            'mudam quando você registrar a amortização em Dívidas e contratos.',
      MonthEndOptionKind.postpone =>
        'Muda a data de “${o.postponed.first.description}” para '
            '${Dates.format(o.postponedTo.first)}.',
      _ => 'Só registra a decisão no fechamento; nenhum lançamento muda.',
    };
    final ok = await confirmDialog(
      context,
      title: 'Aplicar “${o.title}”?',
      message:
          '$what\n\n${widget.month.longLabel} continua fechado com o mesmo '
          'resultado. Só o planejamento futuro muda.',
      confirm: 'Aplicar',
    );
    if (!ok || !mounted) return;
    await runAction(
      context,
      () => fc.applyMonthEndOption(a, o),
      success: 'Planejamento atualizado',
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Banner({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Card(
    color: color.withValues(alpha: 0.08),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

class _AvailableCard extends StatelessWidget {
  final MonthEndAnalysis analysis;
  const _AvailableCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final fc = context.read<FinanceController>();
    return SectionCard(
      title: 'Quanto está livre de verdade',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(
            'Resultado de ${a.closedMonth.longLabel}'
            '${a.isClosed ? ' (fechado)' : ''}',
            MoneyText(a.result, colorize: true),
          ),
          InfoRow('Saldo em contas hoje', MoneyText(a.cash)),
          InfoRow(
            'Compromissos até ${Dates.format(a.windowEnd)}',
            MoneyText(-a.committed),
          ),
          InfoRow(
            'Reserva mínima',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoneyText(-a.minimumReserve),
                IconButton(
                  key: const ValueKey('month-end-edit-reserve'),
                  tooltip: 'Alterar reserva mínima',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _editReserve(context, fc),
                ),
              ],
            ),
          ),
          const Divider(),
          InfoRow(
            'Livre para decidir',
            MoneyText(
              a.available,
              key: const ValueKey('month-end-available'),
              colorize: true,
              style: context.text.titleMedium,
            ),
          ),
          Text(
            'Receitas ainda a receber até ${Dates.format(a.windowEnd)} '
            '(${a.expectedIncome.format()}) não entram nesta conta. '
            'Calculado em ${Dates.format(a.calculatedAt)}.',
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
        ],
      ),
    );
  }

  Future<void> _editReserve(BuildContext context, FinanceController fc) async {
    final ctrl = TextEditingController(
      text: fc.minimumReserve.isZero ? '' : fc.minimumReserve.formatPlain(),
    );
    final v = await showDialog<Money>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reserva mínima'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Quanto você quer manter sempre em conta, sem usar para metas '
              'nem dívidas.',
            ),
            const SizedBox(height: 12),
            MoneyField(controller: ctrl, label: 'Valor', allowZero: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, Money.tryEval(ctrl.text) ?? Money.zero),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (v == null || !context.mounted) return;
    await runAction(
      context,
      () => fc.setMinimumReserve(v),
      success: 'Reserva mínima salva',
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  final MonthEndAnalysis analysis;
  const _ScenarioCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final (icon, color, text) = switch (a.scenario) {
      MonthEndScenario.surplus => (
        Icons.savings_outlined,
        context.fin.positive,
        'Depois de pagar o que vence até ${Dates.format(a.windowEnd)} e manter '
            'a reserva, sobram ${a.available.format()}. Compare abaixo o que '
            'fazer com esse dinheiro.',
      ),
      MonthEndScenario.committed => (
        Icons.event_note_outlined,
        context.fin.warning,
        'O mês fechou positivo, mas o caixa já está comprometido: separe '
            '${a.setAside.format()} para os compromissos até '
            '${Dates.format(a.windowEnd)}. '
            '${a.available.isNegative ? 'Faltam ${(-a.available).format()} para cobrir tudo e manter a reserva.' : 'Não sobra valor livre para antecipar dívidas agora.'}',
      ),
      MonthEndScenario.shortfall => (
        Icons.warning_amber_outlined,
        context.fin.negative,
        a.shortfalls.isEmpty
            ? 'O mês fechou negativo (${a.result.format()}). Veja abaixo como '
                  'equilibrar os próximos meses.'
            : 'A projeção fica abaixo da reserva em '
                  '${a.shortfalls.length} ${a.shortfalls.length == 1 ? 'mês' : 'meses'}, '
                  'a partir de ${a.shortfalls.first.month.longLabel}. Compare as '
                  'mudanças de planejamento abaixo.',
      ),
    };
    return Card(
      key: ValueKey('month-end-scenario-${a.scenario.name}'),
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(a.scenario.label),
        subtitle: Text(text),
      ),
    );
  }
}

class _ObligationsCard extends StatelessWidget {
  final MonthEndAnalysis analysis;
  const _ObligationsCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    return Card(
      child: ExpansionTile(
        key: const ValueKey('month-end-obligations'),
        initiallyExpanded: a.scenario == MonthEndScenario.committed,
        title: Text('Compromissos até ${Dates.format(a.windowEnd)}'),
        subtitle: Text(
          a.obligations.isEmpty
              ? 'Nada a pagar'
              : '${a.obligations.length} • separe ${a.setAside.format()}',
        ),
        children: [
          for (final o in a.obligations)
            ListTile(
              dense: true,
              leading: Icon(
                o.isInvoice ? Icons.credit_card : Icons.receipt_long,
                size: 20,
              ),
              title: Text(o.description),
              subtitle: Text(
                '${o.overdue ? 'Venceu em' : 'Vence em'} ${Dates.format(o.date)}',
                style: o.overdue
                    ? TextStyle(color: context.fin.negative)
                    : null,
              ),
              trailing: MoneyText(o.amount),
            ),
        ],
      ),
    );
  }
}

class _ShortfallCard extends StatelessWidget {
  final MonthEndAnalysis analysis;
  const _ShortfallCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    return SectionCard(
      key: const ValueKey('month-end-shortfalls'),
      title: 'Meses abaixo da reserva',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in a.shortfalls) ...[
            InfoRow(
              s.month.longLabel,
              Text(
                'saldo ${s.projected.format()} • faltam ${s.gap.format()}',
                textAlign: TextAlign.end,
                style: TextStyle(color: context.fin.negative),
              ),
            ),
            for (final c in s.contributors)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '• ${c.description}${c.fixed ? ' (fixa)' : ''}',
                        style: context.text.bodySmall,
                      ),
                    ),
                    MoneyText(c.amount, style: context.text.bodySmall),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final MonthEndAnalysis analysis;
  final MonthEndOption option;
  final bool selected;
  final VoidCallback onSelect;
  const _OptionCard({
    super.key,
    required this.analysis,
    required this.option,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final o = option;
    final a = analysis;
    final cmp = a.compare(o);
    final next = cmp.first;
    final small = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    return Card(
      shape: selected
          ? RoundedRectangleBorder(
              side: BorderSide(color: context.colors.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? context.colors.primary : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(o.title, style: context.text.titleSmall),
                  ),
                  if (o.kind == MonthEndOptionKind.debtPrepay ||
                      o.kind == MonthEndOptionKind.renegotiate)
                    Pill(
                      o.isLenderQuote
                          ? 'Proposta do credor'
                          : 'Estimativa do app',
                      color: o.isLenderQuote
                          ? context.fin.positive
                          : context.fin.warning,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(o.why),
              if (!o.isComplete) ...[
                const SizedBox(height: 6),
                Text(
                  'Dados necessários: ${o.missingFields.join(', ')}.',
                  style: TextStyle(color: context.fin.negative),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    _Metric('Saída agora', o.upfront.format()),
                    if (o.interestSavings != null)
                      _Metric(
                        o.kind == MonthEndOptionKind.debtPrepay
                            ? 'Economia estimada'
                            : 'Economia de juros',
                        o.interestSavings!.format(),
                      ),
                    if (o.monthlyRelief != null)
                      _Metric(
                        o.kind == MonthEndOptionKind.debtPrepay
                            ? 'Parcela menor (opção)'
                            : 'Alívio por mês',
                        o.monthlyRelief!.format(),
                      ),
                    if (o.totalCostChange != null)
                      _Metric(
                        'Custo total',
                        '${o.totalCostChange!.isPositive ? '+' : ''}${o.totalCostChange!.format()}',
                      ),
                    _Metric(
                      'Caixa no fim de ${next.month.shortLabel}',
                      next.after.format(),
                    ),
                    _Metric(
                      'Meses abaixo da reserva',
                      '${a.shortfallMonthsAfter(o)}',
                    ),
                  ],
                ),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Projeção antes e depois'),
                    children: [
                      Table(
                        columnWidths: const {0: FlexColumnWidth(1.2)},
                        children: [
                          TableRow(
                            children: [
                              Text('Mês', style: small),
                              Text(
                                'Antes',
                                style: small,
                                textAlign: TextAlign.end,
                              ),
                              Text(
                                'Depois',
                                style: small,
                                textAlign: TextAlign.end,
                              ),
                            ],
                          ),
                          for (final c in cmp)
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Text(c.month.shortLabel),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: MoneyText(c.before),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: MoneyText(
                                    c.after,
                                    color: c.after < a.minimumReserve
                                        ? context.fin.negative
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      for (final s in o.assumptions)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('• $s', style: small),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: context.text.labelSmall?.copyWith(color: context.fin.subtle),
      ),
      Text(value, style: context.text.bodyMedium),
    ],
  );
}

/// Proposta de refinanciamento ou renegociação (fica só nesta tela).
class _OfferDialog extends StatefulWidget {
  const _OfferDialog();

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  final name = TextEditingController();
  final cur = TextEditingController();
  final curN = TextEditingController();
  final nw = TextEditingController();
  final nwN = TextEditingController();
  final fee = TextEditingController();
  String? error;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Proposta de renegociação'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Dívida'),
          ),
          MoneyField(controller: cur, label: 'Parcela atual'),
          TextField(
            controller: curN,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Parcelas restantes hoje',
            ),
          ),
          MoneyField(controller: nw, label: 'Nova parcela'),
          TextField(
            controller: nwN,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Novo número de parcelas',
            ),
          ),
          MoneyField(
            controller: fee,
            label: 'Entrada, tarifas e IOF (opcional)',
            allowZero: true,
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: TextStyle(color: context.fin.negative),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final c = Money.tryEval(cur.text);
          final cn = int.tryParse(curN.text.trim());
          final n = Money.tryEval(nw.text);
          final nn = int.tryParse(nwN.text.trim());
          if (c == null || cn == null || n == null || nn == null) {
            setState(
              () => error = 'Informe parcela e prazo atuais e os da proposta.',
            );
            return;
          }
          Navigator.pop(
            context,
            RenegotiationOffer(
              name: name.text.trim().isEmpty ? 'Dívida' : name.text.trim(),
              currentInstallment: c,
              currentRemainingMonths: cn,
              newInstallment: n,
              newMonths: nn,
              upfrontCost: Money.tryEval(fee.text) ?? Money.zero,
            ),
          );
        },
        child: const Text('Comparar'),
      ),
    ],
  );
}
