/// Organização do menu lateral: as seções, na ordem, e os destinos de cada
/// uma. O padrão vem do app; o usuário pode mudar a ordem, mover destinos
/// entre seções, renomear seções e criar as suas ([AppSettings.menuLayout]).
class MenuSection {
  final String id;

  /// Nome escolhido pelo usuário (nulo = nome padrão da seção).
  final String? label;

  /// Ids dos destinos, na ordem do menu.
  final List<String> items;

  const MenuSection(this.id, this.items, {this.label});

  /// Seção criada pelo usuário (as do app não podem ser excluídas).
  bool get isCustom => id.startsWith(customPrefix);

  static const customPrefix = 'custom-';

  MenuSection copyWith({String? label, List<String>? items}) =>
      MenuSection(id, items ?? this.items, label: label ?? this.label);

  Map<String, Object?> toJson() => {
    'id': id,
    if (label != null) 'label': label,
    'items': items,
  };
}

class MenuLayout {
  MenuLayout._();

  static List<Object?> toJson(List<MenuSection> sections) => [
    for (final s in sections) s.toJson(),
  ];

  /// Aplica a organização salva [saved] sobre o padrão [defaults]. Tolera
  /// dados antigos: destinos desconhecidos ou repetidos são ignorados;
  /// seções e destinos novos do app (que o usuário ainda não viu) entram no
  /// lugar padrão, no fim.
  static List<MenuSection> resolve(
    List<MenuSection> defaults,
    List<Object?>? saved,
  ) {
    if (saved == null || saved.isEmpty) return defaults;
    final known = {for (final s in defaults) ...s.items};
    final defaultIds = {for (final s in defaults) s.id};
    final placed = <String>{};
    final seen = <String>{};
    final out = <MenuSection>[];
    for (final raw in saved) {
      if (raw is! Map) continue;
      final id = raw['id'];
      if (id is! String || !seen.add(id)) continue;
      if (!defaultIds.contains(id) &&
          !id.startsWith(MenuSection.customPrefix)) {
        continue;
      }
      final label = raw['label'];
      final items = <String>[
        for (final i
            in (raw['items'] is List ? raw['items'] as List : const []))
          if (i is String && known.contains(i) && placed.add(i)) i,
      ];
      out.add(
        MenuSection(
          id,
          items,
          label: label is String && label.trim().isNotEmpty
              ? label.trim()
              : null,
        ),
      );
    }
    for (final d in defaults) {
      final missing = [
        for (final i in d.items)
          if (!placed.contains(i)) i,
      ];
      final at = out.indexWhere((s) => s.id == d.id);
      if (at < 0) {
        out.add(MenuSection(d.id, missing));
      } else if (missing.isNotEmpty) {
        out[at] = out[at].copyWith(items: [...out[at].items, ...missing]);
      }
    }
    return out;
  }
}
