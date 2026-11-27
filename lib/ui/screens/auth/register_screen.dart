import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/cloud_config.dart';
import '../../../core/legal_links.dart';
import '../../../data/auth_service.dart';
import '../../../data/cloud/invite_api.dart';
import '../../../state/auth_controller.dart';
import '../../theme.dart';

class RegisterScreen extends StatefulWidget {
  /// Convite pelo WhatsApp que trouxe a pessoa (nome já preenchido).
  final InviteInfo? invite;
  const RegisterScreen({super.key, this.invite});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.invite?.name ?? '');
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool accepted = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.invite != null) ...[
              Card(
                key: const ValueKey('register-invite'),
                color: context.colors.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Você foi selecionado(a) por '
                        '${widget.invite!.inviterName}',
                        style: context.text.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.invite!.joinAccount && widget.invite!.limited
                            ? 'Ao criar a conta, você vê e lança nos cartões e '
                                  'contas que ${widget.invite!.inviterName} '
                                  'liberou para você, e o seu WhatsApp já fica '
                                  'ligado ao bot.'
                            : widget.invite!.joinAccount
                            ? 'Ao criar a conta, você passa a usar o orçamento '
                                  'de ${widget.invite!.inviterName}, e o seu '
                                  'WhatsApp já fica ligado ao bot.'
                            : 'Ao criar a conta, você ganha o seu próprio '
                                  'orçamento, e o seu WhatsApp já fica ligado '
                                  'ao bot.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              CloudConfig.enabled
                  ? 'Crie sua conta: seus dados ficam na nuvem e aparecem '
                        'em todos os seus aparelhos.'
                  : 'Esta é a primeira conta deste dispositivo e será a de '
                        'administrador. Depois, novos usuários são criados em '
                        'Mais › Usuários.',
              style: context.text.bodyMedium?.copyWith(
                color: context.fin.subtle,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe seu nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
              validator: (v) => LocalAuthService.validateEmail(v ?? ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Senha',
                helperText: 'Mínimo de 8 caracteres, com letras e números',
              ),
              validator: (v) => LocalAuthService.validatePassword(v ?? ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmar senha'),
              validator: (v) =>
                  v != password.text ? 'As senhas não conferem' : null,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: accepted,
              onChanged: (v) => setState(() => accepted = v ?? false),
              title: const Text(
                'Li e aceito os termos de uso, a política de privacidade e o '
                'tratamento dos meus dados conforme a LGPD.',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => LegalLinks.open(LegalLinks.terms),
                  child: const Text('Ler os termos de uso'),
                ),
                TextButton(
                  onPressed: () => LegalLinks.open(LegalLinks.privacy),
                  child: const Text('Ler a política de privacidade'),
                ),
              ],
            ),
            if (auth.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  auth.error!,
                  style: TextStyle(color: context.colors.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: auth.busy || !accepted
                  ? null
                  : () async {
                      if (!_form.currentState!.validate()) return;
                      final ok = await auth.register(
                        name.text,
                        email.text,
                        password.text,
                      );
                      if (ok && context.mounted) Navigator.pop(context);
                    },
              child: const Text('Criar conta'),
            ),
          ],
        ),
      ),
    );
  }
}
