import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/calculators.dart' show monthlyFromAnnual;
import '../../../domain/engine/debt_engine.dart';
import '../../../domain/models/debt.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import 'debt_detail_screen.dart';
import 'debt_form_screen.dart';
import 'debt_widgets.dart';

/// Dívidas e contratos: empréstimos e financiamentos, simulação Price × SAC,
/// comparação entre dívidas e simulações salvas. Só planeja: nada é pago
/// nem alterado no credor.
class DebtsScreen extends StatelessWidget {
  final int initialTab;
  const DebtsScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    initialIndex: initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Dívidas e contratos'),
        bottom: const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Contratos'),
            Tab(text: 'Novo financiamento'),
            Tab(text: 'Comparar dívidas'),
            Tab(text: 'Simulações salvas'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          _ContractsTab(),
          NewFinancingTab(),
          CompareDebtsTab(),
          _ScenariosTab(),
        ],
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Contratos

class _ContractsTab extends StatefulWidget {
  const _ContractsTab();
  @override
  State<_ContractsTab> createState() => _ContractsTabState();
}

class _ContractsTabState extends State<_ContractsTab> {
  bool showArchived = false;

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final list = fc.debts.where((d) => showArchived || !d.archived).toList();
    final active = fc.activeDebts;
    final total = active.fold(
      Money.zero,
      (a, d) => a + (d.outstanding ?? Money.zero),
    );
    final monthly = active.fold(Money.zero, (a, d) {
      final s = remainingSchedule(d, fc.today);
      return a + (s?.firstPayment ?? Money.zero);
    });
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-debt',
        key: const Key('debt-new'),
        onPressed: () async {
          final id = await push<String>(context, const DebtFormScreen());
          if (id != null && context.mounted) {
            push(context, DebtDetailScreen(id));
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo contrato'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          SectionCard(
            title: 'Resumo',
            child: Column(
              children: [
                InfoRow('Saldo devedor somado', MoneyText(total)),
                InfoRow('Parcelas do próximo mês', MoneyText(monthly)),
                InfoRow('Contratos ativos', Text('${active.length}')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const EmptyState(
              icon: Icons.request_quote_outlined,
              title: 'Nenhum contrato',
              message:
                  'Cadastre empréstimos e financiamentos para simular '
                  'antecipações, quitação e comparar onde vale mais usar '
                  'o dinheiro.',
            ),
          for (final d in list) _DebtCard(d),
          if (fc.debts.any((d) => d.archived))
            SwitchListTile(
              title: const Text('Mostrar arquivados e quitados'),
              value: showArchived,
              onChanged: (v) => setState(() => showArchived = v),
            ),
        ],
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  final DebtContract d;
  const _DebtCard(this.d);

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final s = remainingSchedule(d, fc.today);
    final missing = missingForEstimate(d);
    return Card(
      child: ListTile(
        leading: Icon(debtIcon(d.kind)),
        title: Text(d.name),
        subtitle: Text(
          [
            if (d.lender.isNotEmpty) d.lender,
            if (d.archived) 'arquivado',
            if (s != null && s.months > 0)
              '${s.months} parcelas · próxima ${s.firstPayment.format()}',
            if (missing.isNotEmpty) 'faltam dados: ${missing.length}',
          ].join(' · '),
        ),
        trailing: d.outstanding == null
            ? null
            : MoneyText(d.outstanding!, style: context.text.titleSmall),
        onTap: () => push(context, DebtDetailScreen(d.id)),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Novo financiamento: Price × SAC

class NewFinancingTab extends StatefulWidget {
  const NewFinancingTab({super.key});
  @override
  State<NewFinancingTab> createState() => _NewFinancingTabState();
}

class _NewFinancingTabState extends State<NewFinancingTab> {
  final principal = TextEditingController(text: '100.000,00');
  final rate = TextEditingController(text: '1');
  final months = TextEditingController(text: '120');
  final fees = TextEditingController();
  final upfront = TextEditingController();
  final indexRate = TextEditingController();
  RateBasis basis = RateBasis.monthly;
  DebtIndex index = DebtIndex.none;
  late DateTime first = Dates.addMonths(Dates.today(), 1);
  AmortizationSystem show = AmortizationSystem.price;

  FinancingComparison? _calc() {
    final p = Money.tryEval(principal.text);
    var r = parsePercent(rate.text);
    final n = int.tryParse(months.text);
    if (p == null || !p.isPositive || r == null || n == null || n <= 0) {
      return null;
    }
    if (n > 600) return null;
    if (basis == RateBasis.annual) r = monthlyFromAnnual(r);
    return compareFinancing(
      principal: p,
      monthlyRate: r,
      months: n,
      firstDue: first,
      monthlyFees: Money.tryEval(fees.text) ?? Money.zero,
      upfrontCharges: Money.tryEval(upfront.text) ?? Money.zero,
      index: index,
      indexRate: index == DebtIndex.none
          ? 0
          : (parsePercent(indexRate.text) ?? 0),
      calculatedAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _calc();
    void upd(_) => setState(() {});
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        SectionCard(
          title: 'Mesmos termos nos dois sistemas',
          child: Column(
            children: [
              TextField(
                key: const Key('fin-principal'),
                controller: principal,
                onChanged: upd,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor financiado',
                  prefixText: 'R\$ ',
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('fin-rate'),
                      controller: rate,
                      onChanged: upd,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Taxa de juros',
                        suffixText: '%',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<RateBasis>(
                    value: basis,
                    items: [
                      for (final b in RateBasis.values)
                        DropdownMenuItem(value: b, child: Text(b.label)),
                    ],
                    onChanged: (v) => setState(() => basis = v!),
                  ),
                ],
              ),
              TextField(
                key: const Key('fin-months'),
                controller: months,
                onChanged: upd,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Prazo (meses)'),
              ),
              const SizedBox(height: 8),
              DateField(
                value: first,
                label: 'Primeira parcela',
                onChanged: (d) => setState(() => first = d ?? first),
              ),
              TextField(
                controller: fees,
                onChanged: upd,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Seguros e taxas por mês',
                  prefixText: 'R\$ ',
                ),
              ),
              TextField(
                controller: upfront,
                onChanged: upd,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'IOF e tarifas na contratação',
                  prefixText: 'R\$ ',
                ),
              ),
              DropdownButtonFormField<DebtIndex>(
                initialValue: index,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Correção do saldo',
                ),
                items: [
                  for (final i in DebtIndex.values)
                    DropdownMenuItem(value: i, child: Text(i.label)),
                ],
                onChanged: (v) => setState(() => index = v!),
              ),
              if (index != DebtIndex.none)
                TextField(
                  controller: indexRate,
                  onChanged: upd,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Estimativa de ${index.label} ao mês',
                    suffixText: '%',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (c == null)
          const SectionCard(
            child: Text(
              'Informe valor, taxa e prazo (até 600 meses) para comparar.',
            ),
          )
        else ...[
          SectionCard(
            title: 'Price × SAC',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CompareTable(c),
                const SizedBox(height: 8),
                Text(
                  c.sacInterestSavings.isPositive
                      ? 'No SAC você paga ${c.sacInterestSavings.format()} a '
                            'menos de juros, mas a primeira parcela é '
                            '${(c.sac.schedule.firstPayment - c.price.schedule.firstPayment).format()} '
                            'maior.'
                      : 'Os dois sistemas custam o mesmo com esses termos.',
                  style: context.text.bodyMedium,
                ),
                const SizedBox(height: 8),
                AssumptionsList(
                  calculatedAt: c.calculatedAt,
                  assumptions: c.assumptions,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _save(context, c),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Salvar simulação'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Cronograma mês a mês',
            trailing: SegmentedButton<AmortizationSystem>(
              segments: const [
                ButtonSegment(
                  value: AmortizationSystem.price,
                  label: Text('Price'),
                ),
                ButtonSegment(
                  value: AmortizationSystem.sac,
                  label: Text('SAC'),
                ),
              ],
              selected: {show},
              onSelectionChanged: (s) => setState(() => show = s.first),
            ),
            child: ScheduleTable(
              show == AmortizationSystem.price
                  ? c.price.schedule
                  : c.sac.schedule,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _save(BuildContext context, FinancingComparison c) {
    final fc = context.read<FinanceController>();
    Map<String, Object?> row(String label, FinancingOption o) => {
      'label': label,
      'firstPayment': o.schedule.firstPayment.cents,
      'lastPayment': o.schedule.lastPayment.cents,
      'totalInterest': o.schedule.totalInterest.cents,
      'totalFees': o.schedule.totalFees.cents,
      'totalCost': o.schedule.totalCost.cents,
      'cetMonthly': o.cetMonthly,
    };
    return runAction(
      context,
      () => fc.saveDebtScenario(
        DebtScenario(
          id: newId('dsc_'),
          name:
              'Financiamento de ${c.price.schedule.principal.format()} em '
              '${c.price.schedule.months}x',
          kind: ScenarioKind.newFinancing,
          calculatedAt: c.calculatedAt,
          inputs: {
            'principal': c.price.schedule.principal.cents,
            'months': c.price.schedule.months,
            'rate': rate.text,
            'basis': basis.name,
            'firstDue': Dates.toIso(first),
          },
          summary: [row('Price', c.price), row('SAC', c.sac)],
          notes: c.assumptions.join('\n'),
        ),
      ),
      success: 'Simulação salva',
    );
  }
}

class _CompareTable extends StatelessWidget {
  final FinancingComparison c;
  const _CompareTable(this.c);

  @override
  Widget build(BuildContext context) {
    final p = c.price, s = c.sac;
    String cet(FinancingOption o) => o.cetMonthly == null
        ? '—'
        : '${pct(o.cetMonthly!)} a.m.\n${pct(o.cetAnnual!)} a.a.';
    final rows = <(String, String, String)>[
      (
        'Primeira parcela',
        p.schedule.firstPayment.format(),
        s.schedule.firstPayment.format(),
      ),
      (
        'Última parcela',
        p.schedule.lastPayment.format(),
        s.schedule.lastPayment.format(),
      ),
      (
        'Total de juros',
        p.schedule.totalInterest.format(),
        s.schedule.totalInterest.format(),
      ),
      if (p.schedule.totalCorrection.isPositive)
        (
          'Correção do saldo',
          p.schedule.totalCorrection.format(),
          s.schedule.totalCorrection.format(),
        ),
      if (p.schedule.totalFees.isPositive)
        (
          'Seguros e taxas',
          p.schedule.totalFees.format(),
          s.schedule.totalFees.format(),
        ),
      if (p.schedule.upfrontCharges.isPositive)
        (
          'Custos na contratação',
          p.schedule.upfrontCharges.format(),
          s.schedule.upfrontCharges.format(),
        ),
      (
        'Custo total',
        p.schedule.totalCost.format(),
        s.schedule.totalCost.format(),
      ),
      ('CET estimado', cet(p), cet(s)),
    ];
    final bold = context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.3),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
      },
      children: [
        TableRow(
          children: [
            const SizedBox(),
            Text('Price', style: bold, textAlign: TextAlign.right),
            Text('SAC', style: bold, textAlign: TextAlign.right),
          ],
        ),
        for (final r in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(r.$1),
              ),
              for (final v in [r.$2, r.$3])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(v, textAlign: TextAlign.right),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Comparar dívidas

class CompareDebtsTab extends StatefulWidget {
  const CompareDebtsTab({super.key});
  @override
  State<CompareDebtsTab> createState() => _CompareDebtsTabState();
}

class _CompareDebtsTabState extends State<CompareDebtsTab> {
  final cash = TextEditingController(text: '10.000,00');
  late final reserve = TextEditingController(
    text: context.read<FinanceController>().minimumReserve.formatPlain(),
  );
  DebtSort sort = DebtSort.totalSaved;
  int? expanded;

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final amount = Money.tryEval(cash.text) ?? Money.zero;
    final res = Money.tryEval(reserve.text) ?? Money.zero;
    final today = fc.today;
    final list = amount.isPositive
        ? sortEstimates(compareDebts(fc.activeDebts, amount, asOf: today), sort)
        : const <DebtEstimate>[];
    final cols = projectionAhead(fc);
    final ok = list.where((e) => e.ok).toList();
    final missingByDebt = <String, DebtEstimate>{};
    for (final e in list.where((e) => !e.ok && e.missing.isNotEmpty)) {
      missingByDebt.putIfAbsent(e.debt.id, () => e);
    }
    final blocked = list.where((e) => !e.ok && e.missing.isEmpty).toList();
    final base = cashImpact(cols, const {}, reserve: res);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        SectionCard(
          title: 'Quanto você tem para usar',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('cmp-cash'),
                controller: cash,
                onChanged: (_) => setState(() => expanded = null),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Dinheiro disponível',
                  prefixText: 'R\$ ',
                ),
              ),
              TextField(
                key: const Key('cmp-reserve'),
                controller: reserve,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _saveReserve(fc),
                onTapOutside: (_) => _saveReserve(fc),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Reserva mínima (fica salva nas Preferências)',
                  prefixText: 'R\$ ',
                ),
              ),
              if (base.points.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Sem usar o dinheiro, o menor saldo projetado nos '
                    'próximos 12 meses é ${base.minBefore.format()}.',
                    style: context.text.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              SegmentedButton<DebtSort>(
                segments: [
                  for (final s in DebtSort.values)
                    ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {sort},
                onSelectionChanged: (s) => setState(() => sort = s.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (fc.activeDebts.isEmpty)
          const EmptyState(
            icon: Icons.request_quote_outlined,
            title: 'Cadastre seus contratos',
            message: 'Na aba Contratos, cadastre ao menos duas dívidas.',
          ),
        if (missingByDebt.isNotEmpty)
          SectionCard(
            title: 'Faltam dados para estimar',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in missingByDebt.values) ...[
                  Text(e.debt.name, style: context.text.titleSmall),
                  MissingFieldsCard(
                    missing: e.missing,
                    onEdit: () => push(context, DebtFormScreen(debt: e.debt)),
                    onQuote: () => addLenderQuote(context, e.debt),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        for (var i = 0; i < ok.length; i++)
          _OptionCard(
            e: ok[i],
            rank: i + 1,
            expanded: expanded == i,
            onTap: () => setState(() => expanded = expanded == i ? null : i),
            impact: cashImpact(cols, ok[i].result!.cashDelta(), reserve: res),
          ),
        if (ok.length >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => _saveComparison(fc, amount, ok),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Salvar esta comparação'),
            ),
          ),
        if (blocked.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Opções que não se aplicam',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in blocked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${e.debt.name} · ${e.option.label}: ${e.blocked}',
                      style: context.text.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _saveReserve(FinanceController fc) {
    final v = Money.tryEval(reserve.text);
    if (v != null && !v.isNegative && v != fc.minimumReserve) {
      fc.setMinimumReserve(v);
    }
  }

  Future<void> _saveComparison(
    FinanceController fc,
    Money amount,
    List<DebtEstimate> ok,
  ) => runAction(
    context,
    () => fc.saveDebtScenario(
      DebtScenario(
        id: newId('dsc_'),
        name: 'Comparação com ${amount.format()}',
        kind: ScenarioKind.comparison,
        calculatedAt: fc.today,
        inputs: {'cash': amount.cents, 'sort': sort.name},
        summary: [for (final e in ok) e.result!.toSummary()],
      ),
    ),
    success: 'Comparação salva',
  );
}

class _OptionCard extends StatelessWidget {
  final DebtEstimate e;
  final int rank;
  final bool expanded;
  final VoidCallback onTap;
  final CashImpact impact;
  const _OptionCard({
    required this.e,
    required this.rank,
    required this.expanded,
    required this.onTap,
    required this.impact,
  });

  @override
  Widget build(BuildContext context) {
    final r = e.result!;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 12, child: Text('$rank')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${e.debt.name} · ${e.option.label}',
                      style: context.text.titleSmall,
                    ),
                  ),
                  SourcePill(r.source),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _kv(context, 'Sai agora', r.outflow.format()),
                  _kv(context, 'Economia', r.totalSaved.format()),
                  _kv(context, 'Parcela', '−${r.monthlyRelief.format()}/mês'),
                  _kv(context, 'Prazo', '${r.monthsBefore} → ${r.monthsAfter}'),
                  _kv(context, 'Menor caixa', impact.minAfter.format()),
                ],
              ),
              if (impact.breaksReserve)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Deixa o caixa abaixo da reserva mínima a partir de '
                    '${impact.firstBelowReserve!.shortLabel}.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.fin.negative,
                    ),
                  ),
                ),
              if (expanded) ...[
                const Divider(),
                PrepayResultView(r, impact: impact),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () =>
                          push(context, DebtDetailScreen(e.debt.id)),
                      child: const Text('Abrir contrato'),
                    ),
                    FilledButton(
                      onPressed: () => confirmApplyPlan(context, r),
                      child: const Text('Levar para o planejamento'),
                    ),
                  ],
                ),
              ] else
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Toque para ver detalhes',
                    style: context.text.bodySmall?.copyWith(
                      color: context.fin.subtle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        k,
        style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
      ),
      Text(v, style: context.text.bodyMedium),
    ],
  );
}

// -----------------------------------------------------------------------------
// Simulações salvas

class _ScenariosTab extends StatefulWidget {
  const _ScenariosTab();
  @override
  State<_ScenariosTab> createState() => _ScenariosTabState();
}

class _ScenariosTabState extends State<_ScenariosTab> {
  final selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final list = fc.debtScenarios;
    if (list.isEmpty) {
      return const EmptyState(
        icon: Icons.bookmarks_outlined,
        title: 'Nenhuma simulação salva',
        message:
            'Salve simulações de financiamento, antecipação ou comparação '
            'para comparar depois.',
      );
    }
    final picked = list.where((s) => selected.contains(s.id)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        Text(
          'Marque duas ou mais para comparar lado a lado.',
          style: context.text.bodySmall,
        ),
        for (final s in list)
          Card(
            child: CheckboxListTile(
              value: selected.contains(s.id),
              onChanged: (v) => setState(
                () => v! ? selected.add(s.id) : selected.remove(s.id),
              ),
              title: Text(s.name),
              subtitle: Text(
                '${s.kind.label} · calculada em ${Dates.format(s.calculatedAt)}'
                '${s.appliedAt == null ? '' : ' · no plano desde ${Dates.format(s.appliedAt!)}'}',
              ),
              secondary: IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await confirmDialog(
                    context,
                    title: 'Excluir simulação?',
                    message: 'O plano já confirmado não muda.',
                    confirm: 'Excluir',
                    destructive: true,
                  );
                  if (ok) {
                    selected.remove(s.id);
                    await fc.deleteDebtScenario(s);
                  }
                },
              ),
            ),
          ),
        if (picked.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: picked.length == 1 ? 'Detalhes' : 'Comparação',
            child: _ScenarioCompare(picked),
          ),
        ],
      ],
    );
  }
}

class _ScenarioCompare extends StatelessWidget {
  final List<DebtScenario> list;
  const _ScenarioCompare(this.list);

  @override
  Widget build(BuildContext context) {
    String m(Object? v) => v == null ? '—' : Money((v as num).toInt()).format();
    final rows = <(String, List<String>)>[];
    final heads = <String>[];
    final cells = <List<String>>[];
    for (final s in list) {
      for (final r in s.summary) {
        heads.add(
          [
            s.name,
            if (r['label'] != null) r['label'],
            if (r['option'] != null && s.kind == ScenarioKind.comparison)
              '${r['debtName']} · ${PrepayOption.values.where((o) => o.name == r['option']).firstOrNull?.label ?? ''}',
          ].join('\n'),
        );
        cells.add([
          if (s.kind == ScenarioKind.newFinancing) ...[
            m(r['firstPayment']),
            m(r['lastPayment']),
            m(r['totalInterest']),
            m(r['totalCost']),
          ] else ...[
            m(r['outflow']),
            m(r['totalSaved']),
            m(r['monthlyRelief']),
            '${r['monthsBefore']} → ${r['monthsAfter']}',
          ],
          r['source'] == 'lender' ? 'Cotação do credor' : 'Estimativa do app',
        ]);
      }
    }
    final fin = list.every((s) => s.kind == ScenarioKind.newFinancing);
    final labels = fin
        ? ['1ª parcela', 'Última parcela', 'Juros', 'Custo total', 'Fonte']
        : ['Sai agora', 'Economia', 'Parcela a menos', 'Prazo', 'Fonte'];
    if (list.any((s) => s.kind == ScenarioKind.newFinancing) && !fin) {
      return const Text(
        'Compare simulações do mesmo tipo (financiamento com financiamento, '
        'antecipação com antecipação).',
      );
    }
    for (var i = 0; i < labels.length; i++) {
      rows.add((labels[i], [for (final c in cells) c[i]]));
    }
    final small = context.text.bodySmall;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        horizontalMargin: 4,
        dataRowMaxHeight: 40,
        headingRowHeight: 64,
        columns: [
          const DataColumn(label: Text('')),
          for (final h in heads)
            DataColumn(label: Text(h, style: small), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(Text(r.$1, style: small)),
                for (final v in r.$2) DataCell(Text(v, style: small)),
              ],
            ),
        ],
      ),
    );
  }
}
