import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/cloud/cloud_auth_service.dart';
import '../../../data/cloud/invite_api.dart';
import '../../../state/auth_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// API dos convites pelo WhatsApp (nula sem a nuvem ou na demonstração).
InviteApi? inviteApiOf(BuildContext context) {
  final auth = context.read<AuthController>();
  final s = auth.service;
  if (s is! CloudAuthService || auth.user == null || auth.user!.isDemo) {
    return null;
  }
  return HttpInviteApi(s.api);
}

/// Convidar pessoas pelo WhatsApp (somente administradores): o bot manda a
/// mensagem com o link de cadastro para o número informado.
class InvitesScreen extends StatefulWidget {
  final InviteApi? api;
  final Future<void> Function(Uri url)? openUrl;
  const InvitesScreen({super.key, this.api, this.openUrl});
  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> {
  late final InviteApi? _api = widget.api ?? inviteApiOf(context);
  Future<InvitesState>? _state;
  InviteTemplate? _template;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final api = _api;
    if (api == null) return;
    final next = api.list().then((s) {
      _template = s.template;
      return s;
    });
    setState(() {
      _state = next;
    });
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    final open = widget.openUrl;
    if (open != null) return open(uri);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copy(WhatsAppInvite i) async {
    await Clipboard.setData(ClipboardData(text: i.link));
    if (mounted) showMessage(context, 'Link do convite copiado');
  }

  /// Depois de criar ou reenviar: avisa se o bot mandou ou oferece o envio
  /// pelo WhatsApp do próprio administrador.
  Future<void> _after(WhatsAppInvite i, InviteTemplate t) async {
    _template = t;
    _reload();
    if (!mounted) return;
    if (i.sentByBot) {
      showMessage(context, 'Convite enviado pelo WhatsApp para ${i.name}');
      return;
    }
    final manual = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Envie pelo seu WhatsApp'),
        content: Text(
          i.sendStatus == 'failed'
              ? 'O bot não conseguiu enviar a mensagem (${i.sendError ?? 'erro na Meta'}). '
                    'Você pode mandar o convite pelo seu próprio WhatsApp: '
                    'o texto e o link já vão prontos.'
              : '${i.sendError ?? 'O bot ainda não pode enviar o convite.'} '
                    'Enquanto isso, mande pelo seu próprio WhatsApp: o texto e '
                    'o link já vão prontos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Agora não'),
          ),
          FilledButton.icon(
            key: const ValueKey('invite-send-manual'),
            icon: const Icon(Icons.send),
            onPressed: () => Navigator.pop(ctx, true),
            label: const Text('Abrir o WhatsApp'),
          ),
        ],
      ),
    );
    if (manual == true) await _open(i.shareUrl);
  }

  Future<void> _new() async {
    final created = await showDialog<(WhatsAppInvite, InviteTemplate)>(
      context: context,
      builder: (_) => _InviteDialog(api: _api!),
    );
    if (created != null) await _after(created.$1, created.$2);
  }

  Future<void> _resend(WhatsAppInvite i) async {
    try {
      final r = await _api!.resend(i.id);
      await _after(r.$1, r.$2);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  Future<void> _cancel(WhatsAppInvite i) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancelar o convite de ${i.name}?',
      message: 'O link enviado deixa de valer.',
      confirm: 'Cancelar convite',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await _api!.cancel(i.id);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convidar pelo WhatsApp')),
      floatingActionButton: _api == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('new-invite'),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Convidar'),
              onPressed: _new,
            ),
      body: _api == null
          ? const EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Disponível com a conta na nuvem',
              message:
                  'Os convites pelo WhatsApp usam o servidor do app. Entre '
                  'com a sua conta (não a de demonstração).',
            )
          : FutureBuilder<InvitesState>(
              future: _state,
              builder: (context, snap) {
                if (snap.hasError) {
                  // Servidor sem a rota de convites (ainda não atualizado).
                  if ('${snap.error}'.contains('404')) {
                    return EmptyState(
                      icon: Icons.cloud_sync_outlined,
                      title: 'Servidor ainda não atualizado',
                      message:
                          'Os convites pelo WhatsApp precisam da versão nova '
                          'do servidor. Tente de novo em alguns minutos.',
                      actionLabel: 'Tentar de novo',
                      onAction: _reload,
                    );
                  }
                  return ErrorState(message: '${snap.error}', onRetry: _reload);
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final s = snap.data!;
                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _state;
                  },
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'Informe o nome e o WhatsApp da pessoa. O bot manda uma '
                          'mensagem dizendo que ela foi selecionada para participar '
                          'do sistema, com o botão para fazer o cadastro. Quando '
                          'ela cria a conta, o WhatsApp dela já fica ligado ao bot.',
                          style: context.text.bodySmall?.copyWith(
                            color: context.fin.subtle,
                          ),
                        ),
                      ),
                      _TemplateBanner(_template ?? s.template),
                      if (s.invites.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 32),
                          child: EmptyState(
                            icon: Icons.forward_to_inbox_outlined,
                            title: 'Nenhum convite ainda',
                            message: 'Toque em Convidar para chamar alguém.',
                          ),
                        ),
                      for (final i in s.invites) _tile(context, i),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _tile(BuildContext context, WhatsAppInvite i) {
    final (label, color) = _statusOf(context, i);
    return ListTile(
      key: ValueKey('invite-${i.phone}'),
      leading: CircleAvatar(
        child: Text(i.name.isNotEmpty ? i.name[0].toUpperCase() : '?'),
      ),
      title: Text(i.name),
      subtitle: Text(
        [
          i.phoneLabel,
          if (i.joinAccount) 'usa o seu orçamento',
          if (i.isAccepted && i.userName != null) 'conta: ${i.userName}',
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pill(label, color: color),
          if (!i.isAccepted)
            PopupMenuButton<String>(
              key: ValueKey('invite-menu-${i.phone}'),
              onSelected: (v) => switch (v) {
                'resend' => _resend(i),
                'manual' => _open(i.shareUrl),
                'copy' => _copy(i),
                _ => _cancel(i),
              },
              itemBuilder: (_) => [
                if (i.isPending || i.status == 'expired')
                  const PopupMenuItem(
                    value: 'resend',
                    child: Text('Reenviar pelo bot'),
                  ),
                if (i.isPending) ...const [
                  PopupMenuItem(
                    value: 'manual',
                    child: Text('Enviar pelo meu WhatsApp'),
                  ),
                  PopupMenuItem(value: 'copy', child: Text('Copiar link')),
                ],
                const PopupMenuItem(
                  value: 'cancel',
                  child: Text('Cancelar convite'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  (String, Color) _statusOf(BuildContext context, WhatsAppInvite i) {
    final fin = context.fin;
    if (i.isAccepted) return ('Cadastrado', fin.positive);
    if (i.status == 'expired') return ('Vencido', fin.subtle);
    return switch (i.sendStatus) {
      'read' => ('Lido', context.colors.primary),
      'delivered' => ('Entregue', context.colors.primary),
      'sent' => ('Enviado', context.colors.primary),
      'failed' => ('Falhou', fin.negative),
      _ => ('Não enviado', fin.warning),
    };
  }
}

class _TemplateBanner extends StatelessWidget {
  final InviteTemplate t;
  const _TemplateBanner(this.t);

  @override
  Widget build(BuildContext context) {
    if (t.approved) return const SizedBox.shrink();
    final (icon, text) = switch (t.status) {
      'OFF' => (
        Icons.power_off_outlined,
        'O bot do WhatsApp está desligado no servidor. Mande os convites '
            'pelo seu WhatsApp (menu de cada convite).',
      ),
      'REJECTED' || 'DISABLED' || 'PAUSED' => (
        Icons.block,
        'A Meta não liberou a mensagem de convite'
            '${t.rejectedReason != null ? ' (${t.rejectedReason})' : ''}. '
            'Mande os convites pelo seu WhatsApp (menu de cada convite).',
      ),
      _ => (
        Icons.hourglass_top,
        'A Meta está analisando a mensagem de convite (costuma levar de '
            'minutos a 1 dia). Até lá, o convite fica registrado e você manda '
            'pelo seu WhatsApp, com o texto e o link prontos.',
      ),
    };
    return Card(
      key: const ValueKey('invite-template-banner'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ListTile(
        leading: Icon(icon, color: context.fin.warning),
        title: Text(text, style: context.text.bodyMedium),
      ),
    );
  }
}

class _InviteDialog extends StatefulWidget {
  final InviteApi api;
  const _InviteDialog({required this.api});
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _form = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  bool joinAccount = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.create(
        name: name.text.trim(),
        phone: phone.text.trim(),
        joinAccount: joinAccount,
      );
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Convidar pelo WhatsApp'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('invite-name'),
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('invite-phone'),
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp',
                hintText: '(47) 99999-1234',
                helperText: 'DDD + número. Outro país: comece com +',
              ),
              validator: (v) {
                final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return d.length < 10 ? 'Informe DDD + número' : null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('invite-join'),
              contentPadding: EdgeInsets.zero,
              value: joinAccount,
              onChanged: (v) => setState(() => joinAccount = v),
              title: const Text('Usar o meu orçamento'),
              subtitle: Text(
                joinAccount
                    ? 'A pessoa entra na sua conta e vê e lança no mesmo orçamento.'
                    : 'A pessoa cria um orçamento próprio, separado do seu.',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: context.colors.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('invite-submit'),
        onPressed: busy ? null : _submit,
        child: const Text('Enviar convite'),
      ),
    ],
  );
}
