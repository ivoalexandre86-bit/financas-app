import 'package:flutter/material.dart';

import '../theme.dart';
import 'tx_grid.dart';

/// Uma coluna da [SortGrid].
class SortCol<T> {
  final String id;
  final String label;
  final double width;
  final double minWidth;
  final bool right;

  /// Encolhe até [minWidth] antes de a grade rolar na horizontal.
  final bool flexible;

  /// Recebe a sobra de largura (normalmente a descrição).
  final bool fill;

  /// Fundo destacado (coluna de valor).
  final bool highlight;
  final Widget Function(BuildContext context, T row) cell;
  final int Function(T a, T b)? compare;
  final Widget Function(BuildContext context, List<T> rows)? footer;

  const SortCol({
    required this.id,
    required this.label,
    required this.width,
    required this.cell,
    double? minWidth,
    this.right = false,
    this.flexible = false,
    this.fill = false,
    this.highlight = false,
    this.compare,
    this.footer,
  }) : minWidth = minWidth ?? width;
}

class _Layout<T> {
  final List<(SortCol<T>, double)> cells;
  final double totalWidth;
  const _Layout(this.cells, this.totalWidth);

  static const stripeW = GridLayout.stripeW;
  static const actionW = 36.0;

  /// A sobra vai para a coluna [SortCol.fill]; faltando espaço, as colunas
  /// flexíveis encolhem até o mínimo e depois a grade rola na horizontal.
  factory _Layout.of(double width, List<SortCol<T>> cols) {
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
    double sized(SortCol<T> c) {
      if (c.fill && extra > 0) return c.width + extra;
      if (!c.flexible) return c.width;
      return c.width - (c.width - c.minWidth) * shrink;
    }

    return _Layout([
      for (final c in cols) (c, sized(c)),
    ], sum + extra - slack * shrink);
  }
}

/// Grade única no padrão de Faturas e Outras despesas: cabeçalho escuro
/// ordenável, linhas com listra de status, rodapé com totais e linhas
/// compactas (duas linhas) em telas estreitas.
class SortGrid<T> extends StatefulWidget {
  /// Prefixo das chaves (`<prefix>-sort-<col>`, `<prefix>-row-<id>`,
  /// `<prefix>-footer`).
  final String keyPrefix;
  final List<T> rows;
  final List<SortCol<T>> columns;
  final String Function(T row) rowId;
  final Color Function(BuildContext context, T row) accent;
  final bool Function(T row)? dimmed;
  final ValueChanged<T> onOpen;

  /// Conteúdo da linha no celular (dentro da moldura da grade).
  final Widget Function(BuildContext context, T row) compactRow;

  /// Rótulo do rodapé (vai na coluna [SortCol.fill]).
  final Widget Function(BuildContext context, List<T> rows) footerLabel;

  /// Lado direito do rodapé no celular.
  final Widget Function(BuildContext context, List<T> rows) compactFooter;

  /// Critério de desempate da ordenação.
  final int Function(T a, T b) tieBreak;
  final String initialSort;
  final bool initialAscending;
  final double compactBelow;

  const SortGrid({
    super.key,
    required this.keyPrefix,
    required this.rows,
    required this.columns,
    required this.rowId,
    required this.accent,
    required this.onOpen,
    required this.compactRow,
    required this.footerLabel,
    required this.compactFooter,
    required this.tieBreak,
    required this.initialSort,
    this.initialAscending = true,
    this.dimmed,
    this.compactBelow = 760,
  });

  @override
  State<SortGrid<T>> createState() => _SortGridState<T>();
}

class _SortGridState<T> extends State<SortGrid<T>> {
  late String sort = widget.initialSort;
  late bool ascending = widget.initialAscending;

  void _onSort(SortCol<T> c) => setState(() {
    if (c.id == sort) {
      ascending = !ascending;
    } else {
      sort = c.id;
      ascending = !c.right;
    }
  });

