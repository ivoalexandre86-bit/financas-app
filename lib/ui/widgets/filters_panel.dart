import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/entities.dart';
import '../../state/finance_controller.dart';
import '../theme.dart';
import 'tx_grid.dart';

/// Modelo de filtros escolhido pelo usuário (Preferências ou o botão ao lado
/// de "Filtros"). Fora de um [FinanceController], o modelo original.
FilterStyle filterStyleOf(BuildContext context) {
  try {
    return context.select<FinanceController, FilterStyle>(
      (fc) => fc.data.settings.filterStyle,
    );
  } on ProviderNotFoundException {
    return FilterStyle.classic;
  }
}

/// Botão que alterna entre os dois modelos de filtro.
class FilterStyleToggle extends StatelessWidget {
  const FilterStyleToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final style = filterStyleOf(context);
    final checklist = style == FilterStyle.checklist;
    return IconButton(
      key: const ValueKey('filter-style-toggle'),
      tooltip: checklist
          ? 'Usar filtros em listas suspensas'
          : 'Usar filtros em lista com caixas de seleção',
      icon: Icon(
        checklist ? Icons.arrow_drop_down_circle_outlined : Icons.checklist,
      ),
      onPressed: () => context.read<FinanceController>().setFilterStyle(
        checklist ? FilterStyle.classic : FilterStyle.checklist,
      ),
    );
  }
}

/// Botão padrão de filtros, sempre no canto superior direito das telas:
/// ícone com o número de filtros ativos. Abre o [panel] com
/// [showFilterPanel]; enquanto ele está aberto, cada nova versão do painel
/// (a tela se redesenha quando um filtro muda) aparece na hora.
class FilterButton extends StatefulWidget {
  final int active;

  /// Painel aberto pelo botão. Use [onPressed] para abrir outro conteúdo.
  final FilterPanel? panel;
  final VoidCallback? onPressed;

  /// Prefixo da chave (testes): `$keyPrefix-filters`.
  final String keyPrefix;
  const FilterButton({
    super.key,
    required this.keyPrefix,
    required this.active,
    this.panel,
    this.onPressed,
  }) : assert(panel != null || onPressed != null);

  @override
  State<FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends State<FilterButton> {
  late final _panel = ValueNotifier<Widget>(
    widget.panel ?? const SizedBox.shrink(),
  );

  @override
  void didUpdateWidget(FilterButton old) {
    super.didUpdateWidget(old);
    final p = widget.panel;
    if (p == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _panel.value = p;
    });
  }

  @override
  void dispose() {
    _panel.dispose();
    super.dispose();
  }

