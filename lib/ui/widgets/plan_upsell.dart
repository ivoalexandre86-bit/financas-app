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
