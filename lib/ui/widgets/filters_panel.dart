import 'package:flutter/material.dart';

import '../theme.dart';
import 'tx_grid.dart';

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
                      child: const Text('Limpar'),
                    ),
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
