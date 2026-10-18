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
import '../../widgets/filters_panel.dart';
import '../../widgets/sort_grid.dart';
import '../../widgets/tx_grid.dart';
import '../simulations/sim_common.dart' show SimKpi;
import '../transactions/transaction_form_screen.dart';
import 'installment_details_screen.dart';

/// Quantas parcelas já foram faturadas/vencidas (para "3/12").
int installmentsElapsed(FinanceController fc, List<FinTransaction> parts) {
  final today = fc.today;
  var n = 0;
  for (final t in parts) {
    if (t.status == TransactionStatus.cancelled) continue;
    final card = fc.data.cardById[t.cardId];
    final due = card == null
        ? t.date
        : BillingCycle.closingDate(
            card,
            BillingCycle.invoiceForTransaction(card, t),
          );
    if (!due.isAfter(today)) n++;
  }
  return n;
}

/// Números de uma compra parcelada usados na grade e nos indicadores.
class InstallmentSummary {
  final InstallmentGroup group;
  final String where;
  final String category;

  /// Parcelas não canceladas.
  final int count;
  final int elapsed;
  final int total;
  final int paid;
  final int parcel;
  final DateTime? next;

  InstallmentSummary._(
    this.group,
    this.where,
    this.category,
    this.count,
    this.elapsed,
    this.total,
    this.paid,
    this.parcel,
    this.next,
  );

  factory InstallmentSummary.of(FinanceController fc, InstallmentGroup g) {
    final parts = fc
        .installmentsOf(g.id)
        .where((t) => t.status != TransactionStatus.cancelled)
        .toList();
    final today = fc.today;
    var elapsed = 0, total = 0, paid = 0;
    DateTime? next;
    for (final t in parts) {
      total += t.amount.cents;
      final card = fc.data.cardById[t.cardId];
      final billed = card == null
          ? t.date
          : BillingCycle.closingDate(
              card,
              BillingCycle.invoiceForTransaction(card, t),
            );
      if (!billed.isAfter(today)) {
        elapsed++;
        paid += t.amount.cents;
      } else {
        final due = fc.engine.dueDateOf(t);
        if (next == null || due.isBefore(next)) next = due;
      }
    }
    final where = g.cardId != null
        ? fc.data.cardById[g.cardId]?.name
        : fc.data.accountById[g.accountId]?.name;
    final upcoming = parts.where((t) => !t.date.isBefore(today));
    return InstallmentSummary._(
      g,
      where ?? '—',
      fc.engine.categoryLabel(g.categoryId),
      parts.length,
      elapsed,
      total,
      paid,
      (upcoming.isNotEmpty ? upcoming.first : parts.lastOrNull)?.amount.cents ??
          0,
      next,
    );
  }

  int get remaining => total - paid;
  bool get finished => elapsed >= count;

  /// `c:<cartão>` ou `a:<conta>`, para o filtro.
  String get whereKey =>
      group.cardId != null ? 'c:${group.cardId}' : 'a:${group.accountId ?? ''}';
}

enum _Situation {
  open('Em andamento'),
  done('Quitados');

  final String label;
  const _Situation(this.label);
}

class InstallmentsScreen extends StatefulWidget {
  const InstallmentsScreen({super.key});

  @override
  State<InstallmentsScreen> createState() => _InstallmentsScreenState();
}

class _InstallmentsScreenState extends State<InstallmentsScreen> {
  String query = '';
  String? where;
  String? categoryId;
  _Situation? situation;

  /// null = aberto no desktop e recolhido no celular.
  bool? filtersOpen;
  final searchCtrl = TextEditingController();

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  int get _activeFilters => [
    query.trim().isNotEmpty,
    where != null,
    categoryId != null,
    situation != null,
  ].where((b) => b).length;

