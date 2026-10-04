import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/auth_service.dart';
import '../../../state/auth_controller.dart';
import '../../../state/finance_controller.dart';
import '../../widgets/common.dart';

/// Pergunta (uma vez por abertura do app) se a pessoa quer levar para a
/// nuvem os dados que já estão neste aparelho, quando a conta na nuvem
/// ainda está vazia e o aparelho tem contas locais.
class CloudImportPrompt extends StatefulWidget {
  final Widget child;
  const CloudImportPrompt({super.key, required this.child});

  @override
  State<CloudImportPrompt> createState() => _CloudImportPromptState();
}

class _CloudImportPromptState extends State<CloudImportPrompt> {
  static bool _asked = false;

  Future<void> _maybeAsk() async {
    if (!await LocalAuthService().hasUsers() || !mounted) return;
    final go = await confirmDialog(
      context,
      title: 'Trazer os dados deste aparelho?',
      message:
          'Sua conta na nuvem ainda está vazia, e este aparelho tem lançamentos '
          'de uma conta antiga. Quer levá-los para a nuvem? Assim eles aparecem '
          'em todos os seus aparelhos.',
      confirm: 'Trazer dados',
    );
    if (go && mounted) await showImportFromDevice(context);
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    if (!_asked && !fc.loading && fc.cloudLooksNew) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
    }
    return widget.child;
  }
}

/// Pede e-mail e senha da conta deste aparelho e envia os dados dela para
/// a conta na nuvem (substituindo o que houver lá).
Future<void> showImportFromDevice(BuildContext context) async {
  final fc = context.read<FinanceController>();
  final me = context.read<AuthController>().user;
  final email = TextEditingController(text: me?.email ?? '');
  final password = TextEditingController();
  final key = GlobalKey<FormState>();
  String? error;
  var busy = false;
  final imported = await showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Trazer dados deste aparelho'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Entre com o e-mail e a senha da conta que você usava neste '
                'aparelho. Os dados dela vão substituir os da sua conta na nuvem.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('import-email'),
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail da conta do aparelho',
                ),
                validator: (v) => LocalAuthService.validateEmail(v ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('import-password'),
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha'),
                validator: (v) => (v ?? '').isEmpty ? 'Informe a senha' : null,
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!key.currentState!.validate()) return;
                    setS(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final local = await LocalAuthService().verify(
                        email.text,
                        password.text,
                      );
                      final n = await fc.importFromDevice(local.id);
                      if (ctx.mounted) Navigator.pop(ctx, n);
                    } catch (e) {
                      setS(() {
                        busy = false;
                        error = e is ArgumentError
                            ? e.message.toString()
                            : e.toString();
                      });
                    }
                  },
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Trazer dados'),
          ),
        ],
      ),
    ),
  );
  email.dispose();
  password.dispose();
  if (imported != null && context.mounted) {
    showMessage(context, '$imported registros levados para a nuvem');
  }
}
