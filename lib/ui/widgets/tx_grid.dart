import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Colunas da grade. Cada uma pode ser ordenada, ocultada, reordenada e
/// redimensionada pelo usuário (ver [GridColumnsConfig]).
enum GridColumn {
  date('Data', 96, 72),
  dueDate('Vencimento', 104, 80),
  category('Categoria', 170, 90),
  subcategory('Subcategoria', 150, 80),
  description('Descrição', 300, 120),
  notes('Observações', 220, 90),
  amount('Valor', 136, 96, right: true),
  status('Status', 116, 96);

  final String label;
  final double defaultWidth;
  final double minWidth;
  final bool right;
  const GridColumn(
    this.label,
    this.defaultWidth,
    this.minWidth, {
    this.right = false,
  });

  static const maxWidth = 640.0;

  /// Colunas de texto, que cedem espaço quando a tela é estreita.
  bool get flexible =>
      this == category ||
      this == subcategory ||
      this == description ||
      this == notes;
}

/// Preferência de uma coluna: visível ou não e largura em pixels.
class GridColumnSetting {
  final GridColumn column;
  final bool visible;
  final double width;
  GridColumnSetting(this.column, {this.visible = true, double? width})
    : width = width ?? column.defaultWidth;

  GridColumnSetting copyWith({bool? visible, double? width}) =>
      GridColumnSetting(
        column,
        visible: visible ?? this.visible,
        width: width ?? this.width,
      );
}

/// Ordem, visibilidade e largura das colunas da grade de transações. Fica
/// salva nas preferências do usuário ([AppSettings.txGridColumns]).
class GridColumnsConfig {
  final List<GridColumnSetting> columns;
  const GridColumnsConfig(this.columns);

  static final standard = GridColumnsConfig([
    for (final c in GridColumn.values) GridColumnSetting(c),
  ]);

  List<GridColumnSetting> get visible =>
      columns.where((c) => c.visible).toList();

  bool isVisible(GridColumn c) =>
      columns.any((s) => s.column == c && s.visible);

  GridColumnsConfig _map(
    GridColumn c,
    GridColumnSetting Function(GridColumnSetting) f,
  ) => GridColumnsConfig([for (final s in columns) s.column == c ? f(s) : s]);

  GridColumnsConfig withWidth(GridColumn c, double w) => _map(
    c,
    (s) => s.copyWith(width: w.clamp(c.minWidth, GridColumn.maxWidth)),
  );

  /// Ao menos uma coluna continua visível.
  GridColumnsConfig withVisible(GridColumn c, bool v) {
    if (!v && visible.length <= 1) return this;
    return _map(c, (s) => s.copyWith(visible: v));
  }

  /// Move a coluna da posição [from] para a posição final [to].
  GridColumnsConfig moved(int from, int to) {
    final list = [...columns];
    final item = list.removeAt(from);
    list.insert(to.clamp(0, list.length), item);
    return GridColumnsConfig(list);
  }

  List<Map<String, Object?>> toJson() => [
    for (final s in columns)
      {'id': s.column.name, 'visible': s.visible, 'width': s.width},
  ];

  /// Tolerante: ignora colunas desconhecidas e acrescenta as novas (como
  /// Observações para quem já tinha salvo a grade) na posição padrão.
  factory GridColumnsConfig.fromJson(Object? json) {
    if (json is! List) return standard;
    final out = <GridColumnSetting>[];
    for (final j in json) {
      if (j is! Map) continue;
      final c = GridColumn.values.where((c) => c.name == j['id']).firstOrNull;
      if (c == null || out.any((s) => s.column == c)) continue;
      final w = (j['width'] as num?)?.toDouble();
      out.add(
        GridColumnSetting(
          c,
          visible: j['visible'] as bool? ?? true,
          width: w?.clamp(c.minWidth, GridColumn.maxWidth),
        ),
      );
    }
    for (final c in GridColumn.values) {
      if (out.any((s) => s.column == c)) continue;
      out.insert(c.index.clamp(0, out.length), GridColumnSetting(c));
    }
    if (!out.any((s) => s.visible)) return standard;
    return GridColumnsConfig(out);
  }
}

