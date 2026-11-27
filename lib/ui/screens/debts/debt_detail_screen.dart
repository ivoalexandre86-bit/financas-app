import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/calculators.dart' show annualFromMonthly;
import '../../../domain/engine/debt_engine.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/debt.dart';
import '../../../state/finance_controller.dart';
import '../../../domain/models/scenario.dart';
import '../../app_shell.dart';
import '../../nav.dart';
import '../projection/projection_screen.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import 'debt_form_screen.dart';
import 'debt_widgets.dart';

/// Colunas atuais e futuras da Projeção (12 meses), base do efeito no caixa.
List<ProjectionColumn> projectionAhead(
  FinanceController fc, {
  int months = 12,
}) {
  final from = YearMonth.of(fc.today);
  return fc.engine.projection(MonthRange(from, from.add(months - 1))).columns;
}

/// Pede a cotação do credor e grava no contrato.
Future<void> addLenderQuote(
  BuildContext context,
  DebtContract d, {
  QuoteKind kind = QuoteKind.payoff,
}) async {
  final fc = context.read<FinanceController>();
  final amount = TextEditingController();
  final installments = TextEditingController();
  final newPayment = TextEditingController();
  final newMonths = TextEditingController();
  final note = TextEditingController();
  var k = kind;
  var date = fc.today;
  DateTime? valid = Dates.addDays(fc.today, 10);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Cotação do credor'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<QuoteKind>(
                initialValue: k,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final q in QuoteKind.values)
                    DropdownMenuItem(value: q, child: Text(q.label)),
                ],
                onChanged: (v) => set(() => k = v!),
              ),
              TextField(
                key: const Key('quote-amount'),
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor a pagar',
                  prefixText: 'R\$ ',
                ),
              ),
              if (k == QuoteKind.lastInstallments)
                TextField(
                  controller: installments,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantas parcelas o valor cobre',
                  ),
                ),
              if (k == QuoteKind.prepayment ||
                  k == QuoteKind.renegotiation) ...[
                TextField(
                  controller: newPayment,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Nova parcela',
                    prefixText: 'R\$ ',
                  ),
                ),
                TextField(
                  controller: newMonths,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Novo número de parcelas',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              DateField(
                value: date,
                label: 'Data da cotação',
                onChanged: (v) => set(() => date = v ?? date),
              ),
              DateField(
                value: valid,
                label: 'Válida até',
                clearable: true,
                onChanged: (v) => set(() => valid = v),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Observação'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
  final v = Money.tryEval(amount.text);
  if (ok != true || !context.mounted) return;
  if (v == null || !v.isPositive) {
    showMessage(context, 'Informe o valor da cotação', error: true);
    return;
  }
  final q = LenderQuote(
    id: newId('q_'),
    kind: k,
    date: date,
    amount: v,
    validUntil: valid,
    installments: int.tryParse(installments.text),
    newPayment: Money.tryEval(newPayment.text),
    newMonths: int.tryParse(newMonths.text),
    note: note.text.trim(),
  );
  await runAction(
    context,
    () => fc.saveDebt(d.copyWith(quotes: [...d.quotes, q])),
    success: 'Cotação salva',
  );
}

/// Mostra a opção como cenário na Projeção (antes/depois), sem mudar o
/// orçamento: um cenário com a saída de agora e a diferença de cada parcela.
Future<void> showOnProjection(BuildContext context, PrepayResult r) async {
  final fc = context.read<FinanceController>();
  final id = 'debt_${r.debt.id}_${r.option.name}';
  final flows = <ScenarioFlow>[
    for (final e in r.cashDelta().entries)
      ScenarioFlow(
        id: '${id}_${e.key.key}',
        date: e.key == YearMonth.of(r.calculatedAt)
            ? r.calculatedAt
            : DateTime(e.key.year, e.key.month, 1),
        amount: e.value,
        description: e.value.isNegative && e.key == YearMonth.of(r.calculatedAt)
            ? '${r.debt.name}: ${r.option.label.toLowerCase()}'
            : '${r.debt.name}: diferença nas parcelas',
        source: ScenarioSource.debt,
        refId: r.debt.id,
        amountConfirmed: r.isLenderQuote,
      ),
  ];
  final sc = PlanScenario(
    id: id,
    name: '${r.option.label} – ${r.debt.name}',
    kind: ScenarioSource.debt,
    flows: flows,
    notes: r.assumptions.join('\n'),
  );
  await fc.saveScenario(sc);
  fc.selectScenario(sc.id);
  if (context.mounted && !AppShell.goTo(context, 'projection')) {
    await push(context, const ProjectionScreen());
  }
}

