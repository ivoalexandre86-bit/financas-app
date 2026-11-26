import 'package:flutter/material.dart' hide Simulation;
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/other_entries_engine.dart';
import '../../../domain/models/other_entry.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/tx_grid.dart';
import '../cards/invoice_purchases.dart' show GlowDot;
import 'other_entries.dart' show payStatusColor;
import 'sim_common.dart';

/// Valores de um lançamento usados nas colunas e no rodapé.
class _Row {
  final OtherEntry e;
  final int assigned, received, outstanding;
  final PayStatus? status;
  _Row(this.e, Set<String> me)
    : assigned = OtherSummary.of([e], me).assigned,
      received = OtherSummary.of([e], me).received,
      outstanding = OtherSummary.of([e], me).outstanding,
      status = e.status(me);
}

enum OtherCol {
  description('Descrição', 220, minWidth: 140, flexible: true),
  month('Mês', 80),
  due('Vencimento', 104),
  people('Pessoas', 170, minWidth: 110, flexible: true),
  linked('Orçamento', 96),
  amount('Valor', 120, right: true),
  assigned('Outros', 116, right: true),
  received('Recebido', 116, right: true),
  outstanding('A receber', 116, right: true),
  status('Situação', 116);

  final String label;
  final double width;
  final double minWidth;
  final bool right;
  final bool flexible;
  const OtherCol(
    this.label,
    this.width, {
    double? minWidth,
    this.right = false,
    this.flexible = false,
  }) : minWidth = minWidth ?? width;
}

class _Layout {
  final List<(OtherCol, double)> cells;
  final double totalWidth;
  const _Layout(this.cells, this.totalWidth);

  static const stripeW = GridLayout.stripeW;
  static const actionW = 76.0;

  /// A sobra vai para a descrição; faltando espaço, descrição e pessoas
  /// encolhem até o mínimo e depois a grade rola na horizontal.
  factory _Layout.of(double width, List<OtherCol> cols) {
    var sum = stripeW + actionW;
    var slack = 0.0;
    for (final c in cols) {
      sum += c.width;
      if (c.flexible) slack += c.width - c.minWidth;
    }
    final extra = width > sum ? width - sum : 0.0;
    final shrink = width < sum && slack > 0
        ? ((sum - width) / slack).clamp(0.0, 1.0)
        : 0.0;
    double sized(OtherCol c) {
      if (c == OtherCol.description && extra > 0) return c.width + extra;
      if (!c.flexible) return c.width;
      return c.width - (c.width - c.minWidth) * shrink;
    }

    return _Layout([
      for (final c in cols) (c, sized(c)),
    ], sum + extra - slack * shrink);
  }
}

/// Lançamentos de "Outras despesas/receitas" numa grade única, com
/// ordenação por coluna e rodapé com os totais.
class OtherGrid extends StatefulWidget {
  final List<OtherEntry> entries;
  final bool isIncome;
  final ValueChanged<OtherEntry> onOpen;
  const OtherGrid({
    super.key,
    required this.entries,
    required this.isIncome,
    required this.onOpen,
  });

  @override
  State<OtherGrid> createState() => _OtherGridState();
}

class _OtherGridState extends State<OtherGrid> {
  OtherCol sort = OtherCol.month;
  bool ascending = true;

  /// Lançamentos com os valores por pessoa abertos na própria grade.
  final expanded = <String>{};

  void _toggle(String id) => setState(
    () => expanded.contains(id) ? expanded.remove(id) : expanded.add(id),
  );

  List<OtherCol> get _cols => [
    for (final c in OtherCol.values)
      if (!(widget.isIncome && c == OtherCol.assigned)) c,
  ];

  void _onSort(OtherCol c) => setState(() {
    if (c == sort) {
      ascending = !ascending;
    } else {
      sort = c;
      ascending = !c.right;
    }
  });

