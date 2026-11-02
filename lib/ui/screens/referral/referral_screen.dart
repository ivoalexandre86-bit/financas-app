import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../data/cloud/cloud_auth_service.dart';
import '../../../data/growth.dart';
import '../../../state/auth_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Situação do convite do usuário (servidor: `GET referral`).
class ReferralInfo {
  final String code;
  final int invited;
  final int pending;
  final int rewarded;
  final DateTime? bonusUntil;
  final int rewardDays;
  final int friendDays;
  final int maxRewardsPerYear;
  const ReferralInfo({
    required this.code,
    this.invited = 0,
    this.pending = 0,
    this.rewarded = 0,
    this.bonusUntil,
    this.rewardDays = 30,
    this.friendDays = 15,
    this.maxRewardsPerYear = 12,
  });

  factory ReferralInfo.fromJson(Map<String, Object?> j) {
    int n(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    final b = j['bonusUntil'];
    return ReferralInfo(
      code: j['code'] as String,
      invited: n('invited', 0),
      pending: n('pending', 0),
      rewarded: n('rewarded', 0),
      bonusUntil: b is String ? DateTime.tryParse(b) : null,
      rewardDays: n('rewardDays', 30),
      friendDays: n('friendDays', 15),
      maxRewardsPerYear: n('maxRewardsPerYear', 12),
    );
  }

  /// Link do convite: abre o app (site) com o código no cadastro.
  Uri get link => Uri.parse(
    'https://ivoalexandre86-bit.github.io/financas-app/?ref=$code&utm_source=indicacao',
  );

  String shareText() =>
      'Uso o app Finanças para organizar meu orçamento e ver a projeção dos '
      'próximos meses. Entrando pelo meu convite você ganha $friendDays dias '
      'a mais de teste do Premium: $link';
}

/// Indique e ganhe: link de convite, regras claras e resultado.
class ReferralScreen extends StatefulWidget {
  /// Para testes: carrega o convite sem a API.
  final Future<ReferralInfo> Function()? loader;
  const ReferralScreen({super.key, this.loader});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  late Future<ReferralInfo> _info = _load();

  Future<ReferralInfo> _load() {
    final custom = widget.loader;
    if (custom != null) return custom();
    final service = context.read<AuthController>().service;
    if (service is! CloudAuthService) {
      return Future.error(
        StateError('O convite está disponível com a conta na nuvem.'),
      );
    }
    return service.api.get('referral').then((j) => ReferralInfo.fromJson(j));
  }

  Future<void> _copy(ReferralInfo info) async {
    await Clipboard.setData(ClipboardData(text: info.shareText()));
    Growth.track('referral_share');
    if (mounted) showMessage(context, 'Convite copiado. Cole no WhatsApp.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Indique e ganhe')),
      body: FutureBuilder<ReferralInfo>(
        future: _info,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ErrorState(
              message: '${snap.error}',
              onRetry: () => setState(() => _info = _load()),
            );
          }
          return _body(context, snap.data!);
        },
      ),
    );
  }

  Widget _body(BuildContext context, ReferralInfo info) {
    final subtle = context.text.bodyMedium?.copyWith(color: context.fin.subtle);
    final bonus = info.bonusUntil;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Ganhe ${info.rewardDays} dias de Premium por amigo que assinar',
          style: context.text.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Seu amigo ganha ${info.friendDays} dias a mais de teste do Premium. '
          'Quando ele fizer a primeira assinatura paga, você ganha '
          '${info.rewardDays} dias de Premium.',
          style: subtle,
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Seu código', style: context.text.labelMedium),
                SelectableText(
                  info.code,
                  key: const ValueKey('referral-code'),
                  style: context.text.headlineMedium?.copyWith(
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText('${info.link}', style: context.text.bodySmall),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => _copy(info),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar convite'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _Stat('Convidados', '${info.invited}'),
            _Stat('Aguardando assinatura', '${info.pending}'),
            _Stat('Recompensas', '${info.rewarded}'),
          ],
        ),
        if (bonus != null && bonus.isAfter(DateTime.now())) ...[
          const SizedBox(height: 12),
          Text(
            'Seu Premium por indicação vai até ${Dates.format(bonus.toLocal())}.',
            style: context.text.titleSmall,
          ),
        ],
        const SizedBox(height: 24),
        Text('Regras', style: context.text.titleMedium),
        const SizedBox(height: 8),
        for (final r in [
          'Vale para quem cria a conta pelo seu link ou com o seu código.',
          'A recompensa sai quando o amigo faz a primeira cobrança da '
              'assinatura; só o teste grátis não conta.',
          'Contas da mesma pessoa (mesmo e-mail com apelido ou mesmo '
              'aparelho) não contam como indicação.',
          'Até ${info.maxRewardsPerYear} recompensas por ano. Os dias se '
              'somam e valem mesmo sem assinatura; com o Básico, você usa o '
              'Premium enquanto durarem.',
          'Os dias de Premium não são dinheiro, não têm valor de troca e não '
              'alteram a cobrança da loja.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(r, style: subtle)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: context.text.headlineSmall),
        Text(
          label,
          style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
