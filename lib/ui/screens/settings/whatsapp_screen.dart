import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/cloud/api_client.dart';
import '../../../data/cloud/cloud_auth_service.dart';
import '../../../state/auth_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Situação do WhatsApp para o usuário logado (GET /whatsapp/status).
class WhatsAppStatus {
  final bool enabled;
  final String? botNumber;
  final bool audio;
  final String? linkedNumber;
  const WhatsAppStatus({
    required this.enabled,
    this.botNumber,
    this.audio = false,
    this.linkedNumber,
  });

  factory WhatsAppStatus.fromJson(Map<String, Object?> j) => WhatsAppStatus(
    enabled: j['enabled'] == true,
    botNumber: j['botNumber'] as String?,
    audio: j['audio'] == true,
    linkedNumber: j['linkedNumber'] as String?,
  );
}

/// Formata "5511999990000" como "+55 11 99999-0000" (outros países: +dígitos).
String formatPhone(String digits) {
  final m = RegExp(r'^55(\d{2})(\d{4,5})(\d{4})$').firstMatch(digits);
  if (m == null) return '+$digits';
  return '+55 ${m[1]} ${m[2]}-${m[3]}';
}

/// Configurações › WhatsApp: liga o número do usuário ao bot que registra
/// despesas e receitas enviadas por mensagem.
class WhatsAppScreen extends StatefulWidget {
  /// Cliente da API (padrão: o da sessão na nuvem).
  final ApiClient? api;
  const WhatsAppScreen({super.key, this.api});

  @override
  State<WhatsAppScreen> createState() => _WhatsAppScreenState();
}

class _WhatsAppScreenState extends State<WhatsAppScreen> {
  WhatsAppStatus? status;
  Object? error;
  ({String code, String text, String? url})? link;
  bool busy = false;

  ApiClient get api =>
      widget.api ??
      (context.read<AuthController>().service as CloudAuthService).api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final s = WhatsAppStatus.fromJson(await api.get('whatsapp/status'));
      if (!mounted) return;
      setState(() {
        status = s;
        if (s.linkedNumber != null) link = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> _newCode() async {
    setState(() => busy = true);
    await runAction(context, () async {
      final r = await api.post('whatsapp/link-code');
      setState(
        () => link = (
          code: r['code'] as String,
          text: r['text'] as String,
          url: r['url'] as String?,
        ),
      );
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _open(String url) async {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      if (mounted) {
        showMessage(context, 'Não consegui abrir o WhatsApp', error: true);
      }
    }
  }

  Future<void> _unlink() async {
    final ok = await confirmDialog(
      context,
      title: 'Desvincular WhatsApp?',
      message: 'Mensagens deste número deixam de ser lançadas na sua conta. Você pode vincular de novo quando quiser.',
      confirm: 'Desvincular',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await runAction(context, () async {
      await api.delete('whatsapp/link');
      await _load();
    }, success: 'WhatsApp desvinculado');
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp')),
      body: error != null
          ? _ErrorView(error: error!, onRetry: _load)
          : s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Lance despesas e receitas mandando uma mensagem: texto, foto do cupom ou comprovante${s.audio ? ' ou áudio' : ''}. '
                    'O bot mostra um resumo e só grava depois que você tocar em Confirmar.',
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (!s.enabled)
                    const _Note(
                      icon: Icons.info_outline,
                      text: 'O WhatsApp ainda não foi configurado no servidor. Assim que estiver ativo, o vínculo aparece aqui.',
                    )
                  else if (s.linkedNumber != null)
                    ..._linked(s)
                  else
                    ..._unlinked(s),
                  const SizedBox(height: 24),
                  Text('Exemplos', style: context.text.titleSmall),
                  const SizedBox(height: 8),
                  for (final e in const [
                    'gastei 45,90 no mercado',
                    'uber 23 ontem no cartão Nubank',
                    'tênis 600 em 3x no cartão',
                    'recebi 3500 de salário',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $e', style: context.text.bodyMedium),
                    ),
                ],
              ),
            ),
    );
  }

  List<Widget> _linked(WhatsAppStatus s) => [
    _Note(
      icon: Icons.check_circle_outline,
      color: context.fin.positive,
      text: 'Ligado ao número ${formatPhone(s.linkedNumber!)}.',
    ),
    const SizedBox(height: 12),
    if (s.botNumber != null)
      FilledButton.icon(
        key: const ValueKey('wa-open-chat'),
        icon: const Icon(Icons.chat_outlined),
        label: const Text('Abrir conversa com o bot'),
        onPressed: () => _open('https://wa.me/${s.botNumber}'),
      ),
    const SizedBox(height: 8),
    OutlinedButton.icon(
      key: const ValueKey('wa-unlink'),
      icon: const Icon(Icons.link_off),
      label: const Text('Desvincular'),
      onPressed: _unlink,
    ),
  ];

  List<Widget> _unlinked(WhatsAppStatus s) {
    final l = link;
    if (l == null) {
      return [
        FilledButton.icon(
          key: const ValueKey('wa-link'),
          icon: const Icon(Icons.link),
          label: const Text('Vincular meu WhatsApp'),
          onPressed: busy ? null : _newCode,
        ),
      ];
    }
    return [
      Text(
        'Envie esta mensagem para o bot pelo WhatsApp do número que você quer usar:',
        style: context.text.bodyMedium,
      ),
      const SizedBox(height: 12),
      Center(
        child: SelectableText(
          l.text,
          key: const ValueKey('wa-code'),
          style: context.text.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ),
      if (s.botNumber != null) ...[
        const SizedBox(height: 4),
        Center(
          child: Text(
            'para ${formatPhone(s.botNumber!)}',
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
        ),
      ],
      const SizedBox(height: 4),
      Center(
        child: Text(
          'O código vale por 10 minutos.',
          style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
        ),
      ),
      const SizedBox(height: 16),
      if (l.url != null)
        FilledButton.icon(
          key: const ValueKey('wa-open'),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Abrir no WhatsApp'),
          onPressed: () => _open(l.url!),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.copy),
        label: const Text('Copiar mensagem'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: l.text));
          if (mounted) showMessage(context, 'Mensagem copiada');
        },
      ),
      const SizedBox(height: 8),
      TextButton(
        key: const ValueKey('wa-check'),
        onPressed: _load,
        child: const Text('Já enviei'),
      ),
    ];
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _Note({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color ?? context.fin.subtle),
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: context.text.bodyMedium)),
    ],
  );
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Tentar de novo'),
          ),
        ],
      ),
    ),
  );
}
