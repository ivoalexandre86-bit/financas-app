import 'package:flutter/material.dart' hide Simulation;

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../domain/engine/simulation_engine.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/simulation.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'sim_common.dart';

String _pct(double p) {
  final s = p == p.roundToDouble()
      ? p.toStringAsFixed(0)
      : p.toStringAsFixed(2);
  return '${s.replaceAll('.', ',')}%';
}

double? _parsePct(String t) {
  final v = t.trim().replaceAll('%', '').replaceAll(',', '.');
  if (v.isEmpty) return 0;
  return double.tryParse(v);
}

/// Cadastro das pessoas que dividem as despesas da simulação.
Future<List<SimPerson>?> editPeople(
  BuildContext context,
  List<SimPerson> people,
) => showDialog<List<SimPerson>>(
  context: context,
  builder: (_) => _PeopleDialog(people: people),
);

class _PeopleDialog extends StatefulWidget {
  final List<SimPerson> people;
  const _PeopleDialog({required this.people});

  @override
  State<_PeopleDialog> createState() => _PeopleDialogState();
}

class _PeopleDialogState extends State<_PeopleDialog> {
  late final rows = [
    for (final p in widget.people)
      (
        person: p,
        ctrl: TextEditingController(text: p.name),
        focus: FocusNode(),
      ),
  ];

