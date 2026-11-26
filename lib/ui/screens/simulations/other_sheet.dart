import 'package:flutter/material.dart' hide Simulation;
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/models/other_entry.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/tx_grid.dart';
import 'other_entries.dart' show OtherEntryScreen, payStatusColor;

/// Visão mês a mês (como a Projeção): linhas = lançamento/série ou pessoa,
/// colunas = meses, com total por linha e por mês. Cada linha abre ali
/// mesmo os valores por pessoa (ou, na visão por pessoa, os lançamentos),
/// sem precisar abrir o lançamento.
class OtherSheet extends StatefulWidget {
  final List<OtherEntry> entries;
  final List<YearMonth> months;
  final bool byPerson;
  const OtherSheet({
    super.key,
    required this.entries,
    required this.months,
    required this.byPerson,
  });

  @override
  State<OtherSheet> createState() => _OtherSheetState();
}

class _OtherSheetState extends State<OtherSheet> {
  final expanded = <String>{};
  final hScroll = ScrollController();

  static const _headerH = 44.0, _rowH = 48.0, _subH = 40.0;
  static const _minCellW = 92.0, _totalW = 124.0;

  @override
  void dispose() {
    hScroll.dispose();
    super.dispose();
  }

  List<SheetRow> _rows(FinanceController fc) {
    final live = widget.entries.where((e) => !e.isDeleted).toList();
    final meId = fc.meIds.firstOrNull;
    String name(String id) => fc.personById(id)?.name ?? '?';
    final rows = <String, SheetRow>{};
    if (widget.byPerson) {
      for (final e in live) {
        for (final s in _shares(e, meId)) {
          final r = rows[s.personId] ??= SheetRow(
            s.personId,
            s.personId == '~' ? 'Sem divisão' : name(s.personId),
            color: fc.personById(s.personId)?.color,
            mine: fc.meIds.contains(s.personId) || s.personId == '~',
          );
          r.add(e.month, s.owed, s.paid, e);
          final c = r.child(
            e.seriesId ?? e.id,
            e.description,
            mine: r.mine,
            detail: e.inSeries ? e.seriesKind!.label : null,
          );
          c.add(e.month, s.owed, s.paid, e);
        }
      }
    } else {
      for (final e in live) {
        final key = e.seriesId ?? e.id;
        final r = rows[key] ??= SheetRow(
          key,
          e.description,
          detail: e.inSeries
              ? '${e.seriesKind!.label} · ${e.seriesCount}×'
              : null,
          mine: true,
        );
        r.add(e.month, e.amount, null, e);
        r.status[e.month] = e.status(fc.meIds);
        for (final s in _shares(e, meId)) {
          final c = r.child(
            s.personId,
            s.personId == '~' ? 'Sem divisão' : name(s.personId),
            color: fc.personById(s.personId)?.color,
            mine: fc.meIds.contains(s.personId) || s.personId == '~',
          );
          c.add(e.month, s.owed, s.paid, e);
        }
      }
    }
    final list = rows.values.toList();
    if (widget.byPerson) {
      // Quem é "eu" e "Sem divisão" ficam por último.
      list.sort((a, b) {
        final c = (a.mine ? 1 : 0).compareTo(b.mine ? 1 : 0);
        return c != 0 ? c : a.label.compareTo(b.label);
      });
    }
    return list;
  }

  /// Partes por pessoa; o que ninguém assumiu fica com o responsável
  /// (despesa) ou "Sem divisão" (receita ou sem divisão nenhuma).
  static List<PersonShare> _shares(OtherEntry e, String? meId) {
    if (e.allocations.isEmpty) {
      return [PersonShare('~', null, e.amount, 0)];
    }
    final list = meId == null ? e.shares() : e.sharesWithOwner(meId);
    final out = list.where((s) => s.owed > 0 || s.paid > 0).toList();
    final rest = e.amount - out.fold<int>(0, (a, s) => a + s.owed);
    if (rest > 0) out.add(PersonShare('~', null, rest, 0));
    return out;
  }