  void _open() {
    if (widget.panel == null) {
      widget.onPressed!();
      return;
    }
    _panel.value = widget.panel!;
    showFilterPanel<void>(
      context,
      ValueListenableBuilder<Widget>(
        valueListenable: _panel,
        builder: (_, p, _) => p,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: IconButton(
      key: ValueKey('${widget.keyPrefix}-filters'),
      tooltip: 'Filtros',
      onPressed: _open,
      isSelected: widget.active > 0,
      icon: Badge(
        isLabelVisible: widget.active > 0,
        label: Text('${widget.active}'),
        child: const Icon(Icons.filter_list),
      ),
    ),
  );
}

/// Marca os campos que estão dentro do painel de filtros: lá eles ocupam a
/// largura toda.
class FilterPanelScope extends InheritedWidget {
  const FilterPanelScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FilterPanelScope>() != null;

  @override
  bool updateShouldNotify(FilterPanelScope oldWidget) => false;
}

/// Abre o painel de filtros padrão: no computador, um painel à direita;
/// no celular, uma folha que sobe de baixo. [child] é o conteúdo (em geral
/// um [FilterPanel]).
Future<T?> showFilterPanel<T>(BuildContext context, Widget child) {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  final content = FilterPanelScope(child: child);
  if (!wide) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: content,
      ),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar filtros',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          key: const ValueKey('filter-panel'),
          elevation: 8,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(ctx).colorScheme.surfaceContainerLow,
          child: SizedBox(
            width: 420,
            height: MediaQuery.sizeOf(ctx).height - 24,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: content,
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0.15, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// Conteúdo padrão do painel de filtros: título com o número de filtros
/// ativos, botão que troca o modelo (listas suspensas ou lista com caixas),
/// os campos e, no rodapé, Limpar tudo e Fechar. Os filtros valem na hora.
class FilterPanel extends StatelessWidget {
  final String title;
  final int active;
  final VoidCallback onClear;
  final List<Widget> Function(BuildContext context) fields;

  /// Botão principal do rodapé. Padrão: "Pronto" (os filtros já valem).
  final Widget? primary;

  /// Prefixo das chaves (testes).
  final String keyPrefix;
  const FilterPanel({
    this.primary,
    super.key,
    required this.keyPrefix,
    required this.active,
    required this.onClear,
    required this.fields,
    this.title = 'Filtros',
  });

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      final n = active;
      final p = GridPalette.of(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                Icon(Icons.filter_list, size: 20, color: p.neon),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleMedium,
                  ),
                ),
                if (n > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: p.neon.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$n ${n == 1 ? 'ativo' : 'ativos'}',
                      style: context.text.labelSmall?.copyWith(
                        color: p.neon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                const FilterStyleToggle(),
                IconButton(
                  key: ValueKey('$keyPrefix-filters-close'),
                  tooltip: 'Fechar',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              children: [
                for (final (i, w) in fields(context).indexed) ...[
                  if (i > 0) const SizedBox(height: 12),
                  w,
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              16,
              8 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Row(
              children: [
                TextButton(
                  key: ValueKey('$keyPrefix-filters-clear'),
                  onPressed: n > 0 ? onClear : null,
                  child: const Text('Limpar tudo'),
                ),
                const Spacer(),
                primary ??
                    FilledButton(
                      key: ValueKey('$keyPrefix-filters-done'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Pronto'),
                    ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// Grupo de chips de seleção múltipla (modelo original) ou, no modelo
/// "lista com caixas", um [FilterCheckList].
class FilterChipGroup extends StatelessWidget {
  final String label;
  final List<FilterOption> options;
  final VoidCallback onClear;
  final String keyName;
  const FilterChipGroup({
    super.key,
    required this.keyName,
    required this.label,
    required this.options,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (filterStyleOf(context) == FilterStyle.checklist) {
      return FilterCheckList(
        keyName: keyName,
        label: label,
        options: options,
        onClear: onClear,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: context.text.labelLarge?.copyWith(color: context.fin.subtle),
          ),
        ),
        options.isEmpty
            ? Text(
                'Nenhum cadastro',
                style: TextStyle(color: context.fin.subtle),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in options)
                    FilterChip(
                      key: ValueKey('$keyName-${o.key}'),
                      visualDensity: VisualDensity.compact,
                      avatar: o.color == null
                          ? null
                          : CircleAvatar(radius: 5, backgroundColor: o.color),
                      showCheckmark: o.color == null,
                      label: Text(o.label),
                      selected: o.selected,
                      onSelected: (_) => o.onTap(),
                    ),
                ],
              ),
      ],
    );
  }
}

/// Campo de busca padrão do painel de filtros.
class FilterSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final String keyName;
  const FilterSearchField({
    super.key,
    required this.keyName,
    required this.controller,
    required this.onChanged,
    this.hint = 'Buscar descrição',
  });

  @override
  Widget build(BuildContext context) => TextField(
    key: ValueKey(keyName),
    controller: controller,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search),
      hintText: hint,
      isDense: true,
    ),
    onChanged: onChanged,
  );
}

/// Uma opção de um filtro em lista ([FilterCheckList]).
typedef FilterOption = ({
  String key,
  String label,
  Color? color,
  bool selected,
  VoidCallback onTap,
});

/// Bloco de um filtro no modelo "lista com caixas": título, quantos valores
/// estão marcados, botão Limpar só deste filtro e a lista de opções com
/// caixas de seleção (ou botões de opção quando [radio], para filtros de
/// escolha única). Com muitas opções aparece uma busca.
class FilterCheckList extends StatefulWidget {
  final String label;
  final List<FilterOption> options;

  /// Limpa só este filtro. Nulo = sem botão.
  final VoidCallback? onClear;

  /// Mostra o botão Limpar (padrão: alguma opção marcada).
  final bool? active;
  final bool radio;
  final double width;

  /// Prefixo das chaves (testes): `$keyName-clear` e `$keyName-<opção>`.
  final String keyName;
  const FilterCheckList({
    super.key,
    required this.keyName,
    required this.label,
    required this.options,
    this.onClear,
    this.active,
    this.radio = false,
    this.width = 250,
  });

  @override
  State<FilterCheckList> createState() => _FilterCheckListState();
}

class _FilterCheckListState extends State<FilterCheckList> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    final w = widget;
    final count = w.options.where((o) => o.selected).length;
    final active = w.active ?? count > 0;
    final q = query.trim().toLowerCase();
    final shown = q.isEmpty
        ? w.options
        : w.options.where((o) => o.label.toLowerCase().contains(q)).toList();
    return Container(
      key: ValueKey('${w.keyName}-checklist'),
      width: FilterPanelScope.of(context) ? double.infinity : w.width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    w.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge,
                  ),
                ),
                if (count > 0 && !w.radio) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: p.neon.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: context.text.labelSmall?.copyWith(
                        color: p.neon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (active && w.onClear != null)
                  TextButton(
                    key: ValueKey('${w.keyName}-clear'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: w.onClear,
                    child: const Text('Limpar'),
                  ),
              ],
            ),
          ),
          if (w.options.length > 8)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 4),
              child: TextField(
                key: ValueKey('${w.keyName}-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Buscar',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
          if (w.options.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Nenhum cadastro',
                style: TextStyle(color: context.fin.subtle),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 232),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final o in shown)
                  InkWell(
                    key: ValueKey('${w.keyName}-${o.key}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: o.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: Center(
                              child: w.radio
                                  ? Icon(
                                      o.selected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      size: 20,
                                      color: o.selected
                                          ? context.colors.primary
                                          : context.fin.subtle,
                                    )
                                  : Checkbox(
                                      value: o.selected,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (_) => o.onTap(),
                                    ),
                            ),
                          ),
                          if (o.color != null) ...[
                            CircleAvatar(radius: 5, backgroundColor: o.color),
                            const SizedBox(width: 8),
                          ] else
                            const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              o.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Many {
  const _Many();
}

/// Um filtro de grade que segue o modelo escolhido pelo usuário:
/// lista suspensa (modelo original, um valor por vez) ou lista com caixas
/// de seleção (vários valores, com Limpar próprio).
///
/// [selected] vazio = sem filtro (mostra [allLabel]). Com [multiple] falso o
/// filtro é de escolha única (botões de opção na lista).
class FilterSelect<T extends Object> extends StatelessWidget {
  final String label;
  final Map<T, String> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool multiple;

  /// Item "todos" da lista suspensa. Nulo = filtro sempre tem um valor.
  final String? allLabel;

  /// Limpa o filtro (padrão: `onChanged({})`).
  final VoidCallback? onClear;

  /// Filtro ativo (mostra Limpar). Padrão: algo marcado.
  final bool? active;
  final Map<T, Color>? colors;
  final double width;

  /// Chave base (testes).
  final String keyName;
  const FilterSelect({
    super.key,
    required this.keyName,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multiple = true,
    this.allLabel = 'Todos',
    this.onClear,
    this.active,
    this.colors,
    this.width = 190,
  });

  @override
  Widget build(BuildContext context) {
    if (filterStyleOf(context) == FilterStyle.checklist) {
      return FilterCheckList(
        keyName: keyName,
        label: label,
        radio: !multiple,
        active: active,
        onClear: onClear ?? () => onChanged({}),
        width: width < 250 ? 250 : width,
        options: [
          for (final MapEntry(:key, :value) in options.entries)
            (
              key: _keyOf(key),
              label: value,
              color: colors?[key],
              selected: selected.contains(key),
              onTap: () {
                if (!multiple) {
                  onChanged(
                    selected.contains(key) && allLabel != null ? {} : {key},
                  );
                } else {
                  onChanged(
                    selected.contains(key)
                        ? ({...selected}..remove(key))
                        : {...selected, key},
                  );
                }
              },
            ),
        ],
      );
    }
    final Object? value = selected.isEmpty
        ? null
        : selected.length == 1
        ? selected.first
        : const _Many();
    final items = <Object?, String>{
      null: ?allLabel,
      ...options,
      if (value is _Many) value: '${selected.length} selecionados',
    };
    return SizedBox(
      width: FilterPanelScope.of(context) ? double.infinity : width,
      child: DropdownButtonFormField<Object?>(
        key: ValueKey('$keyName-dropdown-${value is _Many ? 'many' : value}'),
        initialValue: items.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(
              value: e.key,
              enabled: e.key is! _Many,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v is _Many) return;
          onChanged(v == null ? {} : {v as T});
        },
      ),
    );
  }

  static String _keyOf(Object v) => v is Enum ? v.name : '$v';
}