  void _clearFilters() => setState(() {
    searchCtrl.clear();
    query = '';
    where = null;
    categoryId = null;
    situation = null;
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final all = [
      for (final g in fc.data.installmentGroups) InstallmentSummary.of(fc, g),
    ];
    final q = query.trim().toLowerCase();
    final list = all.where((s) {
      if (where != null && s.whereKey != where) return false;
      if (categoryId != null && s.group.categoryId != categoryId) return false;
      if (situation == _Situation.open && s.finished) return false;
      if (situation == _Situation.done && !s.finished) return false;
      return q.isEmpty ||
          s.group.description.toLowerCase().contains(q) ||
          s.group.notes.toLowerCase().contains(q);
    }).toList();
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final open = list.where((s) => !s.finished).toList();
    int sum(
      Iterable<InstallmentSummary> l,
      int Function(InstallmentSummary) f,
    ) => l.fold(0, (a, s) => a + f(s));
    final wheres = <String, String>{for (final s in all) s.whereKey: s.where};
    final cats = <String, String>{
      for (final s in all)
        if (s.group.categoryId != null) s.group.categoryId!: s.category,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Parcelamentos')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-inst',
        onPressed: () => push(context, const TransactionFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nova compra'),
      ),
      body: all.isEmpty
          ? const EmptyState(
              icon: Icons.view_week_outlined,
              title: 'Nenhuma compra parcelada',
              message: 'Ao registrar uma despesa, ative “Compra parcelada” para gerar as parcelas.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                KpiWrap(
                  children: (kpiW) => [
                    SimKpi(
                      width: kpiW,
                      label: 'Em andamento',
                      value: '${open.length}',
                      detail:
                          '${list.length - open.length} quitado'
                          '${list.length - open.length == 1 ? '' : 's'}',
                      icon: Icons.view_week_outlined,
                    ),
                    SimKpi(
                      width: kpiW,
                      label: 'Parcelas por mês',
                      value: fmtMoney(sum(open, (s) => s.parcel)),
                      detail: 'compras em andamento',
                      icon: Icons.event_repeat,
                    ),
                    SimKpi(
                      width: kpiW,
                      label: 'Restante a pagar',
                      value: fmtMoney(sum(list, (s) => s.remaining)),
                      icon: Icons.schedule,
                      color: context.fin.negative,
                    ),
                    SimKpi(
                      width: kpiW,
                      label: 'Total parcelado',
                      value: fmtMoney(sum(list, (s) => s.total)),
                      detail: 'pago ${fmtMoney(sum(list, (s) => s.paid))}',
                      icon: Icons.receipt_long_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FiltersPanel(
                  keyPrefix: 'inst',
                  open: filtersOpen ?? !narrow,
                  active: _activeFilters,
                  onToggle: () =>
                      setState(() => filtersOpen = !(filtersOpen ?? !narrow)),
                  onClear: _clearFilters,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        child: TextField(
                          key: const ValueKey('inst-search'),
                          controller: searchCtrl,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Buscar descrição',
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => query = v),
                        ),
                      ),
                      FilterDropdown<String?>(
                        label: 'Cartão/conta',
                        value: where,
                        items: {null: 'Todos', ...wheres},
                        onChanged: (v) => setState(() => where = v),
                      ),
                      FilterDropdown<String?>(
                        label: 'Categoria',
                        value: categoryId,
                        items: {null: 'Todas', ...cats},
                        onChanged: (v) => setState(() => categoryId = v),
                      ),
                      FilterDropdown<_Situation?>(
                        label: 'Situação',
                        value: situation,
                        items: {
                          null: 'Todas',
                          for (final s in _Situation.values) s: s.label,
                        },
                        onChanged: (v) => setState(() => situation = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.view_week_outlined,
                      title: 'Nada com esses filtros',
                    ),
                  )
                else
                  InstallmentsGrid(
                    rows: list,
                    onOpen: (s) => push(
                      context,
                      InstallmentDetailsScreen(groupId: s.group.id),
                    ),
                  ),
              ],
            ),
    );
  }
}

String fmtMoney(int cents) => Money(cents).format();

/// Compras parceladas numa grade única, ordenável e com totais.
class InstallmentsGrid extends StatelessWidget {
  final List<InstallmentSummary> rows;
  final ValueChanged<InstallmentSummary> onOpen;
  const InstallmentsGrid({super.key, required this.rows, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final tab = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );
    final small = context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    final strong = context.text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: p.neon,
    );
    int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    int sum(List<InstallmentSummary> l, int Function(InstallmentSummary) f) =>
        l.fold(0, (a, s) => a + f(s));
    Color accent(InstallmentSummary s) =>
        s.finished ? context.fin.positive : p.neon;
    Widget status(InstallmentSummary s) => NeonStatus(
      label: s.finished ? 'Quitado' : 'Em andamento',
      color: accent(s),
      done: s.finished,
    );
    Widget money(int v, {TextStyle? style, Color? color}) => v == 0
        ? Text('—', style: subtle)
        : Text(
            fmtMoney(v),
            style: (style ?? context.text.bodySmall)?.copyWith(color: color),
          );
    Widget progress(InstallmentSummary s) => Row(
      children: [
        Text(
          '${s.elapsed.clamp(0, s.count)}/${s.count}',
          style: tab?.copyWith(color: p.neon, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: s.count == 0 ? 0 : s.elapsed / s.count,
              minHeight: 5,
              backgroundColor: context.fin.gridLine,
              color: accent(s),
            ),
          ),
        ),
      ],
    );