/// Geometria da grade para a largura disponível: colunas visíveis com a
/// largura final. A sobra de espaço vai para Descrição (ou Observações);
/// se faltar espaço, a grade rola na horizontal.
class GridLayout {
  /// Celular: linhas de duas linhas, sem cabeçalho de colunas.
  final bool compact;
  final GridColumnsConfig config;
  final List<(GridColumn, double)> cells;
  final double totalWidth;

  const GridLayout._(this.compact, this.config, this.cells, this.totalWidth);

  factory GridLayout.of(double width, GridColumnsConfig config) {
    final vis = config.visible;
    var sum = stripeW + actionW;
    var slack = 0.0; // quanto as colunas de texto podem encolher
    for (final s in vis) {
      sum += s.width;
      if (s.column.flexible) slack += s.width - s.column.minWidth;
    }
    final extra = width > sum ? width - sum : 0.0;
    // Falta espaço: encolhe as colunas de texto proporcionalmente até o
    // mínimo de cada uma; só depois a grade passa a rolar na horizontal.
    final deficit = width < sum ? sum - width : 0.0;
    final shrink = slack <= 0 ? 0.0 : (deficit / slack).clamp(0.0, 1.0);
    final grow = config.isVisible(GridColumn.description)
        ? GridColumn.description
        : config.isVisible(GridColumn.notes)
        ? GridColumn.notes
        : vis.last.column;
    double sized(GridColumnSetting s) {
      if (s.column == grow && extra > 0) return s.width + extra;
      if (!s.column.flexible) return s.width;
      return s.width - (s.width - s.column.minWidth) * shrink;
    }

    return GridLayout._(width < 640, config, [
      for (final s in vis) (s.column, sized(s)),
    ], sum + extra - slack * shrink);
  }

  bool shows(GridColumn c) => config.isVisible(c);

  static const stripeW = 3.0;
  static const actionW = 40.0;
  static const rowH = 36.0;
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

/// Cabeçalho escuro da grade, com sublinhado neon, ordenação por clique,
/// alça para ajustar a largura de cada coluna e botão de configuração.
class GridHeader extends StatelessWidget {
  final GridLayout layout;
  final GridColumn sort;
  final bool ascending;
  final ValueChanged<GridColumn> onSort;

  /// Arrasto da borda direita de uma coluna (delta em pixels).
  final void Function(GridColumn column, double delta) onResize;
  final VoidCallback onResizeEnd;
  final VoidCallback onConfigure;
  const GridHeader({
    super.key,
    required this.layout,
    required this.sort,
    required this.ascending,
    required this.onSort,
    required this.onResize,
    required this.onResizeEnd,
    required this.onConfigure,
  });

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    Widget cell(GridColumn s) {
      final active = s == sort;
      final style = context.text.labelSmall?.copyWith(
        color: active ? p.neon : p.headerText,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      );
      return Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              key: ValueKey('grid-sort-${s.name}'),
              onTap: () => onSort(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: s.right
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
                          ? (ascending
                                ? Icons.arrow_drop_up
                                : Icons.arrow_drop_down)
                          : Icons.unfold_more,
                      size: active ? 18 : 13,
                      color: active
                          ? p.neon
                          : p.headerText.withValues(alpha: 0.45),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Alça de redimensionamento na borda direita.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 9,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                key: ValueKey('grid-resize-${s.name}'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => onResize(s, d.delta.dx),
                onHorizontalDragEnd: (_) => onResizeEnd(),
                child: Center(
                  child: Container(
                    width: 1,
                    height: 16,
                    color: p.headerText.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ),
          ),
        ],
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
              const SizedBox(width: GridLayout.stripeW),
              for (final (c, w) in layout.cells)
                SizedBox(width: w, child: cell(c)),
              SizedBox(
                width: GridLayout.actionW,
                child: IconButton(
                  key: const ValueKey('grid-configure'),
                  tooltip: 'Configurar colunas',
                  iconSize: 17,
                  color: p.headerText,
                  icon: const Icon(Icons.view_column_outlined),
                  onPressed: onConfigure,
                ),
              ),
            ],
          ),
          // Linha neon sob o cabeçalho.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2,
            child: IgnorePointer(
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
          ),
        ],
      ),
    );
  }
}

/// Folha para escolher, ordenar e dimensionar as colunas da grade.
class GridColumnsSheet extends StatefulWidget {
  final GridColumnsConfig initial;
  const GridColumnsSheet({super.key, required this.initial});

