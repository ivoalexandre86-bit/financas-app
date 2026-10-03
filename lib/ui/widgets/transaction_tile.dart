import 'package:flutter/material.dart';

import '../../core/dates.dart';
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
  const TransactionTile({
    super.key,
    required this.tx,
    required this.engine,
    this.onTap,
    this.showDate = true,
  });

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
    final subtitle = [
      if (showDate) Dates.format(tx.date),
      engine.locationLabel(tx),
      if (tx.isInstallment) 'Parcela ${tx.installmentLabel}',
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color, size: 20),
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
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MoneyText(
            isIncome || isTransfer ? tx.amount : -tx.amount,
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
          const SizedBox(height: 2),
          Text(
            tx.status.label,
            style: context.text.labelSmall?.copyWith(
              color: statusColor(context, tx.status),
            ),
          ),
        ],
      ),
    );
  }
}
