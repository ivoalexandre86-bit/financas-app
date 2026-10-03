import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../domain/models/entities.dart';
import '../../state/finance_controller.dart';
import 'category_icons.dart';

/// Campo de valor em reais com validação (aceita "1.234,56").
class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool allowZero;
  final bool allowNegative;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  const MoneyField({
    super.key,
    required this.controller,
    this.label = 'Valor',
    this.allowZero = false,
    this.allowNegative = false,
    this.autofocus = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: allowNegative,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
      ],
      decoration: InputDecoration(labelText: label, prefixText: 'R\$ '),
      validator: (v) {
        final m = Money.tryParse(v ?? '');
        if (m == null) return 'Valor inválido';
        if (!allowNegative && m.isNegative) {
          return 'Valor não pode ser negativo';
        }
        if (!allowZero && m.isZero) return 'Informe um valor maior que zero';
        if (m.cents.abs() > 99999999999) return 'Valor muito alto';
        return null;
      },
    );
  }
}

/// Campo de data (DD/MM/AAAA) que abre o calendário.
class DateField extends StatelessWidget {
  final DateTime? value;
  final String label;
  final ValueChanged<DateTime?> onChanged;
  final bool clearable;
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Data',
    this.clearable = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(2000),
          lastDate: DateTime(now.year + 30),
          locale: const Locale('pt', 'BR'),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: clearable && value != null
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => onChanged(null),
                )
              : const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(value == null ? '—' : Dates.format(value!)),
      ),
    );
  }
}

/// Destino de um lançamento: conta ou cartão.
class Funding {
  final String? accountId;
  final String? cardId;
  const Funding({this.accountId, this.cardId});
  String get key => accountId != null ? 'a:$accountId' : 'c:$cardId';
  static Funding? parse(String? k) {
    if (k == null) return null;
    return k.startsWith('a:')
        ? Funding(accountId: k.substring(2))
        : Funding(cardId: k.substring(2));
  }
}

/// Seletor único de conta **ou** cartão.
class FundingDropdown extends StatelessWidget {
  final FinanceController fc;
  final Funding? value;
  final ValueChanged<Funding?> onChanged;
  final bool allowCards;
  final String label;
  const FundingDropdown({
    super.key,
    required this.fc,
    required this.value,
    required this.onChanged,
    this.allowCards = true,
    this.label = 'Conta ou cartão',
  });

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      for (final a in fc.activeAccounts)
        DropdownMenuItem(
          value: 'a:${a.id}',
          child: Row(
            children: [
              Icon(
                Icons.account_balance_outlined,
                size: 18,
                color: Color(a.color),
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      if (allowCards)
        for (final c in fc.activeCards)
          DropdownMenuItem(
            value: 'c:${c.id}',
            child: Row(
              children: [
                Icon(Icons.credit_card, size: 18, color: Color(c.color)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${c.name} •••• ${c.lastFour}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
    ];
    final v = items.any((i) => i.value == value?.key) ? value?.key : null;
    return DropdownButtonFormField<String>(
      initialValue: v,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items,
      validator: (x) => x == null ? 'Selecione uma conta ou cartão' : null,
      onChanged: (k) => onChanged(Funding.parse(k)),
    );
  }
}

class AccountDropdown extends StatelessWidget {
  final FinanceController fc;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final String? excludeId;
  const AccountDropdown({
    super.key,
    required this.fc,
    required this.value,
    required this.onChanged,
    this.label = 'Conta',
    this.excludeId,
  });

  @override
  Widget build(BuildContext context) {
    final accounts = fc.activeAccounts.where((a) => a.id != excludeId).toList();
    return DropdownButtonFormField<String>(
      initialValue: accounts.any((a) => a.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final a in accounts)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
      ],
      validator: (x) => x == null ? 'Selecione uma conta' : null,
      onChanged: onChanged,
    );
  }
}

/// Categoria e, logo abaixo, as subcategorias da categoria escolhida.
/// O valor é a subcategoria quando houver uma escolhida; senão, a categoria.
class CategoryDropdown extends StatelessWidget {
  final FinanceController fc;
  final CategoryKind kind;
  final String? value;
  final ValueChanged<String?> onChanged;
  const CategoryDropdown({
    super.key,
    required this.fc,
    required this.kind,
    required this.value,
    required this.onChanged,
  });

  List<FinCategory> _sorted(bool Function(FinCategory) test) =>
      fc.data.categories.where(test).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Widget build(BuildContext context) {
    final roots = _sorted((c) => c.kind == kind && c.parentId == null);
    final selected = fc.data.categories.where((c) => c.id == value).firstOrNull;
    final rootId = selected?.parentId ?? selected?.id;
    final root = roots.where((r) => r.id == rootId).firstOrNull;
    final subs = root == null
        ? const <FinCategory>[]
        : _sorted((c) => c.parentId == root.id);
    final subId = selected?.parentId != null ? selected!.id : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('category-${kind.name}-${root?.id}'),
          initialValue: root?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Categoria'),
          items: [for (final r in roots) _item(r, subCount(r))],
          onChanged: onChanged,
        ),
        if (subs.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey('subcategory-${root!.id}-$subId'),
            initialValue: subId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Subcategoria'),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('Nenhuma (só ${root.name})'),
              ),
              for (final s in subs) _item(s, 0),
            ],
            onChanged: (v) => onChanged(v ?? root.id),
          ),
        ],
      ],
    );
  }

  int subCount(FinCategory r) =>
      fc.data.categories.where((c) => c.parentId == r.id).length;

  DropdownMenuItem<String> _item(FinCategory c, int subs) => DropdownMenuItem(
    value: c.id,
    child: Row(
      children: [
        Icon(categoryIcon(c.icon), size: 18, color: Color(c.color)),
        const SizedBox(width: 8),
        Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
        if (subs > 0) ...[
          const SizedBox(width: 6),
          Text(
            '· $subs ${subs == 1 ? 'subcategoria' : 'subcategorias'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ],
    ),
  );
}

class ProjectDropdown extends StatelessWidget {
  final FinanceController fc;
  final String? value;
  final ValueChanged<String?> onChanged;
  const ProjectDropdown({
    super.key,
    required this.fc,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final projects = fc.activeProjects;
    return DropdownButtonFormField<String?>(
      initialValue: projects.any((p) => p.id == value) ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Projeto (opcional)'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Nenhum')),
        for (final p in projects)
          DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Campo numérico inteiro simples (dias, parcelas…).
class IntField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int min;
  final int max;
  final ValueChanged<String>? onChanged;
  const IntField({
    super.key,
    required this.controller,
    required this.label,
    required this.min,
    required this.max,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    onChanged: onChanged,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label),
    validator: (v) {
      final n = int.tryParse(v ?? '');
      if (n == null || n < min || n > max) {
        return 'Entre $min e $max';
      }
      return null;
    },
  );
}