    return SortGrid<InstallmentSummary>(
      keyPrefix: 'inst',
      rows: rows,
      rowId: (s) => s.group.id,
      accent: (context, s) => accent(s),
      onOpen: onOpen,
      initialSort: 'purchase',
      initialAscending: false,
      tieBreak: (a, b) => text(a.group.description, b.group.description),
      columns: [
        SortCol(
          id: 'description',
          label: 'Descrição',
          width: 180,
          minWidth: 120,
          flexible: true,
          fill: true,
          compare: (a, b) => text(a.group.description, b.group.description),
          cell: (context, s) => GridCell(
            child: Text(
              s.group.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SortCol(
          id: 'where',
          label: 'Cartão/conta',
          width: 120,
          minWidth: 90,
          flexible: true,
          compare: (a, b) => text(a.where, b.where),
          cell: (context, s) => GridCell(
            child: Text(
              s.where,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          ),
        ),
        SortCol(
          id: 'category',
          label: 'Categoria',
          width: 130,
          minWidth: 90,
          flexible: true,
          compare: (a, b) => text(a.category, b.category),
          cell: (context, s) => GridCell(
            child: Text(
              s.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtle,
            ),
          ),
        ),
        SortCol(
          id: 'purchase',
          label: 'Compra',
          width: 92,
          compare: (a, b) =>
              a.group.purchaseDate.compareTo(b.group.purchaseDate),
          cell: (context, s) => GridCell(
            child: Text(Dates.format(s.group.purchaseDate), style: tab),
          ),
        ),
        SortCol(
          id: 'progress',
          label: 'Parcelas',
          width: 110,
          compare: (a, b) => (a.count == 0 ? 1.0 : a.elapsed / a.count)
              .compareTo(b.count == 0 ? 1.0 : b.elapsed / b.count),
          cell: (context, s) => GridCell(child: progress(s)),
        ),
        SortCol(
          id: 'parcel',
          label: 'Parcela',
          width: 100,
          right: true,
          compare: (a, b) => a.parcel.compareTo(b.parcel),
          cell: (context, s) => GridCell(right: true, child: money(s.parcel)),
          footer: (context, l) => Text(
            fmtMoney(
              sum(l.where((s) => !s.finished).toList(), (s) => s.parcel),
            ),
            style: small,
          ),
        ),
        SortCol(
          id: 'total',
          label: 'Total',
          width: 112,
          right: true,
          highlight: true,
          compare: (a, b) => a.total.compareTo(b.total),
          cell: (context, s) => GridCell(
            right: true,
            child: Text(
              fmtMoney(s.total),
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          footer: (context, l) =>
              Text(fmtMoney(sum(l, (s) => s.total)), style: strong),
        ),
        SortCol(
          id: 'remaining',
          label: 'Restante',
          width: 104,
          right: true,
          compare: (a, b) => a.remaining.compareTo(b.remaining),
          cell: (context, s) => GridCell(
            right: true,
            child: money(
              s.remaining,
              color: context.fin.negative,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          footer: (context, l) =>
              Text(fmtMoney(sum(l, (s) => s.remaining)), style: small),
        ),
        SortCol(
          id: 'next',
          label: 'Próxima',
          width: 92,
          compare: (a, b) =>
              (a.next ?? DateTime(9999)).compareTo(b.next ?? DateTime(9999)),
          cell: (context, s) => GridCell(
            child: s.next == null
                ? Text('—', style: subtle)
                : Text(Dates.format(s.next!), style: tab),
          ),
        ),
        SortCol(
          id: 'status',
          label: 'Situação',
          width: 134,
          compare: (a, b) => (a.finished ? 1 : 0).compareTo(b.finished ? 1 : 0),
          cell: (context, s) => GridCell(child: status(s)),
        ),
      ],
      compactRow: (context, s) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.group.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    s.where,
                    'compra ${Dates.formatShort(s.group.purchaseDate)}',
                    if (s.next != null) 'próx. ${Dates.formatShort(s.next!)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtle,
                ),
                const SizedBox(height: 4),
                SizedBox(width: 160, child: progress(s)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmtMoney(s.total),
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (!s.finished)
                Text('falta ${fmtMoney(s.remaining)}', style: subtle),
              const SizedBox(height: 3),
              status(s),
            ],
          ),
        ],
      ),
      footerLabel: (context, l) => Text(
        'Total · ${l.length} ${l.length == 1 ? 'compra' : 'compras'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: gridFooterLabelStyle(context),
      ),
      compactFooter: (context, l) {
        final rest = sum(l, (s) => s.remaining);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rest > 0) ...[
              Text('falta ', style: context.text.bodySmall),
              Text(fmtMoney(rest), style: small),
              const SizedBox(width: 10),
            ],
            Text(fmtMoney(sum(l, (s) => s.total)), style: strong),
          ],
        );
      },
    );
  }
}
