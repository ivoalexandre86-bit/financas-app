import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/auth_controller.dart';
import '../../../state/finance_controller.dart';
import '../../app_shell.dart';
import '../../menu_layout.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Organiza o menu lateral: arrastar destinos para mudar a ordem ou levá-los
/// a outra seção, mover seções para cima/baixo, renomear, criar e excluir
/// seções, e voltar ao padrão. Cada mudança é salva na hora nas preferências
/// do usuário (sincronizadas entre aparelhos).
class MenuEditorScreen extends StatefulWidget {
  const MenuEditorScreen({super.key});

  @override
  State<MenuEditorScreen> createState() => _MenuEditorScreenState();
}

/// Linha da lista: cabeçalho de seção ([item] nulo) ou destino.
typedef _Row = ({String section, String? item});

class _MenuEditorScreenState extends State<MenuEditorScreen> {
  late List<MenuSection> sections = MenuLayout.resolve(
    defaultMenuSections,
    context.read<FinanceController>().data.settings.menuLayout,
  );

  bool _visible(String id, bool isAdmin) =>
      isAdmin || !(menuDest(id)?.adminOnly ?? false);

  void _save(List<MenuSection> next) {
    setState(() => sections = next);
    context.read<FinanceController>().saveMenuLayout(MenuLayout.toJson(next));
  }

  List<_Row> _rows(bool isAdmin) => [
    for (final s in sections) ...[
      (section: s.id, item: null),
      for (final i in s.items)
        if (_visible(i, isAdmin)) (section: s.id, item: i),
    ],
  ];

  /// Remonta as seções a partir da lista na nova ordem: cada destino fica na
  /// seção do cabeçalho acima dele. Destinos ocultos (só para
  /// administradores) continuam onde estavam.
  void _fromRows(List<_Row> rows, bool isAdmin) {
    final items = <String, List<String>>{for (final s in sections) s.id: []};
    String? current;
    for (final r in rows) {
      if (r.item == null) {
        current = r.section;
      } else {
        items[current ?? sections.first.id]!.add(r.item!);
      }
    }
    _save([
      for (final s in sections)
        s.copyWith(
          items: [
            ...items[s.id]!,
            for (final i in s.items)
              if (!_visible(i, isAdmin)) i,
          ],
        ),
    ]);
  }

  void _reorder(int from, int to, bool isAdmin) {
    final rows = _rows(isAdmin);
    if (rows[from].item == null) return;
    final r = rows.removeAt(from);
    // Nada pode ficar acima da primeira seção.
    rows.insert(to < 1 ? 1 : to, r);
    _fromRows(rows, isAdmin);
  }

  /// Sobe ([delta] = -1) ou desce (+1) a tela uma posição. Na ponta da
  /// seção, passa para a seção vizinha.
  void _step(int index, int delta, bool isAdmin) {
    final rows = _rows(isAdmin);
    final to = index + delta;
    if (to < 1 || to >= rows.length) return;
    final r = rows[index];
    rows[index] = rows[to];
    rows[to] = r;
    _fromRows(rows, isAdmin);
  }

  void _moveTo(String item, String section) => _save([
    for (final s in sections)
      s.copyWith(
        items: [
          for (final i in s.items)
            if (i != item) i,
          if (s.id == section) item,
        ],
      ),
  ]);

  void _moveSection(int at, int delta) {
    final next = [...sections];
    final s = next.removeAt(at);
    next.insert(at + delta, s);
    _save(next);
  }

  String _label(MenuSection s) => menuGroupFor(s).label;

  Future<String?> _askName(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('menu-section-name'),
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome da seção'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(MenuSection s) async {
    final name = (await _askName('Renomear seção', _label(s)))?.trim();
    if (name == null || name.isEmpty) return;
    _save([
      for (final x in sections)
        x.id == s.id ? MenuSection(x.id, x.items, label: name) : x,
    ]);
  }

  Future<void> _add() async {
    final name = (await _askName('Nova seção', ''))?.trim();
    if (name == null || name.isEmpty) return;
    final id =
        '${MenuSection.customPrefix}${DateTime.now().microsecondsSinceEpoch}';
    _save([...sections, MenuSection(id, const [], label: name)]);
  }

