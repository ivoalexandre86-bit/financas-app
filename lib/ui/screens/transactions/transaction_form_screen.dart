import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';

/// Formulário de nova transação / edição. Otimizado para lançamento rápido:
/// tipo, valor e descrição primeiro; opções avançadas (recorrência,
/// parcelamento) via chaves.
class TransactionFormScreen extends StatefulWidget {
  final FinTransaction? tx;
  final TransactionType? initialType;
  final String? initialProjectId;

  /// Pré-seleciona um cartão (ex.: "Adicionar compra" na fatura).
  final String? initialCardId;
  final DateTime? initialDate;
  const TransactionFormScreen({
    super.key,
    this.tx,
    this.initialType,
    this.initialProjectId,
    this.initialCardId,
    this.initialDate,
  });

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _form = GlobalKey<FormState>();
  late TransactionType type;
  late final TextEditingController amount;
  late final TextEditingController description;
  late final TextEditingController notes;
  final installmentsCtrl = TextEditingController(text: '2');
  final intervalCtrl = TextEditingController(text: '1');
  String? categoryId;
  late DateTime date;
  Funding? funding;
  String? fromAccount;
  String? toAccount;
  String? projectId;
  late TransactionStatus status;

  bool recurring = false;
  RecurrenceFrequency frequency = RecurrenceFrequency.monthly;
  RecurrenceUnit unit = RecurrenceUnit.months;
  DateTime? endDate;

  bool installment = false;
  bool saving = false;

  bool get isEdit => widget.tx != null && !widget.tx!.isVirtual;

  @override
  void initState() {
    super.initState();
    final t = widget.tx;
    final fc = context.read<FinanceController>();
    type = t?.type ?? widget.initialType ?? TransactionType.expense;
    amount = TextEditingController(
      text: t == null ? '' : t.amount.formatPlain(),
    );
    description = TextEditingController(text: t?.description ?? '');
    notes = TextEditingController(text: t?.notes ?? '');
    categoryId = t?.categoryId;
    date = t?.date ?? widget.initialDate ?? fc.today;
    projectId = t?.projectId ?? widget.initialProjectId;
    status = t?.status ?? TransactionStatus.completed;
    if (t != null) {
      if (t.isTransfer) {
        fromAccount = t.accountId;
        toAccount = t.destinationAccountId;
      } else {
        funding = Funding(accountId: t.accountId, cardId: t.cardId);
      }
    } else {
      final accs = fc.activeAccounts;
      if (widget.initialCardId != null) {
        funding = Funding(cardId: widget.initialCardId);
      } else if (accs.isNotEmpty) {
        funding = Funding(accountId: accs.first.id);
      }
    }
  }

  @override
  void dispose() {
    amount.dispose();
    description.dispose();
    notes.dispose();
    installmentsCtrl.dispose();
    intervalCtrl.dispose();
    super.dispose();
  }

  /// Status sugerido conforme a data (futuro = planejada).
  void _onDate(DateTime d, DateTime today) {
    setState(() {
      date = d;
      if (!isEdit) {
        status = d.isAfter(today)
            ? TransactionStatus.planned
            : TransactionStatus.completed;
      }
    });
  }

