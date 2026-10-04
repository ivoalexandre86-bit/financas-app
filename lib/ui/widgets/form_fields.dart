import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../domain/models/entities.dart';
import '../../state/finance_controller.dart';
import '../screens/categories/categories_screen.dart';
import 'category_icons.dart';

/// Campo de valor em reais com validação (aceita "1.234,56").
///
/// Funciona como calculadora: digitar "10*100" mostra "= R\$ 1.000,00" e,
/// ao sair do campo (ou pressionar Enter), o texto vira o resultado. O botão
/// de calculadora abre um teclado com as operações (útil no celular).
class MoneyField extends StatefulWidget {
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
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) _resolve();
    });
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(covariant MoneyField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    focus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Troca a conta pelo resultado ("10*100" → "1.000,00").
  void _resolve() {
    final text = widget.controller.text;
    if (!Money.isExpression(text)) return;
    final m = Money.tryEval(text);
    if (m == null) return;
    final v = m.formatPlain();
    widget.controller.value = TextEditingValue(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
    widget.onChanged?.call(v);
  }

  Future<void> _openCalculator() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => CalculatorPad(initial: widget.controller.text),
    );
    if (r == null) return;
    widget.controller.value = TextEditingValue(
      text: r,
      selection: TextSelection.collapsed(offset: r.length),
    );
    widget.onChanged?.call(r);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final expr = Money.isExpression(text);
    final result = expr ? Money.tryEval(text) : null;
    return TextFormField(
      controller: widget.controller,
      focusNode: focus,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onFieldSubmitted: (_) => _resolve(),
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: widget.allowNegative,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-+*/xX×÷() ]')),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        prefixText: 'R\$ ',
        helperText: !expr
            ? null
            : result == null
            ? 'Conta incompleta'
            : '= ${result.format()}',
        suffixIcon: IconButton(
          tooltip: 'Calculadora',
          icon: const Icon(Icons.calculate_outlined),
          onPressed: _openCalculator,
        ),
      ),
      validator: (v) {
        final m = Money.tryEval(v ?? '');
        if (m == null) return 'Valor inválido';
        if (!widget.allowNegative && m.isNegative) {
          return 'Valor não pode ser negativo';
        }
        if (!widget.allowZero && m.isZero) {
          return 'Informe um valor maior que zero';
        }
        if (m.cents.abs() > 99999999999) return 'Valor muito alto';
        return null;
      },
    );
  }
}

/// Teclado de calculadora: monta a conta e devolve o resultado formatado
/// ("1.000,00") ao confirmar.
class CalculatorPad extends StatefulWidget {
  final String initial;
  const CalculatorPad({super.key, this.initial = ''});
  @override
  State<CalculatorPad> createState() => _CalculatorPadState();
}

class _CalculatorPadState extends State<CalculatorPad> {
  late String expr = widget.initial.trim();

  void _key(String k) => setState(() {
    switch (k) {
      case 'C':
        expr = '';
      case '⌫':
        if (expr.isNotEmpty) expr = expr.substring(0, expr.length - 1);
      case '=':
        final m = Money.tryEval(expr);
        if (m != null) expr = m.formatPlain();
      default:
        expr += k;
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = expr.isEmpty ? null : Money.tryEval(expr);
    const rows = [
      ['C', '(', ')', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '-'],
      ['1', '2', '3', '+'],
      [',', '0', '⌫', '='],
    ];
    Widget key(String k) {
      final op = '÷×-+='.contains(k);
      final fn = k == 'C' || k == '⌫' || k == '(' || k == ')';
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: 52,
            child: op
                ? FilledButton(
                    key: ValueKey('calc-$k'),
                    onPressed: () => _key(k),
                    child: Text(k, style: const TextStyle(fontSize: 20)),
                  )
                : fn
                ? FilledButton.tonal(
                    key: ValueKey('calc-$k'),
                    onPressed: () => _key(k),
                    child: k == '⌫'
                        ? const Icon(Icons.backspace_outlined, size: 20)
                        : Text(k, style: const TextStyle(fontSize: 18)),
                  )
                : OutlinedButton(
                    key: ValueKey('calc-$k'),
                    onPressed: () => _key(k),
                    child: Text(k, style: const TextStyle(fontSize: 20)),
                  ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Calculadora', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      expr.isEmpty ? '0' : expr,
                      key: const ValueKey('calc-expr'),
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result == null ? ' ' : '= ${result.format()}',
                      key: const ValueKey('calc-result'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (final r in rows) Row(children: [for (final k in r) key(k)]),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('calc-use'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: result == null
                    ? null
                    : () => Navigator.pop(context, result.formatPlain()),
                icon: const Icon(Icons.check),
                label: Text(
                  result == null ? 'Usar valor' : 'Usar ${result.format()}',
                ),
              ),
            ],
          ),
        ),
      ),
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
        Wrap(
          spacing: 4,
          children: [
            if (root != null)
              TextButton.icon(
                key: const ValueKey('quick-add-subcategory'),
                onPressed: () => _addSub(context, root),
                icon: const Icon(Icons.add, size: 18),
                label: Text('Nova subcategoria em ${root.name}'),
              ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CategoriesScreen(initialKind: kind),
                ),
              ),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Ajustar categorias'),
            ),
          ],
        ),
      ],
    );
  }

  /// Cria uma subcategoria sem sair do formulário e já a seleciona.
  Future<void> _addSub(BuildContext context, FinCategory root) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nova subcategoria em ${root.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    final n = name?.trim() ?? '';
    if (n.isEmpty) return;
    final c = FinCategory(
      id: newId('cat_'),
      name: n,
      kind: root.kind,
      parentId: root.id,
      icon: root.icon,
      color: root.color,
    );
    await fc.saveCategory(c);
    onChanged(c.id);
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