  /// Exclui uma seção criada pelo usuário; os destinos dela voltam para a
  /// seção padrão de cada um.
  void _delete(MenuSection s) {
    String home(String item) =>
        defaultMenuSections.firstWhere((d) => d.items.contains(item)).id;
    _save([
      for (final x in sections)
        if (x.id != s.id)
          x.copyWith(
            items: [
              ...x.items,
              for (final i in s.items)
                if (home(i) == x.id) i,
            ],
          ),
    ]);
  }

  Future<void> _reset() async {
    final ok = await confirmDialog(
      context,
      title: 'Voltar ao padrão?',
      message: 'O menu volta à organização original e as seções criadas por você são removidas.',
      confirm: 'Voltar ao padrão',
    );
    if (!ok || !mounted) return;
    setState(() => sections = defaultMenuSections);
    context.read<FinanceController>().saveMenuLayout(null);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthController>().user?.isAdmin ?? false;
    final rows = _rows(isAdmin);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizar menu'),
        actions: [
          TextButton.icon(
            key: const ValueKey('menu-reset'),
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Padrão'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('menu-add-section'),
        onPressed: _add,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Nova seção'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(bottom: 96),
            header: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Use as setas ↑ ↓ de cada tela para mudar a ordem (na ponta, '
                'ela passa para a seção vizinha), ou arraste pela alça ≡. As '
                'setas das seções movem a seção inteira. Início fica sempre '
                'no topo; seções vazias não aparecem no menu.',
                style: context.text.bodySmall?.copyWith(
                  color: context.fin.subtle,
                ),
              ),
            ),
            itemCount: rows.length,
            onReorderItem: (from, to) => _reorder(from, to, isAdmin),
            itemBuilder: (context, i) {
              final r = rows[i];
              if (r.item == null) {
                final at = sections.indexWhere((s) => s.id == r.section);
                return _header(context, sections[at], at);
              }
              return _item(
                context,
                r.item!,
                r.section,
                i,
                first: i == 1,
                last: i == rows.length - 1,
                isAdmin: isAdmin,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, MenuSection s, int at) {
    final g = menuGroupFor(s);
    return Container(
      key: ValueKey('menu-edit-section-${s.id}'),
      margin: EdgeInsets.only(top: at == 0 ? 0 : 12),
      color: context.colors.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(g.icon),
        title: Text(
          g.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: s.items.isEmpty
            ? const Text('Vazia: não aparece no menu')
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: ValueKey('menu-section-up-${s.id}'),
              tooltip: 'Mover seção para cima',
              icon: const Icon(Icons.arrow_upward),
              onPressed: at == 0 ? null : () => _moveSection(at, -1),
            ),
            IconButton(
              key: ValueKey('menu-section-down-${s.id}'),
              tooltip: 'Mover seção para baixo',
              icon: const Icon(Icons.arrow_downward),
              onPressed: at == sections.length - 1
                  ? null
                  : () => _moveSection(at, 1),
            ),
            IconButton(
              key: ValueKey('menu-section-rename-${s.id}'),
              tooltip: 'Renomear',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(s),
            ),
            if (s.isCustom)
              IconButton(
                key: ValueKey('menu-section-delete-${s.id}'),
                tooltip: 'Excluir seção',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(s),
              ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    String id,
    String section,
    int index, {
    required bool first,
    required bool last,
    required bool isAdmin,
  }) {
    final d = menuDest(id)!;
    return ListTile(
      key: ValueKey('menu-edit-item-$id'),
      contentPadding: const EdgeInsets.only(left: 40, right: 8),
      leading: Icon(d.icon),
      title: Text(d.label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('menu-item-up-$id'),
            tooltip: 'Subir',
            icon: const Icon(Icons.arrow_upward),
            onPressed: first ? null : () => _step(index, -1, isAdmin),
          ),
          IconButton(
            key: ValueKey('menu-item-down-$id'),
            tooltip: 'Descer',
            icon: const Icon(Icons.arrow_downward),
            onPressed: last ? null : () => _step(index, 1, isAdmin),
          ),
          PopupMenuButton<String>(
            key: ValueKey('menu-move-$id'),
            tooltip: 'Mover para outra seção',
            icon: const Icon(Icons.drive_file_move_outlined),
            onSelected: (to) => _moveTo(id, to),
            itemBuilder: (_) => [
              for (final s in sections)
                if (s.id != section)
                  PopupMenuItem(value: s.id, child: Text(_label(s))),
            ],
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ],
      ),
    );
  }
}
