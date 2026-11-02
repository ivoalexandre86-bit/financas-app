import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_controller.dart';
import '../screens/subscription/subscription_screen.dart';
import '../theme.dart';

/// Plano Grátis em vigor? Sem login (testes de tela) conta como liberado.
bool isGratisPlan(BuildContext context, {bool listen = true}) =>
    Provider.of<AuthController?>(context, listen: listen)?.isGratis ?? false;

/// Plano Premium em vigor? Sem login (testes de tela) conta como liberado.
bool isPremiumPlan(BuildContext context, {bool listen = true}) =>
    Provider.of<AuthController?>(context, listen: listen)?.isPremium ?? true;

Future<void> openSubscription(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const SubscriptionScreen()));

/// Recurso de um plano pago: explica e leva à tela de assinatura.
Future<void> showPlanUpsell(
  BuildContext context, {
  required String feature,
  String plan = 'Básico',
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined),
      title: Text('Recurso do plano $plan'),
      content: Text(feature),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Agora não'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Ver planos'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) await openSubscription(context);
}

/// Faixa curta sobre um limite do plano, com o botão "Ver planos".
class PlanBanner extends StatelessWidget {
  final String text;
  const PlanBanner(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: context.fin.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: context.text.bodySmall)),
          TextButton(
            onPressed: () => openSubscription(context),
            child: const Text('Ver planos'),
          ),
        ],
      ),
    );
  }
}

/// Situação do teste do Premium no Início: dias que faltam e o que
/// acontece depois (sem cobrança automática); terminado há pouco, avisa
/// que a conta está no Grátis.
class TrialStatusBanner extends StatelessWidget {
  const TrialStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final access = Provider.of<AuthController?>(context)?.user?.access;
    final end = access?.trialEndsAt;
    if (access == null || end == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final String text;
    var urgent = false;
    if (access.trial) {
      final days = access.trialDaysLeft(now);
      urgent = days <= 3;
      text = days == 0
          ? 'Último dia do teste do Premium. Amanhã a conta passa para o '
                'Grátis, sem cobrança.'
          : 'Teste do Premium: ${days == 1 ? 'falta 1 dia' : 'faltam $days dias'}. '
                'Depois a conta passa para o Grátis, sem cobrança automática.';
    } else if (access.isGratis &&
        access.status == 'expired' &&
        access.paidUntil == null &&
        now.difference(end).inDays < 14) {
      urgent = true;
      text =
          'Seu teste do Premium terminou e a conta está no plano Grátis. '
          'Seus dados continuam aqui; assine para voltar à projeção de 12 '
          'meses e às simulações sem limite.';
    } else {
      return const SizedBox.shrink();
    }
    final color = urgent
        ? context.fin.warning
        : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: const ValueKey('trial-banner'),
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.workspace_premium_outlined, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: context.text.bodySmall)),
            TextButton(
              onPressed: () => openSubscription(context),
              child: const Text('Ver planos'),
            ),
          ],
        ),
      ),
    );
  }
}
