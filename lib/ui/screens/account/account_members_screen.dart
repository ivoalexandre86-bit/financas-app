import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/cloud/account_api.dart';
import '../../../data/cloud/cloud_auth_service.dart';
import '../../../data/cloud/cloud_finance_repository.dart';
import '../../../state/auth_controller.dart';
import '../../../state/finance_controller.dart';
import '../../widgets/common.dart';

const _appLink = 'https://ivoalexandre86-bit.github.io/financas-app/';

/// API da conta compartilhada para o usuário logado (nula sem a nuvem ou na
/// demonstração).
AccountApi? accountApiOf(BuildContext context) {
  final auth = context.read<AuthController>();
  final s = auth.service;
  if (s is! CloudAuthService || auth.user == null || auth.user!.isDemo) {
    return null;
  }
  return HttpAccountApi(s.api);
}

/// Troca a conta em uso (aceitar convite, sair, ser removido): envia antes
/// o que ainda não subiu, para não gravar na conta errada, e depois relê a
/// conta — o app recarrega com os dados da nova conta.
Future<void> switchAccount(
  BuildContext context,
  Future<void> Function() op,
) async {
  final fc = context.read<FinanceController>();
  final auth = context.read<AuthController>();
  final repo = fc.repo;
  if (repo is CloudFinanceRepository) await repo.flush(throwOnError: true);
  await op();
  await auth.reloadUser();
}

/// Conta com vários usuários: o dono convida pessoas (pelo e-mail) para usar
/// o mesmo orçamento, cada uma com o próprio login.
class AccountMembersScreen extends StatefulWidget {
  /// Para testes; padrão: a API do servidor.
  final AccountApi? api;
  const AccountMembersScreen({super.key, this.api});

  @override
  State<AccountMembersScreen> createState() => _AccountMembersScreenState();
}

class _AccountMembersScreenState extends State<AccountMembersScreen> {
  late final AccountApi? _api = widget.api ?? accountApiOf(context);
  Future<AccountState>? _state;
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _reload() {
    final api = _api;
    if (api == null) return;
    final next = api.state();
    setState(() {
      _state = next;
    });
  }

