import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/money.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';

/// Edição de uma compra parcelada inteira: valor total, número de parcelas,
/// data da compra, descrição, categoria e conta/cartão. As parcelas são
/// recalculadas (no cartão, cada uma cai na fatura correspondente); com 1
/// parcela a compra volta a ser à vista.
class InstallmentEditScreen extends StatefulWidget {
  final String groupId;
  const InstallmentEditScreen({super.key, required this.groupId});

  @override
  State<InstallmentEditScreen> createState() => _InstallmentEditScreenState();
}

class _InstallmentEditScreenState extends State<InstallmentEditScreen> {
  final _form = GlobalKey<FormState>();
  InstallmentGroup? g;
  late final TextEditingController total;
  late final TextEditingController description;
  late final TextEditingController notes;
  late final TextEditingController countCtrl;
  String? categoryId;
  String? projectId;
  late DateTime date;
  Funding? funding;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    g = context.read<FinanceController>().data.groupById[widget.groupId];
    total = TextEditingController(text: g?.totalAmount.formatPlain() ?? '');
    description = TextEditingController(text: g?.description ?? '');
    notes = TextEditingController(text: g?.notes ?? '');
    countCtrl = TextEditingController(text: '${g?.count ?? 2}');
    categoryId = g?.categoryId;
    projectId = g?.projectId;
    date = g?.purchaseDate ?? DateTime.now();
    if (g != null) {
      funding = Funding(accountId: g!.accountId, cardId: g!.cardId);
    }
  }

  @override
  void dispose() {
    total.dispose();
    description.dispose();
    notes.dispose();
    countCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(FinanceController fc) async {
    if (!_form.currentState!.validate()) return;
    final old = g!;
    final n = int.parse(countCtrl.text);
    setState(() => saving = true);
    final ok = await runAction(
      context,
      () => fc.updateInstallmentGroup(
        InstallmentGroup(
          id: old.id,
          description: description.text.trim(),
          totalAmount: Money.tryParse(total.text)!,
          count: n,
          purchaseDate: date,
          accountId: funding?.accountId,
          cardId: funding?.cardId,
          categoryId: categoryId,
          projectId: projectId,
          notes: notes.text.trim(),
          createdAt: old.createdAt,
        ),
      ),
      success: n == 1
          ? 'Compra passou a ser à vista'
          : 'Parcelamento atualizado',
    );
    if (!mounted) return;
    setState(() => saving = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    if (g == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.view_week_outlined,
          title: 'Parcelamento removido',
        ),
      );
    }
    final value = Money.tryParse(total.text);
    final n = int.tryParse(countCtrl.text) ?? 0;
    final paid = fc
        .installmentsOf(g!.id)
        .where((t) => t.status == TransactionStatus.completed)
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('Editar parcelamento')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            MoneyField(
              controller: total,
              label: 'Valor total da compra',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            IntField(
              controller: countCtrl,
              label: 'Número de parcelas',
              min: 1,
              max: 120,
              onChanged: (_) => setState(() {}),
            ),
            if (value != null && n >= 1)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  n == 1
                      ? 'À vista: ${value.format()} (deixa de ser parcelada)'
                      : '$n× de ${value.split(n).first.format()}'
                            '${value.split(n).toSet().length > 1 ? ' (ajuste de centavos na 1ª)' : ''}',
                  key: const ValueKey('installment-preview'),
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.primary,
                  ),
                ),
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
            CategoryDropdown(
              fc: fc,
              kind: CategoryKind.expense,
              value: categoryId,
              onChanged: (v) => setState(() => categoryId = v),
            ),
            const SizedBox(height: 12),
            DateField(
              value: date,
              label: 'Data da compra',
              onChanged: (d) => setState(() => date = d ?? date),
            ),
            const SizedBox(height: 12),
            FundingDropdown(
              fc: fc,
              value: funding,
              onChanged: (f) => setState(() => funding = f),
            ),
            if (funding?.cardId != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  '1ª parcela: ${fc.invoiceHint(funding!.cardId, date) ?? ''}',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.primary,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            ProjectDropdown(
              fc: fc,
              value: projectId,
              onChanged: (v) => setState(() => projectId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observações (opcional)',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'As parcelas são recalculadas com os novos dados'
              '${paid > 0 ? ' ($paid já pagas continuam pagas)' : ''}. '
              'No cartão, as faturas afetadas são atualizadas.',
              style: context.text.bodySmall?.copyWith(
                color: context.fin.subtle,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const ValueKey('save-installment-group'),
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
                : const Text('Salvar parcelamento'),
          ),
        ),
      ),
    );
  }
}
