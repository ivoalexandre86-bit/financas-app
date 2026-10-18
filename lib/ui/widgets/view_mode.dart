import 'package:flutter/material.dart';

/// Como uma lista é exibida: grade (tabela) ou cartões.
enum ViewMode { grid, cards }

/// Botão da barra superior que alterna entre grade e cartões.
class ViewModeToggle extends StatelessWidget {
  final ViewMode mode;
  final ValueChanged<ViewMode> onChanged;

  /// Prefixo das chaves (`<prefix>-view-grid`, `<prefix>-view-cards`).
  final String keyPrefix;
  const ViewModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
    required this.keyPrefix,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: SegmentedButton<ViewMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        ButtonSegment(
          value: ViewMode.grid,
          icon: Icon(
            Icons.table_rows_outlined,
            key: ValueKey('$keyPrefix-view-grid'),
          ),
          tooltip: 'Grade',
        ),
        ButtonSegment(
          value: ViewMode.cards,
          icon: Icon(
            Icons.view_agenda_outlined,
            key: ValueKey('$keyPrefix-view-cards'),
          ),
          tooltip: 'Cartões',
        ),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
    ),
  );
}
