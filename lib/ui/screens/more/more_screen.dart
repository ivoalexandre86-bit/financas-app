import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/auth_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../accounts/accounts_screen.dart';
import '../cards/cards_screen.dart';
import '../cards/invoices_screen.dart';
import '../categories/categories_screen.dart';
import '../installments/installments_screen.dart';
import '../open_finance/open_finance_screen.dart';
import '../recurring/recurring_screen.dart';
import '../settings/settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    Widget item(IconData icon, String title, String subtitle, Widget page) =>
        ListTile(
          leading: Icon(icon, color: context.colors.primary),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push(context, page),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Mais')),
      body: ListView(
        children: [
          ListTile(
            leading: CircleAvatar(
              child: Text(
                (user?.name.isNotEmpty ?? false)
                    ? user!.name[0].toUpperCase()
                    : '?',
              ),
            ),
            title: Text(user?.name ?? ''),
            subtitle: Text(user?.email ?? ''),
          ),
          const Divider(),
          _Header('Finanças'),
          item(
            Icons.account_balance_outlined,
            'Contas',
            'Corrente, poupança, digital, dinheiro, investimentos',
            const AccountsScreen(),
          ),
          item(
            Icons.credit_card,
            'Cartões de crédito',
            'Limites e ciclos',
            const CardsScreen(),
          ),
          item(
            Icons.receipt_outlined,
            'Faturas',
            'Atuais, anteriores e futuras',
            const InvoicesScreen(),
          ),
          item(
            Icons.autorenew,
            'Recorrências',
            'Assinaturas, salário, contas fixas',
            const RecurringScreen(),
          ),
          item(
            Icons.view_week_outlined,
            'Parcelamentos',
            'Compras parceladas',
            const InstallmentsScreen(),
          ),
          item(
            Icons.category_outlined,
            'Categorias',
            'Categorias e subcategorias',
            const CategoriesScreen(),
          ),
          _Header('Integrações'),
          item(
            Icons.hub_outlined,
            'Open Finance',
            'Conexões bancárias e importação',
            const OpenFinanceScreen(),
          ),
          _Header('Aplicativo'),
          item(
            Icons.settings_outlined,
            'Configurações',
            'Tema, regras de cálculo, privacidade e conta',
            const SettingsScreen(),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: context.colors.error),
            title: const Text('Sair'),
            onTap: () => context.read<AuthController>().logout(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text.toUpperCase(),
      style: context.text.labelSmall?.copyWith(
        color: context.fin.subtle,
        letterSpacing: 0.8,
      ),
    ),
  );
}
