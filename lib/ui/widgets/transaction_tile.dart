import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../domain/engine/financial_engine.dart';
import '../../domain/models/entities.dart';
import '../theme.dart';
import 'category_icons.dart';
import 'common.dart';

Color statusColor(BuildContext context, TransactionStatus s) => switch (s) {
  TransactionStatus.completed => context.fin.positive,
  TransactionStatus.pending => context.fin.warning,
  TransactionStatus.planned => context.colors.primary,
  TransactionStatus.cancelled => context.fin.subtle,
};

class TransactionTile extends StatelessWidget {
  final FinTransaction tx;
  final FinancialEngine engine;
  final VoidCallback? onTap;
  final bool showDate;

  /// Quando informado, exibe uma caixa de seleção para alternar o status
  /// entre Concluída e Pendente sem abrir os detalhes (`true` = concluída).
  final ValueChanged<bool>? onStatusToggle;

  /// Valor exibido no lugar do valor da compra (parte de uma compra quando a
  /// fatura foi paga em partes).
  final Money? shareAmount;

  /// Para compras no cartão na lista geral: mostra a data original da compra
  /// e um link para a fatura a que ela pertence.
  final VoidCallback? onInvoiceTap;
  const TransactionTile({
    super.key,
    required this.tx,
    required this.engine,
    this.onTap,
    this.showDate = true,
    this.onStatusToggle,
    this.shareAmount,
    this.onInvoiceTap,
  });

  /// Receitas e despesas não canceladas podem ter o status alternado.
  /// Compras no cartão não: elas são pagas junto com a fatura.
  static bool canToggle(FinTransaction t) =>
      !t.isTransfer &&
      t.cardId == null &&
      t.status != TransactionStatus.cancelled;

  @override
  Widget build(BuildContext context) {
    final cat = engine.data.categoryById[tx.categoryId];
    final isIncome = tx.type == TransactionType.income;
    final isTransfer = tx.isTransfer;
    final color = isTransfer
        ? context.fin.subtle
        : Color(cat?.color ?? context.fin.subtle.toARGB32());
    final icon = isTransfer ? Icons.swap_horiz : categoryIcon(cat?.icon);
    final cancelled = tx.status == TransactionStatus.cancelled;
    final completed = tx.status == TransactionStatus.completed;
    final showToggle = onStatusToggle != null && canToggle(tx);
    // Lançamentos ainda não concluídos ficam com valor esmaecido.
    final openOpacity = completed || cancelled || isTransfer ? 1.0 : 0.72;
    final overdue = !completed && !cancelled && tx.date.isBefore(engine.today);
    final invoice = onInvoiceTap != null ? engine.invoiceOf(tx) : null;
    final subtitle = [
      if (invoice != null)
        'Compra em ${Dates.format(tx.date)}'
      else if (showDate)
        Dates.format(tx.date),
      if (invoice != null)
        engine.categoryLabel(tx.categoryId)
      else
        engine.locationLabel(tx),
      if (tx.isInstallment) 'Parcela ${tx.installmentLabel}',
    ].join(' · ');
    final amount = shareAmount ?? tx.amount;

    return ListTile(
      onTap: onTap,
      contentPadding: showToggle
          ? const EdgeInsets.only(left: 4, right: 16, top: 2, bottom: 2)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showToggle)
            _StatusCheck(
              completed: completed,
              isIncome: isIncome,
              onChanged: onStatusToggle!,
            ),
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 20),
          ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              tx.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                decoration: cancelled ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (tx.isRecurring) ...[
            const SizedBox(width: 6),
            Icon(Icons.autorenew, size: 14, color: context.fin.subtle),
          ],
        ],
      ),
      subtitle: invoice == null
          ? Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.fin.subtle,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
                InkWell(
                  onTap: onInvoiceTap,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 14,
                          color: context.colors.primary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${invoice.title} ›',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(
                              color: context.colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Opacity(
            opacity: openOpacity,
            child: MoneyText(
              isIncome || isTransfer ? amount : -amount,
              showPlus: isIncome,
              style: context.text.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                decoration: cancelled ? TextDecoration.lineThrough : null,
              ),
              color: isTransfer
                  ? null
                  : isIncome
                  ? context.fin.positive
                  : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            overdue ? '${tx.status.label} · atrasada' : tx.status.label,
            style: context.text.labelSmall?.copyWith(
              color: overdue
                  ? context.fin.negative
                  : statusColor(context, tx.status),
              fontWeight: completed ? null : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Caixa de seleção redonda para concluir/reabrir um lançamento com um toque.
class _StatusCheck extends StatelessWidget {
  final bool completed;
  final bool isIncome;
  final ValueChanged<bool> onChanged;
  const _StatusCheck({
    required this.completed,
    required this.isIncome,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final done = isIncome ? 'recebida' : 'paga';
    return Tooltip(
      message: completed ? 'Voltar para pendente' : 'Marcar como $done',
      child: Checkbox(
        value: completed,
        shape: const CircleBorder(),
        activeColor: context.fin.positive,
        side: BorderSide(color: context.fin.warning, width: 2),
        semanticLabel: completed ? 'Concluída' : 'Pendente',
        onChanged: (v) => onChanged(v ?? false),
      ),
    );
  }
}
