import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/auth_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 32),
                    Text('Entrar', style: context.text.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Acompanhe hoje e planeje os próximos meses.',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.fin.subtle,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-mail'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Informe o e-mail'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: password,
                      obscureText: obscure,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => obscure = !obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Informe a senha' : null,
                      onFieldSubmitted: (_) => _submit(auth),
                    ),
                    if (auth.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        auth.error!,
                        style: TextStyle(color: context.colors.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: auth.busy ? null : () => _submit(auth),
                      child: auth.busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: () => push(context, const RegisterScreen()),
                      child: const Text('Criar conta'),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'ou',
                            style: TextStyle(color: context.fin.subtle),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.science_outlined),
                      label: const Text('Explorar com dados de exemplo'),
                      onPressed: auth.busy ? null : auth.enterDemo,
                    ),
                    Text(
                      'A conta de demonstração usa dados fictícios, separados das contas reais.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall?.copyWith(
                        color: context.fin.subtle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit(AuthController auth) {
    if (_form.currentState!.validate()) {
      auth.login(email.text, password.text);
    }
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.colors.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.insights, color: Colors.white),
      ),
      const SizedBox(width: 12),
      Text(
        'Finanças',
        style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    ],
  );
}
