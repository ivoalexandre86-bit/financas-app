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
  if (a.isGratis) return 'Plano Grátis';
  if (a.trial) {
    final days = a.trialDaysLeft(now);
    return 'Teste do Premium: ${days == 1 ? 'falta 1 dia' : 'faltam $days dias'} '
        '(até ${Dates.format(a.trialEndsAt!.toLocal())})';
  }
  final until = a.paidUntil;
  return '${a.premium ? 'Premium' : 'Plano básico'} ativo'
      '${until == null || until.year > 9000 ? '' : ' até ${Dates.format(until.toLocal())}'}';
}

/// Assinar, restaurar e gerenciar a assinatura. Sem assinatura o app segue
/// no plano Grátis (nunca bloqueia).
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
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
    if (auth.isGratis) {
      throw StateError('Não encontramos uma assinatura ativa nesta conta.');
    }
  }, success: 'Assinatura encontrada');

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final access = auth.user?.access;
    final subtle = context.text.bodyMedium?.copyWith(color: context.fin.subtle);
    // Durante o teste vale o Premium; o cartão destacado é o plano em vigor.
    final current = auth.plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Assinatura')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (access != null)
            Text(accessSummary(access), style: context.text.titleMedium),
          if (access?.isGratis ?? false) ...[
            const SizedBox(height: 8),
            Text(
              'Você continua usando o Finanças de graça, com alguns limites. '
              'Assine para liberar tudo; seus dados continuam os mesmos.',
              style: subtle,
            ),
          ],
          const SizedBox(height: 20),
          _PlanCard(
            title: 'Grátis',
            price: 'R\$ 0',
            current: current == 'gratis',
            items: const [
              'Contas, cartões e lançamentos ilimitados, sincronizados',
              'Projeção de 3 meses',
              'WhatsApp: 5 lançamentos por mês, só por texto',
              '1 grupo de despesas compartilhadas',
              '3 orçamentos por categoria e 1 meta de economia',
              'Open Finance: demonstração',
            ],
          ),
          const SizedBox(height: 12),
          _PlanCard(
            title: 'Básico',
            price: 'R\$ 9,99 por mês',
            current: current == 'basico',
            items: const [
              'Contas, cartões e lançamentos ilimitados, sincronizados',
              'Projeção de 12 meses',
              'WhatsApp: 300 lançamentos por mês, com fotos, PDFs e áudios',
              'Grupos de despesas compartilhadas ilimitados',
              'Orçamentos e metas ilimitados',
              'Importar planilha',
              'Open Finance: demonstração',
            ],
          ),
          const SizedBox(height: 12),
          _PlanCard(
            title: 'Premium',
            price: 'R\$ 19,99 por mês',
            current: current == 'premium',
            items: const [
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
          if (Billing.available)
            TextButton(
              onPressed: () => launchUrl(
                Billing.manageUrl,
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Gerenciar ou cancelar na loja'),
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

  /// Plano em vigor: borda destacada e o selo "Seu plano".
  final bool current;
  const _PlanCard({
    required this.title,
    required this.price,
    required this.items,
    this.current = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      shape: current
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: primary, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: context.text.titleMedium)),
                if (current) ...[
                  Pill('Seu plano', color: primary),
                  const SizedBox(width: 8),
                ],
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
