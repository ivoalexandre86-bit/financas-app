import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/billing_cycle.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../cards/invoice_details_screen.dart';
import '../installments/installment_details_screen.dart';
import '../installments/installment_edit_screen.dart';
import '../recurring/recurring_form_screen.dart';
import 'transaction_form_screen.dart';

class TransactionDetailsScreen extends StatelessWidget {
  final FinTransaction tx;
  const TransactionDetailsScreen({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    // Recarrega a versão atual (pode ter sido editada).
    final t = tx.isVirtual
        ? (e
                  .transactionsUntil(tx.date)
                  .where((x) => x.id == tx.id)
                  .firstOrNull ??
              fc.data.transactions
                  .where(
                    (x) =>
                        x.recurringId == tx.recurringId &&
                        x.occurrenceDate == tx.occurrenceDate,
                  )
                  .firstOrNull)
        : fc.data.transactions.where((x) => x.id == tx.id).firstOrNull;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.delete_outline,
          title: 'Transação removida',
        ),
      );
    }
    final isIncome = t.type == TransactionType.income;
    final card = fc.data.cardById[t.cardId];
    final invoice = card == null
        ? null
        : BillingCycle.invoiceForTransaction(card, t);
    final rule = fc.data.ruleById[t.recurringId];
    final project = fc.data.projectById[t.projectId];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes'),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => push(context, TransactionFormScreen(tx: t)),
          ),
          IconButton(
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: t.isVirtual ? 'Pular ocorrência?' : 'Excluir transação?',
                message: t.isVirtual
                    ? 'Esta ocorrência prevista será removida da projeção. A regra recorrente continua ativa.'
                    : t.isInstallment
                    ? 'Somente esta parcela será excluída. Para cancelar as parcelas futuras use os detalhes do parcelamento.'
                    : 'Esta ação não pode ser desfeita.',
                confirm: t.isVirtual ? 'Pular' : 'Excluir',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              final done = await runAction(
                context,
                () => fc.deleteTransaction(t),
                success: 'Transação removida',
              );
              if (done && context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  t.description,
                  style: context.text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                MoneyText(
                  isIncome || t.isTransfer ? t.amount : -t.amount,
                  showPlus: isIncome,
                  color: isIncome ? context.fin.positive : null,
                  style: context.text.headlineMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    Pill(t.type.label, color: context.colors.primary),
                    Pill(t.status.label, color: statusColor(context, t.status)),
                    if (t.isVirtual)
                      Pill(
                        'Prevista',
                        color: context.fin.subtle,
                        icon: Icons.autorenew,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionCard(
            child: Column(
              children: [
                InfoRow.text(
                  card != null ? 'Data da compra' : 'Data',
                  Dates.format(t.date),
                ),
                if (!t.isTransfer)
                  InfoRow.text('Categoria', e.categoryLabel(t.categoryId)),
                InfoRow.text(
                  t.isTransfer ? 'Contas' : 'Conta / cartão',
                  e.locationLabel(t),
                ),
                if (invoice != null) ...[
                  InfoRow.text('Fatura', invoice.shortLabel),
                  InfoRow.text(
                    'Fechamento',
                    Dates.format(BillingCycle.closingDate(card!, invoice)),
                  ),
                  InfoRow.text(
                    'Vencimento',
                    Dates.format(BillingCycle.dueDate(card, invoice)),
                  ),
                ],
                if (!t.isTransfer)
                  InfoRow.text(
                    'Reconhecido em',
                    card == null
                        ? e.recognitionMonth(t)?.longLabel ?? '—'
                        : e
                              .sharesOf(t)
                              .map(
                                (s) =>
                                    '${s.month.longLabel}${s.slice.settled ? '' : ' (previsto)'}',
                              )
                              .join(' + '),
                  ),
                if (project != null) InfoRow.text('Projeto', project.name),
                if (t.isInstallment)
                  InfoRow.text('Parcela', t.installmentLabel),
                if (t.recurringId != null)
                  InfoRow.text(
                    'Recorrência',
                    rule?.description ?? 'Regra removida',
                  ),
                if (t.externalId != null)
                  InfoRow.text('Origem', 'Open Finance'),
                if (t.notes.isNotEmpty) InfoRow.text('Observações', t.notes),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (card != null && !t.isTransfer)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Compras no cartão são pagas pela fatura: ao pagar a fatura, todas as compras dela ficam pagas.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
            ),
          if (card == null &&
              t.status != TransactionStatus.completed &&
              t.status != TransactionStatus.cancelled)
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(
                isIncome ? 'Marcar como recebida' : 'Marcar como paga',
              ),
              onPressed: () => runAction(
                context,
                () => fc.setStatus(t, TransactionStatus.completed),
                success: 'Status atualizado',
              ),
            ),
          if (card == null && t.status == TransactionStatus.completed)
            OutlinedButton.icon(
              icon: const Icon(Icons.undo),
              label: const Text('Voltar para pendente'),
              onPressed: () => runAction(
                context,
                () => fc.setStatus(t, TransactionStatus.pending),
                success: 'Status atualizado',
              ),
            ),
          if (!t.isTransfer)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('details-edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(card != null ? 'Ajustar compra' : 'Editar'),
                    onPressed: () =>
                        push(context, TransactionFormScreen(tx: t)),
                  ),
                  if (TransactionFormScreen.canConvert(t) &&
                      t.type == TransactionType.expense)
                    FilledButton.tonalIcon(
                      key: const ValueKey('details-split'),
                      icon: const Icon(Icons.view_week_outlined),
                      label: const Text('Parcelar'),
                      onPressed: () => push(
                        context,
                        TransactionFormScreen(tx: t, initialInstallment: true),
                      ),
                    ),
                  if (t.isInstallment &&
                      fc.data.groupById[t.installmentGroupId] != null)
                    FilledButton.tonalIcon(
                      key: const ValueKey('details-edit-group'),
                      icon: const Icon(Icons.view_week_outlined),
                      label: const Text('Editar parcelamento'),
                      onPressed: () => push(
                        context,
                        InstallmentEditScreen(groupId: t.installmentGroupId!),
                      ),
                    ),
                  if (TransactionFormScreen.canConvert(t))
                    FilledButton.tonalIcon(
                      key: const ValueKey('details-recurring'),
                      icon: const Icon(Icons.autorenew),
                      label: const Text('Tornar recorrente'),
                      onPressed: () => push(
                        context,
                        TransactionFormScreen(tx: t, initialRecurring: true),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (t.isInstallment)
            OutlinedButton.icon(
              icon: const Icon(Icons.view_week_outlined),
              label: const Text('Ver parcelamento'),
              onPressed: () => push(
                context,
                InstallmentDetailsScreen(groupId: t.installmentGroupId!),
              ),
            ),
          if (rule != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.autorenew),
              label: const Text('Ver regra recorrente'),
              onPressed: () => push(context, RecurringFormScreen(rule: rule)),
            ),
          if (invoice != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.receipt_outlined),
              label: Text('Ver fatura ${invoice.shortLabel}'),
              onPressed: () => push(
                context,
                InvoiceDetailsScreen(cardId: card!.id, month: invoice),
              ),
            ),
        ],
      ),
    );
  }
}
