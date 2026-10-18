import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app.dart';
import '../../../core/legal_links.dart';
import '../../../data/cloud/api_client.dart';
import '../../../state/auth_controller.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../users/users_screen.dart';
import 'cloud_import.dart';
import 'menu_editor_screen.dart';
import '../subscription/subscription_screen.dart';
import 'whatsapp_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final auth = context.watch<AuthController>();
    final s = fc.data.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        children: [
          _h(context, 'Aparência'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', label: Text('Sistema')),
                ButtonSegment(value: 'light', label: Text('Claro')),
                ButtonSegment(value: 'dark', label: Text('Escuro')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) {
                themeMode.value = parseThemeMode(v.first);
                fc.saveSettings(s.copyWith(themeMode: v.first));
              },
            ),
          ),
          _h(context, 'Menu lateral'),
          ListTile(
            key: const ValueKey('menu-editor'),
            leading: const Icon(Icons.reorder),
            title: const Text('Organizar menu'),
            subtitle: Text(
              s.menuLayout == null
                  ? 'Mude a ordem dos itens e das seções, ou leve itens para outra seção.'
                  : 'Organização personalizada. Toque para mudar ou voltar ao padrão.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MenuEditorScreen())),
          ),
          _h(context, 'Lista de transações'),
          for (final group in [true, false])
            ListTile(
              key: ValueKey('group-invoices-$group'),
              leading: Icon(
                s.groupCardInvoices == group
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: s.groupCardInvoices == group
                    ? context.colors.primary
                    : null,
              ),
              title: Text(
                group
                    ? 'Agrupar compras do cartão por fatura'
                    : 'Mostrar compras individualmente',
              ),
              subtitle: Text(
                group
                    ? 'Cada fatura aparece como uma única linha, com o valor que sai da conta (padrão).'
                    : 'Cada compra do cartão aparece na lista, no mês de pagamento da fatura.',
              ),
              onTap: () =>
                  fc.saveSettings(s.copyWith(groupCardInvoices: group)),
            ),
          _h(context, 'Regras de cálculo'),
          const ListTile(
            leading: Icon(Icons.event_available_outlined),
            title: Text('Regime de caixa'),
            subtitle: Text(
              'Compras no cartão contam no mês em que a fatura é paga (no vencimento, enquanto não for paga). Totais, categorias e orçamentos usam o mesmo critério.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Pagamentos de fatura e transferências'),
            subtitle: Text(
              'Nunca são contados como despesa: a compra no cartão já é a despesa; o pagamento apenas liquida a fatura.',
            ),
          ),
          if (fc.isCloud) ...[
            _h(context, 'Nuvem'),
            if (auth.user?.access case final access?)
              ListTile(
                key: const ValueKey('subscription'),
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Assinatura'),
                subtitle: Text(accessSummary(access)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                ),
              ),
            ListTile(
              key: const ValueKey('cloud-refresh'),
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Atualizar agora'),
              subtitle: const Text(
                'Seus dados ficam salvos na nuvem: entre com a mesma conta em qualquer aparelho para ver tudo.',
              ),
              onTap: () => runAction(context, () async {
                if (!await fc.refreshFromCloud()) {
                  throw const OfflineException();
                }
              }, success: 'Dados atualizados'),
            ),
            ListTile(
              key: const ValueKey('cloud-import'),
              leading: const Icon(Icons.upload_outlined),
              title: const Text('Trazer dados deste aparelho'),
              subtitle: const Text(
                'Leva para a nuvem os dados de uma conta antiga criada neste navegador.',
              ),
              onTap: () => showImportFromDevice(context),
            ),
            ListTile(
              key: const ValueKey('whatsapp'),
              leading: const Icon(Icons.chat_outlined),
              title: const Text('WhatsApp'),
              subtitle: const Text(
                'Lance despesas e receitas por mensagem, foto ou áudio.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const WhatsAppScreen())),
            ),
          ],
          _h(context, 'Privacidade e dados (LGPD)'),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Política de privacidade'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => LegalLinks.open(LegalLinks.privacy),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Termos de uso'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => LegalLinks.open(LegalLinks.terms),
          ),
          if (!fc.isDemo)
            ListTile(
              key: const ValueKey('change-password'),
              leading: const Icon(Icons.password),
              title: const Text('Alterar minha senha'),
              onTap: () => changeOwnPassword(context),
            ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: context.colors.error,
            ),
            title: Text(
              'Excluir minha conta e dados',
              style: TextStyle(color: context.colors.error),
            ),
            subtitle: const Text(
              'Remove permanentemente todos os dados financeiros deste usuário.',
            ),
            onTap: () async {
              final ok = await confirmDialog(
                context,
                title: 'Excluir conta?',
                message: fc.isCloud
                    ? 'Todos os seus dados (contas, transações, projetos, conexões) serão apagados da nuvem e de todos os aparelhos. Esta ação não pode ser desfeita.'
                    : 'Todos os seus dados (contas, transações, projetos, conexões) serão apagados deste dispositivo. Esta ação não pode ser desfeita.',
                confirm: 'Excluir definitivamente',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              final nav = Navigator.of(context);
              final repo = fc.repo;
              // A conta é removida primeiro: se não puder (único
              // administrador), os dados ficam intactos.
              final done = await runAction(context, auth.deleteAccount);
              if (!done) return;
              await repo.destroy();
              if (nav.mounted) nav.popUntil((r) => r.isFirst);
            },
          ),
          _h(context, 'Sobre'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Finanças · versão 0.1.0 (MVP)'),
            subtitle: Text(
              'Valores em centavos inteiros (sem ponto flutuante). Moeda: Real (BRL).',
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _h(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      t.toUpperCase(),
      style: context.text.labelSmall?.copyWith(
        color: context.fin.subtle,
        letterSpacing: 0.8,
      ),
    ),
  );
}