  @override
  State<GridColumnsSheet> createState() => _GridColumnsSheetState();
}

class _GridColumnsSheetState extends State<GridColumnsSheet> {
  late GridColumnsConfig cfg = widget.initial;

  @override
  Widget build(BuildContext context) {
    final cols = cfg.columns;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Colunas da grade', style: context.text.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Marque as colunas que quer ver, arraste para mudar a ordem e '
              'ajuste a largura. Na grade, você também pode arrastar a borda '
              'do cabeçalho.',
              style: context.text.bodySmall?.copyWith(
                color: context.fin.subtle,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: cols.length,
                onReorderItem: (a, b) => setState(() => cfg = cfg.moved(a, b)),
                itemBuilder: (context, i) {
                  final s = cols[i];
                  final c = s.column;
                  return Row(
                    key: ValueKey('col-${c.name}'),
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_indicator),
                        ),
                      ),
                      Checkbox(
                        key: ValueKey('col-visible-${c.name}'),
                        value: s.visible,
                        onChanged: (v) => setState(
                          () => cfg = cfg.withVisible(c, v ?? false),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(c.label, overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        child: Slider(
                          value: s.width.clamp(c.minWidth, GridColumn.maxWidth),
                          min: c.minWidth,
                          max: GridColumn.maxWidth,
                          onChanged: s.visible
                              ? (v) => setState(() => cfg = cfg.withWidth(c, v))
                              : null,
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${s.width.round()}',
                          textAlign: TextAlign.right,
                          style: context.text.labelSmall,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => cfg = GridColumnsConfig.standard),
                  child: const Text('Restaurar padrão'),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('grid-columns-save'),
                  onPressed: () => Navigator.pop(context, cfg),
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ],
        ),
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

  /// Mostra a seta de lista suspensa (o toque abre a lista de status).
  final bool dropdown;
  const NeonStatus({
    super.key,
    required this.label,
    required this.color,
    this.onTap,
    this.tooltip,
    this.done = false,
    this.dropdown = false,
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
          if (dropdown && onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 14, color: color),
          ],
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

/// Realce de uma célula editável: contorno neon ao passar o mouse, para
/// indicar que o clique edita o campo ali mesmo.
class _EditableHover extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;
  const _EditableHover({
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  @override
  State<_EditableHover> createState() => _EditableHoverState();
}

class _EditableHoverState extends State<_EditableHover> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 700),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(
                color: hover
                    ? p.neon.withValues(alpha: 0.55)
                    : Colors.transparent,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Campo de texto editável direto na grade, como numa planilha: um clique
/// abre a edição; Enter ou clicar fora grava; Esc desfaz.
class InlineTextCell extends StatefulWidget {
  /// Texto inicial do editor (ex.: valor sem "R$").
  final String value;

  /// O que a célula mostra fora da edição.
  final Widget display;
  final bool right;
  final Color? background;
  final TextInputType? keyboardType;
  final String hint;

  /// Devolve a mensagem de erro, ou null quando o texto é válido.
  final String? Function(String text)? validate;
  final Future<void> Function(String text) onSubmit;

  /// Sem o preenchimento lateral da [GridCell] (linhas do celular).
  final bool dense;
  const InlineTextCell({
    super.key,
    required this.value,
    required this.display,
    required this.onSubmit,
    this.right = false,
    this.background,
    this.keyboardType,
    this.hint = '',
    this.validate,
    this.dense = false,
  });

  @override
  State<InlineTextCell> createState() => _InlineTextCellState();
}

class _InlineTextCellState extends State<InlineTextCell> {
  bool editing = false;
  String? error;
  final ctrl = TextEditingController();
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus && editing) _commit();
    });
  }

  @override
  void dispose() {
    ctrl.dispose();
    focus.dispose();
    super.dispose();
  }

  void _start() {
    ctrl.text = widget.value;
    ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: ctrl.text.length,
    );
    setState(() {
      editing = true;
      error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editing) focus.requestFocus();
    });
  }

  void _cancel() {
    if (!editing) return;
    setState(() {
      editing = false;
      error = null;
    });
  }

  Future<void> _commit() async {
    if (!editing) return;
    final text = ctrl.text.trim();
    if (text == widget.value.trim()) return _cancel();
    final err = widget.validate?.call(text);
    if (err != null) {
      // Com o foco ainda no campo, mostra o erro; se o usuário saiu, desfaz.
      if (focus.hasFocus) {
        setState(() => error = err);
      } else {
        _cancel();
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(err)));
      }
      return;
    }
    setState(() {
      editing = false;
      error = null;
    });
    await widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.symmetric(horizontal: widget.dense ? 0 : 10);
    if (!editing) {
      return _EditableHover(
        tooltip: 'Clique para editar',
        onTap: _start,
        child: Container(
          color: widget.background,
          padding: pad,
          alignment: widget.right
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: widget.display,
        ),
      );
    }
    final p = GridPalette.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(
        color: error != null ? context.fin.negative : p.neon,
        width: 1.4,
      ),
    );
    return Container(
      color: widget.background,
      padding: EdgeInsets.symmetric(
        horizontal: widget.dense ? 0 : 3,
        vertical: widget.dense ? 0 : 3,
      ),
      alignment: Alignment.center,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
        child: TextField(
          controller: ctrl,
          focusNode: focus,
          keyboardType: widget.keyboardType,
          textAlign: widget.right ? TextAlign.right : TextAlign.left,
          style: context.text.bodyMedium,
          // Enter grava sem tirar o foco antes (para mostrar o erro).
          onEditingComplete: () {},
          onSubmitted: (_) => _commit(),
          onChanged: (_) {
            if (error != null) setState(() => error = null);
          },
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            filled: true,
            fillColor: p.panel,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 7,
            ),
            enabledBorder: border,
            focusedBorder: border,
            border: border,
            errorText: null,
            suffixIcon: error == null
                ? null
                : Tooltip(
                    message: error!,
                    child: Icon(
                      Icons.error_outline,
                      size: 16,
                      color: context.fin.negative,
                    ),
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 22,
              minHeight: 16,
            ),
          ),
        ),
      ),
    );
  }
}