  List<T> get _sorted {
    final col = widget.columns.where((c) => c.id == sort).firstOrNull;
    final cmp = col?.compare;
    return [...widget.rows]..sort((a, b) {
      if (cmp != null) {
        final c = cmp(a, b);
        if (c != 0) return ascending ? c : -c;
      }
      return widget.tieBreak(a, b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth - 2;
        final layout = width < widget.compactBelow
            ? null
            : _Layout<T>.of(width, widget.columns);
        final body = <Widget>[
          for (final (i, r) in rows.indexed)
            GridRowShell(
              key: ValueKey('${widget.keyPrefix}-row-${widget.rowId(r)}'),
              accent: widget.accent(context, r),
              zebra: i.isOdd,
              dimmed: widget.dimmed?.call(r) ?? false,
              height: layout == null ? null : 40,
              onTap: () => widget.onOpen(r),
              child: layout == null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                      child: Row(
                        children: [
                          Expanded(child: widget.compactRow(context, r)),
                          const Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                    )
                  : _cells(context, layout, (c) => c.cell(context, r)),
            ),
          _footer(context, rows, layout),
        ];
        return GridPanel(
          child: layout == null
              ? Column(children: body)
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: layout.totalWidth,
                    child: Column(
                      children: [_header(context, layout), ...body],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _cells(
    BuildContext context,
    _Layout<T> layout,
    Widget Function(SortCol<T>) cell,
  ) {
    final p = GridPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (c, w) in layout.cells)
          SizedBox(
            width: w,
            child: c.highlight
                ? ColoredBox(color: p.valueBg, child: cell(c))
                : cell(c),
          ),
        SizedBox(
          width: _Layout.actionW,
          child: Icon(Icons.chevron_right, size: 20, color: p.neon),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, _Layout<T> layout) {
    final p = GridPalette.of(context);
    Widget cell(SortCol<T> c) {
      final active = c.id == sort;
      final sortable = c.compare != null;
      return InkWell(
        key: ValueKey('${widget.keyPrefix}-sort-${c.id}'),
        onTap: sortable ? () => _onSort(c) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: c.right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  c.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: active ? p.neon : p.headerText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (sortable) ...[
                const SizedBox(width: 2),
                Icon(
                  active
                      ? (ascending
                            ? Icons.arrow_drop_up
                            : Icons.arrow_drop_down)
                      : Icons.unfold_more,
                  size: active ? 18 : 13,
                  color: active ? p.neon : p.headerText.withValues(alpha: 0.45),
                ),
              ],
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

  Widget _footer(BuildContext context, List<T> rows, _Layout<T>? layout) {
    final p = GridPalette.of(context);
    final decoration = BoxDecoration(
      color: p.neon.withValues(alpha: 0.06),
      border: Border(
        top: BorderSide(color: p.neon.withValues(alpha: 0.5), width: 1),
      ),
    );
    final key = ValueKey('${widget.keyPrefix}-footer');
    if (layout == null) {
      return Container(
        key: key,
        decoration: decoration,
        padding: const EdgeInsets.fromLTRB(13, 10, 16, 10),
        child: Row(
          children: [
            Expanded(child: widget.footerLabel(context, rows)),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: widget.compactFooter(context, rows),
              ),
            ),
          ],
        ),
      );
    }
    // O rótulo ocupa a coluna de descrição e as vizinhas sem total.
    final cells = <Widget>[];
    final list = layout.cells;
    for (var i = 0; i < list.length; i++) {
      final (c, w) = list[i];
      if (c.fill) {
        var width = w;
        while (i + 1 < list.length &&
            list[i + 1].$1.footer == null &&
            !list[i + 1].$1.highlight) {
          width += list[++i].$2;
        }
        cells.add(
          SizedBox(
            width: width,
            child: GridCell(child: widget.footerLabel(context, rows)),
          ),
        );
        continue;
      }
      final f = c.footer;
      final cell = f == null
          ? const SizedBox.shrink()
          : GridCell(right: c.right, child: f(context, rows));
      cells.add(
        SizedBox(
          width: w,
          child: c.highlight ? ColoredBox(color: p.valueBg, child: cell) : cell,
        ),
      );
    }
    return Container(
      key: key,
      height: 42,
      decoration: decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: _Layout.stripeW),
          ...cells,
          const SizedBox(width: _Layout.actionW),
        ],
      ),
    );
  }
}

/// Estilo do rótulo do rodapé ("Total · 3 itens").
TextStyle? gridFooterLabelStyle(BuildContext context) =>
    context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700);

/// Indicadores no topo da tela: dois por linha em telas estreitas (pela
/// largura realmente disponível, descontando o menu lateral).
class KpiWrap extends StatelessWidget {
  final List<Widget> Function(double width) children;
  final double width;
  const KpiWrap({super.key, required this.children, this.width = 200});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: children(
        box.maxWidth < 760 ? ((box.maxWidth - 10) / 2).floorToDouble() : width,
      ),
    ),
  );
}
