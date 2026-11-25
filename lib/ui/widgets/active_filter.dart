import 'package:flutter/material.dart';

import 'filters_panel.dart';

/// Filtro de situação das telas de cadastro (Contas, Cartões): mostra só os
/// ativos (padrão), só os inativos ou todos.
enum ActiveFilter {
  active('Ativos'),
  inactive('Inativos'),
  all('Todos');

  final String label;
  const ActiveFilter(this.label);

  bool matches(bool isActive) => switch (this) {
    ActiveFilter.active => isActive,
    ActiveFilter.inactive => !isActive,
    ActiveFilter.all => true,
  };

  /// Conta como filtro aplicado só quando difere do padrão (Ativos).
  int get count => this == ActiveFilter.active ? 0 : 1;
}

/// Campo "Situação" do painel de filtros (escolha única, sempre com valor).
class ActiveFilterField extends StatelessWidget {
  final String keyName;
  final ActiveFilter value;
  final ValueChanged<ActiveFilter> onChanged;
  const ActiveFilterField({
    super.key,
    required this.keyName,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => FilterSelect<ActiveFilter>(
    keyName: keyName,
    label: 'Situação',
    allLabel: null,
    multiple: false,
    selected: {value},
    active: value != ActiveFilter.active,
    onClear: () => onChanged(ActiveFilter.active),
    options: {for (final f in ActiveFilter.values) f: f.label},
    onChanged: (v) => onChanged(v.isEmpty ? ActiveFilter.active : v.first),
  );
}