  Future<void> _save(FinanceController fc) async {
    if (!_form.currentState!.validate()) return;
    final value = Money.tryParse(amount.text)!;
    // No cartão, o status acompanha a fatura: a compra é paga junto com ela.
    if (funding?.cardId != null &&
        type != TransactionType.transfer &&
        status != TransactionStatus.cancelled) {
      status = isEdit && widget.tx!.cardId == funding!.cardId
          ? widget.tx!.status
          : TransactionStatus.pending;
    }
    setState(() => saving = true);
    final isTransfer = type == TransactionType.transfer;
    final ok = await runAction(
      context,
      () async {
        if (installment && !isEdit && type == TransactionType.expense) {
          final n = int.parse(installmentsCtrl.text);
          await fc.createInstallmentPurchase(
            InstallmentGroup(
              id: newId('ig_'),
              description: description.text.trim(),
              totalAmount: value,
              count: n,
              purchaseDate: date,
              accountId: funding?.accountId,
              cardId: funding?.cardId,
              categoryId: categoryId,
              projectId: projectId,
              notes: notes.text.trim(),
            ),
            firstStatus: status,
          );
          return;
        }
        if (recurring && !isEdit && !isTransfer) {
          final rule = RecurringRule(
            id: newId('rec_'),
            type: type,
            amount: value,
            description: description.text.trim(),
            categoryId: categoryId,
            accountId: funding?.accountId,
            cardId: funding?.cardId,
            projectId: projectId,
            frequency: frequency,
            interval: int.tryParse(intervalCtrl.text) ?? 1,
            unit: unit,
            startDate: date,
            endDate: endDate,
            notes: notes.text.trim(),
          );
          await fc.createRule(rule);
          // A primeira ocorrência já realizada é registrada como concluída.
          if (status == TransactionStatus.completed &&
              !date.isAfter(fc.today)) {
            await fc.saveTransaction(
              FinTransaction(
                id: newId('tx_'),
                type: type,
                amount: value,
                description: rule.description,
                categoryId: categoryId,
                date: date,
                accountId: rule.accountId,
                cardId: rule.cardId,
                projectId: projectId,
                notes: rule.notes,
                status: status,
                recurringId: rule.id,
                occurrenceDate: date,
              ),
            );
          }
          return;
        }
        final base =
            widget.tx ??
            FinTransaction(
              id: newId('tx_'),
              type: type,
              amount: value,
              description: '',
              date: date,
            );
        await fc.saveTransaction(
          base.copyWith(
            type: type,
            amount: value,
            description: description.text.trim(),
            categoryId: isTransfer ? null : categoryId,
            date: date,
            accountId: isTransfer ? fromAccount : funding?.accountId,
            cardId: isTransfer ? null : funding?.cardId,
            destinationAccountId: isTransfer ? toAccount : null,
            projectId: projectId,
            notes: notes.text.trim(),
            status: status,
          ),
        );
      },
      success: isEdit
          ? 'Transação atualizada'
          : installment
          ? 'Compra parcelada registrada'
          : recurring
          ? 'Recorrência criada'
          : 'Transação registrada',
    );
    if (!mounted) return;
    setState(() => saving = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final isTransfer = type == TransactionType.transfer;
    final t = widget.tx;
    final value = Money.tryParse(amount.text);
    final n = int.tryParse(installmentsCtrl.text) ?? 0;
    final canAdvanced = t == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Editar transação' : 'Nova transação'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            if (t?.isInstallment == true)
              _Notice(
                'Você está editando apenas a parcela ${t!.installmentLabel}. '
                'Para alterar ou cancelar parcelas futuras, use os detalhes do parcelamento.',
              ),
            if (t?.isRecurring == true)
              const _Notice(
                'Alterações aqui valem somente para esta ocorrência. '
                'Para alterar a regra, edite a recorrência.',
              ),
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Despesa'),
                  icon: Icon(Icons.north_east, size: 16),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Receita'),
                  icon: Icon(Icons.south_west, size: 16),
                ),
                ButtonSegment(
                  value: TransactionType.transfer,
                  label: Text('Transf.'),
                  icon: Icon(Icons.swap_horiz, size: 16),
                ),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() {
                type = s.first;
                categoryId = null;
                if (type != TransactionType.expense) installment = false;
                if (type == TransactionType.transfer) recurring = false;
              }),
            ),
            const SizedBox(height: 16),
            MoneyField(
              controller: amount,
              label: installment ? 'Valor total da compra' : 'Valor',
              autofocus: t == null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Descrição'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Informe uma descrição'
                  : (v.length > 120 ? 'Máximo de 120 caracteres' : null),
            ),
            const SizedBox(height: 12),
            if (!isTransfer) ...[
              CategoryDropdown(
                fc: fc,
                kind: type == TransactionType.income
                    ? CategoryKind.income
                    : CategoryKind.expense,
                value: categoryId,
                onChanged: (v) => setState(() => categoryId = v),
              ),
              const SizedBox(height: 12),
            ],
            DateField(
              value: date,
              label: installment ? 'Data da compra' : 'Data',
              onChanged: (d) => d == null ? null : _onDate(d, fc.today),
            ),
            const SizedBox(height: 12),
            if (isTransfer) ...[
              AccountDropdown(
                fc: fc,
                value: fromAccount,
                label: 'Conta de origem',
                onChanged: (v) => setState(() => fromAccount = v),
              ),
              const SizedBox(height: 12),
              AccountDropdown(
                fc: fc,
                value: toAccount,
                label: 'Conta de destino',
                excludeId: fromAccount,
                onChanged: (v) => setState(() => toAccount = v),
              ),
            ] else ...[
              FundingDropdown(
                fc: fc,
                value: funding,
                onChanged: (f) => setState(() => funding = f),
              ),
              if (funding?.cardId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    fc.invoiceHint(funding!.cardId, date) ?? '',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.primary,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            ProjectDropdown(
              fc: fc,
              value: projectId,
              onChanged: (v) => setState(() => projectId = v),
            ),
            const SizedBox(height: 12),
            if (funding?.cardId != null && !isTransfer)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Status acompanha a fatura'),
                subtitle: const Text(
                  'Compras no cartão ficam pagas quando a fatura é paga.',
                ),
              )
            else
              DropdownButtonFormField<TransactionStatus>(
                initialValue: status,
                decoration: InputDecoration(
                  labelText: installment ? 'Status da 1ª parcela' : 'Status',
                ),
                items: [
                  for (final s in TransactionStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (s) => setState(() => status = s!),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observações (opcional)',
              ),
            ),
            if (canAdvanced && !isTransfer) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Transação recorrente'),
                subtitle: const Text(
                  'Gera ocorrências futuras automaticamente',
                ),
                value: recurring,
                onChanged: (v) => setState(() {
                  recurring = v;
                  if (v) installment = false;
                }),
              ),
              if (recurring) _recurrenceFields(),
              if (type == TransactionType.expense)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Compra parcelada'),
                  subtitle: const Text('Divide o valor total em parcelas'),
                  value: installment,
                  onChanged: (v) => setState(() {
                    installment = v;
                    if (v) recurring = false;
                  }),
                ),
              if (installment) ...[
                IntField(
                  controller: installmentsCtrl,
                  label: 'Número de parcelas',
                  min: 2,
                  max: 120,
                  onChanged: (_) => setState(() {}),
                ),
                if (value != null && n >= 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      '$n× de ${value.split(n).first.format()}'
                      '${value.split(n).toSet().length > 1 ? ' (ajuste de centavos na 1ª)' : ''}',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.colors.primary,
                      ),
                    ),
                  ),
              ],
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
            onPressed: saving ? null : () => _save(fc),
            child: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isEdit ? 'Salvar alterações' : 'Salvar'),
          ),
        ),
      ),
    );
  }

  Widget _recurrenceFields() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
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
                    controller: intervalCtrl,
                    label: 'A cada',
                    min: 1,
                    max: 365,
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
          const SizedBox(height: 12),
          DateField(
            value: endDate,
            label: 'Data final (opcional)',
            clearable: true,
            onChanged: (d) => setState(() => endDate = d),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Repete a partir de ${Dates.format(date)}, no mesmo dia.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice(this.text);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.colors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 18, color: context.colors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: context.text.bodySmall)),
      ],
    ),
  );
}