/// Célula que abre um menu de opções (categoria, subcategoria) ou outro
/// seletor (data) ao ser clicada.
class InlinePickerCell extends StatelessWidget {
  final Widget display;
  final Future<void> Function(BuildContext cellContext) onPick;
  final String tooltip;
  final bool dense;
  const InlinePickerCell({
    super.key,
    required this.display,
    required this.onPick,
    this.tooltip = 'Clique para alterar',
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) => Builder(
    builder: (cellContext) => _EditableHover(
      tooltip: tooltip,
      onTap: () => onPick(cellContext),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 10),
        alignment: Alignment.centerLeft,
        child: display,
      ),
    ),
  );
}

/// Opção de um menu de [showCellMenu].
class CellMenuOption<T> {
  final T value;
  final String label;
  final Color? color;
  final bool indent;
  final bool selected;
  const CellMenuOption(
    this.value,
    this.label, {
    this.color,
    this.indent = false,
    this.selected = false,
  });
}

/// Abre um menu logo abaixo da célula e devolve a opção escolhida.
Future<T?> showCellMenu<T>(
  BuildContext cellContext,
  List<CellMenuOption<T>> options,
) {
  final box = cellContext.findRenderObject()! as RenderBox;
  final overlay =
      Overlay.of(cellContext).context.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(
    Offset(0, box.size.height),
    ancestor: overlay,
  );
  final rect = RelativeRect.fromRect(
    topLeft & Size(box.size.width, 0),
    Offset.zero & overlay.size,
  );
  final p = GridPalette.of(cellContext);
  return showMenu<T>(
    context: cellContext,
    position: rect,
    constraints: BoxConstraints(
      minWidth: box.size.width.clamp(180, 320),
      maxWidth: 320,
      maxHeight: 420,
    ),
    items: [
      for (final o in options)
        PopupMenuItem<T>(
          value: o.value,
          height: 36,
          padding: EdgeInsets.only(left: o.indent ? 28 : 12, right: 12),
          child: Row(
            children: [
              if (o.color != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: o.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  o.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: o.selected
                      ? TextStyle(color: p.neon, fontWeight: FontWeight.w700)
                      : null,
                ),
              ),
              if (o.selected) Icon(Icons.check, size: 16, color: p.neon),
            ],
          ),
        ),
    ],
  );
}
