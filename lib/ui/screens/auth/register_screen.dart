import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/auth_service.dart';
import '../../../state/auth_controller.dart';
import '../../theme.dart';

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
                'Li e aceito a política de privacidade e o tratamento dos meus dados conforme a LGPD.',
              ),
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
