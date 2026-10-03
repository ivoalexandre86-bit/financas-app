import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../state/finance_controller.dart';
import 'screens/home/home_screen.dart';
import 'screens/more/more_screen.dart';
import 'screens/projection/projection_screen.dart';
import 'screens/projects/projects_screen.dart';
import 'screens/transactions/transactions_screen.dart';
import 'widgets/common.dart';

/// Estrutura principal com a barra de navegação inferior (5 seções).
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
      body: Column(
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transações',
          ),
          NavigationDestination(
            icon: Icon(Icons.table_chart_outlined),
            selectedIcon: Icon(Icons.table_chart),
            label: 'Projeção',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Projetos',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu),
            selectedIcon: Icon(Icons.menu_open),
            label: 'Mais',
          ),
        ],
      ),
    );
  }
}
