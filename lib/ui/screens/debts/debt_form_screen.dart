import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../data/cloud/ai_api.dart';
import '../../../domain/engine/calculators.dart' show monthlyFromAnnual;
import '../../../domain/models/debt.dart';
import '../../../domain/models/enums.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import 'debt_widgets.dart';

/// Valor opcional (vazio = não informado).
class OptionalMoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool highlighted;
  const OptionalMoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      prefixText: 'R\$ ',
      helperText: highlighted ? 'Lido do anexo: confira' : null,
    ),
    validator: (v) {
      if ((v ?? '').trim().isEmpty) return null;
      final m = Money.tryEval(v!);
      if (m == null || m.isNegative) return 'Valor inválido';
      return null;
    },
  );
}

Money? _money(TextEditingController c) =>
    c.text.trim().isEmpty ? null : Money.tryEval(c.text);
int? _int(TextEditingController c) => int.tryParse(c.text.trim());
String _mText(Money? m) => m == null ? '' : m.formatPlain();

/// Cadastro de empréstimo ou financiamento. Com o contrato ou extrato
/// anexado, a IA preenche os campos para o usuário revisar antes de salvar.
class DebtFormScreen extends StatefulWidget {
  final DebtContract? debt;
  const DebtFormScreen({super.key, this.debt});
  @override
  State<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends State<DebtFormScreen> {
  final form = GlobalKey<FormState>();
  late final DebtContract base;
  late final name = TextEditingController(text: base.name);
  late final lender = TextEditingController(text: base.lender);
  late final rate = TextEditingController(text: percentText(base.monthlyRate));
  late final original = TextEditingController(
    text: _mText(base.originalPrincipal),
  );
  late final term = TextEditingController(text: '${base.termMonths ?? ''}');
  late final outstanding = TextEditingController(
    text: _mText(base.outstanding),
  );
  late final remaining = TextEditingController(
    text: '${base.remainingMonths ?? ''}',
  );
  late final payment = TextEditingController(text: _mText(base.currentPayment));
  late final indexRate = TextEditingController(
    text: percentText(
      base.indexMonthlyRate == 0 ? null : base.indexMonthlyRate,
    ),
  );
  late final feeRate = TextEditingController(
    text: percentText(
      base.prepaymentFeeRate == 0 ? null : base.prepaymentFeeRate,
    ),
  );
  late final notes = TextEditingController(text: base.notes);
  late DebtKind kind = base.kind;
  late AmortizationSystem? system = base.system;
  RateBasis basis = RateBasis.monthly;
  late DateTime? contractDate = base.contractDate;
  late DateTime? balanceDate = base.balanceDate;
  late DateTime? nextDue = base.nextDueDate;
  late DebtIndex index = base.index;
  late OptionSupport lastInst = base.lastInstallments;
  late OptionSupport redTerm = base.reduceTerm;
  late OptionSupport redPay = base.reducePayment;
  late OptionSupport payoff = base.payoff;
  late DebtInstallments mode = base.installments;
  late String? accountId = base.accountId;
  late String? categoryId = base.categoryId;
  late String? linkedRuleId = base.linkedRuleId;
  late String? linkedGroupId = base.linkedGroupId;
  late List<DebtFee> fees = [...base.fees];
  late List<DebtAttachment> attachments = [...base.attachments];
  late Set<String> extracted = {...base.extractedFields};
  bool reading = false;

  @override
  void initState() {
    super.initState();
    base =
        widget.debt ??
        DebtContract(id: newId('debt_'), name: '', balanceDate: Dates.today());
  }

  bool _x(String f) => extracted.contains(f);

  static const _types = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  Future<void> _attach({required bool read}) async {
    final ai = Provider.of<AiService?>(context, listen: false);
    final file = await FilePicker.pickFile(
      dialogTitle: 'Contrato ou extrato (PDF ou foto)',
      type: FileType.custom,
      allowedExtensions: _types.keys.toList(),
    );
    if (file == null || !mounted) return;
    final bytes = await file.xFile.readAsBytes();
    final ext = file.name.split('.').last.toLowerCase();
    final mime = _types[ext] ?? 'application/octet-stream';
    if (bytes.length > DebtAttachment.maxBytes) {
      if (mounted) {
        showMessage(
          context,
          'Arquivo grande demais para guardar (máximo 2 MB). Os dados ainda '
          'podem ser lidos, mas o arquivo não fica anexado.',
          error: true,
        );
      }
    } else {
      setState(
        () => attachments.add(
          DebtAttachment(
            id: newId('att_'),
            name: file.name,
            mime: mime,
            size: bytes.length,
            data: base64Encode(bytes),
          ),
        ),
      );
    }
    if (!read) return;
    if (ai == null) {
      if (mounted) {
        showMessage(
          context,
          'A leitura automática precisa da conta na nuvem. Preencha os '
          'campos à mão.',
          error: true,
        );
      }
      return;
    }
    setState(() => reading = true);
    try {
      final c = await ai.readContract(bytes: bytes, mimeType: mime);
      if (!mounted) return;
      _applyExtracted(c);
      showMessage(
        context,
        'Contrato lido. Confira os campos marcados antes de salvar.',
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Não consegui ler: $e', error: true);
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  void _applyExtracted(Map<String, Object?> c) {
    Money? m(String k) => c[k] == null ? null : Money((c[k] as num).toInt());
    DateTime? d(String k) =>
        c[k] == null ? null : Dates.fromIso(c[k] as String);
    setState(() {
      final got = <String>{};
      void put(String k, VoidCallback f) {
        if (c[k] != null) {
          f();
          got.add(k);
        }
      }

      put('name', () {
        if (name.text.trim().isEmpty) name.text = c['name'] as String;
      });
      put('lender', () => lender.text = c['lender'] as String);
      put(
        'kind',
        () => kind =
            DebtKind.values.where((k) => k.name == c['kind']).firstOrNull ??
            kind,
      );
      put(
        'system',
        () => system = AmortizationSystem.values
            .where((s) => s.name == c['system'])
            .firstOrNull,
      );
      put('monthlyRate', () {
        basis = RateBasis.monthly;
        rate.text = percentText((c['monthlyRate'] as num).toDouble());
      });
      put(
        'originalPrincipal',
        () => original.text = _mText(m('originalPrincipal')),
      );
      put('contractDate', () => contractDate = d('contractDate'));
      put('termMonths', () => term.text = '${c['termMonths']}');
      put('outstanding', () => outstanding.text = _mText(m('outstanding')));
      put('balanceDate', () => balanceDate = d('balanceDate'));
      put('remainingMonths', () => remaining.text = '${c['remainingMonths']}');
      put('nextDueDate', () => nextDue = d('nextDueDate'));
      put('currentPayment', () => payment.text = _mText(m('currentPayment')));
      put(
        'index',
        () => index =
            DebtIndex.values.where((x) => x.name == c['index']).firstOrNull ??
            index,
      );
      if (c['fees'] is List && (c['fees'] as List).isNotEmpty) {
        fees = [
          for (final f in c['fees'] as List)
            DebtFee.fromJson(Map<String, Object?>.from(f as Map)),
        ];
        got.add('fees');
      }
      final n = (c['notes'] as String?) ?? '';
      if (n.isNotEmpty && !notes.text.contains(n)) {
        notes.text = [
          if (notes.text.isNotEmpty) notes.text,
          'Leitura do anexo: $n',
        ].join('\n');
      }
      extracted = {...extracted, ...got};
    });
  }

  double? _rate() {
    final r = parsePercent(rate.text);
    if (r == null) return null;
    return basis == RateBasis.annual ? monthlyFromAnnual(r) : r;
  }

  Future<void> _addFee() async {
    final nameC = TextEditingController();
    final valC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encargo mensal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(
                labelText: 'Nome (ex.: Seguro MIP/DFI)',
              ),
            ),
            TextField(
              controller: valC,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor por mês',
                prefixText: 'R\$ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    final v = Money.tryEval(valC.text);
    if (ok == true && v != null && v.isPositive) {
      setState(
        () => fees.add(
          DebtFee(nameC.text.trim().isEmpty ? 'Encargo' : nameC.text.trim(), v),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    final fc = context.read<FinanceController>();
    final d = base.copyWith(
      name: name.text.trim(),
      lender: lender.text.trim(),
      kind: kind,
      system: system,
      monthlyRate: _rate(),
      originalPrincipal: _money(original),
      contractDate: contractDate,
      termMonths: _int(term),
      outstanding: _money(outstanding),
      balanceDate: balanceDate,
      remainingMonths: _int(remaining),
      nextDueDate: nextDue,
      currentPayment: _money(payment),
      fees: fees,
      index: index,
      indexMonthlyRate: index == DebtIndex.none
          ? 0
          : (parsePercent(indexRate.text) ?? 0),
      lastInstallments: lastInst,
      reduceTerm: redTerm,
      reducePayment: redPay,
      payoff: payoff,
      prepaymentFeeRate: parsePercent(feeRate.text) ?? 0,
      installments: mode,
      accountId: accountId,
      categoryId: categoryId,
      linkedRuleId: mode == DebtInstallments.linked ? linkedRuleId : null,
      linkedGroupId: mode == DebtInstallments.linked ? linkedGroupId : null,
      attachments: attachments,
      extractedFields: extracted.toList(),
      notes: notes.text.trim(),
    );
    final ok = await runAction(
      context,
      () => fc.saveDebt(d),
      success: 'Contrato salvo',
    );
    if (ok && mounted) Navigator.pop(context, d.id);
  }

  Widget _support(
    String label,
    OptionSupport v,
    ValueChanged<OptionSupport> f,
  ) => DropdownButtonFormField<OptionSupport>(
    initialValue: v,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final o in OptionSupport.values)
        DropdownMenuItem(value: o, child: Text(o.label)),
    ],
    onChanged: (x) => setState(() => f(x!)),
  );

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final hasAi = Provider.of<AiService?>(context) != null;
    const gap = SizedBox(height: 12);
    final rules =
        fc.data.recurringRules
            .where((r) => r.type == TransactionType.expense)
            .toList()
          ..sort((a, b) => a.description.compareTo(b.description));
    final groups = fc.data.installmentGroups.toList()
      ..sort((a, b) => a.description.compareTo(b.description));
    String? linkValue = linkedRuleId != null
        ? 'r:$linkedRuleId'
        : linkedGroupId != null
        ? 'g:$linkedGroupId'
        : null;
    final linkItems = [
      for (final r in rules)
        DropdownMenuItem(
          value: 'r:${r.id}',
          child: Text(
            'Recorrência: ${r.description} (${r.amount.format()})',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      for (final g in groups)
        DropdownMenuItem(
          value: 'g:${g.id}',
          child: Text(
            'Parcelamento: ${g.description} (${g.count}x)',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    if (!linkItems.any((i) => i.value == linkValue)) linkValue = null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.debt == null ? 'Novo contrato' : 'Editar contrato'),
        actions: [TextButton(onPressed: _save, child: const Text('Salvar'))],
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            SectionCard(
              title: 'Contrato ou extrato',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasAi
                        ? 'Anexe o PDF ou uma foto e o app lê os dados. '
                              'Nada é salvo antes de você revisar.'
                        : 'Anexe o PDF ou uma foto para guardar com o '
                              'contrato.',
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (hasAi)
                        FilledButton.icon(
                          key: const Key('debt-read'),
                          onPressed: reading ? null : () => _attach(read: true),
                          icon: reading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.document_scanner_outlined),
                          label: const Text('Anexar e ler dados'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _attach(read: false),
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Só anexar'),
                      ),
                    ],
                  ),
                  for (final a in attachments)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(a.name),
                      subtitle: Text(
                        '${(a.size / 1024).toStringAsFixed(0)} KB · '
                        '${Dates.format(a.addedAt)}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Remover anexo',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => attachments.remove(a)),
                      ),
                    ),
                  if (extracted.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${extracted.length} campos vieram do anexo e estão '
                        'marcados com "Lido do anexo". Confira cada um.',
                        style: context.text.bodySmall?.copyWith(
                          color: context.fin.warning,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            gap,
            SectionCard(
              title: 'Identificação',
              child: Column(
                children: [
                  TextFormField(
                    key: const Key('debt-name'),
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nome (ex.: Financiamento do carro)',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Informe um nome' : null,
                  ),
                  TextFormField(
                    controller: lender,
                    decoration: InputDecoration(
                      labelText: 'Credor (banco, financeira)',
                      helperText: _x('lender')
                          ? 'Lido do anexo: confira'
                          : null,
                    ),
                  ),
                  DropdownButtonFormField<DebtKind>(
                    initialValue: kind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: [
                      for (final k in DebtKind.values)
                        DropdownMenuItem(value: k, child: Text(k.label)),
                    ],
                    onChanged: (v) => setState(() => kind = v!),
                  ),
                ],
              ),
            ),
            gap,
            SectionCard(
              title: 'Situação atual',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OptionalMoneyField(
                    key: const Key('debt-outstanding'),
                    controller: outstanding,
                    label: 'Saldo devedor',
                    highlighted: _x('outstanding'),
                  ),
                  const SizedBox(height: 8),
                  DateField(
                    value: balanceDate,
                    label: 'Data do saldo',
                    clearable: true,
                    onChanged: (d) => setState(() => balanceDate = d),
                  ),
                  TextFormField(
                    key: const Key('debt-remaining'),
                    controller: remaining,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Parcelas restantes',
                      helperText: _x('remainingMonths')
                          ? 'Lido do anexo: confira'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DateField(
                    value: nextDue,
                    label: 'Vencimento da próxima parcela',
                    clearable: true,
                    onChanged: (d) => setState(() => nextDue = d),
                  ),
                  OptionalMoneyField(
                    controller: payment,
                    label: 'Parcela atual (sem seguros e taxas)',
                    highlighted: _x('currentPayment'),
                  ),
                ],
              ),
            ),
            gap,
            SectionCard(
              title: 'Condições do contrato',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<AmortizationSystem?>(
                    key: const Key('debt-system'),
                    initialValue: system,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Sistema de amortização',
                      helperText: _x('system')
                          ? 'Lido do anexo: confira'
                          : null,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Não sei')),
                      DropdownMenuItem(
                        value: AmortizationSystem.price,
                        child: Text('Price (parcelas iguais)'),
                      ),
                      DropdownMenuItem(
                        value: AmortizationSystem.sac,
                        child: Text('SAC (parcelas decrescentes)'),
                      ),
                    ],
                    onChanged: (v) => setState(() => system = v),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('debt-rate'),
                          controller: rate,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Taxa de juros',
                            suffixText: '%',
                            helperText: _x('monthlyRate')
                                ? 'Lido do anexo: confira'
                                : null,
                          ),
                          validator: (v) =>
                              (v ?? '').trim().isNotEmpty &&
                                  parsePercent(v!) == null
                              ? 'Taxa inválida'
                              : null,
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
                  DropdownButtonFormField<DebtIndex>(
                    initialValue: index,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Correção do saldo (indexador)',
                    ),
                    items: [
                      for (final i in DebtIndex.values)
                        DropdownMenuItem(value: i, child: Text(i.label)),
                    ],
                    onChanged: (v) => setState(() => index = v!),
                  ),
                  if (index != DebtIndex.none)
                    TextFormField(
                      controller: indexRate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Estimativa de ${index.label} ao mês',
                        suffixText: '%',
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text('Encargos mensais', style: context.text.titleSmall),
                  for (final f in fees)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.name),
                      subtitle: Text('${f.monthly.format()} por mês'),
                      trailing: IconButton(
                        tooltip: 'Remover',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => fees.remove(f)),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _addFee,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar seguro ou taxa'),
                  ),
                ],
              ),
            ),
            gap,
            SectionCard(
              title: 'Dados originais (opcional)',
              child: Column(
                children: [
                  OptionalMoneyField(
                    controller: original,
                    label: 'Valor contratado',
                    highlighted: _x('originalPrincipal'),
                  ),
                  const SizedBox(height: 8),
                  DateField(
                    value: contractDate,
                    label: 'Data do contrato',
                    clearable: true,
                    onChanged: (d) => setState(() => contractDate = d),
                  ),
                  TextFormField(
                    controller: term,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Prazo total (parcelas)',
                    ),
                  ),
                ],
              ),
            ),
            gap,
            SectionCard(
              title: 'O contrato permite',
              child: Column(
                children: [
                  _support(
                    'Antecipar as últimas parcelas',
                    lastInst,
                    (v) => lastInst = v,
                  ),
                  _support(
                    'Amortizar e reduzir o prazo',
                    redTerm,
                    (v) => redTerm = v,
                  ),
                  _support(
                    'Amortizar e reduzir a parcela',
                    redPay,
                    (v) => redPay = v,
                  ),
                  _support('Quitar antes do prazo', payoff, (v) => payoff = v),
                  TextFormField(
                    controller: feeRate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Tarifa sobre o valor antecipado',
                      suffixText: '%',
                      helperText: 'Deixe vazio se não houver.',
                    ),
                  ),
                ],
              ),
            ),
            gap,
            SectionCard(
              title: 'Parcelas na Projeção',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cada parcela conta uma vez só: ou ela já está lançada '
                    '(recorrência ou parcelamento), ou o app gera a partir do '
                    'contrato.',
                    style: context.text.bodySmall,
                  ),
                  DropdownButtonFormField<DebtInstallments>(
                    key: const Key('debt-mode'),
                    initialValue: mode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Parcelas'),
                    items: [
                      for (final m in DebtInstallments.values)
                        DropdownMenuItem(value: m, child: Text(m.label)),
                    ],
                    onChanged: (v) => setState(() => mode = v!),
                  ),
                  if (mode == DebtInstallments.linked)
                    linkItems.isEmpty
                        ? const Text(
                            'Nenhuma recorrência ou parcelamento de despesa '
                            'lançado ainda.',
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: linkValue,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Lançamento das parcelas',
                            ),
                            items: linkItems,
                            validator: (v) =>
                                v == null ? 'Escolha o lançamento' : null,
                            onChanged: (v) => setState(() {
                              linkedRuleId = v!.startsWith('r:')
                                  ? v.substring(2)
                                  : null;
                              linkedGroupId = v.startsWith('g:')
                                  ? v.substring(2)
                                  : null;
                            }),
                          ),
                  if (mode != DebtInstallments.none || accountId != null)
                    AccountDropdown(
                      fc: fc,
                      value: accountId,
                      label: 'Conta que paga as parcelas',
                      onChanged: (v) => setState(() => accountId = v),
                    ),
                  if (mode == DebtInstallments.generated) ...[
                    const SizedBox(height: 8),
                    CategoryDropdown(
                      fc: fc,
                      kind: CategoryKind.expense,
                      value: categoryId,
                      onChanged: (v) => setState(() => categoryId = v),
                    ),
                  ],
                ],
              ),
            ),
            gap,
            TextFormField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('debt-save'),
              onPressed: _save,
              child: const Text('Salvar contrato'),
            ),
          ],
        ),
      ),
    );
  }
}
