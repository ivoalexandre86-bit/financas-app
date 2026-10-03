import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app.dart';
import '../../../state/auth_controller.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final auth = context.read<AuthController>();
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
          _h(context, 'Privacidade e dados (LGPD)'),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Política de privacidade'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Política de privacidade'),
                content: const SingleChildScrollView(child: Text(_privacy)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ),
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
                message: 'Todos os seus dados (contas, transações, projetos, conexões) serão apagados deste dispositivo. Esta ação não pode ser desfeita.',
                confirm: 'Excluir definitivamente',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              await fc.repo.destroy();
              await auth.deleteAccount();
              if (context.mounted) {
                Navigator.of(context).popUntil((r) => r.isFirst);
              }
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

const _privacy = '''
Seus dados financeiros são armazenados de forma isolada por usuário e usados exclusivamente para calcular saldos, faturas e projeções.

• Não vendemos nem compartilhamos dados com terceiros.
• Senhas são protegidas com hash (PBKDF2-HMAC-SHA256 com salt); nunca são armazenadas em texto.
• O app nunca solicita ou armazena senhas bancárias. Conexões Open Finance usam o consentimento oficial da instituição e podem ser revogadas a qualquer momento.
• Você pode excluir sua conta e todos os dados a qualquer momento em Configurações.
• Base legal (LGPD, art. 7º): execução de contrato e consentimento para integrações Open Finance.

Texto provisório — revisar com assessoria jurídica antes da publicação.
''';