/// Confirma e leva a opção para o planejamento.
Future<bool> confirmApplyPlan(BuildContext context, PrepayResult r) async {
  final fc = context.read<FinanceController>();
  var accountId = r.debt.accountId ?? fc.activeAccounts.firstOrNull?.id;
  final linked = r.debt.installments == DebtInstallments.linked;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Levar para o planejamento?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('O que muda no seu plano futuro:'),
              const SizedBox(height: 6),
              Text(
                '• Saída planejada de ${r.outflow.format()} hoje '
                '(${r.option.label.toLowerCase()}).',
              ),
              if (r.after.isEmpty)
                const Text(
                  '• O contrato fica como quitado e as parcelas '
                  'planejadas saem da Projeção.',
                )
              else
                Text(
                  '• A partir de ${Dates.format(r.after.rows.first.dueDate)}, '
                  '${r.after.months} parcelas de '
                  '${r.paymentAfter.format()} (antes '
                  '${r.monthsBefore} de ${r.paymentBefore.format()}).',
                ),
              if (linked)
                const Text(
                  '• O lançamento que representava as parcelas é encerrado '
                  'a partir da próxima parcela e o app passa a gerá-las.',
                ),
              const Text('• Meses fechados e parcelas já pagas não mudam.'),
              const SizedBox(height: 8),
              Text(
                'Nada é pago nem alterado no credor: confirme o valor com '
                'ele antes de pagar.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              AccountDropdown(
                fc: fc,
                value: accountId,
                label: 'Conta de onde sai o dinheiro',
                onChanged: (v) => set(() => accountId = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('plan-confirm'),
            onPressed: accountId == null
                ? null
                : () => Navigator.pop(ctx, true),
            child: const Text('Confirmar no plano'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || accountId == null || !context.mounted) return false;
  return runAction(
    context,
    () => fc.applyDebtPlan(r, accountId: accountId!),
    success: 'Plano atualizado. Veja na Projeção.',
  );
}

/// Detalhe do contrato: situação, cronograma, simulação de antecipação,
/// cotações do credor e pagamentos registrados.
class DebtDetailScreen extends StatefulWidget {
  final String debtId;
  const DebtDetailScreen(this.debtId, {super.key});
  @override
  State<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends State<DebtDetailScreen> {
  PrepayOption option = PrepayOption.reduceTerm;
  final amount = TextEditingController(text: '5.000,00');
  final installments = TextEditingController(text: '3');

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final d = fc.debtById(widget.debtId);
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Contrato não encontrado')),
      );
    }
    final today = fc.today;
    final schedule = remainingSchedule(d, today);
    final missing = missingForEstimate(d);
    final payments = fc.debtPayments(d);
    final est = estimatePrepayment(
      d,
      option,
      amount: Money.tryEval(amount.text) ?? Money.zero,
      installments: option == PrepayOption.lastInstallments
          ? int.tryParse(installments.text)
          : null,
      asOf: today,
    );
    final impact = est.result == null
        ? null
        : cashImpact(
            projectionAhead(fc),
            est.result!.cashDelta(),
            reserve: fc.minimumReserve,
          );
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(d.name),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => push(context, DebtFormScreen(debt: d)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'archive') {
                await fc.saveDebt(d.copyWith(archived: !d.archived));
              } else if (v == 'delete') {
                final ok = await confirmDialog(
                  context,
                  title: 'Excluir contrato?',
                  message:
                      'As parcelas planejadas geradas por ele saem da '
                      'Projeção. Pagamentos já registrados ficam.',
                  confirm: 'Excluir',
                  destructive: true,
                );
                if (ok && context.mounted) {
                  await fc.deleteDebt(d);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(d.archived ? 'Reativar' : 'Arquivar'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          SectionCard(
            title: 'Situação',
            child: Column(
              children: [
                InfoRow('Credor', Text(d.lender.isEmpty ? '—' : d.lender)),
                InfoRow('Tipo', Text(d.kind.label)),
                InfoRow(
                  'Saldo devedor',
                  d.outstanding == null
                      ? const Text('não informado')
                      : MoneyText(d.outstanding!),
                ),
                InfoRow(
                  'Taxa',
                  Text(
                    d.monthlyRate == null
                        ? 'não informada'
                        : '${pct(d.monthlyRate!)} a.m. · '
                              '${pct(annualFromMonthly(d.monthlyRate!))} a.a.',
                  ),
                ),
                InfoRow('Sistema', Text(d.system?.label ?? 'não informado')),
                InfoRow(
                  'Parcelas restantes',
                  Text('${d.remainingMonths ?? '—'}'),
                ),
                if (schedule != null)
                  InfoRow(
                    'Próxima parcela',
                    Text(
                      '${schedule.firstPayment.format()} em '
                      '${Dates.format(schedule.rows.first.dueDate)}',
                    ),
                  ),
                if (schedule != null && schedule.interestKnown)
                  InfoRow(
                    'Juros que faltam pagar',
                    MoneyText(schedule.totalInterest),
                  ),
                InfoRow('Na Projeção', Text(d.installments.label)),
                if (missing.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: MissingFieldsCard(
                      missing: missing,
                      onEdit: () => push(context, DebtFormScreen(debt: d)),
                      onQuote: () => addLenderQuote(context, d),
                    ),
                  ),
              ],
            ),
          ),
          gap,
          SectionCard(
            title: 'Antecipar ou quitar',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<PrepayOption>(
                  key: const Key('prepay-option'),
                  initialValue: option,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Opção'),
                  items: [
                    for (final o in PrepayOption.values)
                      DropdownMenuItem(
                        value: o,
                        child: Text(
                          d.supportOf(o) == OptionSupport.notAllowed
                              ? '${o.label} (contrato não permite)'
                              : o.label,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => option = v!),
                ),
                if (option == PrepayOption.lastInstallments)
                  TextField(
                    controller: installments,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantas parcelas antecipar',
                    ),
                    onChanged: (_) => setState(() {}),
                  )
                else if (option != PrepayOption.payoff)
                  TextField(
                    key: const Key('prepay-amount'),
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor disponível',
                      prefixText: 'R\$ ',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                const SizedBox(height: 12),
                if (est.result case final r?) ...[
                  PrepayResultView(r, impact: impact),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _saveScenario(fc, r),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Salvar simulação'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('prepay-scenario'),
                        onPressed: () => showOnProjection(context, r),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Ver na Projeção'),
                      ),
                      FilledButton.icon(
                        key: const Key('prepay-apply'),
                        onPressed: () => confirmApplyPlan(context, r),
                        icon: const Icon(Icons.event_available_outlined),
                        label: const Text('Levar para o planejamento'),
                      ),
                    ],
                  ),
                ] else
                  MissingFieldsCard(
                    missing: est.missing,
                    blocked: est.blocked,
                    onEdit: () => push(context, DebtFormScreen(debt: d)),
                    onQuote: () => addLenderQuote(
                      context,
                      d,
                      kind: switch (option) {
                        PrepayOption.payoff => QuoteKind.payoff,
                        PrepayOption.lastInstallments =>
                          QuoteKind.lastInstallments,
                        _ => QuoteKind.prepayment,
                      },
                    ),
                  ),
              ],
            ),
          ),
          gap,
          SectionCard(
            title: 'Cotações do credor',
            trailing: IconButton(
              tooltip: 'Informar cotação',
              icon: const Icon(Icons.add),
              onPressed: () => addLenderQuote(context, d),
            ),
            child: d.quotes.isEmpty
                ? Text(
                    'Peça ao banco o boleto de quitação ou a simulação de '
                    'amortização e registre aqui: o valor do credor '
                    'prevalece sobre a estimativa do app.',
                    style: context.text.bodySmall,
                  )
                : Column(
                    children: [
                      for (final q in d.quotes)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            q.isValidOn(today)
                                ? Icons.verified_outlined
                                : Icons.history,
                          ),
                          title: Text('${q.kind.label}: ${q.amount.format()}'),
                          subtitle: Text(
                            'De ${Dates.format(q.date)}'
                            '${q.validUntil == null ? '' : ' · válida até ${Dates.format(q.validUntil!)}'}'
                            '${q.isValidOn(today) ? '' : ' (vencida)'}'
                            '${q.note.isEmpty ? '' : ' · ${q.note}'}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Remover',
                            icon: const Icon(Icons.close),
                            onPressed: () => fc.saveDebt(
                              d.copyWith(
                                quotes: d.quotes
                                    .where((x) => x.id != q.id)
                                    .toList(),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          gap,
          SectionCard(
            title: 'Pagamentos registrados',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (payments.isEmpty)
                  Text(
                    'Nenhum pagamento concluído ligado a este contrato.',
                    style: context.text.bodySmall,
                  ),
                for (final t in payments.reversed.take(12))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.description),
                    subtitle: Text(Dates.format(t.date)),
                    trailing: MoneyText(t.amount),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _linkPayment(fc, d),
                      icon: const Icon(Icons.link),
                      label: const Text('Vincular pagamento'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final n = await fc.advanceDebtByPayments(d);
                        if (context.mounted) {
                          showMessage(
                            context,
                            n == 0
                                ? 'Nenhuma parcela paga desde o último saldo.'
                                : 'Saldo atualizado com $n parcela(s) paga(s).',
                          );
                        }
                      },
                      icon: const Icon(Icons.update),
                      label: const Text('Atualizar saldo pelas pagas'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          gap,
          if (schedule != null)
            SectionCard(
              title: 'Cronograma restante',
              child: ScheduleTable(schedule),
            ),
        ],
      ),
    );
  }

  Future<void> _saveScenario(FinanceController fc, PrepayResult r) => runAction(
    context,
    () => fc.saveDebtScenario(
      DebtScenario(
        id: newId('dsc_'),
        name: '${r.option.label} – ${r.debt.name}',
        kind: ScenarioKind.prepayment,
        calculatedAt: r.calculatedAt,
        inputs: {
          'debtId': r.debt.id,
          'option': r.option.name,
          'amount': r.outflow.cents,
        },
        summary: [r.toSummary()],
      ),
    ),
    success: 'Simulação salva em Simulações salvas',
  );

  Future<void> _linkPayment(FinanceController fc, DebtContract d) async {
    final list = fc
        .linkableDebtPayments(d)
        .where((t) => !d.linkedTxIds.contains(t.id))
        .take(60)
        .toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => ListView(
        children: [
          const ListTile(title: Text('Escolha o pagamento')),
          if (list.isEmpty)
            const ListTile(title: Text('Nenhuma despesa concluída.')),
          for (final t in list)
            ListTile(
              title: Text(t.description),
              subtitle: Text(Dates.format(t.date)),
              trailing: Text(t.amount.format()),
              onTap: () => Navigator.pop(ctx, t.id),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await runAction(
      context,
      () => fc.saveDebt(d.copyWith(linkedTxIds: [...d.linkedTxIds, picked])),
      success: 'Pagamento vinculado',
    );
  }
}