  void _toggle(String key) => setState(
    () => expanded.contains(key) ? expanded.remove(key) : expanded.add(key),
  );

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final months = widget.months;
    if (months.isEmpty) return const SizedBox.shrink();
    final rows = _rows(fc);
    final p = GridPalette.of(context);
    final now = YearMonth.now();
    final totals = <YearMonth, int>{};
    for (final r in rows) {
      for (final v in r.values.entries) {
        totals[v.key] = (totals[v.key] ?? 0) + v.value;
      }
    }
    final grand = months.fold(0, (a, m) => a + (totals[m] ?? 0));
    final allOpen =
        rows.isNotEmpty &&
        rows.every((r) => r.children.isEmpty || expanded.contains(r.key));
    final headerStyle = context.text.labelSmall?.copyWith(
      color: p.headerText,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final tab = const [FontFeature.tabularFigures()];

    // Linhas visíveis (principal + abertas), na ordem.
    final visible = <(SheetRow, bool)>[
      for (final r in rows) ...[
        (r, false),
        if (expanded.contains(r.key))
          for (final c in r.children.values) (c, true),
      ],
    ];

    return GridPanel(
      child: LayoutBuilder(
        builder: (context, box) {
          final labelW = box.maxWidth < 640 ? 150.0 : 240.0;
          final cellW = ((box.maxWidth - labelW - _totalW) / months.length)
              .clamp(_minCellW, double.infinity)
              .toDouble();

          Widget rowBg(int i, bool sub, Widget child) => Container(
            height: sub ? _subH : _rowH,
            decoration: BoxDecoration(
              color: sub
                  ? p.neon.withValues(alpha: 0.04)
                  : i.isOdd
                  ? p.zebra
                  : null,
              border: Border(bottom: BorderSide(color: p.line, width: 0.6)),
            ),
            child: child,
          );

          Widget labelCell(SheetRow r, bool sub) {
            final open = expanded.contains(r.key);
            final accent = sub ? Color(r.color ?? p.neon2.toARGB32()) : p.neon;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: GridLayout.stripeW,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: sub ? 0.5 : 0.85),
                    boxShadow: [
                      if (!sub)
                        BoxShadow(
                          color: accent.withValues(alpha: 0.55),
                          blurRadius: 6,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: InkWell(
                    key: ValueKey('oe-sheet-row-${r.key}'),
                    onTap: sub || r.children.isEmpty
                        ? null
                        : () => _toggle(r.key),
                    child: Padding(
                      padding: EdgeInsets.only(left: sub ? 22 : 6, right: 4),
                      child: Row(
                        children: [
                          if (!sub)
                            Icon(
                              r.children.isEmpty
                                  ? Icons.remove
                                  : open
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                              color: r.children.isEmpty
                                  ? Colors.transparent
                                  : p.neon,
                            ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sub
                                      ? context.text.bodySmall
                                      : context.text.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                ),
                                if (r.detail != null)
                                  Text(
                                    r.detail!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: subtle?.copyWith(fontSize: 11),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          Widget valueCell(SheetRow r, bool sub, YearMonth m) {
            final v = r.values[m];
            final e = r.entries[m];
            final paid = r.paid[m];
            final current = m == now;
            Widget? note;
            if (v != null && paid != null && !r.mine && v > 0) {
              final rest = v - paid;
              note = rest <= 0
                  ? Text(
                      'pago',
                      style: subtle?.copyWith(
                        color: context.fin.positive,
                        fontSize: 11,
                      ),
                    )
                  : paid > 0
                  ? Text(
                      'falta ${_plain(rest)}',
                      style: subtle?.copyWith(
                        color: payStatusColor(context, PayStatus.partial),
                        fontSize: 11,
                      ),
                    )
                  : Text(
                      'a receber',
                      style: subtle?.copyWith(
                        color: context.fin.negative,
                        fontSize: 11,
                      ),
                    );
            } else if (!sub && r.status[m] != null && v != null) {
              final s = r.status[m]!;
              note = Text(
                s.label.toLowerCase(),
                style: subtle?.copyWith(
                  color: payStatusColor(context, s),
                  fontSize: 11,
                ),
              );
            }
            return SizedBox(
              width: cellW,
              child: Material(
                color: current
                    ? p.neon.withValues(alpha: 0.06)
                    : Colors.transparent,
                child: InkWell(
                  key: ValueKey(
                    'oe-sheet-cell-${sub ? 'sub-' : ''}${r.key}-${m.key}',
                  ),
                  hoverColor: p.hover,
                  onTap: e == null
                      ? null
                      : () => push(context, OtherEntryScreen(entryId: e.id)),
                  child: GridCell(
                    right: true,
                    child: v == null
                        ? Text('—', style: subtle)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _plain(v),
                                maxLines: 1,
                                style:
                                    (sub
                                            ? context.text.bodySmall
                                            : context.text.bodyMedium)
                                        ?.copyWith(
                                          fontWeight: sub
                                              ? FontWeight.w500
                                              : FontWeight.w600,
                                          fontFeatures: tab,
                                        ),
                              ),
                              ?note,
                            ],
                          ),
                  ),
                ),
              ),
            );
          }

          Widget totalCell(int v, {bool strong = false, Key? key}) => SizedBox(
            width: _totalW,
            child: Container(
              color: p.valueBg,
              child: GridCell(
                right: true,
                child: Text(
                  _plain(v),
                  key: key,
                  maxLines: 1,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                    color: strong ? p.neon : null,
                    fontFeatures: tab,
                  ),
                ),
              ),
            ),
          );

          final footerDeco = BoxDecoration(
            color: p.neon.withValues(alpha: 0.06),
            border: Border(
              top: BorderSide(color: p.neon.withValues(alpha: 0.5)),
            ),
          );

          final labels = Container(
            width: labelW,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: p.line)),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: _headerH,
                  child: Row(
                    children: [
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          widget.byPerson ? 'PESSOA' : 'LANÇAMENTO',
                          style: headerStyle,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('oe-sheet-expand-all'),
                        tooltip: allOpen
                            ? 'Recolher todos'
                            : widget.byPerson
                            ? 'Abrir lançamentos de todos'
                            : 'Abrir valores por pessoa de todos',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        color: p.neon,
                        icon: Icon(
                          allOpen ? Icons.unfold_less : Icons.unfold_more,
                        ),
                        onPressed: () => setState(() {
                          if (allOpen) {
                            expanded.clear();
                          } else {
                            expanded.addAll(rows.map((r) => r.key));
                          }
                        }),
                      ),
                    ],
                  ),
                ),
                for (final (i, (r, sub)) in visible.indexed)
                  rowBg(i, sub, labelCell(r, sub)),
                Container(
                  height: _rowH,
                  decoration: footerDeco,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 13),
                  child: Text(
                    'Total',
                    style: context.text.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );

          final scrolling = Scrollbar(
            controller: hScroll,
            thumbVisibility:
                cellW * months.length + _totalW > box.maxWidth - labelW,
            child: SingleChildScrollView(
              controller: hScroll,
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final m in months)
                        Container(
                          width: cellW,
                          height: _headerH,
                          color: m == now
                              ? p.neon.withValues(alpha: 0.10)
                              : null,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                m.shortLabel.toUpperCase(),
                                style: headerStyle?.copyWith(
                                  color: m == now ? p.neon : null,
                                ),
                              ),
                              if (m == now)
                                Text(
                                  'atual',
                                  style: context.text.labelSmall?.copyWith(
                                    color: p.headerText.withValues(alpha: 0.6),
                                    fontSize: 9,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Container(
                        width: _totalW,
                        height: _headerH,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('TOTAL', style: headerStyle),
                      ),
                    ],
                  ),
                  for (final (i, (r, sub)) in visible.indexed)
                    rowBg(
                      i,
                      sub,
                      Row(
                        children: [
                          for (final m in months) valueCell(r, sub, m),
                          totalCell(
                            months.fold(0, (a, m) => a + (r.values[m] ?? 0)),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    height: _rowH,
                    decoration: footerDeco,
                    child: Row(
                      children: [
                        for (final m in months)
                          SizedBox(
                            width: cellW,
                            child: GridCell(
                              right: true,
                              child: Text(
                                _plain(totals[m] ?? 0),
                                maxLines: 1,
                                style: context.text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: tab,
                                ),
                              ),
                            ),
                          ),
                        totalCell(
                          grand,
                          strong: true,
                          key: const ValueKey('oe-sheet-total'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );

          return Stack(
            children: [
              // Faixa do cabeçalho com a linha neon, atrás da coluna fixa e
              // da parte que rola, como na Projeção.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: _headerH,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: p.header),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              p.neon,
                              p.neon2,
                              p.neon.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labels,
                  Expanded(child: scrolling),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Uma linha da visão mês a mês, com as linhas que ela abre.
class SheetRow {
  final String key;
  final String label;
  final String? detail;
  final int? color;

  /// Parte do próprio usuário (ou sem divisão): não mostra "a receber".
  final bool mine;
  final values = <YearMonth, int>{};
  final paid = <YearMonth, int>{};
  final status = <YearMonth, PayStatus?>{};
  final entries = <YearMonth, OtherEntry>{};
  final children = <String, SheetRow>{};
  SheetRow(this.key, this.label, {this.detail, this.color, this.mine = false});

  void add(YearMonth m, int value, int? paidValue, OtherEntry e) {
    values[m] = (values[m] ?? 0) + value;
    if (paidValue != null) paid[m] = (paid[m] ?? 0) + paidValue;
    entries[m] ??= e;
  }

  SheetRow child(
    String key,
    String label, {
    int? color,
    bool mine = false,
    String? detail,
  }) => children[key] ??= SheetRow(
    '${this.key}/$key',
    label,
    color: color,
    mine: mine,
    detail: detail,
  );
}

/// Valores sem "R$", como na Projeção.
String _plain(int cents) => Money(cents).formatPlain();
