import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../theme.dart';

/// Valor monetário com figuras tabulares e cor opcional por sinal.
class MoneyText extends StatelessWidget {
  final Money value;
  final TextStyle? style;
  final bool colorize;
  final bool showPlus;
  final Color? color;
  const MoneyText(
    this.value, {
    super.key,
    this.style,
    this.colorize = false,
    this.showPlus = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        (colorize
            ? (value.isNegative
                  ? context.fin.negative
                  : value.isPositive
                  ? context.fin.positive
                  : null)
            : null);
    final s = (style ?? DefaultTextStyle.of(context).style).copyWith(
      color: c,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final txt = (showPlus && value.isPositive ? '+' : '') + value.format();
    return Text(txt, style: s, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

/// Seletor de mês "‹ Outubro de 2026 ›".
class MonthSwitcher extends StatelessWidget {
  final YearMonth month;
  final ValueChanged<YearMonth> onChanged;
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = month == YearMonth.now();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Mês anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(month.previous),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isCurrent ? null : () => onChanged(YearMonth.now()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(month.longLabel, style: context.text.titleMedium),
          ),
        ),
        IconButton(
          tooltip: 'Próximo mês',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(month.next),
        ),
      ],
    );
  }
}

/// Cartão de seção com título.
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: EdgeInsets.only(
                  bottom: 12,
                  left: padding.horizontal == 0 ? 16 : 0,
                  right: padding.horizontal == 0 ? 8 : 0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title!, style: context.text.titleMedium),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.fin.subtle),
            const SizedBox(height: 12),
            Text(
              title,
              style: context.text.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: context.text.bodyMedium?.copyWith(
                  color: context.fin.subtle,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorState({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.error_outline,
    title: 'Algo deu errado',
    message: message,
    actionLabel: onRetry == null ? null : 'Tentar novamente',
    onAction: onRetry,
  );
}

/// Pequeno rótulo colorido (status, tipo…).
class Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const Pill(this.label, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha "rótulo …… valor" para telas de detalhe.
class InfoRow extends StatelessWidget {
  final String label;
  final Widget value;
  const InfoRow(this.label, this.value, {super.key});
  factory InfoRow.text(String label, String value) =>
      InfoRow(label, Text(value, textAlign: TextAlign.end));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: context.fin.subtle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: DefaultTextStyle.merge(
                style: context.text.bodyMedium,
                child: value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirmar',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
}

/// Executa uma ação assíncrona exibindo sucesso/erro em snackbar.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) showMessage(context, success);
    return true;
  } catch (e) {
    if (context.mounted) {
      final msg = e is ArgumentError
          ? '${e.message}'
          : e is StateError
          ? e.message
          : '$e';
      showMessage(context, msg, error: true);
    }
    return false;
  }
}

/// Faixa que identifica a conta de demonstração.
class SampleDataBanner extends StatelessWidget {
  const SampleDataBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: context.fin.warning.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 16, color: context.fin.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Dados de exemplo — conta de demonstração',
              style: context.text.labelMedium?.copyWith(
                color: context.fin.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