  Future<void> _run(
    Future<AccountState> Function() op, {
    String? success,
  }) async {
    setState(() => _busy = true);
    try {
      final s = await op();
      if (!mounted) return;
      setState(() {
        _state = Future.value(s);
      });
      if (success != null) showMessage(context, success);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim();
    await _run(
      () => _api!.invite(email),
      success: 'Convite enviado para $email',
    );
    if (mounted) _email.clear();
  }

  Future<void> _remove(AccountMember m) async {
    final ok = await confirmDialog(
      context,
      title: m.isInvited ? 'Cancelar convite?' : 'Remover ${m.label}?',
      message: m.isInvited
          ? 'O convite para ${m.email} deixa de valer.'
          : '${m.label} deixa de ver e lançar neste orçamento e volta a usar '
                'a própria conta. Os lançamentos que fez aqui continuam aqui.',
      confirm: m.isInvited ? 'Cancelar convite' : 'Remover',
      destructive: true,
    );
    if (ok && mounted) await _run(() => _api!.remove(m.id!));
  }

  Future<void> _leave(AccountState s) async {
    final ok = await confirmDialog(
      context,
      title: 'Sair da conta de ${s.ownerName}?',
      message:
          'Você deixa de ver este orçamento e volta para os seus próprios '
          'dados. Os lançamentos que você fez aqui continuam na conta de '
          '${s.ownerName}.',
      confirm: 'Sair da conta',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _switchTo(() => _api!.leave());
  }

  Future<void> _accept(AccountState s, AccountInvite i) async {
    final ok = await confirmDialog(
      context,
      title: 'Usar a conta de ${i.ownerName}?',
      message:
          'Você passa a ver e lançar no orçamento de ${i.ownerName}, com o seu '
          'login. ${s.isOwner ? 'Os seus dados atuais ficam guardados e voltam se você sair da conta.' : 'Você sai da conta de ${s.ownerName}.'}',
      confirm: 'Aceitar',
    );
    if (!ok || !mounted) return;
    await _switchTo(() => _api!.accept(i.id));
  }

  Future<void> _switchTo(Future<AccountState> Function() op) async {
    setState(() => _busy = true);
    try {
      await switchAccount(context, op);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyInvite(AccountState s, String? email) async {
    final msg =
        '${s.ownerName} convidou você para usar o mesmo orçamento no app '
        'Finanças. Entre em $_appLink com '
        '${email == null ? 'o seu e-mail' : 'o e-mail $email'} (ou crie a '
        'conta com ele) e aceite o convite em Configurações › Pessoas na conta.';
    await Clipboard.setData(ClipboardData(text: msg));
    if (mounted) showMessage(context, 'Mensagem de convite copiada');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pessoas na conta')),
      body: _api == null
          ? const EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Disponível com a conta na nuvem',
              message:
                  'Entre com a sua conta (e-mail e senha) para convidar '
                  'outras pessoas para o mesmo orçamento.',
            )
          : FutureBuilder<AccountState>(
              future: _state,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorState(message: '${snap.error}', onRetry: _reload);
                }
                final s = snap.data;
                if (s == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return AbsorbPointer(
                  absorbing: _busy,
                  child: _body(context, s),
                );
              },
            ),
    );
  }

  Widget _body(BuildContext context, AccountState s) {
    final theme = Theme.of(context);
    final me = Provider.of<AuthController?>(context, listen: false)?.user;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_busy) const LinearProgressIndicator(),
        for (final i in s.invites)
          Card(
            key: ValueKey('invite-${i.id}'),
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Convite de ${i.ownerName}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${i.ownerName} (${i.ownerEmail}) convidou você para usar '
                    'o mesmo orçamento.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        key: ValueKey('accept-${i.id}'),
                        onPressed: () => _accept(s, i),
                        child: const Text('Aceitar'),
                      ),
                      OutlinedButton(
                        onPressed: () => _run(
                          () => _api!.reject(i.id),
                          success: 'Convite recusado',
                        ),
                        child: const Text('Recusar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.isOwner
                      ? 'Sua conta'
                      : 'Você está usando a conta de ${s.ownerName}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  s.isOwner
                      ? 'Convide quem divide o orçamento com você. Cada pessoa '
                            'entra com o próprio e-mail e senha, e todos veem e '
                            'lançam nas mesmas contas, cartões e transações, em '
                            'qualquer aparelho.'
                      : 'Você vê e lança no orçamento de ${s.ownerName}. Os '
                            'seus próprios dados estão guardados e voltam se '
                            'você sair desta conta.',
                ),
                if (!s.isOwner) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('leave-account'),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sair desta conta'),
                    onPressed: () => _leave(s),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text('Pessoas', style: theme.textTheme.titleSmall),
        ),
        Card(
          child: Column(
            children: [
              for (final m in s.members)
                ListTile(
                  key: ValueKey('member-${m.email}'),
                  leading: CircleAvatar(
                    child: Text(m.label.characters.first.toUpperCase()),
                  ),
                  title: Text(
                    m.userId != null && m.userId == me?.id
                        ? '${m.label} (você)'
                        : m.label,
                  ),
                  subtitle: Text(switch (m.status) {
                    'owner' => 'Dono da conta · ${m.email}',
                    'invited' => 'Convite pendente · ${m.email}',
                    _ => m.email,
                  }),
                  trailing: !s.isOwner || m.isOwner
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (m.isInvited)
                              IconButton(
                                tooltip: 'Copiar mensagem de convite',
                                icon: const Icon(Icons.copy_outlined),
                                onPressed: () => _copyInvite(s, m.email),
                              ),
                            IconButton(
                              key: ValueKey('remove-${m.email}'),
                              tooltip: m.isInvited
                                  ? 'Cancelar convite'
                                  : 'Remover',
                              icon: const Icon(Icons.person_remove_outlined),
                              onPressed: () => _remove(m),
                            ),
                          ],
                        ),
                ),
            ],
          ),
        ),
        if (s.isOwner) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text('Convidar pessoa', style: theme.textTheme.titleSmall),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: s.guestCount >= s.maxMembers
                  ? Text(
                      'A conta já tem ${s.maxMembers} pessoas além de você '
                      '(o máximo).',
                    )
                  : Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            key: const ValueKey('invite-email'),
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'E-mail da pessoa',
                              prefixIcon: Icon(Icons.alternate_email),
                            ),
                            validator: (v) =>
                                RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch((v ?? '').trim())
                                ? null
                                : 'Informe um e-mail válido',
                            onFieldSubmitted: (_) => _invite(),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'A pessoa entra no app com este e-mail (ou cria a '
                            'conta com ele) e aceita o convite, que aparece ao '
                            'abrir o app e em Configurações › Pessoas na conta.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const ValueKey('send-invite'),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Convidar'),
                            onPressed: _invite,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Ao abrir o app com convite pendente, pergunta (uma vez por abertura) se a
/// pessoa quer entrar na conta de quem convidou.
class AccountInvitePrompt extends StatefulWidget {
  final Widget child;
  const AccountInvitePrompt({super.key, required this.child});

  @override
  State<AccountInvitePrompt> createState() => _AccountInvitePromptState();
}

class _AccountInvitePromptState extends State<AccountInvitePrompt> {
  static final _asked = <String>{};

  Future<void> _ask() async {
    final api = accountApiOf(context);
    if (api == null) return;
    final AccountState s;
    try {
      s = await api.state();
    } catch (_) {
      return;
    }
    if (s.invites.isEmpty || !mounted) return;
    final i = s.invites.first;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Convite de ${i.ownerName}'),
        content: Text(
          '${i.ownerName} (${i.ownerEmail}) convidou você para usar o mesmo '
          'orçamento, com o seu login. '
          '${s.isOwner ? 'Os seus dados atuais ficam guardados e voltam se você sair da conta.' : 'Você sai da conta de ${s.ownerName}.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Agora não'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Recusar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aceitar'),
          ),
        ],
      ),
    );
    if (go == null || !mounted) return;
    try {
      if (go) {
        await switchAccount(context, () => api.accept(i.id));
      } else {
        await api.reject(i.id);
        if (mounted) await context.read<AuthController>().reloadUser();
      }
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final fc = context.watch<FinanceController>();
    if (user != null &&
        user.pendingInvites > 0 &&
        !fc.loading &&
        _asked.add(user.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
    }
    return widget.child;
  }
}
