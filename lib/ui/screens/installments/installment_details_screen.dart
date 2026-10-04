import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/billing_cycle.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/transaction_tile.dart';
import '../transactions/transaction_details_screen.dart';
import 'installment_edit_screen.dart';
import 'installments_screen.dart';

class InstallmentDetailsScreen extends StatelessWidget {
  final String groupId;
  const InstallmentDetailsScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final g = fc.data.groupById[groupId];
    if (g == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.view_week_outlined,
          title: 'Parcelamento removido',
        ),
      );
    }
    final parts = fc.installmentsOf(g.id);
    final card = fc.data.cardById[g.cardId];
    final elapsed = installmentsElapsed(fc, parts);
    final future = parts.where(fc.isFutureInstallment).toList();
    final futureTotal = future.map((t) => t.amount).sum();
    final cancelled = parts
        .where((t) => t.status == TransactionStatus.cancelled)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(g.description),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') {
                push(context, InstallmentEditScreen(groupId: g.id));
              } else if (v == 'cancel') {
                final ok = await confirmDialog(
                  context,
                  title: 'Cancelar parcelas futuras?',
                  message:
                      '${future.length} parcelas (${futureTotal.format()}) serão canceladas. Parcelas já faturadas/pagas não são alteradas.',
                  confirm: 'Cancelar parcelas',
                  destructive: true,
                );
                if (ok && context.mounted) {
                  await runAction(
                    context,
                    () => fc.cancelFutureInstallments(g.id),
                    success: 'Parcelas futuras canceladas',
                  );
                }
              } else if (v == 'amount') {
                await _editAmount(context, fc, future);
              } else if (v == 'delete') {
                final ok = await confirmDialog(
                  context,
                  title: 'Excluir compra parcelada?',
                  message:
                      'Todas as ${parts.length} parcelas serão excluídas, inclusive as passadas. Prefira “Cancelar parcelas futuras” para preservar o histórico.',
                  confirm: 'Excluir tudo',
                  destructive: true,
                );
                if (ok && context.mounted) {
                  final done = await runAction(
                    context,
                    () => fc.deleteInstallmentGroup(g.id),
                    success: 'Compra excluída',
                  );
                  if (done && context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Editar parcelamento (valor, nº de parcelas…)'),
              ),
              PopupMenuItem(
                value: 'amount',
                enabled: future.isNotEmpty,
                child: const Text('Alterar valor das parcelas futuras'),
              ),
              PopupMenuItem(
                value: 'cancel',
                enabled: future.isNotEmpty,
                child: const Text('Cancelar parcelas futuras'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Excluir compra'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SectionCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MoneyText(
                          g.totalAmount,
                          style: context.text.headlineMedium,
                        ),
                      ),
                      Text(
                        '${elapsed.clamp(0, g.count)}/${g.count}',
                        style: context.text.titleLarge?.copyWith(
                          color: context.colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: elapsed / g.count,
                      minHeight: 8,
                      backgroundColor: context.fin.gridLine,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InfoRow.text('Data da compra', Dates.format(g.purchaseDate)),
                  InfoRow.text(
                    card != null ? 'Cartão' : 'Conta',
                    card?.name ?? fc.data.accountById[g.accountId]?.name ?? '—',
                  ),
                  InfoRow.text(
                    'Categoria',
                    fc.engine.categoryLabel(g.categoryId),
                  ),
                  if (g.projectId != null)
                    InfoRow.text(
                      'Projeto',
                      fc.data.projectById[g.projectId]?.name ?? '—',
                    ),
                  InfoRow(
                    'A vencer (${future.length})',
                    MoneyText(futureTotal),
                  ),
                  if (cancelled > 0) InfoRow.text('Canceladas', '$cancelled'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Parcelas', style: context.text.titleMedium),
          ),
          for (final t in parts)
            card == null
                ? TransactionTile(
                    tx: t,
                    engine: fc.engine,
                    onTap: () => push(context, TransactionDetailsScreen(tx: t)),
                  )
                : ListTile(
                    onTap: () => push(context, TransactionDetailsScreen(tx: t)),
                    leading: CircleAvatar(
                      child: Text(
                        '${t.installmentNumber}',
                        style: context.text.labelLarge,
                      ),
                    ),
                    title: Text(
                      'Fatura ${BillingCycle.invoiceForTransaction(card, t).shortLabel}',
                    ),
                    subtitle: Text(
                      'Vence ${Dates.format(BillingCycle.dueDate(card, BillingCycle.invoiceForTransaction(card, t)))} · ${t.status.label}',
                    ),
                    trailing: MoneyText(
                      t.amount,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: t.status == TransactionStatus.cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
        ],
      ),
    );
  }

  Future<void> _editAmount(
    BuildContext context,
    FinanceController fc,
    List<FinTransaction> future,
  ) async {
    final ctrl = TextEditingController(text: future.first.amount.formatPlain());
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo valor das parcelas futuras'),
        content: Form(
          key: key,
          child: MoneyField(controller: ctrl, label: 'Valor por parcela'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await runAction(
        context,
        () => fc.updateFutureInstallmentAmount(
          future.first.installmentGroupId!,
          Money.tryEval(ctrl.text)!,
        ),
        success: 'Parcelas futuras atualizadas',
      );
    }
  }
}
