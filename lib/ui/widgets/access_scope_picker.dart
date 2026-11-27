import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/cloud/account_api.dart';
import '../../state/finance_controller.dart';
import '../theme.dart';

/// Cartões e contas que podem ser liberados (os ativos do meu orçamento),
/// como pares (id, nome).
class ScopeOptions {
  final List<(String, String)> cards;
  final List<(String, String)> accounts;
  const ScopeOptions({this.cards = const [], this.accounts = const []});

  /// Lê do orçamento aberto; sem ele (ex.: testes), listas vazias.
  factory ScopeOptions.of(BuildContext context) {
    final fc = context.read<FinanceController?>();
    if (fc == null) return const ScopeOptions();
    return ScopeOptions(
      cards: [for (final c in fc.activeCards) (c.id, c.name)],
      accounts: [for (final a in fc.activeAccounts) (a.id, a.name)],
    );
  }

  /// "Todo o orçamento" ou "Cartão Nubank, Conta Itaú".
  String label(AccessScope? scope) {
    if (scope == null) return 'Todo o orçamento';
    String name(List<(String, String)> l, String id) =>
        l.where((e) => e.$1 == id).firstOrNull?.$2 ?? '(removido)';
    final parts = [
      for (final id in scope.cards) 'Cartão ${name(cards, id)}',
      for (final id in scope.accounts) 'Conta ${name(accounts, id)}',
    ];
    return parts.isEmpty ? 'Nada liberado' : parts.join(', ');
  }
}

/// Escolha do acesso: todo o orçamento ou só os cartões e contas marcados.
/// Usado no convite (dentro do formulário) e na edição do acesso.
class AccessScopeFields extends StatelessWidget {
  final ScopeOptions options;
  final bool limited;
  final Set<String> cards;
  final Set<String> accounts;
  final ValueChanged<bool> onLimited;
  final VoidCallback onChanged;

  /// Mensagem de erro (ex.: nada marcado).
  final String? error;

  const AccessScopeFields({
    super.key,
    required this.options,
    required this.limited,
    required this.cards,
    required this.accounts,
    required this.onLimited,
    required this.onChanged,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    Widget box(String id, String label, Set<String> set) => CheckboxListTile(
      key: ValueKey('scope-$id'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: set.contains(id),
      title: Text(label),
      onChanged: (v) {
        v == true ? set.add(id) : set.remove(id);
        onChanged();
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RadioGroup<bool>(
          groupValue: limited,
          onChanged: (v) => onLimited(v ?? false),
          child: const Column(
            children: [
              RadioListTile<bool>(
                key: ValueKey('scope-limited'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: true,
                title: Text('Só o que eu escolher'),
                subtitle: Text(
                  'Vê e lança apenas nos cartões e contas marcados.',
                ),
              ),
              RadioListTile<bool>(
                key: ValueKey('scope-all'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: false,
                title: Text('Todo o orçamento'),
              ),
            ],
          ),
        ),
        if (limited) ...[
          if (options.cards.isEmpty && options.accounts.isEmpty)
            Text(
              'Cadastre um cartão ou conta para liberar.',
              style: context.text.bodySmall,
            ),
          if (options.cards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Cartões', style: context.text.labelLarge),
            ),
          for (final (id, name) in options.cards) box(id, name, cards),
          if (options.accounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Contas', style: context.text.labelLarge),
            ),
          for (final (id, name) in options.accounts) box(id, name, accounts),
          if (error != null)
            Text(error!, style: TextStyle(color: context.colors.error)),
        ],
      ],
    );
  }
}

/// Diálogo para editar o acesso de uma pessoa. Devolve null se cancelou;
/// `(null,)` = todo o orçamento; `(scope,)` = só o escolhido.
Future<(AccessScope?,)?> pickAccessScope(
  BuildContext context, {
  required String who,
  AccessScope? initial,
  ScopeOptions? options,
}) => showDialog<(AccessScope?,)>(
  context: context,
  builder: (_) => _ScopeDialog(
    who: who,
    initial: initial,
    options: options ?? ScopeOptions.of(context),
  ),
);

class _ScopeDialog extends StatefulWidget {
  final String who;
  final AccessScope? initial;
  final ScopeOptions options;
  const _ScopeDialog({
    required this.who,
    required this.initial,
    required this.options,
  });
  @override
  State<_ScopeDialog> createState() => _ScopeDialogState();
}

class _ScopeDialogState extends State<_ScopeDialog> {
  late bool limited = widget.initial != null;
  late final cards = {...?widget.initial?.cards};
  late final accounts = {...?widget.initial?.accounts};
  String? error;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Acesso de ${widget.who}'),
    content: SingleChildScrollView(
      child: AccessScopeFields(
        options: widget.options,
        limited: limited,
        cards: cards,
        accounts: accounts,
        error: error,
        onLimited: (v) => setState(() {
          limited = v;
          error = null;
        }),
        onChanged: () => setState(() => error = null),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('scope-save'),
        onPressed: () {
          if (!limited) return Navigator.pop(context, (null,));
          if (cards.isEmpty && accounts.isEmpty) {
            setState(() => error = 'Marque ao menos um cartão ou conta.');
            return;
          }
          Navigator.pop(context, (
            AccessScope(cards: cards.toList(), accounts: accounts.toList()),
          ));
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}
