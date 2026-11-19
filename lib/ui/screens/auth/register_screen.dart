import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/cloud_config.dart';
import '../../../core/legal_links.dart';
import '../../../data/auth_service.dart';
import '../../../data/cloud/cloud_auth_service.dart';
import '../../../data/growth.dart';
import '../../../state/auth_controller.dart';
import '../../theme.dart';
import '../onboarding/onboarding_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool accepted = false;
  bool hidden = true;
  String? inviter;

  @override
  void initState() {
    super.initState();
    _loadInvite();
  }

  /// Convite no link (?ref=): mostra de quem é e o bônus de teste.
  Future<void> _loadInvite() async {
    final code = Growth.ref;
    final service = context.read<AuthController>().service;
    if (code == null || service is! CloudAuthService) return;
    try {
      final r = await service.api.get('referral/$code');
      if (mounted) setState(() => inviter = r['name'] as String?);
    } catch (_) {
      // Convite inválido ou sem internet: segue o cadastro normal.
    }
  }

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
            if (inviter != null) ...[
              const SizedBox(height: 12),
              Text(
                'Convite de $inviter: você ganha 15 dias a mais de teste do '
                'Premium.',
                key: const ValueKey('invite'),
                style: context.text.titleSmall,
              ),
            ],
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
              obscureText: hidden,
              decoration: InputDecoration(
                labelText: 'Senha',
                helperText: 'Mínimo de 8 caracteres, com letras e números',
                suffixIcon: IconButton(
                  tooltip: hidden ? 'Mostrar senha' : 'Esconder senha',
                  onPressed: () => setState(() => hidden = !hidden),
                  icon: Icon(
                    hidden ? Icons.visibility_outlined : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (v) => LocalAuthService.validatePassword(v ?? ''),
            ),
            if (CloudConfig.enabled) ...[
              const SizedBox(height: 16),
              TrialTerms(null, days: inviter == null ? 30 : 45),
            ],
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