  int _cmp(_Row a, _Row b, String Function(OtherEntry) people) {
    int text(String x, String y) => x.toLowerCase().compareTo(y.toLowerCase());
    final c = switch (sort) {
      OtherCol.description => text(a.e.description, b.e.description),
      OtherCol.month => a.e.month.compareTo(b.e.month),
      OtherCol.due => (a.e.dueDate ?? a.e.month.lastDay).compareTo(
        b.e.dueDate ?? b.e.month.lastDay,
      ),
      OtherCol.people => text(people(a.e), people(b.e)),
      OtherCol.linked => (a.e.linked ? 0 : 1).compareTo(b.e.linked ? 0 : 1),
      OtherCol.amount => a.e.amount.compareTo(b.e.amount),
      OtherCol.assigned => a.assigned.compareTo(b.assigned),
      OtherCol.received => a.received.compareTo(b.received),
      OtherCol.outstanding => a.outstanding.compareTo(b.outstanding),
      OtherCol.status => (a.status?.index ?? 9).compareTo(b.status?.index ?? 9),
    };
    final r = ascending ? c : -c;
    if (r != 0) return r;
    final m = a.e.month.compareTo(b.e.month);
    return m != 0 ? m : text(a.e.description, b.e.description);
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final me = fc.meIds;
    String people(OtherEntry e) =>
        [for (final s in e.shares()) fc.personById(s.personId)?.name ?? '?']
            .join(', ');
    final rows = [for (final e in widget.entries) _Row(e, me)]
      ..sort((a, b) => _cmp(a, b, people));
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth - 2;
        final compact = width < 760;
        final layout = compact ? null : _Layout.of(width, _cols);
        final body = <Widget>[
          for (final (i, r) in rows.indexed) ...[
            layout == null
                ? _CompactRow(
                    r: r,
                    index: i,
                    people: people(r.e),
                    isIncome: widget.isIncome,
                    expanded: expanded.contains(r.e.id),
                    onToggle: () => _toggle(r.e.id),
                    onOpen: () => widget.onOpen(r.e),
                  )
                : _GridRow(
                    r: r,
                    index: i,
                    layout: layout,
                    people: people(r.e),
                    expanded: expanded.contains(r.e.id),
                    onToggle: () => _toggle(r.e.id),
                    onOpen: () => widget.onOpen(r.e),
                  ),
            if (expanded.contains(r.e.id))
              _Shares(
                e: r.e,
                isIncome: widget.isIncome,
                width: layout?.totalWidth,
                onOpen: () => widget.onOpen(r.e),
              ),
          ],
          _Footer(rows: rows, layout: layout, isIncome: widget.isIncome),
        ];
        return GridPanel(
          child: layout == null
              ? Column(children: body)
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: layout.totalWidth,
                    child: Column(
                      children: [
                        _Header(
                          layout: layout,
                          sort: sort,
                          ascending: ascending,
                          isIncome: widget.isIncome,
                          onSort: _onSort,
                        ),
                        ...body,
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

String _label(OtherCol c, bool isIncome) => switch (c) {
  OtherCol.people when isIncome => 'Quem paga',
  OtherCol.amount when isIncome => 'Previsto',
  _ => c.label,
};

class _Header extends StatelessWidget {
  final _Layout layout;
  final OtherCol sort;
  final bool ascending;
  final bool isIncome;
  final ValueChanged<OtherCol> onSort;
  const _Header({
    required this.layout,
    required this.sort,
    required this.ascending,
    required this.isIncome,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    Widget cell(OtherCol c) {
      final active = c == sort;
      return InkWell(
        key: ValueKey('oe-sort-${c.name}'),
        onTap: () => onSort(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: c.right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  _label(c, isIncome).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: active ? p.neon : p.headerText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                active
                    ? (ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down)
                    : Icons.unfold_more,
                size: active ? 18 : 13,
                color: active ? p.neon : p.headerText.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 38,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: p.header),
        border: Border(bottom: BorderSide(color: p.neon, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: _Layout.stripeW),
          for (final (c, w) in layout.cells) SizedBox(width: w, child: cell(c)),
          const SizedBox(width: _Layout.actionW),
        ],
      ),
    );
  }
}

Widget _status(BuildContext context, PayStatus? s) => NeonStatus(
  label: s?.label ?? 'Sem divisão',
  color: payStatusColor(context, s),
  done: s == PayStatus.paid,
);

class _GridRow extends StatelessWidget {
  final _Row r;
  final int index;
  final _Layout layout;
  final String people;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  const _GridRow({
    required this.r,
    required this.index,
    required this.layout,
    required this.people,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final e = r.e;
    final p = GridPalette.of(context);
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final tab = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );
    Widget money(int v, {TextStyle? style, Color? color}) => v == 0
        ? Text('—', style: subtle)
        : Text(
            fmtCents(v),
            style: (style ?? context.text.bodySmall)?.copyWith(color: color),
          );
    Widget cell(OtherCol c) => switch (c) {
      OtherCol.description => GridCell(
        child: Text(
          [
            e.description,
            if (e.inSeries)
              '(${e.seriesKind?.label ?? ''} ${e.seriesLabel})'.replaceAll(
                '( ',
                '(',
              ),
          ].join(' '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            decoration: e.isDeleted ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
      OtherCol.month => GridCell(
        child: Text(
          e.month.shortLabel,
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      OtherCol.due => GridCell(
        child: Text(
          e.dueDate == null ? '—' : Dates.format(e.dueDate!),
          style: tab,
        ),
      ),
      OtherCol.people => GridCell(
        child: Text(
          people.isEmpty ? '—' : people,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: people.isEmpty ? subtle : context.text.bodySmall,
        ),
      ),
      OtherCol.linked => GridCell(
        child: Tooltip(
          message: e.linked ? 'Vinculado ao orçamento' : 'Não vinculado',
          child: Row(
            children: [
              Icon(
                e.linked ? Icons.link : Icons.link_off,
                size: 16,
                color: e.linked ? context.fin.positive : context.fin.subtle,
              ),
              const SizedBox(width: 4),
              Text(e.linked ? 'Sim' : 'Não', style: subtle),
            ],
          ),
        ),
      ),
      OtherCol.amount => GridCell(
        right: true,
        background: p.valueBg,
        child: Text(
          fmtCents(e.amount),
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      OtherCol.assigned => GridCell(right: true, child: money(r.assigned)),
      OtherCol.received => GridCell(
        right: true,
        child: money(r.received, color: context.fin.positive),
      ),
      OtherCol.outstanding => GridCell(
        right: true,
        child: money(
          r.outstanding,
          color: context.fin.negative,
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      OtherCol.status => GridCell(child: _status(context, r.status)),
    };

    return GridRowShell(
      key: ValueKey('oe-row-${e.id}'),
      accent: payStatusColor(context, r.status),
      zebra: index.isOdd,
      dimmed: e.isDeleted,
      selected: expanded,
      height: 40,
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (c, w) in layout.cells) SizedBox(width: w, child: cell(c)),
          SizedBox(
            width: _Layout.actionW,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ExpandButton(id: e.id, expanded: expanded, onTap: onToggle),
                Icon(Icons.chevron_right, size: 20, color: p.neon),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha no celular: duas linhas com o resumo.
class _CompactRow extends StatelessWidget {
  final _Row r;
  final int index;
  final String people;
  final bool isIncome;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  const _CompactRow({
    required this.r,
    required this.index,
    required this.people,
    required this.isIncome,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final e = r.e;
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    return GridRowShell(
      key: ValueKey('oe-row-${e.id}'),
      accent: payStatusColor(context, r.status),
      zebra: index.isOdd,
      dimmed: e.isDeleted,
      selected: expanded,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            Icon(
              e.linked ? Icons.link : Icons.link_off,
              size: 16,
              color: e.linked ? context.fin.positive : context.fin.subtle,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      decoration: e.isDeleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    [
                      e.month.shortLabel,
                      if (e.inSeries)
                        '${e.seriesKind?.label ?? ''} ${e.seriesLabel}'.trim(),
                      if (e.dueDate != null)
                        'vence ${Dates.format(e.dueDate!)}',
                      if (r.outstanding > 0)
                        '${isIncome ? 'a receber' : 'falta'} '
                            '${fmtCents(r.outstanding)}',
                    ].join(' · '),
                    style: subtle,
                  ),
                  if (people.isNotEmpty)
                    Text(
                      people,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtle,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  fmtCents(e.amount),
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                _status(context, r.status),
              ],
            ),
            _ExpandButton(id: e.id, expanded: expanded, onTap: onToggle),
          ],
        ),
      ),
    );
  }
}

/// Totais dos lançamentos exibidos (excluídos não somam).
class _Footer extends StatelessWidget {
  final List<_Row> rows;
  final _Layout? layout;
  final bool isIncome;
  const _Footer({
    required this.rows,
    required this.layout,
    required this.isIncome,
  });

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    final live = rows.where((r) => !r.e.isDeleted).toList();
    int sum(int Function(_Row) f) => live.fold(0, (a, r) => a + f(r));
    final total = sum((r) => r.e.amount);
    final outstanding = sum((r) => r.outstanding);
    final small = context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    final strong = context.text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: p.neon,
    );
    final noun = isIncome ? 'receita' : 'despesa';
    final label = Text(
      'Total · ${live.length} ${live.length == 1 ? noun : '${noun}s'}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
    final decoration = BoxDecoration(
      color: p.neon.withValues(alpha: 0.06),
      border: Border(
        top: BorderSide(color: p.neon.withValues(alpha: 0.5), width: 1),
      ),
    );
    final l = layout;
    if (l == null) {
      return Container(
        key: const ValueKey('oe-footer'),
        decoration: decoration,
        padding: const EdgeInsets.fromLTRB(13, 10, 16, 10),
        child: Row(
          children: [
            Expanded(child: label),
            if (outstanding > 0) ...[
              Text(
                isIncome ? 'a receber ' : 'falta ',
                style: context.text.bodySmall,
              ),
              Text(fmtCents(outstanding), style: small),
              const SizedBox(width: 10),
            ],
            Text(fmtCents(total), style: strong),
          ],
        ),
      );
    }
    Widget money(int v) =>
        v == 0 ? const SizedBox.shrink() : Text(fmtCents(v), style: small);
    Widget cell(OtherCol c) => switch (c) {
      OtherCol.description => GridCell(child: label),
      OtherCol.amount => GridCell(
        right: true,
        background: p.valueBg,
        child: Text(fmtCents(total), style: strong),
      ),
      OtherCol.assigned => GridCell(
        right: true,
        child: money(sum((r) => r.assigned)),
      ),
      OtherCol.received => GridCell(
        right: true,
        child: money(sum((r) => r.received)),
      ),
      OtherCol.outstanding => GridCell(right: true, child: money(outstanding)),
      _ => const SizedBox.shrink(),
    };
    return Container(
      key: const ValueKey('oe-footer'),
      height: 42,
      decoration: decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: _Layout.stripeW),
          for (final (c, w) in l.cells) SizedBox(width: w, child: cell(c)),
          const SizedBox(width: _Layout.actionW),
        ],
      ),
    );
  }
}

class _ExpandButton extends StatelessWidget {
  final String id;
  final bool expanded;
  final VoidCallback onTap;
  const _ExpandButton({
    required this.id,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    key: ValueKey('oe-expand-$id'),
    tooltip: expanded ? 'Recolher' : 'Ver valores por pessoa',
    visualDensity: VisualDensity.compact,
    iconSize: 20,
    color: GridPalette.of(context).neon,
    icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
    onPressed: onTap,
  );
}

/// Valores por pessoa de um lançamento, abertos logo abaixo da linha.
class _Shares extends StatelessWidget {
  final OtherEntry e;
  final bool isIncome;
  final double? width;
  final VoidCallback onOpen;
  const _Shares({
    required this.e,
    required this.isIncome,
    required this.width,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final p = GridPalette.of(context);
    final me = fc.meIds;
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final tab = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final meId = me.firstOrNull;
    final shares = meId == null ? e.shares() : e.sharesWithOwner(meId);
    final rest = e.amount - shares.fold<int>(0, (a, s) => a + s.owed);
    Widget money(double w, int v, {Color? color, bool bold = false}) =>
        SizedBox(
          width: w,
          child: Text(
            v == 0 ? '—' : fmtCents(v),
            textAlign: TextAlign.right,
            style: (v == 0 ? subtle : tab)?.copyWith(
              color: v == 0 ? null : color,
              fontWeight: bold ? FontWeight.w700 : null,
            ),
          ),
        );
    final panel = Container(
      key: ValueKey('oe-shares-${e.id}'),
      decoration: BoxDecoration(
        color: p.neon.withValues(alpha: 0.04),
        border: Border(
          left: BorderSide(color: p.neon.withValues(alpha: 0.6), width: 3),
          bottom: BorderSide(color: p.line),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 560;
          final w = narrow ? 84.0 : 112.0;
          Widget head(String t) => SizedBox(
            width: w,
            child: Text(t, textAlign: TextAlign.right, style: subtle),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (shares.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    isIncome
                        ? 'Sem pagador definido.'
                        : 'Sem divisão: o valor todo fica com você.',
                    style: subtle,
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('Pessoa', style: subtle)),
                      head('Parte'),
                      if (!narrow) head(isIncome ? 'Recebido' : 'Pago'),
                      head(isIncome ? 'A receber' : 'Falta'),
                      if (!narrow) const SizedBox(width: 120),
                    ],
                  ),
                ),
                for (final s in shares)
                  Builder(
                    builder: (context) {
                      final person = fc.personById(s.personId);
                      final mine = me.contains(s.personId);
                      final balance = mine ? 0 : (s.owed - s.paid);
                      return Padding(
                        key: ValueKey('oe-share-${e.id}-${s.personId}'),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            GlowDot(Color(person?.color ?? 0xFF94A3B8)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                [
                                  person?.name ?? '?',
                                  if (s.percent != null)
                                    '· ${_pct(s.percent!)}',
                                ].join(' '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodyMedium,
                              ),
                            ),
                            money(w, s.owed, bold: true),
                            if (!narrow)
                              money(
                                w,
                                mine ? 0 : s.paid,
                                color: context.fin.positive,
                              ),
                            money(
                              w,
                              balance < 0 ? 0 : balance,
                              color: context.fin.negative,
                            ),
                            if (!narrow)
                              SizedBox(
                                width: 120,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: mine
                                      ? Text('sua parte', style: subtle)
                                      : _status(context, s.status),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                if (rest > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Expanded(child: Text('Sem divisão', style: subtle)),
                        money(w, rest),
                        if (!narrow) SizedBox(width: w),
                        SizedBox(width: w),
                        if (!narrow) const SizedBox(width: 120),
                      ],
                    ),
                  ),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                    'Abrir ${isIncome ? 'receita' : 'despesa'} completa',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return width == null ? panel : SizedBox(width: width, child: panel);
  }
}

String _pct(double v) {
  final r = (v * 10).round() / 10;
  return '${r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1).replaceAll('.', ',')}%';
}
