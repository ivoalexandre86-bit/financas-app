import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../state/auth_controller.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Tela que cobre o app até digitar o PIN ([AppSettings.pinLock]).
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final pin = TextEditingController();
  String? error;
  int attempts = 0;

  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  void _submit() {
    final fc = context.read<FinanceController>();
    if (fc.checkPin(pin.text)) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      attempts++;
      error = 'PIN incorreto';
      pin.clear();
    });
  }

  Future<void> _forgot() async {
    final ok = await confirmDialog(
      context,
      title: 'Esqueceu o PIN?',
      message:
          'Saia e entre de novo com seu e-mail e senha. Depois, troque ou '
          'remova o PIN em Configurações › Privacidade.',
      confirm: 'Sair',
    );
    if (ok && mounted) await context.read<AuthController>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthController>().user?.name ?? '';
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: context.colors.primary,
                ),
                const SizedBox(height: 12),
                Text('App bloqueado', style: context.text.titleLarge),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(name, style: context.text.bodyMedium),
                ],
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey('lock-pin'),
                  controller: pin,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  textAlign: TextAlign.center,
                  style: context.text.headlineSmall?.copyWith(letterSpacing: 8),
                  decoration: InputDecoration(
                    labelText: 'PIN',
                    errorText: error,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('lock-unlock'),
                    onPressed: _submit,
                    child: const Text('Desbloquear'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _forgot,
                  child: const Text('Esqueci o PIN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ativa, troca ou remove o PIN de bloqueio.
Future<void> showPinSettings(BuildContext context) async {
  final fc = context.read<FinanceController>();
  if (fc.hasPin) {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('pin-change'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Trocar PIN'),
              onTap: () => Navigator.pop(context, 'change'),
            ),
            ListTile(
              key: const ValueKey('pin-remove'),
              leading: const Icon(Icons.lock_open_outlined),
              title: const Text('Remover bloqueio'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'remove') {
      final current = await _askPin(context, 'PIN atual');
      if (current == null || !context.mounted) return;
      if (!fc.checkPin(current)) {
        showMessage(context, 'PIN incorreto', error: true);
        return;
      }
      await fc.setPin(null);
      if (context.mounted) showMessage(context, 'Bloqueio removido');
      return;
    }
    final current = await _askPin(context, 'PIN atual');
    if (current == null || !context.mounted) return;
    if (!fc.checkPin(current)) {
      showMessage(context, 'PIN incorreto', error: true);
      return;
    }
  }
  if (!context.mounted) return;
  final first = await _askPin(context, 'Novo PIN (4 a 8 números)');
  if (first == null || !context.mounted) return;
  if (first.length < 4) {
    showMessage(context, 'O PIN deve ter de 4 a 8 números.', error: true);
    return;
  }
  final again = await _askPin(context, 'Repita o novo PIN');
  if (again == null || !context.mounted) return;
  if (again != first) {
    showMessage(context, 'Os PINs não conferem.', error: true);
    return;
  }
  await fc.setPin(first);
  if (context.mounted) {
    showMessage(context, 'Bloqueio por PIN ativado');
  }
}

Future<String?> _askPin(BuildContext context, String label) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Bloqueio por PIN'),
      content: TextField(
        key: const ValueKey('pin-input'),
        controller: c,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(8),
        ],
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('pin-ok'),
          onPressed: () => Navigator.pop(context, c.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
