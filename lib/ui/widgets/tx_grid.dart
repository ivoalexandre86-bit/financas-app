import 'package:flutter/material.dart';

import '../theme.dart';

/// Paleta "neon" da grade de transações. O cabeçalho é sempre escuro (como
/// numa planilha) e os acentos brilham em ciano/violeta nos dois temas.
class GridPalette {
  final Color panel;
  final Color line;
  final Color zebra;
  final Color valueBg;
  final Color neon;
  final Color neon2;
  final Color headerText;
  final List<Color> header;
  final Color hover;

  const GridPalette._({
    required this.panel,
    required this.line,
    required this.zebra,
    required this.valueBg,
    required this.neon,
    required this.neon2,
    required this.headerText,
    required this.header,
    required this.hover,
  });

  static GridPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const GridPalette._(
            panel: Color(0xFF0E1320),
            line: Color(0xFF1C2538),
            zebra: Color(0x06FFFFFF),
            valueBg: Color(0x0D22D3EE),
            neon: Color(0xFF22D3EE),
            neon2: Color(0xFFA78BFA),
            headerText: Color(0xFFCFFAFE),
            header: [Color(0xFF070B16), Color(0xFF111A30)],
            hover: Color(0x1422D3EE),
          )
        : const GridPalette._(
            panel: Color(0xFFFFFFFF),
            line: Color(0xFFE6EAF2),
            zebra: Color(0x060F172A),
            valueBg: Color(0x0F0891B2),
            neon: Color(0xFF0891B2),
            neon2: Color(0xFF7C3AED),
            headerText: Color(0xFFE0F2FE),
            header: [Color(0xFF0B1120), Color(0xFF1E293B)],
            hover: Color(0x140891B2),
          );
  }
}

/// Colunas visíveis conforme a largura disponível.
class GridLayout {
  /// Celular: linhas de duas linhas, sem cabeçalho de colunas.
  final bool compact;

  /// Coluna própria para a subcategoria (telas largas).
  final bool showSub;
  const GridLayout({required this.compact, required this.showSub});

  factory GridLayout.of(double width) =>
      GridLayout(compact: width < 640, showSub: width >= 980);

  static const dateW = 92.0;
  static const amountW = 136.0;
  static const statusW = 116.0;
  static const actionW = 40.0;
  static const rowH = 36.0;
}

/// Colunas ordenáveis.
enum GridSort {
  date('Data'),
  category('Categoria'),
  subcategory('Subcategoria'),
  description('Descrição'),
  amount('Valor'),
  status('Status');

  final String label;
  const GridSort(this.label);
}

/// Painel com borda em degradê e brilho suave que envolve a grade.
class GridPanel extends StatelessWidget {
  final Widget child;
  const GridPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            p.neon.withValues(alpha: 0.55),
            p.neon2.withValues(alpha: 0.35),
            p.line,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: p.neon.withValues(alpha: 0.10),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
      ),
      padding: const EdgeInsets.all(1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: ColoredBox(color: p.panel, child: child),
      ),
    );
  }
}

/// Cabeçalho escuro da grade, com sublinhado neon e ordenação por clique.
class GridHeader extends StatelessWidget {
  final GridLayout layout;
  final GridSort sort;
  final bool ascending;
  final ValueChanged<GridSort> onSort;
  const GridHeader({
    super.key,
    required this.layout,
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    Widget cell(GridSort s, {bool right = false}) {
      final active = s == sort;
      final style = context.text.labelSmall?.copyWith(
        color: active ? p.neon : p.headerText,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      );
      return InkWell(
        key: ValueKey('grid-sort-${s.name}'),
        onTap: () => onSort(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  s.label.toUpperCase(),
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
      decoration: BoxDecoration(gradient: LinearGradient(colors: p.header)),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: 3),
              SizedBox(width: GridLayout.dateW, child: cell(GridSort.date)),
              Expanded(flex: 3, child: cell(GridSort.category)),
              if (layout.showSub)
                Expanded(flex: 3, child: cell(GridSort.subcategory)),
              Expanded(flex: 5, child: cell(GridSort.description)),
              SizedBox(
                width: GridLayout.amountW,
                child: cell(GridSort.amount, right: true),
              ),
              SizedBox(width: GridLayout.statusW, child: cell(GridSort.status)),
              const SizedBox(width: GridLayout.actionW),
            ],
          ),
          // Linha neon sob o cabeçalho.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [p.neon, p.neon2, p.neon.withValues(alpha: 0)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: p.neon.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Moldura de uma linha: listra de tipo à esquerda, zebra, foco e seleção.
class GridRowShell extends StatelessWidget {
  final Color accent;
  final bool zebra;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final double? height;
  final Widget child;
  const GridRowShell({
    super.key,
    required this.accent,
    required this.child,
    this.zebra = false,
    this.selected = false,
    this.dimmed = false,
    this.onTap,
    this.onDoubleTap,
    this.height,
  });

  /// Sem altura fixa (celular), a listra acompanha a altura do conteúdo.
  Widget _intrinsic(Widget row) =>
      height == null ? IntrinsicHeight(child: row) : row;

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    return Material(
      color: selected
          ? p.neon.withValues(alpha: 0.12)
          : zebra
          ? p.zebra
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        hoverColor: p.hover,
        splashColor: p.neon.withValues(alpha: 0.10),
        highlightColor: p.neon.withValues(alpha: 0.06),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.line, width: 0.6)),
          ),
          child: _intrinsic(
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: selected ? p.neon : accent.withValues(alpha: 0.85),
                    boxShadow: [
                      BoxShadow(
                        color: (selected ? p.neon : accent).withValues(
                          alpha: 0.55,
                        ),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Opacity(opacity: dimmed ? 0.55 : 1, child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Célula de texto de uma linha da grade.
class GridCell extends StatelessWidget {
  final Widget child;
  final bool right;
  final Color? background;
  const GridCell({
    super.key,
    required this.child,
    this.right = false,
    this.background,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: background,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: right ? Alignment.centerRight : Alignment.centerLeft,
    child: child,
  );
}

/// Indicador de status com ponto luminoso; vira botão quando [onTap] existe.
class NeonStatus extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool done;
  const NeonStatus({
    super.key,
    required this.label,
    required this.color,
    this.onTap,
    this.tooltip,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          done
              ? Icon(Icons.check_rounded, size: 12, color: color)
              : Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.8),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Tooltip(
      message: tooltip ?? '',
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: pill,
        ),
      ),
    );
  }
}
