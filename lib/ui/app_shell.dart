import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../state/auth_controller.dart';
import '../state/finance_controller.dart';
import 'nav.dart';
import 'screens/cards/invoices_screen.dart';
import 'screens/categories/categories_screen.dart';
import 'screens/dashboards/dashboards_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/more/more_screen.dart';
import 'screens/projection/projection_screen.dart';
import 'screens/projects/projects_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/transactions/transactions_screen.dart';
import 'screens/users/users_screen.dart';
import 'widgets/common.dart';

/// Estrutura principal com o menu lateral recolhível (5 seções).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static void goToTab(BuildContext context, int index) =>
      context.findAncestorStateOfType<_AppShellState>()?.select(index);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  String? _appliedTheme;

  /// Menu lateral expandido (`null` = padrão pela largura da tela).
  bool? expanded;

  void select(int i) => setState(() => index = i);

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
    const pages = [
      HomeScreen(),
      TransactionsScreen(),
      ProjectionScreen(),
      ProjectsScreen(),
      MoreScreen(),
    ];
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SideMenu(
            selected: index,
            onSelect: select,
            expanded: expanded ?? MediaQuery.sizeOf(context).width >= 600,
            onToggle: () => setState(
              () => expanded =
                  !(expanded ?? MediaQuery.sizeOf(context).width >= 600),
            ),
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
                    child: IndexedStack(index: index, children: pages),
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

/// Item de navegação do menu lateral.
typedef _NavItem = ({IconData icon, IconData selectedIcon, String label});

const _tabs = <_NavItem>[
  (
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard,
    label: 'Início',
  ),
  (
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    label: 'Transações',
  ),
  (
    icon: Icons.table_chart_outlined,
    selectedIcon: Icons.table_chart,
    label: 'Projeção',
  ),
  (icon: Icons.flag_outlined, selectedIcon: Icons.flag, label: 'Projetos'),
  (icon: Icons.menu, selectedIcon: Icons.menu_open, label: 'Mais'),
];

/// Menu lateral escuro (estilo painel administrativo), com ícone e texto.
/// O botão ☰ recolhe o menu para só os ícones e o expande de novo.
class SideMenu extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final bool expanded;
  final VoidCallback onToggle;
  const SideMenu({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.expanded,
    required this.onToggle,
  });

  static const bg = Color(0xFF343A40);
  static const fg = Color(0xFFC2C7D0);
  static const line = Color(0xFF4B545C);
  static const expandedWidth = 232.0;
  static const collapsedWidth = 64.0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final name = user?.name ?? '';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: expanded ? expandedWidth : collapsedWidth,
      color: bg,
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
                    height: 44,
                    child: Row(
                      mainAxisAlignment: wide
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        if (wide) const SizedBox(width: 14),
                        Icon(icon, size: 20, color: c),
                        if (wide) ...[
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c,
                                fontSize: 15,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                        tooltip: expanded ? 'Recolher menu' : 'Expandir menu',
                        color: fg,
                        icon: const Icon(Icons.menu),
                        onPressed: onToggle,
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
                      onTap: () => onSelect(4),
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
                      for (var i = 0; i < _tabs.length; i++)
                        entry(
                          key: ValueKey('side-menu-$i'),
                          icon: i == selected
                              ? _tabs[i].selectedIcon
                              : _tabs[i].icon,
                          label: _tabs[i].label,
                          active: i == selected,
                          onTap: () => onSelect(i),
                        ),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Divider(height: 1, color: line),
                      ),
                      const SizedBox(height: 8),
                      entry(
                        icon: Icons.category_outlined,
                        label: 'Categorias',
                        onTap: () => push(context, const CategoriesScreen()),
                      ),
                      entry(
                        icon: Icons.receipt_outlined,
                        label: 'Faturas',
                        onTap: () => push(context, const InvoicesScreen()),
                      ),
                      entry(
                        icon: Icons.insights_outlined,
                        label: 'Painéis',
                        onTap: () => push(context, const DashboardsScreen()),
                      ),
                      if (user?.isAdmin ?? false)
                        entry(
                          key: const ValueKey('side-menu-users'),
                          icon: Icons.manage_accounts_outlined,
                          label: 'Usuários',
                          onTap: () => push(context, const UsersScreen()),
                        ),
                      entry(
                        icon: Icons.settings_outlined,
                        label: 'Configurações',
                        onTap: () => push(context, const SettingsScreen()),
                      ),
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
