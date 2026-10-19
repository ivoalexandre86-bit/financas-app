import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/subscription_detector.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/remembered_filters.dart';
import '../../widgets/sort_grid.dart';
import '../../widgets/tx_grid.dart';
import '../../widgets/view_mode.dart';
import '../recurring/recurring_form_screen.dart';

/// Assinaturas: recorrências de despesa e gastos que se repetem todo mês,
/// com o custo mensal/anual e os aumentos de preço.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});
  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen>
    with RememberedFilters {
  ViewMode view = ViewMode.cards;

  @override
  String get filterKey => 'subscriptions';

  @override
  Map<String, Object?> filtersToJson() => {'view': view.name};

  @override
  void restoreFilters(Map<String, Object?> saved, FinanceController fc) =>
      view = FilterJson.enumOrNull(ViewMode.values, saved['view']) ?? view;

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final subs = SubscriptionDetector.detect(fc.engine);
    final totals = SubscriptionDetector.totals(subs);
    final increases = subs.where((s) => s.priceIncreased).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assinaturas'),
        actions: [
          ViewModeToggle(
            keyPrefix: 'subscriptions',
            mode: view,
            onChanged: (v) => setFilters(() => view = v),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (subs.isEmpty)
            const SectionCard(
              child: EmptyState(
                icon: Icons.autorenew,
                title: 'Nenhuma assinatura encontrada',
                message:
                    'Cadastre recorrências de despesa ou continue lançando '
                    'seus gastos: cobranças que se repetem em pelo menos 3 '
                    'dos últimos 6 meses com valor parecido aparecem aqui.',
              ),
            )
          else ...[
            KpiWrap(
              children: (w) => [
                _Kpi(width: w, label: 'Custo mensal', value: totals.monthly),
                _Kpi(width: w, label: 'Custo anual', value: totals.annual),
              ],
            ),
            if (increases > 0) ...[
              const SizedBox(height: 8),
              Card(
                color: context.fin.warning.withValues(alpha: 0.12),
                child: ListTile(
                  leading: Icon(Icons.trending_up, color: context.fin.warning),
                  title: Text(
                    increases == 1
                        ? '1 assinatura ficou mais cara'
                        : '$increases assinaturas ficaram mais caras',
                  ),
                  subtitle: const Text(
                    'A última cobrança veio mais de 5% acima da anterior.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (view == ViewMode.grid)
              SubscriptionsGrid(
                subscriptions: subs,
                onOpen: (s) => openSubscription(context, s),
              )
            else
              for (final s in subs) ...[
                SubscriptionTile(subscription: s),
                const SizedBox(height: 8),
              ],
          ],
        ],
      ),
    );
  }
}

/// Recorrência: abre a regra; detectada: oferece criar a recorrência.
void openSubscription(BuildContext context, Subscription s) {
  if (s.rule != null) {
    push(context, RecurringFormScreen(rule: s.rule));
  } else {
    createRecurringFrom(context, s);
  }
}

/// Abre o cadastro de recorrência preenchido com a assinatura detectada.
Future<void> createRecurringFrom(BuildContext context, Subscription s) {
  final last = s.lastDate ?? Dates.today();
  return push(
    context,
    RecurringFormScreen(
      prefill: RecurringRule(
        id: newId('rec_'),
        type: TransactionType.expense,
        amount: s.lastAmount ?? s.monthly,
        description: s.name,
        categoryId: s.categoryId,
        accountId: s.accountId,
        cardId: s.cardId,
        dayOfMonth: last.day,
        startDate: Dates.addMonths(last, 1),
      ),
    ),
  );
}

class _Kpi extends StatelessWidget {
  final double width;
  final String label;
  final Money value;
  const _Kpi({required this.width, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.bodyMedium),
          const SizedBox(height: 4),
          MoneyText(
            value,
            style: context.text.titleLarge?.copyWith(
              color: context.fin.expense,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

String _subtitle(Subscription s) => [
  s.source.label,
  if (s.lastDate != null) 'última ${Dates.format(s.lastDate!)}',
  '${s.monthsSeen} ${s.monthsSeen == 1 ? 'mês' : 'meses'}',
].join(' · ');

/// Cartão de uma assinatura.
class SubscriptionTile extends StatelessWidget {
  final Subscription subscription;
  const SubscriptionTile({super.key, required this.subscription});

  @override
  Widget build(BuildContext context) {
    final s = subscription;
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: s.rule == null ? null : () => openSubscription(context, s),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    s.isDetected ? Icons.auto_awesome : Icons.autorenew,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall,
                        ),
                        Text(_subtitle(s), style: subtle),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MoneyText(
                        s.monthly,
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text('${s.annual.format()}/ano', style: subtle),
                    ],
                  ),
                ],
              ),
              if (s.priceIncreased || s.isDetected) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (s.priceIncreased) _IncreasePill(s),
                    if (s.isDetected)
                      TextButton.icon(
                        onPressed: () => createRecurringFrom(context, s),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Criar recorrência'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IncreasePill extends StatelessWidget {
  final Subscription s;
  const _IncreasePill(this.s);

  @override
  Widget build(BuildContext context) => Pill(
    'Aumento de ${s.increasePercent.toStringAsFixed(0)}% '
    '(${s.previousAmount!.format()} → ${s.lastAmount!.format()})',
    color: context.fin.warning,
    icon: Icons.trending_up,
  );
}

/// Assinaturas em grade ordenável.
class SubscriptionsGrid extends StatelessWidget {
  final List<Subscription> subscriptions;
  final ValueChanged<Subscription> onOpen;
  const SubscriptionsGrid({
    super.key,
    required this.subscriptions,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final strong = context.text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
    );
    int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    Widget money(Money v, {TextStyle? style}) => Text(v.format(), style: style);
    Money sum(List<Subscription> l, Money Function(Subscription) f) =>
        l.map(f).sum();
    final far = DateTime(1900);

    return SortGrid<Subscription>(
      keyPrefix: 'subs',
      rows: subscriptions,
      rowId: (s) => '${s.source.name}:${s.rule?.id ?? s.name}',
      accent: (context, s) => s.priceIncreased
          ? context.fin.warning
          : s.isDetected
          ? context.fin.subtle
          : context.colors.primary,
      onOpen: onOpen,
      initialSort: 'monthly',
      initialAscending: false,
      tieBreak: (a, b) => text(a.name, b.name),
      columns: [
        SortCol(
          id: 'name',
          label: 'Assinatura',
          width: 220,
          minWidth: 140,
          flexible: true,
          fill: true,
          compare: (a, b) => text(a.name, b.name),
          cell: (context, s) => GridCell(
            child: Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SortCol(
          id: 'source',
          label: 'Origem',
          width: 120,
          compare: (a, b) => a.source.index.compareTo(b.source.index),
          cell: (context, s) => GridCell(
            child: Text(s.source.label, style: context.text.bodySmall),
          ),
        ),
        SortCol(
          id: 'last',
          label: 'Última cobrança',
          width: 130,
          compare: (a, b) => (a.lastDate ?? far).compareTo(b.lastDate ?? far),
          cell: (context, s) => GridCell(
            child: Text(
              s.lastDate == null ? '—' : Dates.format(s.lastDate!),
              style: subtle,
            ),
          ),
        ),
        SortCol(
          id: 'months',
          label: 'Meses',
          width: 80,
          right: true,
          compare: (a, b) => a.monthsSeen.compareTo(b.monthsSeen),
          cell: (context, s) => GridCell(
            right: true,
            child: Text('${s.monthsSeen}', style: context.text.bodySmall),
          ),
        ),
        SortCol(
          id: 'increase',
          label: 'Aumento',
          width: 96,
          right: true,
          compare: (a, b) => a.increasePercent.compareTo(b.increasePercent),
          cell: (context, s) => GridCell(
            right: true,
            child: Text(
              s.priceIncreased
                  ? '+${s.increasePercent.toStringAsFixed(0)}%'
                  : '—',
              style: context.text.bodySmall?.copyWith(
                color: s.priceIncreased ? context.fin.warning : null,
                fontWeight: s.priceIncreased ? FontWeight.w700 : null,
              ),
            ),
          ),
        ),
        SortCol(
          id: 'monthly',
          label: 'Mensal',
          width: 124,
          right: true,
          highlight: true,
          compare: (a, b) => a.monthly.compareTo(b.monthly),
          cell: (context, s) =>
              GridCell(right: true, child: money(s.monthly, style: strong)),
          footer: (context, l) =>
              money(sum(l, (s) => s.monthly), style: strong),
        ),
        SortCol(
          id: 'annual',
          label: 'Anual',
          width: 132,
          right: true,
          compare: (a, b) => a.annual.compareTo(b.annual),
          cell: (context, s) => GridCell(
            right: true,
            child: money(s.annual, style: context.text.bodySmall),
          ),
          footer: (context, l) => money(sum(l, (s) => s.annual), style: strong),
        ),
      ],
      compactRow: (context, s) => Row(
        children: [
          Icon(
            s.isDetected ? Icons.auto_awesome : Icons.autorenew,
            size: 20,
            color: s.priceIncreased
                ? context.fin.warning
                : context.colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _subtitle(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          money(s.monthly, style: strong),
        ],
      ),
      footerLabel: (context, l) => Text(
        'Total · ${l.length} ${l.length == 1 ? 'assinatura' : 'assinaturas'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: gridFooterLabelStyle(context),
      ),
      compactFooter: (context, l) =>
          Text('${sum(l, (s) => s.monthly).format()}/mês', style: strong),
    );
  }
}
