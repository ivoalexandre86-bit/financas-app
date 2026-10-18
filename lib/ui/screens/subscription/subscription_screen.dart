import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/dates.dart';
import '../../../core/legal_links.dart';
import '../../../data/auth_service.dart';
import '../../../data/billing.dart';
import '../../../state/auth_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Situação da assinatura em uma linha (Configurações).
String accessSummary(Access a) {
  final now = DateTime.now();
  if (a.status == 'admin' || a.status == 'free') return 'Conta sem cobrança';
  if (a.expired) {
    return 'Teste grátis encerrado. Assine para continuar lançando.';
  }
  if (a.trial) {
    final days = a.trialDaysLeft(now);
    return 'Teste grátis: ${days == 1 ? 'falta 1 dia' : 'faltam $days dias'} '
        '(até ${Dates.format(a.trialEndsAt!.toLocal())})';
  }
  final until = a.paidUntil;
  return '${a.premium ? 'Premium' : 'Plano básico'} ativo'
      '${until == null || until.year > 9000 ? '' : ' até ${Dates.format(until.toLocal())}'}';
}

/// Assinar, restaurar e gerenciar a assinatura. Com [gate], é a tela que
/// aparece no lugar do app quando o teste ou a assinatura vencem.
class SubscriptionScreen extends StatefulWidget {
  final bool gate;
  const SubscriptionScreen({super.key, this.gate = false});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  Future<List<StorePlan>>? _plans;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final id = context.read<AuthController>().user?.id;
    if (Billing.available && id != null) _plans = Billing.plans(id);
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    await runAction(context, action, success: success);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _buy(StorePlan plan) => _run(() async {
    final auth = context.read<AuthController>();
    if (!await Billing.buy(auth.user!.id, plan)) return;
    await auth.refreshSubscription();
  }, success: 'Assinatura confirmada. Obrigado!');

  Future<void> _restore() => _run(() async {
    final auth = context.read<AuthController>();
    if (Billing.available) await Billing.restore(auth.user!.id);
    await auth.refreshSubscription();
    if (auth.locked) {
      throw StateError('Não encontramos uma assinatura ativa nesta conta.');
    }
  }, success: 'Assinatura encontrada');

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final access = auth.user?.access;
    final subtle = context.text.bodyMedium?.copyWith(color: context.fin.subtle);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assinatura'),
        automaticallyImplyLeading: !widget.gate,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.gate) ...[
            Text('Seu teste grátis acabou', style: context.text.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Assine para continuar usando o Finanças. Seus dados continuam '
              'guardados e voltam assim que a assinatura for confirmada.',
              style: subtle,
            ),
          ] else if (access != null)
            Text(accessSummary(access), style: context.text.titleMedium),
          const SizedBox(height: 20),
          const _PlanCard(
            title: 'Básico',
            price: 'R\$ 9,99 por mês',
            items: [
              'Contas, cartões, faturas e projeções',
              'Mesmos dados no celular e no computador',
              'Lançamentos pelo WhatsApp (até 300 por mês)',
            ],
          ),
          const SizedBox(height: 12),
          const _PlanCard(
            title: 'Premium',
            price: 'R\$ 19,99 por mês',
            items: [
              'Tudo do Básico',
              'Open Finance: importa contas e cartões do seu banco',
            ],
          ),
          const SizedBox(height: 20),
          if (_plans != null)
            FutureBuilder<List<StorePlan>>(
              future: _plans,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final plans = snap.data ?? const <StorePlan>[];
                if (plans.isEmpty) {
                  return Text(
                    'Não foi possível carregar os planos da loja agora.',
                    style: subtle,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final p in plans)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: _busy ? null : () => _buy(p),
                          child: Text(
                            'Assinar ${p.premium ? 'Premium' : 'Básico'} · ${p.price}',
                          ),
                        ),
                      ),
                  ],
                );
              },
            )
          else
            Text(
              'A assinatura é feita pelo app Finanças no celular (App Store ou '
              'Google Play). Depois de assinar, entre aqui com a mesma conta.',
              style: subtle,
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _busy ? null : _restore,
            child: Text(Billing.available ? 'Restaurar compras' : 'Já assinei'),
          ),
          if (Billing.available && !widget.gate)
            TextButton(
              onPressed: () => launchUrl(
                Billing.manageUrl,
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Gerenciar ou cancelar na loja'),
            ),
          if (widget.gate)
            TextButton(
              onPressed: _busy ? null : auth.logout,
              child: const Text('Sair da conta'),
            ),
          const SizedBox(height: 16),
          Text(
            'A assinatura renova todo mês e pode ser cancelada a qualquer '
            'momento nas assinaturas da sua loja.',
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
            textAlign: TextAlign.center,
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: () => LegalLinks.open(LegalLinks.terms),
                child: const Text('Termos de uso'),
              ),
              TextButton(
                onPressed: () => LegalLinks.open(LegalLinks.privacy),
                child: const Text('Privacidade'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final List<String> items;
  const _PlanCard({
    required this.title,
    required this.price,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: context.text.titleMedium)),
                Text(price, style: context.text.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
