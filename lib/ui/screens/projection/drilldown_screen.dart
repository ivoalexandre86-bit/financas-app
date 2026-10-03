import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../transactions/transaction_details_screen.dart';

enum DrillRow {
  income('Receitas'),
  expenses('Despesas'),
  net('Resultado');

  final String label;
  const DrillRow(this.label);
}

/// Detalhamento de um valor da matriz.
///
/// Navegação: total do mês → categoria → conta/cartão → transação.
/// Usa exatamente os mesmos filtros e regras de reconhecimento da matriz
/// ([FinancialEngine.monthEvents]).
class DrilldownScreen extends StatefulWidget {
  final YearMonth month;
  final DrillRow row;
  final ProjectionFilter filter;
  final String? rootCategoryId; // nível 2
  final String? locationKey; // nível 3 ('a:id' | 'c:id')
  const DrilldownScreen({
    super.key,
    required this.month,
    required this.row,
    this.filter = ProjectionFilter.none,
    this.rootCategoryId,
    this.locationKey,
  });

  @override
  State<DrilldownScreen> createState() => _DrilldownScreenState();
}

class _DrilldownScreenState extends State<DrilldownScreen> {
  EventSource? source;

  bool _rowMatch(RecognizedEvent e) => switch (widget.row) {
    DrillRow.income => e.isIncome,
    DrillRow.expenses => e.isExpense,
    DrillRow.net => true,
  };

  Money _value(RecognizedEvent e) =>
      widget.row == DrillRow.expenses ? -e.signed : e.signed;

  String _locKey(FinTransaction t) =>
      t.cardId != null ? 'c:${t.cardId}' : 'a:${t.accountId}';

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final all = e
        .monthEvents(widget.filter, widget.month)
        .where(_rowMatch)
        .where(
          (x) =>
              widget.rootCategoryId == null ||
              e.rootCategoryId(x.tx.categoryId) == widget.rootCategoryId,
        )
        .where(
          (x) =>
              widget.locationKey == null || _locKey(x.tx) == widget.locationKey,
        )
        .toList();
    final events = source == null
        ? all
        : all.where((x) => x.source == source).toList();
    final total = events.map(_value).sum();

    final level = widget.locationKey != null
        ? 3
        : widget.rootCategoryId != null
        ? 2
        : 1;
    final title = switch (level) {
      1 => '${widget.row.label} · ${widget.month.shortLabel}',
      2 => e.data.categoryById[widget.rootCategoryId]?.name ?? 'Sem categoria',
      _ => _locationName(e, widget.locationKey!),
    };

    // Resumo por origem (sempre sobre o conjunto do nível).
    final bySource = <EventSource, Money>{};
    for (final x in all) {
      bySource[x.source] = (bySource[x.source] ?? Money.zero) + _value(x);
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.month.longLabel} — ${widget.row.label}',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
                const SizedBox(height: 4),
                MoneyText(
                  total,
                  colorize: widget.row == DrillRow.net,
                  style: context.text.headlineMedium,
                ),
                if (level > 1)
                  Text(
                    [
                      if (level >= 2 && widget.rootCategoryId != null)
                        e.data.categoryById[widget.rootCategoryId]?.name ??
                            'Sem categoria',
                      if (level == 3) _locationName(e, widget.locationKey!),
                    ].join(' › '),
                    style: context.text.labelMedium?.copyWith(
                      color: context.fin.subtle,
                    ),
                  ),
              ],
            ),
          ),
          if (bySource.length > 1 || source != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in EventSource.values)
                    if (bySource.containsKey(s))
                      FilterChip(
                        label: Text('${s.label}: ${bySource[s]!.format()}'),
                        selected: source == s,
                        onSelected: (v) =>
                            setState(() => source = v ? s : null),
                      ),
                ],
              ),
            ),
          if (events.isEmpty)
            const EmptyState(
              icon: Icons.insights_outlined,
              title: 'Nenhum lançamento',
              message: 'Não há valores para este recorte.',
            )
          else if (level == 1)
            ..._groupList(
              context,
              events,
              keyOf: (x) => e.rootCategoryId(x.tx.categoryId),
              labelOf: (k) => e.data.categoryById[k]?.name ?? 'Sem categoria',
              iconOf: (k) {
                final c = e.data.categoryById[k];
                return (categoryIcon(c?.icon), Color(c?.color ?? 0xFF6B7280));
              },
              onTap: (k) => push(
                context,
                DrilldownScreen(
                  month: widget.month,
                  row: widget.row,
                  filter: widget.filter,
                  rootCategoryId: k,
                ),
              ),
              total: total,
            )
          else if (level == 2)
            ..._groupList(
              context,
              events,
              keyOf: (x) => _locKey(x.tx),
              labelOf: (k) => _locationName(e, k),
              iconOf: (k) => k.startsWith('c:')
                  ? (
                      Icons.credit_card,
                      Color(
                        e.data.cardById[k.substring(2)]?.color ?? 0xFF1B2A4A,
                      ),
                    )
                  : (
                      Icons.account_balance_outlined,
                      Color(
                        e.data.accountById[k.substring(2)]?.color ?? 0xFF2457D6,
                      ),
                    ),
              onTap: (k) => push(
                context,
                DrilldownScreen(
                  month: widget.month,
                  row: widget.row,
                  filter: widget.filter,
                  rootCategoryId: widget.rootCategoryId,
                  locationKey: k,
                ),
              ),
              total: total,
            )
          else
            for (final x in events)
              TransactionTile(
                tx: x.tx,
                engine: e,
                onStatusToggle: (done) => context
                    .read<FinanceController>()
                    .toggleCompleted(x.tx, done),
                onTap: () => push(context, TransactionDetailsScreen(tx: x.tx)),
              ),
        ],
      ),
    );
  }

  String _locationName(FinancialEngine e, String key) {
    final id = key.substring(2);
    return key.startsWith('c:')
        ? (e.data.cardById[id]?.name ?? 'Cartão')
        : (e.data.accountById[id]?.name ?? 'Sem conta');
  }

  List<Widget> _groupList(
    BuildContext context,
    List<RecognizedEvent> events, {
    required String Function(RecognizedEvent) keyOf,
    required String Function(String) labelOf,
    required (IconData, Color) Function(String) iconOf,
    required void Function(String) onTap,
    required Money total,
  }) {
    final sums = <String, Money>{};
    final counts = <String, int>{};
    for (final x in events) {
      final k = keyOf(x);
      sums[k] = (sums[k] ?? Money.zero) + _value(x);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final keys = sums.keys.toList()
      ..sort((a, b) => sums[b]!.cents.abs().compareTo(sums[a]!.cents.abs()));
    final denom = total.cents.abs() == 0 ? 1 : total.cents.abs();
    return [
      for (final k in keys)
        () {
          final (icon, color) = iconOf(k);
          final share = (sums[k]!.cents.abs() / denom).clamp(0.0, 1.0);
          return ListTile(
            onTap: () => onTap(k),
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color, size: 20),
            ),
            title: Text(labelOf(k)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 6,
                        color: color,
                        backgroundColor: context.fin.gridLine,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(share * 100).toStringAsFixed(0)}% · ${counts[k]} itens',
                    style: context.text.labelSmall,
                  ),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoneyText(
                  sums[k]!,
                  colorize: widget.row == DrillRow.net,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          );
        }(),
    ];
  }
}