  void _add() {
    final focus = FocusNode();
    setState(
      () => rows.add((
        person: SimPerson(
          id: newId('pp_'),
          name: '',
          color: simColors[rows.length % simColors.length],
        ),
        ctrl: TextEditingController(),
        focus: focus,
      )),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pessoas que dividem as despesas'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Depois, em cada despesa, informe o % de cada pessoa.',
              style: context.text.bodySmall?.copyWith(
                color: context.fin.subtle,
              ),
            ),
            const SizedBox(height: 8),
            for (var k = 0; k < rows.length; k++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 8,
                      backgroundColor: Color(rows[k].person.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: ValueKey('sim-person-$k'),
                        controller: rows[k].ctrl,
                        focusNode: rows[k].focus,
                        decoration: InputDecoration(
                          labelText: 'Pessoa ${k + 1}',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remover',
                      onPressed: () => setState(() => rows.removeAt(k)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('sim-person-add'),
                onPressed: _add,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Adicionar pessoa'),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('sim-people-save'),
        onPressed: () => Navigator.pop(context, [
          for (final r in rows)
            if (r.ctrl.text.trim().isNotEmpty)
              r.person.copyWith(name: r.ctrl.text.trim()),
        ]),
        child: const Text('Salvar'),
      ),
    ],
  );
}

/// Campos de % por pessoa (com "Dividir igualmente").
class SharesEditor extends StatefulWidget {
  final List<SimPerson> people;
  final Map<String, double> initial;

  /// Valor de referência (centavos) para mostrar quanto cabe a cada um.
  final int sample;
  final ValueChanged<Map<String, double>?> onChanged;
  const SharesEditor({
    super.key,
    required this.people,
    required this.initial,
    required this.onChanged,
    this.sample = 0,
  });

  @override
  State<SharesEditor> createState() => _SharesEditorState();
}

class _SharesEditorState extends State<SharesEditor> {
  late final ctrls = {
    for (final p in widget.people)
      p.id: TextEditingController(
        text: (widget.initial[p.id] ?? 0) == 0
            ? ''
            : _pct(widget.initial[p.id]!).replaceAll('%', ''),
      ),
  };

  Map<String, double>? get _value {
    final out = <String, double>{};
    for (final e in ctrls.entries) {
      final v = _parsePct(e.value.text);
      if (v == null || v < 0 || v > 100) return null;
      if (v > 0) out[e.key] = v;
    }
    return out;
  }

  void _emit() {
    setState(() {});
    widget.onChanged(_value);
  }

  void _equal() {
    final n = widget.people.length;
    if (n == 0) return;
    // Partes iguais com 2 casas; a última fecha os 100%.
    final base = (10000 / n).floor() / 100;
    for (var k = 0; k < n; k++) {
      final v = k == n - 1 ? 100 - base * (n - 1) : base;
      ctrls[widget.people[k].id]!.text = _pct(
        double.parse(v.toStringAsFixed(2)),
      ).replaceAll('%', '');
    }
    _emit();
  }

  void _clear() {
    for (final c in ctrls.values) {
      c.clear();
    }
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    final total = v?.values.fold(0.0, (a, p) => a + p);
    final split = SimItem(
      id: '',
      type: TransactionType.expense,
      description: '',
      shares: v ?? const {},
    ).splitCents(widget.sample);
    final ok = total != null && total <= 100.0001;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in widget.people)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                CircleAvatar(radius: 6, backgroundColor: Color(p.color)),
                const SizedBox(width: 8),
                Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                if (widget.sample > 0 && (split[p.id] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      fmtCents(split[p.id]!),
                      style: context.text.bodySmall?.copyWith(
                        color: context.fin.subtle,
                      ),
                    ),
                  ),
                SizedBox(
                  width: 96,
                  child: TextField(
                    key: ValueKey('sim-share-${p.id}'),
                    controller: ctrls[p.id],
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      suffixText: '%',
                      hintText: '0',
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              key: const ValueKey('sim-share-equal'),
              onPressed: _equal,
              child: const Text('Dividir igualmente'),
            ),
            TextButton(onPressed: _clear, child: const Text('Limpar')),
            Text(
              total == null
                  ? 'Percentual inválido'
                  : total == 0
                  ? 'Sem divisão'
                  : 'Total: ${_pct(double.parse(total.toStringAsFixed(2)))}',
              style: context.text.labelMedium?.copyWith(
                color: !ok
                    ? context.colors.error
                    : (total - 100).abs() < 0.001 || total == 0
                    ? context.fin.positive
                    : context.fin.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (ok && total > 0 && (total - 100).abs() >= 0.001)
          Text(
            total > 100
                ? 'A soma passa de 100%.'
                : 'Faltam ${_pct(double.parse((100 - total).toStringAsFixed(2)))}: '
                      'essa parte fica como "não dividido".',
            style: context.text.bodySmall?.copyWith(color: context.fin.warning),
          ),
      ],
    );
  }
}

/// Valida um mapa de percentuais (soma até 100%).
String? validateShares(Map<String, double>? s) {
  if (s == null) return 'Percentual inválido (use de 0 a 100)';
  final t = s.values.fold(0.0, (a, p) => a + p);
  if (t > 100.0001) return 'A soma dos percentuais passa de 100%';
  return null;
}

Future<Map<String, double>?> editShares(
  BuildContext context,
  List<SimPerson> people,
  SimItem item,
  int sample,
) {
  Map<String, double>? value = Map.of(item.shares);
  String? error;
  return showDialog<Map<String, double>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text('Divisão: ${item.description}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SharesEditor(
                people: people,
                initial: item.shares,
                sample: sample,
                onChanged: (v) => value = v,
              ),
              if (error != null)
                Text(error!, style: TextStyle(color: ctx.colors.error)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('sim-share-save'),
            onPressed: () {
              final e = validateShares(value);
              if (e != null) {
                setD(() => error = e);
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    ),
  );
}

/// Fechamento por pessoa: quanto cada um paga de cada despesa no mês (ou no
/// período), a partir dos percentuais de cada linha.
class SimPeopleView extends StatefulWidget {
  final FinanceController fc;
  final Simulation sim;
  final ValueChanged<List<SimItem>> onItemsChanged;
  final ValueChanged<List<SimPerson>> onPeopleChanged;
  const SimPeopleView({
    super.key,
    required this.fc,
    required this.sim,
    required this.onItemsChanged,
    required this.onPeopleChanged,
  });

  @override
  State<SimPeopleView> createState() => _SimPeopleViewState();
}

class _SimPeopleViewState extends State<SimPeopleView> {
  String? monthKey; // null = período inteiro
  bool income = false;
  bool onlySplit = false;

  Simulation get sim => widget.sim;

  Future<void> _people() async {
    final r = await editPeople(context, sim.people);
    if (r == null) return;
    final ids = {for (final p in r) p.id};
    final removed = sim.people.any((p) => !ids.contains(p.id));
    widget.onPeopleChanged(r);
    if (removed) {
      // Tira das linhas os percentuais de quem saiu.
      widget.onItemsChanged([
        for (final i in sim.items)
          i.shares.keys.every(ids.contains)
              ? i
              : i.copyWith(
                  shares: {
                    for (final e in i.shares.entries)
                      if (ids.contains(e.key)) e.key: e.value,
                  },
                ),
      ]);
    }
  }

  Future<void> _edit(SimItem i, int sample) async {
    final r = await editShares(context, sim.people, i, sample);
    if (r == null) return;
    widget.onItemsChanged([
      for (final x in sim.items) x.id == i.id ? x.copyWith(shares: r) : x,
    ]);
  }

  /// Copia os percentuais de uma linha para todas as despesas sem divisão.
  void _copyToUnsplit(SimItem from) {
    widget.onItemsChanged([
      for (final x in sim.items)
        x.isIncome == from.isIncome && !x.isSplit
            ? x.copyWith(shares: from.shares)
            : x,
    ]);
    showMessage(context, 'Divisão copiada para as linhas sem divisão');
  }

  @override
  Widget build(BuildContext context) {
    final people = sim.people;
    if (people.isEmpty) {
      return EmptyState(
        icon: Icons.groups_outlined,
        title: 'Divida as despesas entre pessoas',
        message:
            'Cadastre quem participa dos pagamentos (ex.: Pai, Mãe, Elis, '
            'Ivo) e informe o % de cada um em cada despesa. Aqui aparece o '
            'fechamento de quanto cada pessoa paga.',
        actionLabel: 'Cadastrar pessoas',
        onAction: _people,
      );
    }
    final allMonths = sim.months;
    final months = monthKey == null ? allMonths : [YearMonth.parse(monthKey!)];
    final fin = context.fin;
    final rows = sim.items
        .where(
          (i) =>
              i.isIncome == income &&
              i.totalIn(months) != 0 &&
              (!onlySplit || i.isSplit),
        )
        .toList();
    final totals = SimulationEngine.byPerson(rows, months, income);
    final grand = rows.fold(0, (a, i) => a + i.totalIn(months));
    final unsplit = totals[null] ?? 0;
    final head = context.text.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );
    final body = context.text.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final headBg = income ? fin.income : const Color(0xFFD32F2F);

    Widget cell(Widget c, {bool left = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Align(
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        child: c,
      ),
    );

    Widget money(int v, {double? pct, bool bold = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          v == 0 ? '–' : fmtCents(v),
          style: body?.copyWith(fontWeight: bold ? FontWeight.w700 : null),
        ),
        if (pct != null && pct > 0)
          Text(
            _pct(pct),
            style: context.text.labelSmall?.copyWith(color: fin.subtle),
          ),
      ],
    );

    final table = Table(
      defaultColumnWidth: const FixedColumnWidth(130),
      columnWidths: {
        0: const FixedColumnWidth(230),
        people.length + 3: const FixedColumnWidth(56),
      },
      border: TableBorder(horizontalInside: BorderSide(color: fin.gridLine)),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: headBg),
          children: [
            cell(Text('Item', style: head), left: true),
            cell(Text(monthKey == null ? 'Período' : 'Mês', style: head)),
            for (final p in people) cell(Text(p.name, style: head)),
            cell(Text('Não dividido', style: head)),
            const SizedBox(),
          ],
        ),
        for (final i in rows)
          () {
            final total = i.totalIn(months);
            var split = <String?, int>{};
            for (final m in months) {
              final v = i.valueAt(m);
              if (v == 0) continue;
              i.splitCents(v).forEach((k, c) => split[k] = (split[k] ?? 0) + c);
            }
            return TableRow(
              children: [
                InkWell(
                  onTap: () => _edit(i, total),
                  child: cell(
                    Text(
                      i.description,
                      overflow: TextOverflow.ellipsis,
                      style: body?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    left: true,
                  ),
                ),
                cell(money(total)),
                for (final p in people)
                  InkWell(
                    key: ValueKey('sim-pp-${i.id}-${p.id}'),
                    onTap: () => _edit(i, total),
                    child: cell(money(split[p.id] ?? 0, pct: i.shares[p.id])),
                  ),
                cell(
                  Text(
                    (split[null] ?? 0) == 0 ? '–' : fmtCents(split[null]!),
                    style: body?.copyWith(
                      color: (split[null] ?? 0) == 0 ? null : fin.warning,
                    ),
                  ),
                ),
                PopupMenuButton<int>(
                  tooltip: 'Ações',
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (a) => a == 0
                      ? _edit(i, total)
                      : a == 1
                      ? _copyToUnsplit(i)
                      : widget.onItemsChanged([
                          for (final x in sim.items)
                            x.id == i.id ? x.copyWith(shares: const {}) : x,
                        ]),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 0, child: Text('Editar %')),
                    if (i.isSplit)
                      const PopupMenuItem(
                        value: 1,
                        child: Text('Usar esta divisão nas linhas sem divisão'),
                      ),
                    if (i.isSplit)
                      const PopupMenuItem(
                        value: 2,
                        child: Text('Remover divisão'),
                      ),
                  ],
                ),
              ],
            );
          }(),
        TableRow(
          decoration: BoxDecoration(color: context.colors.primaryContainer),
          children: [
            cell(
              Text('Total', style: body?.copyWith(fontWeight: FontWeight.w700)),
              left: true,
            ),
            cell(money(grand, bold: true)),
            for (final p in people) cell(money(totals[p.id] ?? 0, bold: true)),
            cell(money(unsplit, bold: true)),
            const SizedBox(),
          ],
        ),
      ],
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                key: const ValueKey('sim-pp-month'),
                initialValue: monthKey,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Fechamento de'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Período inteiro'),
                  ),
                  for (final m in allMonths)
                    DropdownMenuItem(value: m.key, child: Text(m.longLabel)),
                ],
                onChanged: (v) => setState(() => monthKey = v),
              ),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Despesas')),
                ButtonSegment(value: true, label: Text('Receitas')),
              ],
              selected: {income},
              onSelectionChanged: (s) => setState(() => income = s.first),
            ),
            FilterChip(
              label: const Text('Só divididas'),
              selected: onlySplit,
              onSelected: (v) => setState(() => onlySplit = v),
            ),
            OutlinedButton.icon(
              key: const ValueKey('sim-people-edit'),
              onPressed: _people,
              icon: const Icon(Icons.groups_outlined),
              label: Text('Pessoas (${people.length})'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final p in people)
              SimKpi(
                label: p.name,
                value: fmtCents(totals[p.id] ?? 0),
                detail: grand == 0
                    ? null
                    : '${_pct(double.parse(((totals[p.id] ?? 0) / grand * 100).toStringAsFixed(1)))} do total',
                icon: Icons.person_outline,
                color: Color(p.color),
              ),
            if (unsplit != 0)
              SimKpi(
                label: 'Não dividido',
                value: fmtCents(unsplit),
                detail: 'toque numa linha para dividir',
                icon: Icons.help_outline,
                color: fin.warning,
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Toque numa linha para informar o % de cada pessoa.',
          style: context.text.bodySmall?.copyWith(color: fin.subtle),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: table,
            ),
          ),
        ),
      ],
    );
  }
}
