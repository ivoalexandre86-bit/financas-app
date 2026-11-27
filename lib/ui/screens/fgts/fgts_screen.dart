import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/fgts_engine.dart';
import '../../../domain/engine/projection_filter.dart';
import '../../../domain/models/asset.dart';
import '../../../domain/models/fgts.dart';
import '../../../domain/models/scenario.dart';
import '../../../state/finance_controller.dart';
import '../../app_shell.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../projection/projection_screen.dart';

/// FGTS: saldo como ativo à parte e saques simulados em cenários.
class FgtsScreen extends StatelessWidget {
  const FgtsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final a = fc.fgts;
    return Scaffold(
      appBar: AppBar(title: const Text('FGTS')),
      floatingActionButton: a == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('fgts-new-withdrawal'),
              heroTag: 'fab-fgts',
              onPressed: () =>
                  push(context, FgtsWithdrawalFormScreen(fgtsId: a.id)),
              icon: const Icon(Icons.add),
              label: const Text('Simular saque'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (a == null)
            SectionCard(
              title: 'Acompanhe o seu FGTS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Registre o saldo do FGTS como um bem à parte no seu '
                    'patrimônio. Ele só entra no caixa da Projeção quando '
                    'você escolhe um cenário com um saque simulado.',
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('fgts-register'),
                    onPressed: () => push(context, const FgtsFormScreen()),
                    icon: const Icon(Icons.add),
                    label: const Text('Registrar saldo do FGTS'),
                  ),
                ],
              ),
            )
          else ...[
            _BalanceCard(fgts: a),
            const SizedBox(height: 12),
            _ForecastCard(fgts: a),
            const SizedBox(height: 12),
            _WithdrawalsCard(fgts: a),
          ],
          const SizedBox(height: 12),
          const FgtsSourceNote(),
        ],
      ),
    );
  }
}

/// Selo "Confirmado" / "Estimado".
class ConfirmedPill extends StatelessWidget {
  final bool confirmed;
  final String what;
  const ConfirmedPill({super.key, required this.confirmed, this.what = ''});

