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

/// Painel de filtros recolhível com contador de filtros ativos e
/// botão Limpar (mesmo padrão da tela de Faturas)..
class FiltersPanel extends StatelessWidget {
  final bool open;
  final int active;
  final VoidCallback onToggle;
  final VoidCallback onClear;
  final Widget child;

  /// Prefixo das chaves dos botões (testes).
  final String keyPrefix;
  const FiltersPanel({
    super.key,
    required this.keyPrefix,
    required this.open,
    required this.active,
    required this.onToggle,
    required this.onClear,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final p = GridPalette.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('$keyPrefix-filters-toggle'),
            borderRadius: BorderRadius.circular(16),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: [
                  Icon(Icons.filter_list, size: 18, color: p.neon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Filtros',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleSmall,
                          ),
                        ),
                        if (active > 0) ...[
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
                              '$active ${active == 1 ? 'ativo' : 'ativos'}',
                              style: context.text.labelSmall?.copyWith(
                                color: p.neon,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (active > 0)
                    TextButton(
                      key: ValueKey('$keyPrefix-filters-clear'),
                      onPressed: onClear,
                      child: Text(
                        filterStyleOf(context) == FilterStyle.checklist
                            ? 'Limpar tudo'
                            : 'Limpar',
                      ),
                    ),
                  const FilterStyleToggle(),
                  IconButton(
                    tooltip: open ? 'Recolher filtros' : 'Mostrar filtros',
                    onPressed: onToggle,
                    icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// Lista suspensa compacta usada dentro do [FiltersPanel].
class FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  final double width;
  const FilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 190,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    ),
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
      width: w.width,
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
      width: width,
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
