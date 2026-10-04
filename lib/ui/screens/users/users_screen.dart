import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/cloud_config.dart';
import '../../../data/auth_service.dart';
import '../../../state/auth_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Lista de usuários do dispositivo (somente administradores). Cada usuário
/// entra com o próprio e-mail e senha e tem um orçamento separado.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<AppUser>> _users;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      setState(() => _users = context.read<AuthController>().listUsers());

  Future<void> _open([AppUser? user]) async {
    final changed = await push<bool>(context, UserFormScreen(user: user));
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthController>().user;
    return Scaffold(
      appBar: AppBar(title: const Text('Usuários')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('new-user'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Novo usuário'),
        onPressed: () => _open(),
      ),
      body: FutureBuilder<List<AppUser>>(
        future: _users,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorState(message: '${snap.error}', onRetry: _reload);
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snap.data!;
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Cada usuário entra com o próprio e-mail e senha e vê apenas o próprio orçamento. '
                  'Os usuários ficam salvos neste navegador/dispositivo.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
              ),
              for (final u in users)
                ListTile(
                  key: ValueKey('user-${u.email}'),
                  leading: CircleAvatar(
                    child: Text(
                      u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                    ),
                  ),
                  title: Text(u.id == me?.id ? '${u.name} (você)' : u.name),
                  subtitle: Text(u.email),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (u.isAdmin)
                        Pill('Administrador', color: context.colors.primary),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _open(u),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Cria (sem [user]) ou edita um usuário. Retorna `true` se algo mudou.
class UserFormScreen extends StatefulWidget {
  final AppUser? user;
  const UserFormScreen({super.key, this.user});
  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.user?.name);
  late final email = TextEditingController(text: widget.user?.email);
  final password = TextEditingController();
  final confirm = TextEditingController();
  late bool isAdmin = widget.user?.isAdmin ?? false;
  bool busy = false;

  bool get _editing => widget.user != null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    setState(() => busy = true);
    final ok = await runAction(
      context,
      () => _editing
          ? auth.updateUser(
              widget.user!.id,
              name: name.text,
              email: email.text,
              isAdmin: isAdmin,
            )
          : auth.createUser(
              name.text,
              email.text,
              password.text,
              isAdmin: isAdmin,
            ),
      success: _editing ? 'Usuário atualizado' : 'Usuário criado',
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _resetPassword() async {
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _NewPasswordDialog(title: 'Redefinir senha'),
    );
    if (r == null || !mounted) return;
    await runAction(
      context,
      () => context.read<AuthController>().resetPassword(widget.user!.id, r.$2),
      success: 'Senha redefinida',
    );
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Excluir usuário?',
      message:
          'O usuário ${widget.user!.name} e todo o orçamento dele (contas, transações, cartões, painéis) serão apagados ${CloudConfig.enabled ? 'da nuvem' : 'deste dispositivo'}. Esta ação não pode ser desfeita.',
      confirm: 'Excluir definitivamente',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final done = await runAction(
      context,
      () => context.read<AuthController>().deleteUser(widget.user!.id),
      success: 'Usuário excluído',
    );
    if (done && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.user?.id == context.watch<AuthController>().user?.id;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar usuário' : 'Novo usuário')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              key: const ValueKey('user-name'),
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('user-email'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail (login)'),
              validator: (v) => LocalAuthService.validateEmail(v ?? ''),
            ),
            if (!_editing) ...[
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('user-password'),
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha inicial',
                  helperText: 'Mínimo de 8 caracteres, com letras e números',
                ),
                validator: (v) => LocalAuthService.validatePassword(v ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('user-confirm'),
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmar senha'),
                validator: (v) =>
                    v != password.text ? 'As senhas não conferem' : null,
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('user-admin'),
              contentPadding: EdgeInsets.zero,
              value: isAdmin,
              onChanged: (v) => setState(() => isAdmin = v),
              title: const Text('Administrador'),
              subtitle: const Text(
                'Pode criar, editar e excluir usuários. O orçamento de cada um continua separado.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('user-save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: busy ? null : _save,
              child: Text(_editing ? 'Salvar' : 'Criar usuário'),
            ),
            if (_editing) ...[
              const SizedBox(height: 24),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_reset),
                title: const Text('Redefinir senha'),
                subtitle: const Text('Define uma nova senha para este usuário'),
                onTap: _resetPassword,
              ),
              if (!isMe)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: context.colors.error,
                  ),
                  title: Text(
                    'Excluir usuário',
                    style: TextStyle(color: context.colors.error),
                  ),
                  subtitle: const Text('Apaga o usuário e o orçamento dele'),
                  onTap: _delete,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pede uma nova senha (com confirmação) e, se [askCurrent], a senha atual.
/// Retorna `(senhaAtual, novaSenha)`.
class _NewPasswordDialog extends StatefulWidget {
  final String title;
  final bool askCurrent;
  const _NewPasswordDialog({required this.title, this.askCurrent = false});
  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _form = GlobalKey<FormState>();
  final current = TextEditingController();
  final pw = TextEditingController();
  final confirm = TextEditingController();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.askCurrent)
            TextFormField(
              key: const ValueKey('pw-current'),
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha atual'),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Informe a senha atual' : null,
            ),
          TextFormField(
            key: const ValueKey('pw-new'),
            controller: pw,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Nova senha',
              helperText: 'Mínimo de 8 caracteres, com letras e números',
            ),
            validator: (v) => LocalAuthService.validatePassword(v ?? ''),
          ),
          TextFormField(
            key: const ValueKey('pw-confirm'),
            controller: confirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirmar senha'),
            validator: (v) => v != pw.text ? 'As senhas não conferem' : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, (current.text, pw.text));
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}

/// Troca da própria senha (qualquer usuário), a partir de Configurações.
Future<void> changeOwnPassword(BuildContext context) async {
  final r = await showDialog<(String, String)>(
    context: context,
    builder: (_) =>
        const _NewPasswordDialog(title: 'Alterar senha', askCurrent: true),
  );
  if (r == null || !context.mounted) return;
  await runAction(
    context,
    () => context.read<AuthController>().changePassword(r.$1, r.$2),
    success: 'Senha alterada',
  );
}