  @override
  Widget build(BuildContext context) {
    final label = confirmed ? 'confirmad' : 'estimad';
    final suffix = what.endsWith('a') ? 'a' : 'o';
    final text = what.isEmpty
        ? (confirmed ? 'Confirmado' : 'Estimado')
        : '${what[0].toUpperCase()}${what.substring(1)} $label$suffix';
    return Pill(
      text,
      color: confirmed ? context.fin.positive : context.fin.warning,
      icon: confirmed ? Icons.verified_outlined : Icons.schedule,
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final Asset fgts;
  const _BalanceCard({required this.fgts});

  @override
  Widget build(BuildContext context) {
    final d = fgts.fgts ?? FgtsDetails(balanceDate: fgts.updatedAt);
    return SectionCard(
      title: 'Saldo do FGTS',
      trailing: IconButton(
        tooltip: 'Editar',
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => push(context, FgtsFormScreen(fgts: fgts)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MoneyText(
            fgts.value,
            key: const ValueKey('fgts-balance'),
            style: context.text.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConfirmedPill(confirmed: d.balanceConfirmed),
              Text(
                'em ${Dates.format(d.balanceDate)}',
                style: context.text.bodySmall?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow.text(
            'Depósito mensal',
            d.monthlyDeposit.isZero
                ? 'Não informado'
                : d.monthlyDeposit.format(),
          ),
          InfoRow.text(
            'Rendimento usado na estimativa',
            '${d.annualRatePct.toStringAsFixed(2).replaceAll('.', ',')}% ao ano',
          ),
          if (d.employer.isNotEmpty) InfoRow.text('Vínculo', d.employer),
          const SizedBox(height: 8),
          Text(
            'Entra no patrimônio como ativo à parte. Não é dinheiro em conta: '
            'só vira caixa num saque.',
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
        ],
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  final Asset fgts;
  const _ForecastCard({required this.fgts});

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final today = fc.today;
    return SectionCard(
      title: 'Saldo previsto (sem saques)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final years in const [1, 2, 5])
            InfoRow(
              'Em $years ${years == 1 ? 'ano' : 'anos'}',
              MoneyText(
                FgtsEngine.projectedBalance(
                  fgts,
                  DateTime(today.year + years, today.month, today.day),
                ),
              ),
            ),
          Text(
            'Estimativa: saldo informado + depósitos mensais + rendimento. '
            'A TR e a distribuição de lucros não entram.',
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
        ],
      ),
    );
  }
}

class _WithdrawalsCard extends StatelessWidget {
  final Asset fgts;
  const _WithdrawalsCard({required this.fgts});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final list = FgtsEngine.withdrawals(fgts, fc.scenarios);
    return SectionCard(
      title: 'Saques simulados',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (list.isEmpty)
            Text(
              'Nenhum saque simulado. Use "Simular saque" para criar um '
              'cenário com valor, data e finalidade. O orçamento base não '
              'muda.',
              style: context.text.bodyMedium,
            ),
          for (final w in list) _WithdrawalTile(fgts: fgts, w: w),
        ],
      ),
    );
  }
}

class _WithdrawalTile extends StatelessWidget {
  final Asset fgts;
  final FgtsWithdrawal w;
  const _WithdrawalTile({required this.fgts, required this.w});

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final f = w.flow;
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    return Padding(
      key: ValueKey('fgts-withdrawal-${f.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  w.purpose.label,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MoneyText(
                f.amount,
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Text(
            '${Dates.format(f.date)} · cenário "${w.scenario.name}"',
            style: subtle,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (f.realized)
                Pill(
                  'Recebido',
                  color: context.fin.positive,
                  icon: Icons.check_circle_outline,
                )
              else ...[
                ConfirmedPill(confirmed: f.amountConfirmed, what: 'valor'),
                ConfirmedPill(confirmed: f.dateConfirmed, what: 'data'),
              ],
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              if (!f.realized) ...[
                TextButton.icon(
                  onPressed: () {
                    fc.selectScenario(w.scenario.id);
                    if (!AppShell.goTo(context, 'projection')) {
                      push(context, const ProjectionScreen());
                    }
                  },
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('Ver na Projeção'),
                ),
                TextButton.icon(
                  onPressed: () => push(
                    context,
                    FgtsWithdrawalFormScreen(
                      fgtsId: fgts.id,
                      scenarioId: w.scenario.id,
                      flowId: f.id,
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                ),
                TextButton.icon(
                  onPressed: () => _receive(context, w),
                  icon: const Icon(Icons.download_done, size: 18),
                  label: const Text('Registrar recebimento'),
                ),
              ],
              TextButton.icon(
                onPressed: () => _delete(context, w),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Excluir'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, FgtsWithdrawal w) async {
    final fc = context.read<FinanceController>();
    final s = w.scenario.withoutFlow(w.flow.id);
    final only = s.flows.isEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir saque simulado?'),
        content: Text(
          w.flow.realized
              ? 'O lançamento do recebimento continua em Movimentações.'
              : only
              ? 'O cenário "${w.scenario.name}" também será excluído.'
              : 'Os outros fluxos do cenário continuam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(
      context,
      () => only ? fc.deleteScenario(w.scenario) : fc.saveScenario(s),
      success: 'Saque excluído',
    );
  }

  Future<void> _receive(BuildContext context, FgtsWithdrawal w) async {
    final fc = context.read<FinanceController>();
    final amount = TextEditingController(text: w.flow.amount.formatPlain());
    var date = fc.today;
    String? account = fc.activeAccounts.firstOrNull?.id;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Registrar recebimento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Lança a receita concluída na conta, baixa o saldo do FGTS '
                  'e tira o saque do cenário, para não contar duas vezes.',
                  style: ctx.text.bodySmall,
                ),
                const SizedBox(height: 12),
                MoneyField(controller: amount, label: 'Valor recebido'),
                const SizedBox(height: 12),
                DateField(
                  value: date,
                  label: 'Data do crédito',
                  onChanged: (d) => setState(() => date = d ?? date),
                ),
                const SizedBox(height: 12),
                AccountDropdown(
                  fc: fc,
                  value: account,
                  onChanged: (v) => setState(() => account = v),
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
                final acc = account;
                if (acc == null) return;
                final ok = await runAction(
                  ctx,
                  () => fc.receiveFgtsWithdrawal(
                    w.scenario,
                    w.flow,
                    accountId: acc,
                    amount: v,
                    date: date,
                  ),
                  success: 'Recebimento registrado',
                );
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Por que o acompanhamento é manual.
class FgtsSourceNote extends StatelessWidget {
  const FgtsSourceNote({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Atualização automática',
      child: Text(
        'Ainda não existe uma fonte oficial ou autorizada que entregue o saldo '
        'do FGTS a um app de finanças pessoais. O FGTS não faz parte do Open '
        'Finance, e a consulta autorizada pela Caixa vale só para '
        'instituições financeiras habilitadas, mostra apenas os depósitos '
        'dos últimos 12 meses e não o saldo. Por isso o acompanhamento é '
        'manual: confira o saldo no app FGTS (Caixa) e atualize aqui, '
        'marcando como confirmado.',
        style: context.text.bodySmall,
      ),
    );
  }
}

/// Cadastro e edição do saldo do FGTS.
class FgtsFormScreen extends StatefulWidget {
  final Asset? fgts;
  const FgtsFormScreen({super.key, this.fgts});
  @override
  State<FgtsFormScreen> createState() => _FgtsFormScreenState();
}

class _FgtsFormScreenState extends State<FgtsFormScreen> {
  final _form = GlobalKey<FormState>();
  late final FgtsDetails d0 = widget.fgts?.fgts ?? FgtsDetails();
  late final balance = TextEditingController(
    text: widget.fgts?.value.formatPlain() ?? '',
  );
  late final deposit = TextEditingController(
    text: d0.monthlyDeposit.isZero ? '' : d0.monthlyDeposit.formatPlain(),
  );
  final salary = TextEditingController();
  late final rate = TextEditingController(
    text: d0.annualRatePct.toStringAsFixed(2).replaceAll('.', ','),
  );
  late final employer = TextEditingController(text: d0.employer);
  late DateTime balanceDate = d0.balanceDate;
  late bool confirmed = widget.fgts == null ? true : d0.balanceConfirmed;

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fgts == null ? 'Registrar FGTS' : 'Editar FGTS'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MoneyField(
              key: const ValueKey('fgts-form-balance'),
              controller: balance,
              allowZero: true,
              label: 'Saldo total do FGTS',
            ),
            const SizedBox(height: 12),
            DateField(
              value: balanceDate,
              label: 'Data do saldo',
              onChanged: (v) => setState(() => balanceDate = v ?? balanceDate),
            ),
            SwitchListTile(
              key: const ValueKey('fgts-form-confirmed'),
              contentPadding: EdgeInsets.zero,
              value: confirmed,
              onChanged: (v) => setState(() => confirmed = v),
              title: const Text('Saldo conferido no extrato'),
              subtitle: const Text(
                'Desligue se o valor for uma estimativa sua.',
              ),
            ),
            const SizedBox(height: 4),
            MoneyField(
              controller: deposit,
              allowZero: true,
              optional: true,
              label: 'Depósito mensal (opcional)',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: MoneyField(
                    controller: salary,
                    allowZero: true,
                    optional: true,
                    label: 'Ou informe o salário bruto',
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    final s = Money.tryEval(salary.text);
                    if (s == null) return;
                    setState(
                      () =>
                          deposit.text = FgtsDetails.depositFromSalary(s)
                              .formatPlain(),
                    );
                  },
                  child: const Text('Calcular 8%'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: rate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Rendimento ao ano (%)',
                helperText: 'Por lei, 3% ao ano + TR. Usado só na estimativa.',
              ),
              validator: (v) =>
                  double.tryParse((v ?? '').replaceAll(',', '.')) == null
                  ? 'Informe um número'
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: employer,
              decoration: const InputDecoration(
                labelText: 'Vínculo ou empregador (opcional)',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('fgts-form-save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                final v = Money.tryEval(balance.text) ?? Money.zero;
                final details = d0.copyWith(
                  monthlyDeposit: Money.tryEval(deposit.text) ?? Money.zero,
                  annualRatePct: double.parse(rate.text.replaceAll(',', '.')),
                  balanceConfirmed: confirmed,
                  balanceDate: balanceDate,
                  employer: employer.text.trim(),
                );
                final base =
                    widget.fgts ??
                    Asset(
                      id: newId('asset_'),
                      name: 'FGTS',
                      kind: AssetKind.fgts,
                      value: v,
                    );
                final a = base
                    .withValue(v, balanceDate)
                    .copyWith(fgts: details);
                final ok = await runAction(
                  context,
                  () => fc.saveAsset(a),
                  success: 'FGTS salvo',
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

/// Saque simulado do FGTS dentro de um cenário.
class FgtsWithdrawalFormScreen extends StatefulWidget {
  final String fgtsId;
  final String? scenarioId;
  final String? flowId;
  const FgtsWithdrawalFormScreen({
    super.key,
    required this.fgtsId,
    this.scenarioId,
    this.flowId,
  });
  @override
  State<FgtsWithdrawalFormScreen> createState() =>
      _FgtsWithdrawalFormScreenState();
}

/// Valor especial do seletor de cenário: criar um cenário novo.
const _newScenario = '__new__';

class _FgtsWithdrawalFormScreenState extends State<FgtsWithdrawalFormScreen> {
  final _form = GlobalKey<FormState>();
  late final FinanceController fc = context.read<FinanceController>();
  late final PlanScenario? s0 = fc.scenarios
      .where((s) => s.id == widget.scenarioId)
      .firstOrNull;
  late final ScenarioFlow? f0 = s0?.flows
      .where((f) => f.id == widget.flowId)
      .firstOrNull;
  late final amount = TextEditingController(
    text: f0?.amount.formatPlain() ?? '',
  );
  late final name = TextEditingController();
  late final notes = TextEditingController(text: f0?.notes ?? '');
  late DateTime date =
      f0?.date ?? DateTime(fc.today.year, fc.today.month + 3, 10);
  late FgtsPurpose purpose = f0 == null
      ? FgtsPurpose.birthday
      : FgtsPurpose.parse(f0!.purpose);
  late bool amountConfirmed = f0?.amountConfirmed ?? false;
  late bool dateConfirmed = f0?.dateConfirmed ?? false;
  late String scenarioId = s0?.id ?? _newScenario;

  Asset get fgts => fc.assets.firstWhere((a) => a.id == widget.fgtsId);

  PlanScenario? get scenario =>
      fc.scenarios.where((s) => s.id == scenarioId).firstOrNull;

  ScenarioFlow _flow() => ScenarioFlow(
    id: f0?.id ?? newId('flow_'),
    date: Dates.dateOnly(date),
    amount: Money.tryEval(amount.text) ?? Money.zero,
    description: 'Saque do FGTS · ${purpose.label}',
    source: ScenarioSource.fgts,
    refId: widget.fgtsId,
    purpose: purpose.name,
    amountConfirmed: amountConfirmed,
    dateConfirmed: dateConfirmed,
    notes: notes.text.trim(),
  );

  List<ScenarioFlow> get _others => [
    for (final f in scenario?.flows ?? const <ScenarioFlow>[])
      if (f.id != f0?.id && f.source == ScenarioSource.fgts) f,
  ];

  @override
  Widget build(BuildContext context) {
    context.watch<FinanceController>();
    final flow = _flow();
    final before = FgtsEngine.projectedBalance(
      fgts,
      date,
      withdrawals: _others,
    );
    final warnings = flow.amount.isZero
        ? const <String>[]
        : FgtsEngine.warnings(fgts, flow, others: _others, today: fc.today);
    final options = [
      for (final s in fc.scenarios)
        if (!s.archived) s,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(f0 == null ? 'Simular saque do FGTS' : 'Editar saque'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('fgts-w-scenario'),
              initialValue: scenarioId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cenário'),
              items: [
                const DropdownMenuItem(
                  value: _newScenario,
                  child: Text('Novo cenário'),
                ),
                for (final s in options)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: f0 != null
                  ? null
                  : (v) => setState(() => scenarioId = v ?? scenarioId),
            ),
            if (scenarioId == _newScenario) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('fgts-w-name'),
                controller: name,
                decoration: InputDecoration(
                  labelText: 'Nome do cenário',
                  hintText: 'FGTS · ${purpose.label}',
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<FgtsPurpose>(
              key: const ValueKey('fgts-w-purpose'),
              initialValue: purpose,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Finalidade'),
              items: [
                for (final p in FgtsPurpose.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (v) => setState(() => purpose = v ?? purpose),
            ),
            if (purpose.paidToThirdParty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Nessa modalidade o dinheiro vai direto ao vendedor ou ao '
                  'banco. Na Projeção ele aparece como entrada que cobre a '
                  'despesa planejada (entrada do imóvel, amortização).',
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            MoneyField(
              key: const ValueKey('fgts-w-amount'),
              controller: amount,
              label: 'Valor do saque',
              onChanged: (_) => setState(() {}),
            ),
            Wrap(
              spacing: 4,
              children: [
                if (purpose == FgtsPurpose.birthday)
                  TextButton(
                    onPressed: () => setState(
                      () =>
                          amount.text = FgtsEngine.birthdayAmount(before)
                              .formatPlain(),
                    ),
                    child: const Text('Usar limite do saque-aniversário'),
                  ),
                TextButton(
                  onPressed: () =>
                      setState(() => amount.text = before.formatPlain()),
                  child: const Text('Todo o saldo previsto'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: amountConfirmed,
              onChanged: (v) => setState(() => amountConfirmed = v),
              title: const Text('Valor confirmado'),
              subtitle: const Text('Ex.: valor liberado no app FGTS.'),
            ),
            DateField(
              value: date,
              label: 'Data prevista',
              onChanged: (v) => setState(() => date = v ?? date),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: dateConfirmed,
              onChanged: (v) => setState(() => dateConfirmed = v),
              title: const Text('Data confirmada'),
            ),
            const SizedBox(height: 4),
            InfoRow('Saldo previsto do FGTS na data', MoneyText(before)),
            InfoRow(
              'Saldo do FGTS depois do saque',
              MoneyText(before - flow.amount, colorize: true),
            ),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 18,
                      color: context.fin.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(w, style: context.text.bodySmall)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (!flow.amount.isZero)
              _CashPreview(flow: flow, scenario: scenario),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('fgts-w-save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                final f = _flow();
                if (f.amount.cents <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Informe o valor do saque')),
                  );
                  return;
                }
                final base =
                    scenario ??
                    PlanScenario(
                      id: newId('scn_'),
                      name: name.text.trim().isEmpty
                          ? 'FGTS · ${purpose.label}'
                          : name.text.trim(),
                      kind: ScenarioSource.fgts,
                    );
                final ok = await runAction(
                  context,
                  () => fc.saveScenario(base.withFlow(f)),
                  success: 'Saque simulado salvo',
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

/// Caixa projetado com e sem o saque (12 meses a partir do atual).
class _CashPreview extends StatelessWidget {
  final ScenarioFlow flow;
  final PlanScenario? scenario;
  const _CashPreview({required this.flow, required this.scenario});

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final se = fc.scenarioEngine;
    final range = MonthRange.starting(fc.engine.currentMonth, 12);
    final base = fc.engine.projection(range);
    final flows = [...?scenario?.flows.where((f) => f.id != flow.id), flow];
    final withIt = se.apply(base, flows);
    final m = se.monthOf(flow);
    final i = base.columns.indexWhere((c) => c.month == m);
    final last = base.columns.length - 1;
    return SectionCard(
      title: 'Caixa projetado',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (i >= 0) ...[
            Text('No fim de ${m.longLabel}', style: context.text.labelLarge),
            InfoRow(
              'Orçamento base',
              MoneyText(base.columns[i].accumulated, colorize: true),
            ),
            InfoRow(
              'Com este cenário',
              MoneyText(withIt.columns[i].accumulated, colorize: true),
            ),
          ] else
            Text(
              'A data fica depois dos próximos 12 meses.',
              style: context.text.bodySmall,
            ),
          const Divider(),
          Text(
            'Em ${base.columns[last].month.longLabel}',
            style: context.text.labelLarge,
          ),
          InfoRow(
            'Orçamento base',
            MoneyText(base.columns[last].accumulated, colorize: true),
          ),
          InfoRow(
            'Com este cenário',
            MoneyText(withIt.columns[last].accumulated, colorize: true),
          ),
          Text(
            'O saque só entra no caixa quando você escolhe o cenário na '
            'Projeção. Patrimônio não muda: o FGTS diminui e o caixa aumenta.',
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
        ],
      ),
    );
  }
}
