import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../state/auth_controller.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Gasto fixo sugerido no 1º acesso.
class _Fixed {
  final String categoryId;
  final String label;
  final IconData icon;
  final int day;
  final controller = TextEditingController();
  _Fixed(this.categoryId, this.label, this.icon, {this.day = 10});
}

/// "Monte seu orçamento em 1 minuto": saldo de hoje, renda do mês e gastos
/// fixos. Ao concluir, abre a projeção dos próximos meses. Tudo pode ser
/// ajustado depois; nada é obrigatório.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Abre como tela cheia; criado o orçamento, mostra a projeção.
  static Future<void> open(
    BuildContext context, {
    required void Function() showProjection,
  }) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const OnboardingScreen(),
      ),
    );
    if (done == true) showProjection();
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final balance = TextEditingController();
  final income = TextEditingController();
  int incomeDay = 5;
  bool busy = false;
  final fixed = [
    _Fixed('cat_rent', 'Aluguel ou financiamento', Icons.home_outlined, day: 5),
    _Fixed('cat_groceries', 'Mercado', Icons.shopping_cart_outlined),
    _Fixed('cat_energy', 'Luz e água', Icons.bolt_outlined),
    _Fixed('cat_internet', 'Internet e celular', Icons.wifi),
    _Fixed('cat_transport', 'Transporte', Icons.directions_car_outlined),
    _Fixed('cat_subscriptions', 'Assinaturas', Icons.subscriptions_outlined),
  ];

  static Money _parse(TextEditingController c) =>
      Money.tryEval(c.text.trim().isEmpty ? '0' : c.text) ?? Money.zero;

  Money get _income => _parse(income);
  Money get _expenses =>
      fixed.fold(Money.zero, (a, f) => a + _parse(f.controller));

  Future<void> _finish() async {
    final fc = context.read<FinanceController>();
    setState(() => busy = true);
    final ok = await runAction(
      context,
      () => fc.completeOnboarding(
        balance: _parse(balance),
        income: _income,
        incomeDay: incomeDay,
        expenses: [
          for (final f in fixed)
            (
              categoryId: f.categoryId,
              description: f.label,
              amount: _parse(f.controller),
              day: f.day,
            ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (!ok) return;
    // Quem abriu leva o usuário à projeção.
    Navigator.of(context).pop(true);
  }

  Future<void> _skip() async {
    await context.read<FinanceController>().skipOnboarding();
    if (mounted) Navigator.of(context).pop(false);
  }

  Widget _money(TextEditingController c, String label, {Key? key}) => TextField(
    key: key,
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, prefixText: 'R\$ '),
    onChanged: (_) => setState(() {}),
  );

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AuthController>().user?.access;
    final subtle = context.text.bodyMedium?.copyWith(color: context.fin.subtle);
    final left = _income - _expenses;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seu orçamento em 1 minuto'),
        actions: [
          TextButton(
            onPressed: busy ? null : _skip,
            child: const Text('Agora não'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            'Responda três perguntas e veja quanto vai sobrar nos próximos '
            'meses. Tudo pode ser ajustado depois.',
            style: subtle,
          ),
          if (access != null && access.trial) ...[
            const SizedBox(height: 16),
            TrialTerms(access.trialEndsAt),
          ],
          const SizedBox(height: 24),
          Text(
            '1. Quanto você tem na conta hoje?',
            style: context.text.titleMedium,
          ),
          const SizedBox(height: 8),
          _money(balance, 'Saldo atual', key: const ValueKey('ob-balance')),
          const SizedBox(height: 24),
          Text('2. Quanto entra por mês?', style: context.text.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _money(
                  income,
                  'Salário ou renda',
                  key: const ValueKey('ob-income'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  initialValue: incomeDay,
                  decoration: const InputDecoration(labelText: 'Dia'),
                  items: [
                    for (var d = 1; d <= 28; d++)
                      DropdownMenuItem(value: d, child: Text('Dia $d')),
                  ],
                  onChanged: (d) => setState(() => incomeDay = d ?? 5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('3. Gastos fixos do mês', style: context.text.titleMedium),
          Text('Deixe em branco o que não tiver.', style: subtle),
          const SizedBox(height: 8),
          for (final f in fixed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(f.icon, color: context.fin.subtle),
                  const SizedBox(width: 12),
                  Expanded(child: _money(f.controller, f.label)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.savings_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      left.isNegative
                          ? 'Faltam ${(-left).formatVisible()} por mês'
                          : 'Sobram ${left.formatVisible()} por mês',
                      key: const ValueKey('ob-left'),
                      style: context.text.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('ob-finish'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: busy ? null : _finish,
            icon: const Icon(Icons.show_chart),
            label: const Text('Ver minha projeção'),
          ),
        ],
      ),
    );
  }
}

/// Condições do teste do Premium, sempre as mesmas palavras (cadastro,
/// 1º acesso e assinatura).
class TrialTerms extends StatelessWidget {
  final DateTime? endsAt;
  const TrialTerms(this.endsAt, {super.key});

  @override
  Widget build(BuildContext context) {
    final until = endsAt == null
        ? 'por 30 dias'
        : 'até ${Dates.format(endsAt!.toLocal())}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.workspace_premium_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Premium liberado $until: projeção de 12 meses, simulações e '
              'comparação de cenários sem limite, WhatsApp com fotos e áudios '
              'e Open Finance. Sem cartão de crédito. No fim do teste, a conta '
              'passa sozinha para o plano Grátis; nada é cobrado se você não '
              'assinar.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
