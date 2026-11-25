import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ids.dart';
import '../../domain/models/entities.dart';
import '../theme.dart';
import 'common.dart';

/// Lista editável de dependentes (cartões adicionais, quem usa a conta).
/// Dependentes são só rótulos para marcar quem fez cada lançamento; não
/// têm login próprio.
class DependentsEditor extends StatelessWidget {
  final List<Dependent> value;
  final ValueChanged<List<Dependent>> onChanged;

  /// Pede o final do cartão adicional (cartões).
  final bool askLastFour;

  /// Quantos lançamentos cada dependente tem (avisa ao remover).
  final int Function(String dependentId)? usage;

  const DependentsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.askLastFour = false,
    this.usage,
  });

  Future<void> _edit(BuildContext context, [Dependent? d]) async {
    final result = await showDialog<Dependent>(
      context: context,
      builder: (_) => _DependentDialog(dependent: d, askLastFour: askLastFour),
    );
    if (result == null) return;
    onChanged([
      for (final x in value) x.id == result.id ? result : x,
      if (d == null) result,
    ]);
  }

  Future<void> _remove(BuildContext context, Dependent d) async {
    final n = usage?.call(d.id) ?? 0;
    final ok = await confirmDialog(
      context,
      title: 'Remover ${d.name}?',
      message: n == 0
          ? 'O dependente sai da lista ao salvar.'
          : '$n lançamento(s) de ${d.name} passam a constar como do titular.',
      confirm: 'Remover',
      destructive: true,
    );
    if (ok)
      onChanged([
        for (final x in value)
          if (x.id != d.id) x,
      ]);
  }

  static String? _subtitle(Dependent d) {
    final parts = [
      if (d.lastFour.isNotEmpty) 'Cartão final ${d.lastFour}',
      if (d.phone.isNotEmpty) 'WhatsApp ${Dependent.formatPhone(d.phone)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Dependentes', style: context.text.titleSmall),
        Text(
          askLastFour
              ? 'Cartões adicionais. Ao lançar uma compra você escolhe quem usou, e a fatura mostra o total de cada um. '
                    'Com o WhatsApp cadastrado, o dependente lança os gastos dele mandando para o bot.'
              : 'Pessoas que também usam esta conta. Ao lançar você escolhe quem usou. '
                    'Com o WhatsApp cadastrado, o dependente lança os gastos dele mandando para o bot.',
          style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
        ),
        for (final d in value)
          ListTile(
            key: ValueKey('dep-${d.id}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(d.name),
            subtitle: _subtitle(d) == null ? null : Text(_subtitle(d)!),
            onTap: () => _edit(context, d),
            trailing: IconButton(
              tooltip: 'Remover dependente',
              icon: const Icon(Icons.close),
              onPressed: () => _remove(context, d),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Adicionar dependente'),
          ),
        ),
      ],
    );
  }
}

class _DependentDialog extends StatefulWidget {
  final Dependent? dependent;
  final bool askLastFour;
  const _DependentDialog({this.dependent, required this.askLastFour});

  @override
  State<_DependentDialog> createState() => _DependentDialogState();
}

class _DependentDialogState extends State<_DependentDialog> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.dependent?.name ?? '');
  late final last4 = TextEditingController(
    text: widget.dependent?.lastFour ?? '',
  );
  late final phone = TextEditingController(
    text: Dependent.formatPhone(widget.dependent?.phone ?? ''),
  );

  String get _phoneDigits => phone.text.replaceAll(RegExp(r'\D'), '');

  @override
  void dispose() {
    name.dispose();
    last4.dispose();
    phone.dispose();
    super.dispose();
  }

  void _ok() {
    if (!_form.currentState!.validate()) return;
    final d = widget.dependent;
    Navigator.pop(
      context,
      d == null
          ? Dependent(
              id: newId('dep_'),
              name: name.text.trim(),
              lastFour: last4.text.trim(),
              phone: _phoneDigits,
            )
          : d.copyWith(
              name: name.text.trim(),
              lastFour: last4.text.trim(),
              phone: _phoneDigits,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.dependent == null ? 'Novo dependente' : 'Editar dependente',
      ),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
              onFieldSubmitted: (_) => _ok(),
            ),
            if (widget.askLastFour) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: last4,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Final do cartão adicional (opcional)',
                ),
                onFieldSubmitted: (_) => _ok(),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('dep-phone'),
              controller: phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9()+\- ]')),
              ],
              decoration: const InputDecoration(
                labelText: 'WhatsApp (opcional)',
                hintText: '(11) 99999-1234',
                helperText:
                    'Gastos que ele mandar ao bot entram aqui em nome dele.',
                helperMaxLines: 2,
              ),
              validator: (_) {
                final n = _phoneDigits.length;
                return n == 0 || (n >= 10 && n <= 13)
                    ? null
                    : 'Informe DDD e número';
              },
              onFieldSubmitted: (_) => _ok(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _ok, child: const Text('Salvar')),
      ],
    );
  }
}
