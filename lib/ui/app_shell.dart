import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../state/auth_controller.dart';
import '../state/finance_controller.dart';
import '../state/shared_controller.dart';
import 'menu_layout.dart';
import 'screens/accounts/accounts_screen.dart';
import 'screens/budgets/budgets_screen.dart';
import 'screens/cards/cards_screen.dart';
import 'screens/cards/invoices_screen.dart';
import 'screens/categories/categories_screen.dart';
import 'screens/dashboards/dashboards_screen.dart';
import 'screens/goals/goals_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/import/expense_import_screen.dart';
import 'screens/installments/installments_screen.dart';
import 'screens/open_finance/open_finance_screen.dart';
import 'screens/projection/projection_screen.dart';
import 'screens/projects/projects_screen.dart';
import 'screens/recurring/recurring_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/shared/shared_screen.dart';
import 'screens/simulations/simulations_screen.dart';
import 'screens/transactions/transactions_screen.dart';
import 'screens/users/users_screen.dart';
import 'widgets/common.dart';

/// Estrutura principal com o menu lateral recolhível, em seções.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Abre um destino do menu (ex.: `'transactions'`, `'accounts'`).
  /// Retorna `false` fora do [AppShell].
  static bool goTo(BuildContext context, String id) {
    final state = context.findAncestorStateOfType<_AppShellState>();
    state?.select(id);
    return state != null;
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int index = 0;
  String? _appliedTheme;
  DateTime _lastRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Ao voltar para o app, baixa da nuvem o que foi lançado em outro lugar
  /// (outro aparelho ou WhatsApp).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final fc = context.read<FinanceController>();
    if (!fc.isCloud || fc.loading) return;
    final now = DateTime.now();
    if (now.difference(_lastRefresh) < const Duration(seconds: 30)) return;
    _lastRefresh = now;
    fc.refreshFromCloud().ignore();
    try {
      context.read<SharedController>().refresh().ignore();
    } on ProviderNotFoundException {
      // Sem despesas compartilhadas nesta árvore (ex.: testes).
    }
  }

  /// Menu lateral expandido (`null` = padrão pela largura da tela).
  bool? expanded;

  /// Destino aberto na área de conteúdo.
  String selected = 'home';

  /// Páginas já abertas (mantêm o estado ao trocar de destino).
  final _visited = <String>{'home'};

  void select(String id) => setState(() {
    selected = id;
    _visited.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    if (!fc.loading && _appliedTheme != fc.data.settings.themeMode) {
      _appliedTheme = fc.data.settings.themeMode;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => themeMode.value = parseThemeMode(_appliedTheme!),
      );
    }
    if (fc.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (fc.error != null) {
      return Scaffold(
        body: ErrorState(message: fc.error!, onRetry: fc.load),
      );
    }
    final wideScreen = MediaQuery.sizeOf(context).width >= 600;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SideMenu(
            selected: selected,
            onSelect: select,
            expanded: expanded ?? wideScreen,
            layout: fc.data.settings.menuLayout,
            onToggle: () =>
                setState(() => expanded = !(expanded ?? wideScreen)),
          ),
          Expanded(
            child: Column(
              children: [
                if (fc.data.settings.isSampleData)
                  const SafeArea(bottom: false, child: SampleDataBanner()),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: fc.data.settings.isSampleData,
                    child: IndexedStack(
                      index: _destinations.indexWhere((d) => d.id == selected),
                      children: [
                        for (final d in _destinations)
                          _visited.contains(d.id)
                              ? KeyedSubtree(
                                  key: ValueKey('page-${d.id}'),
                                  child: d.page,
                                )
                              : const SizedBox.shrink(),
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

/// Destino do menu: abre a tela na área de conteúdo, ao lado do menu.
class MenuDest {
  final String id;
  final IconData icon;
  final String label;
  final Widget page;
  final bool adminOnly;
  const MenuDest(
    this.id,
    this.icon,
    this.label,
    this.page, {
    this.adminOnly = false,
  });
}

/// Seção recolhível do menu.
class MenuGroup {
  final String id;
  final IconData icon;
  final String label;
  final List<MenuDest> items;
  const MenuGroup(this.id, this.icon, this.label, this.items);
}

const menuHome = MenuDest(
  'home',
  Icons.space_dashboard_outlined,
  'Início',
  HomeScreen(),
);

/// Hierarquia do menu, na ordem do uso: lançar (inclui faturas) → contas e
/// cartões → planejar (inclui importar planilha) → configurar.
const menuGroups = <MenuGroup>[
  MenuGroup('entries', Icons.receipt_long_outlined, 'Lançamentos', [
    MenuDest(
      'transactions',
      Icons.receipt_long_outlined,
      'Transações',
      TransactionsScreen(),
    ),
    MenuDest('recurring', Icons.autorenew, 'Recorrências', RecurringScreen()),
    MenuDest(
      'installments',
      Icons.view_week_outlined,
      'Parcelamentos',
      InstallmentsScreen(),
    ),
    MenuDest('invoices', Icons.receipt_outlined, 'Faturas', InvoicesScreen()),
    MenuDest(
      'other-entries',
      Icons.call_split,
      'Outras despesas',
      SimulationsScreen(initialTab: 1),
    ),
    MenuDest('shared', Icons.groups_outlined, 'Compartilhadas', SharedScreen()),
  ]),
  MenuGroup(
    'wallet',
    Icons.account_balance_wallet_outlined,
    'Contas e cartões',
    [
      MenuDest(
        'accounts',
        Icons.account_balance_outlined,
        'Contas',
        AccountsScreen(),
      ),
      MenuDest('cards', Icons.credit_card, 'Cartões', CardsScreen()),
    ],
  ),
  MenuGroup('planning', Icons.insights_outlined, 'Planejamento', [
    MenuDest(
      'projection',
      Icons.table_chart_outlined,
      'Projeção',
      ProjectionScreen(),
    ),
    MenuDest('budgets', Icons.savings_outlined, 'Orçamentos', BudgetsScreen()),
    MenuDest('goals', Icons.emoji_events_outlined, 'Metas', GoalsScreen()),
    MenuDest('projects', Icons.flag_outlined, 'Projetos', ProjectsScreen()),
    MenuDest(
      'simulations',
      Icons.science_outlined,
      'Simulações',
      SimulationsScreen(),
    ),
    MenuDest(
      'dashboards',
      Icons.insights_outlined,
      'Painéis',
      DashboardsScreen(),
    ),
    MenuDest(
      'import',
      Icons.upload_file,
      'Importar planilha',
      ExpenseImportScreen(),
    ),
  ]),
  MenuGroup('settings-group', Icons.settings_outlined, 'Configurações', [
    MenuDest('settings', Icons.tune, 'Preferências', SettingsScreen()),
    MenuDest(
      'categories',
      Icons.category_outlined,
      'Categorias',
      CategoriesScreen(),
    ),
    MenuDest(
      'open-finance',
      Icons.hub_outlined,
      'Open Finance',
      OpenFinanceScreen(),
    ),
    MenuDest(
      'users',
      Icons.manage_accounts_outlined,
      'Usuários',
      UsersScreen(),
      adminOnly: true,
    ),
  ]),
];

final _destinations = <MenuDest>[
  menuHome,
  for (final g in menuGroups) ...g.items,
];

/// Destino do menu pelo id (nulo = desconhecido).
MenuDest? menuDest(String id) {
  for (final d in _destinations) {
    if (d.id == id) return d;
  }
  return null;
}

/// Organização padrão do menu (sem Início, que fica sempre no topo).
final defaultMenuSections = <MenuSection>[
  for (final g in menuGroups)
    MenuSection(g.id, [for (final d in g.items) d.id]),
];

/// Seções do menu na organização escolhida pelo usuário ([layout], em JSON;
/// nulo = padrão).
List<MenuGroup> resolveMenuGroups(List<Object?>? layout) {
  if (layout == null) return menuGroups;
  return [
    for (final s in MenuLayout.resolve(defaultMenuSections, layout))
      menuGroupFor(s),
  ];
}

/// Seção do menu com o ícone e o nome (padrão ou do usuário) de [s].
MenuGroup menuGroupFor(MenuSection s) {
  final base = menuGroups.where((g) => g.id == s.id).firstOrNull;
  return MenuGroup(
    s.id,
    base?.icon ?? Icons.folder_outlined,
    s.label ?? base?.label ?? 'Nova seção',
    [for (final id in s.items) ?menuDest(id)],
  );
}

/// Menu lateral escuro (estilo painel administrativo), com ícone e texto,
/// organizado em seções recolhíveis. O botão ☰ recolhe o menu para só os
/// ícones; recolhido, tocar numa seção abre a lista dos itens dela.
class SideMenu extends StatefulWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final bool expanded;
  final VoidCallback onToggle;

  /// Organização escolhida pelo usuário ([AppSettings.menuLayout]).
  final List<Object?>? layout;
  const SideMenu({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.expanded,
    required this.onToggle,
    this.layout,
  });

  static const bg = Color(0xFF343A40);
  static const fg = Color(0xFFC2C7D0);
  static const line = Color(0xFF4B545C);
  static const expandedWidth = 232.0;
  static const collapsedWidth = 64.0;

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  /// Seções abertas. Só a primeira (Lançamentos, no padrão) começa aberta,
  /// para o menu caber sem rolar; ao abrir um destino, a seção dele é aberta.
  late final _open = <String>{if (_groups.isNotEmpty) _groups.first.id};

  bool _contains(MenuGroup g, String id) => g.items.any((d) => d.id == id);

  late var _groups = resolveMenuGroups(widget.layout);

  @override
  void didUpdateWidget(SideMenu old) {
    super.didUpdateWidget(old);
    if (!identical(old.layout, widget.layout)) {
      _groups = resolveMenuGroups(widget.layout);
    }
    if (old.selected != widget.selected) {
      for (final g in _groups) {
        if (_contains(g, widget.selected)) _open.add(g.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const fg = SideMenu.fg;
    const line = SideMenu.line;
    final user = context.watch<AuthController>().user;
    final isAdmin = user?.isAdmin ?? false;
    final name = user?.name ?? '';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: widget.expanded ? SideMenu.expandedWidth : SideMenu.collapsedWidth,
      color: SideMenu.bg,
      child: SafeArea(
        right: false,
        child: LayoutBuilder(
          builder: (context, box) {
            // Durante a animação, o texto só aparece quando cabe.
            final wide = box.maxWidth >= 150;
            Widget entry({
              required IconData icon,
              required String label,
              required VoidCallback onTap,
              bool active = false,
              bool child = false,
              bool header = false,
              Widget? trailing,
              Color? color,
              Key? key,
            }) {
              final c = color ?? (active ? Colors.white : fg);
              final tile = Material(
                color: active
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  key: key,
                  borderRadius: BorderRadius.circular(6),
                  onTap: onTap,
                  child: SizedBox(
                    height: child ? 38 : 44,
                    child: Row(
                      mainAxisAlignment: wide
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        if (wide) SizedBox(width: child ? 30 : 14),
                        Icon(icon, size: child ? 18 : 20, color: c),
                        if (wide) ...[
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c,
                                fontSize: child ? 14 : 15,
                                fontWeight: active || header
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          ?trailing,
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                child: Semantics(
                  button: true,
                  selected: active,
                  label: label,
                  excludeSemantics: true,
                  child: wide
                      ? tile
                      : Tooltip(
                          message: label,
                          preferBelow: false,
                          child: tile,
                        ),
                ),
              );
            }

            Widget dest(MenuDest d, {bool child = false}) => entry(
              key: ValueKey('side-menu-${d.id}'),
              icon: d.icon,
              label: d.label,
              child: child,
              active: d.id == widget.selected,
              onTap: () => widget.onSelect(d.id),
            );

            // Recolhido: a seção vira um ícone que abre a lista dos itens.
            Future<void> popup(
              BuildContext anchor,
              List<MenuDest> items,
            ) async {
              final box = anchor.findRenderObject()! as RenderBox;
              final at = box.localToGlobal(Offset(box.size.width, 0));
              final id = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
                items: [
                  for (final d in items)
                    PopupMenuItem(
                      value: d.id,
                      child: Row(
                        children: [
                          Icon(d.icon, size: 20),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              d.label,
                              overflow: TextOverflow.ellipsis,
                              style: d.id == widget.selected
                                  ? const TextStyle(fontWeight: FontWeight.w600)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
              if (id != null) widget.onSelect(id);
            }

            Widget group(MenuGroup g) {
              final items = [
                for (final d in g.items)
                  if (!d.adminOnly || isAdmin) d,
              ];
              // Seção vazia (tudo movido para outras) não aparece.
              if (items.isEmpty) return const SizedBox.shrink();
              final hasSelected = items.any((d) => d.id == widget.selected);
              final open = _open.contains(g.id);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Builder(
                    builder: (anchor) => entry(
                      key: ValueKey('side-menu-group-${g.id}'),
                      icon: g.icon,
                      label: g.label,
                      header: true,
                      active: !wide && hasSelected,
                      trailing: Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: fg,
                      ),
                      onTap: () {
                        if (!wide) {
                          popup(anchor, items);
                        } else {
                          setState(
                            () => open ? _open.remove(g.id) : _open.add(g.id),
                          );
                        }
                      },
                    ),
                  ),
                  if (wide && open)
                    for (final d in items) dest(d, child: true),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Marca + botão de recolher/expandir.
                SizedBox(
                  height: 56,
                  child: Row(
                    mainAxisAlignment: wide
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      if (wide) ...[
                        const SizedBox(width: 16),
                        const CircleAvatar(
                          radius: 15,
                          backgroundColor: Color(0xFF2A78D6),
                          child: Icon(
                            Icons.account_balance_wallet,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Finanças',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      IconButton(
                        key: const ValueKey('side-menu-toggle'),
                        tooltip: widget.expanded
                            ? 'Recolher menu'
                            : 'Expandir menu',
                        color: fg,
                        icon: const Icon(Icons.menu),
                        onPressed: widget.onToggle,
                      ),
                      if (wide) const SizedBox(width: 4),
                    ],
                  ),
                ),
                const Divider(height: 1, color: line),
                if (name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: entry(
                      icon: Icons.person,
                      label: name,
                      onTap: () => widget.onSelect('settings'),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(height: 1, color: line),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      dest(menuHome),
                      for (final g in _groups) group(g),
                    ],
                  ),
                ),
                const Divider(height: 1, color: line),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: entry(
                    icon: Icons.logout,
                    label: 'Sair',
                    onTap: () => context.read<AuthController>().logout(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
