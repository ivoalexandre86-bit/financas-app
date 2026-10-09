import 'package:flutter/material.dart' hide Simulation;
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/other_entries_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../domain/models/other_entry.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import 'sim_common.dart';

Color payStatusColor(BuildContext context, PayStatus? s) => switch (s) {
  PayStatus.paid => context.fin.positive,
  PayStatus.partial => Colors.amber.shade800,
  PayStatus.pending => context.fin.negative,
  null => context.fin.subtle,
};

Widget payStatusPill(BuildContext context, PayStatus? s, {String? label}) =>
    Pill(label ?? s?.label ?? 'Sem divisão', color: payStatusColor(context, s));

String _typeNoun(TransactionType t) =>
    t == TransactionType.income ? 'receita' : 'despesa';

/// Lista de "Outras despesas" ou "Outras receitas", com resumo e filtros.
class OtherEntriesView extends StatefulWidget {
  final TransactionType type;
  final YearMonth? initialMonth;
  const OtherEntriesView({super.key, required this.type, this.initialMonth});

  @override
  State<OtherEntriesView> createState() => _OtherEntriesViewState();
}

class _OtherEntriesViewState extends State<OtherEntriesView> {
  /// 'all', 'y:2026' ou 'm:2026-10'.
  late String period = widget.initialMonth == null
      ? 'all'
      : 'm:${widget.initialMonth!.key}';
  String? personId;
  PayStatus? status;
  String query = '';

  /// null = todos; true = só vinculados; false = só não vinculados.
  bool? linked;
  bool showDeleted = false;

  bool get isIncome => widget.type == TransactionType.income;

  bool _inPeriod(OtherEntry e) {
    if (period == 'all') return true;
    if (period.startsWith('y:')) {
      return '${e.month.year}' == period.substring(2);
    }
    return e.month.key == period.substring(2);
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final me = fc.meIds;
    final ofType = fc.otherEntries.where((e) => e.type == widget.type).toList();
    final q = query.trim().toLowerCase();
    final list =
        ofType.where((e) {
          if (e.isDeleted != showDeleted) return false;
          if (!_inPeriod(e)) return false;
          if (personId != null &&
              !e.allocations.any((a) => a.personId == personId)) {
            return false;
          }
          if (status != null && e.status(me) != status) return false;
          if (linked != null && e.linked != linked) return false;
          return q.isEmpty ||
              e.description.toLowerCase().contains(q) ||
              e.notes.toLowerCase().contains(q);
        }).toList()..sort((a, b) {
          final c = b.month.compareTo(a.month);
          return c != 0 ? c : a.description.compareTo(b.description);
        });
    final sum = OtherSummary.of(list.where((e) => !e.isDeleted), me);
    final months = {for (final e in ofType) e.month}.toList()
      ..sort((a, b) => b.compareTo(a));
    final years = {for (final m in months) m.year}.toList()..sort();
    final periodOptions = {
      'all': 'Todos os meses',
      for (final y in years.reversed) 'y:$y': 'Ano $y',
      for (final m in months) 'm:${m.key}': m.shortLabel,
    };
    if (!periodOptions.containsKey(period)) {
      periodOptions[period] = period.startsWith('m:')
          ? YearMonth.parse(period.substring(2)).shortLabel
          : period;
    }
    final selMonth = period.startsWith('m:')
        ? YearMonth.parse(period.substring(2))
        : null;
    final account = fc.otherAccount;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Text(
          isIncome
              ? 'Receitas avulsas (aluguel recebido, ajuda de alguém...). As '
                    'vinculadas entram no orçamento como uma linha "Outras '
                    'receitas" por mês.'
              : 'Despesas que você paga e divide com outras pessoas. As '
                    'vinculadas entram no orçamento como uma linha "Outras '
                    'despesas" por mês (como a fatura do cartão), e cada '
                    'reembolso recebido vira uma receita na data do pagamento.',
          style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: ValueKey('oe-new-${widget.type.name}'),
              onPressed: () => editOtherEntry(
                context,
                type: widget.type,
                month: selMonth ?? YearMonth.now(),
              ),
              icon: const Icon(Icons.add),
              label: Text('Nova ${_typeNoun(widget.type)}'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('oe-people'),
              onPressed: () => editPersons(context),
              icon: const Icon(Icons.group_outlined),
              label: Text('Pessoas (${fc.people.length})'),
            ),
            PopupMenuButton<String>(
              tooltip: 'Conta usada no orçamento',
              onSelected: (id) =>
                  runAction(context, () => fc.setOtherAccount(id)),
              itemBuilder: (_) => [
                for (final a in fc.activeAccounts)
                  CheckedPopupMenuItem(
                    value: a.id,
                    checked: a.id == account?.id,
                    child: Text(a.name),
                  ),
              ],
              child: Chip(
                avatar: const Icon(Icons.account_balance_outlined, size: 16),
                label: Text('Conta: ${account?.name ?? 'nenhuma'}'),
              ),
            ),
          ],
        ),
        if (account == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Cadastre uma conta para que os lançamentos entrem no orçamento.',
              style: TextStyle(color: context.fin.negative),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: isIncome
              ? [
                  SimKpi(
                    label: 'Previsto',
                    value: fmtCents(sum.total),
                    icon: Icons.event_note_outlined,
                  ),
                  SimKpi(
                    label: 'Recebido',
                    value: fmtCents(sum.received),
                    icon: Icons.check_circle_outline,
                    color: context.fin.positive,
                  ),
                  SimKpi(
                    label: 'A receber',
                    value: fmtCents(sum.outstanding),
                    icon: Icons.schedule,
                    color: context.fin.negative,
                  ),
                  _counts(context, sum),
                ]
              : [
                  SimKpi(
                    label: 'Total de despesas',
                    value: fmtCents(sum.total),
                    icon: Icons.receipt_long_outlined,
                  ),
                  SimKpi(
                    label: 'Atribuído a outras pessoas',
                    value: fmtCents(sum.assigned),
                    icon: Icons.group_outlined,
                  ),
                  SimKpi(
                    label: 'Recebido',
                    value: fmtCents(sum.received),
                    icon: Icons.check_circle_outline,
                    color: context.fin.positive,
                  ),
                  SimKpi(
                    label: 'A receber',
                    value: fmtCents(sum.outstanding),
                    icon: Icons.schedule,
                    color: context.fin.negative,
                  ),
                  _counts(context, sum),
                ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                key: const ValueKey('oe-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar descrição',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            _Filter<String>(
              label: 'Mês/ano',
              value: period,
              items: periodOptions,
              onChanged: (v) => setState(() => period = v ?? 'all'),
            ),
            _Filter<String?>(
              label: 'Pessoa',
              value: personId,
              items: {null: 'Todas', for (final p in fc.people) p.id: p.name},
              onChanged: (v) => setState(() => personId = v),
            ),
            _Filter<PayStatus?>(
              label: isIncome ? 'Recebimento' : 'Pagamento',
              value: status,
              items: {
                null: 'Todos',
                for (final s in PayStatus.values) s: s.label,
              },
              onChanged: (v) => setState(() => status = v),
            ),
            _Filter<bool?>(
              label: 'Orçamento',
              value: linked,
              items: const {
                null: 'Todos',
                true: 'Vinculados',
                false: 'Não vinculados',
              },
              onChanged: (v) => setState(() => linked = v),
            ),
            FilterChip(
              label: const Text('Excluídos'),
              selected: showDeleted,
              onSelected: (v) => setState(() => showDeleted = v),
            ),
          ],
        ),
        if (selMonth != null) ...[
          const SizedBox(height: 12),
          _MonthLine(type: widget.type, month: selMonth),
        ],
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: EmptyState(
              icon: isIncome
                  ? Icons.savings_outlined
                  : Icons.receipt_long_outlined,
              title: ofType.isEmpty
                  ? 'Nenhuma ${_typeNoun(widget.type)} ainda'
                  : 'Nada com esses filtros',
            ),
          )
        else
          for (final e in list) _EntryTile(entry: e),
      ],
    );
  }

  Widget _counts(BuildContext context, OtherSummary s) => SizedBox(
    width: 190,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Situação',
              style: context.text.labelMedium?.copyWith(
                color: context.fin.subtle,
              ),
            ),
            const SizedBox(height: 6),
            Text('${s.pending} pendentes'),
            Text('${s.partial} parciais'),
            Text('${s.paid} pagos'),
          ],
        ),
      ),
    ),
  );
}

class _Filter<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  const _Filter({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

/// Como o mês aparece no orçamento: a linha consolidada.
class _MonthLine extends StatelessWidget {
  final TransactionType type;
  final YearMonth month;
  const _MonthLine({required this.type, required this.month});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final id = OtherSync.monthTxId(type, month);
    final tx = fc.data.transactions.where((t) => t.id == id).firstOrNull;
    final n = fc.otherEntries
        .where(
          (e) => e.type == type && e.month == month && e.linked && !e.isDeleted,
        )
        .length;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.link),
        title: Text(
          tx == null
              ? 'Nada deste mês no orçamento'
              : 'No orçamento: "${tx.description}" em ${Dates.format(tx.date)}',
        ),
        subtitle: Text(
          tx == null
              ? 'Nenhum lançamento vinculado em ${month.shortLabel}.'
              : '$n ${n == 1 ? 'lançamento consolidado' : 'lançamentos consolidados'}'
                    ' · ${tx.status == TransactionStatus.completed ? 'pago' : 'pendente'}',
        ),
        trailing: tx == null
            ? null
            : Text(fmtCents(tx.amount.cents), style: context.text.titleMedium),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final OtherEntry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = entry;
    final st = e.status(fc.meIds);
    final names = [
      for (final s in e.shares()) fc.personById(s.personId)?.name ?? '?',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: ValueKey('oe-tile-${e.id}'),
        onTap: () => push(context, OtherEntryScreen(entryId: e.id)),
        leading: Icon(
          e.linked ? Icons.link : Icons.link_off,
          color: e.linked ? context.fin.positive : context.fin.subtle,
        ),
        title: Text(
          e.description,
          style: e.isDeleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          [
            e.month.shortLabel,
            if (e.dueDate != null) 'vence ${Dates.format(e.dueDate!)}',
            if (names.isNotEmpty) names.join(', '),
            if (!e.isIncome && e.settled) 'conta paga',
          ].join(' · '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fmtCents(e.amount), style: context.text.titleSmall),
            const SizedBox(height: 4),
            payStatusPill(context, st),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Cadastro de pessoas

Future<void> editPersons(BuildContext context) async {
  final fc = context.read<FinanceController>();
  final r = await showDialog<List<Person>>(
    context: context,
    builder: (_) => _PersonsDialog(people: fc.people),
  );
  if (r == null || !context.mounted) return;
  final used = {
    for (final e in fc.otherEntries)
      for (final a in e.allocations) a.personId,
    for (final e in fc.otherEntries)
      for (final p in e.payments) p.personId,
  };
  final ids = r.map((p) => p.id).toSet();
  final removedUsed = fc.people
      .where((p) => !ids.contains(p.id) && used.contains(p.id))
      .map((p) => p.name)
      .toList();
  if (removedUsed.isNotEmpty) {
    showMessage(
      context,
      '${removedUsed.join(', ')} tem lançamentos e não pode ser removido.',
      error: true,
    );
    return;
  }
  await runAction(context, () => fc.savePeople(r));
}

class _PersonsDialog extends StatefulWidget {
  final List<Person> people;
  const _PersonsDialog({required this.people});

  @override
  State<_PersonsDialog> createState() => _PersonsDialogState();
}

class _PersonsDialogState extends State<_PersonsDialog> {
  late final rows = [
    for (final p in widget.people)
      (p, TextEditingController(text: p.name), FocusNode()),
  ];
  late final isMe = {
    for (final p in widget.people)
      if (p.isMe) p.id,
  };

  @override
  void initState() {
    super.initState();
    if (rows.isEmpty) _add();
  }

  void _add() {
    final f = FocusNode();
    rows.add((
      Person(
        id: newId('pp_'),
        name: '',
        color: simColors[rows.length % simColors.length],
      ),
      TextEditingController(),
      f,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) => f.requestFocus());
  }

  @override
  void dispose() {
    for (final r in rows) {
      r.$2.dispose();
      r.$3.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pessoas'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Quem divide as despesas com você. Marque "Sou eu" na sua '
                'própria linha: a sua parte não é cobrada.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final (i, r) in rows.indexed)
                Row(
                  children: [
                    CircleAvatar(radius: 8, backgroundColor: Color(r.$1.color)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: ValueKey('oe-person-name-$i'),
                        controller: r.$2,
                        focusNode: r.$3,
                        decoration: const InputDecoration(labelText: 'Nome'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    FilterChip(
                      label: const Text('Sou eu'),
                      selected: isMe.contains(r.$1.id),
                      onSelected: (v) => setState(() {
                        isMe.clear();
                        if (v) isMe.add(r.$1.id);
                      }),
                    ),
                    IconButton(
                      tooltip: 'Remover',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => rows.removeAt(i)),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('oe-person-add'),
                  onPressed: () => setState(_add),
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
          key: const ValueKey('oe-people-save'),
          onPressed: () => Navigator.pop(context, [
            for (final r in rows)
              if (r.$2.text.trim().isNotEmpty)
                r.$1.copyWith(
                  name: r.$2.text.trim(),
                  isMe: isMe.contains(r.$1.id),
                ),
          ]),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Formulário do lançamento

Future<OtherEntry?> editOtherEntry(
  BuildContext context, {
  OtherEntry? entry,
  TransactionType type = TransactionType.expense,
  YearMonth? month,
}) async {
  final fc = context.read<FinanceController>();
  final draft = await showDialog<OtherEntry>(
    context: context,
    builder: (_) => ChangeNotifierProvider.value(
      value: fc,
      child: OtherEntryForm(
        entry:
            entry ??
            OtherEntry(
              id: newId('oe_'),
              type: type,
              description: '',
              amount: 0,
              month: month ?? YearMonth.now(),
            ),
        isNew: entry == null,
      ),
    ),
  );
  if (draft == null || !context.mounted) return null;
  OtherEntry? saved;
  await runAction(context, () async {
    saved = await fc.saveOtherEntry(draft);
  }, success: entry == null ? 'Lançamento criado' : 'Lançamento salvo');
  return saved;
}

class _AllocRow {
  String? personId;
  AllocMode mode;
  final TextEditingController ctl;

  /// Percentual exato de "Dividir igualmente" (ex.: 33,333...), usado
  /// enquanto o texto mostrado não for alterado.
  double? exact;
  _AllocRow(this.personId, this.mode, String text, {this.exact})
    : ctl = TextEditingController(text: text);
}

class OtherEntryForm extends StatefulWidget {
  final OtherEntry entry;
  final bool isNew;
  const OtherEntryForm({super.key, required this.entry, required this.isNew});

  @override
  State<OtherEntryForm> createState() => _OtherEntryFormState();
}

class _OtherEntryFormState extends State<OtherEntryForm> {
  late final e = widget.entry;
  late TransactionType type = e.type;
  late final desc = TextEditingController(text: e.description);
  late final amount = TextEditingController(
    text: e.amount > 0 ? Money(e.amount).formatPlain() : '',
  );
  late final notes = TextEditingController(text: e.notes);
  late YearMonth month = e.month;
  late DateTime? due = e.dueDate;
  late bool linked = e.linked;
  late bool settled = e.settled;
  late final rows = [
    for (final a in e.allocations)
      _AllocRow(
        a.personId,
        a.mode,
        a.mode == AllocMode.percent
            ? _pct(a.value.toDouble())
            : Money(a.value.round()).formatPlain(),
        exact: a.mode == AllocMode.percent ? a.value.toDouble() : null,
      ),
  ];
  String? error;

  static String _pct(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    for (final c in [desc, amount, notes, ...rows.map((r) => r.ctl)]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _amount => Money.tryEval(amount.text)?.cents ?? 0;

  num? _value(_AllocRow r) => r.mode == AllocMode.percent
      ? (r.exact != null && r.ctl.text == _pct(r.exact!)
            ? r.exact
            : double.tryParse(r.ctl.text.trim().replaceAll(',', '.')))
      : Money.tryEval(r.ctl.text)?.cents;

  List<Allocation> get _allocs => [
    for (final r in rows)
      if (r.personId != null) Allocation(r.personId!, r.mode, _value(r) ?? 0),
  ];

  OtherEntry get _draft => e.copyWith(
    type: type,
    description: desc.text.trim(),
    amount: _amount,
    month: month,
    dueDate: due,
    notes: notes.text.trim(),
    linked: linked,
    settled: settled,
    allocations: _allocs,
  );

  void _equal(FinanceController fc) {
    setState(() {
      if (rows.every((r) => r.personId == null)) {
        rows
          ..clear()
          ..addAll([
            for (final p in fc.people) _AllocRow(p.id, AllocMode.percent, ''),
          ]);
      }
      final n = rows.where((r) => r.personId != null).length;
      if (n == 0) return;
      // Percentual exato (100/n): os centavos são repartidos sem sobra.
      final each = 100 / n;
      for (final r in rows) {
        if (r.personId == null) continue;
        r.mode = AllocMode.percent;
        r.exact = each;
        r.ctl.text = _pct(each);
      }
    });
  }

  void _submit() {
    final d = _draft;
    String? err;
    if (d.description.isEmpty) {
      err = 'Informe uma descrição';
    } else if (d.amount <= 0) {
      err = 'Informe o valor total';
    } else if (rows.any((r) => r.personId != null && _value(r) == null)) {
      err = 'Confira os valores da divisão';
    } else if (rows.any((r) => r.personId == null)) {
      err = 'Escolha a pessoa em cada linha da divisão';
    } else if ({for (final r in rows) r.personId}.length != rows.length) {
      err = 'A mesma pessoa aparece duas vezes';
    } else if (_pctTotal(d) > 100.0001) {
      err = 'A soma dos percentuais passa de 100%';
    } else if (d.allocated > d.amount) {
      err = 'A divisão passa do valor total';
    }
    if (err != null) {
      setState(() => error = err);
      return;
    }
    Navigator.pop(context, d);
  }

  num _pctTotal(OtherEntry d) => d.allocations
      .where((a) => a.mode == AllocMode.percent)
      .fold<num>(0, (s, a) => s + a.value);

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final d = _draft;
    final now = YearMonth.now();
    final monthOpts = {
      for (var i = -24; i <= 24; i++) now.add(i),
      month,
    }.toList()..sort();
    final pct = _pctTotal(d);
    final hasPct = d.allocations.any((a) => a.mode == AllocMode.percent);
    final income = type == TransactionType.income;
    return AlertDialog(
      title: Text(
        widget.isNew ? 'Nova ${_typeNoun(type)}' : 'Editar ${_typeNoun(type)}',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Outra despesa'),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Outra receita'),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (s) => setState(() => type = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('oe-desc'),
                controller: desc,
                autofocus: widget.isNew,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MoneyField(
                      key: const ValueKey('oe-amount'),
                      controller: amount,
                      label: 'Valor total',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MonthDropdown(
                      label: 'Mês de referência',
                      value: month,
                      options: monthOpts,
                      onChanged: (m) => setState(() => month = m),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DateField(
                label: income ? 'Data prevista' : 'Vencimento',
                value: due,
                clearable: true,
                onChanged: (v) => setState(() => due = v),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const ValueKey('oe-linked'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Vincular ao orçamento'),
                subtitle: Text(
                  'Soma na linha "${OtherSync.typeLabel(type)}" de '
                  '${month.shortLabel}',
                ),
                value: linked,
                onChanged: (v) => setState(() => linked = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(income ? 'Já recebi tudo' : 'Já paguei esta conta'),
                value: settled,
                onChanged: (v) => setState(() => settled = v),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      income ? 'Quem paga' : 'Divisão entre pessoas',
                      style: context.text.titleSmall,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('oe-equal'),
                    onPressed: fc.people.isEmpty ? null : () => _equal(fc),
                    child: const Text('Dividir igualmente'),
                  ),
                ],
              ),
              if (fc.people.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Cadastre as pessoas para dividir.'),
                      ),
                      TextButton(
                        onPressed: () => editPersons(context),
                        child: const Text('Cadastrar pessoas'),
                      ),
                    ],
                  ),
                ),
              for (final (i, r) in rows.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('oe-alloc-person-$i'),
                          initialValue: r.personId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Pessoa',
                            isDense: true,
                          ),
                          items: [
                            for (final p in fc.people)
                              DropdownMenuItem(
                                value: p.id,
                                child: Text(p.isMe ? '${p.name} (eu)' : p.name),
                              ),
                          ],
                          onChanged: (v) => setState(() => r.personId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SegmentedButton<AllocMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: AllocMode.percent,
                            label: Text('%'),
                          ),
                          ButtonSegment(
                            value: AllocMode.fixed,
                            label: Text('R\$'),
                          ),
                        ],
                        selected: {r.mode},
                        onSelectionChanged: (s) => setState(() {
                          r.mode = s.first;
                          r.ctl.clear();
                        }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          key: ValueKey('oe-alloc-value-$i'),
                          controller: r.ctl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: r.mode == AllocMode.percent
                                ? '%'
                                : 'Valor',
                            helperText: r.personId == null
                                ? null
                                : fmtCents(d.owedByPerson()[r.personId] ?? 0),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => rows.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              if (fc.people.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('oe-alloc-add'),
                    onPressed: () => setState(
                      () => rows.add(
                        _AllocRow(
                          fc.people
                              .where(
                                (p) => !rows.any((r) => r.personId == p.id),
                              )
                              .firstOrNull
                              ?.id,
                          AllocMode.percent,
                          '',
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar pessoa'),
                  ),
                ),
              if (rows.isNotEmpty) _allocFooter(context, d, pct, hasPct),
              const SizedBox(height: 8),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    key: const ValueKey('oe-form-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
          key: const ValueKey('oe-save'),
          onPressed: _submit,
          child: const Text('Salvar'),
        ),
      ],
    );
  }

  Widget _allocFooter(
    BuildContext context,
    OtherEntry d,
    num pct,
    bool hasPct,
  ) {
    final un = d.unallocated;
    final over = un < 0 || pct > 100.0001;
    final ok = un == 0 && !over;
    final color = over
        ? context.fin.negative
        : ok
        ? context.fin.positive
        : Colors.amber.shade800;
    final text = over
        ? 'A divisão passa do total (${hasPct ? '${_pct(pct.toDouble())}%' : fmtCents(d.allocated)})'
        : ok
        ? 'Tudo distribuído${hasPct ? ' (${_pct(pct.toDouble())}%)' : ''}'
        : 'Falta distribuir ${fmtCents(un)}'
              '${hasPct ? ' · ${_pct(pct.toDouble())}% informados' : ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.info_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              key: const ValueKey('oe-alloc-footer'),
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Detalhe do lançamento

class OtherEntryScreen extends StatelessWidget {
  final String entryId;
  const OtherEntryScreen({super.key, required this.entryId});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.otherEntryById(entryId);
    if (e == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Lançamento não encontrado',
        ),
      );
    }
    final me = fc.meIds;
    final shares = e.shares();
    final monthTx = fc.data.transactions
        .where((t) => t.id == OtherSync.monthTxId(e.type, e.month))
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(e.description),
        actions: [
          if (!e.isDeleted)
            IconButton(
              key: const ValueKey('oe-edit'),
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => editOtherEntry(context, entry: e),
            ),
          if (e.isDeleted)
            TextButton.icon(
              onPressed: () => runAction(
                context,
                () => fc.restoreOtherEntry(e),
                success: 'Lançamento restaurado',
              ),
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar'),
            )
          else
            IconButton(
              key: const ValueKey('oe-delete'),
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, e),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (e.isDeleted)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(
                  'Excluído em ${Dates.format(e.deletedAt!)}. Não entra mais '
                  'no orçamento; pagamentos e histórico foram mantidos.',
                ),
              ),
            ),
          SectionCard(
            title: e.isIncome ? 'Outra receita' : 'Outra despesa',
            child: Column(
              children: [
                InfoRow.text('Valor total', fmtCents(e.amount)),
                InfoRow.text('Mês de referência', e.month.longLabel),
                InfoRow.text(
                  e.isIncome ? 'Data prevista' : 'Vencimento',
                  e.dueDate == null ? '—' : Dates.format(e.dueDate!),
                ),
                InfoRow(
                  e.isIncome ? 'Recebimento' : 'Reembolsos',
                  payStatusPill(context, e.status(me)),
                ),
                if (!e.isIncome)
                  InfoRow.text(
                    'A conta',
                    e.settled ? 'Paga por mim' : 'Ainda não paga',
                  ),
                if (e.isIncome)
                  InfoRow.text(
                    'Recebido',
                    '${fmtCents(e.received)} de ${fmtCents(e.amount)}',
                  ),
                if (e.unallocated != 0 && e.allocations.isNotEmpty)
                  InfoRow.text('Sem divisão', fmtCents(e.unallocated)),
                if (e.notes.isNotEmpty) InfoRow.text('Observações', e.notes),
              ],
            ),
          ),
          SectionCard(
            title: 'Orçamento',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(e.linked ? Icons.link : Icons.link_off),
              title: Text(
                e.linked
                    ? 'Faz parte da linha "${OtherSync.typeLabel(e.type)}" de '
                          '${e.month.shortLabel}'
                    : 'Não vinculado ao orçamento',
              ),
              subtitle: monthTx == null || !e.linked
                  ? null
                  : Text(
                      'Total da linha: ${fmtCents(monthTx.amount.cents)} em '
                      '${Dates.format(monthTx.date)}',
                    ),
              trailing: e.isDeleted
                  ? null
                  : Switch(
                      key: const ValueKey('oe-link-switch'),
                      value: e.linked,
                      onChanged: (v) => runAction(
                        context,
                        () => fc.saveOtherEntry(e.copyWith(linked: v)),
                      ),
                    ),
            ),
          ),
          SectionCard(
            title: e.isIncome ? 'Quem paga' : 'Partes por pessoa',
            child: shares.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Sem divisão. Use "Editar" para informar o % ou o valor '
                      'de cada pessoa.',
                      style: TextStyle(color: context.fin.subtle),
                    ),
                  )
                : Column(
                    children: [
                      for (final s in shares)
                        _ShareTile(
                          entry: e,
                          share: s,
                          isMe: me.contains(s.personId),
                        ),
                    ],
                  ),
          ),
          SectionCard(
            title: 'Pagamentos',
            child: e.payments.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Nenhum pagamento registrado.',
                      style: TextStyle(color: context.fin.subtle),
                    ),
                  )
                : Column(
                    children: [
                      for (final p in [
                        ...e.payments,
                      ]..sort((a, b) => b.date.compareTo(a.date)))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${fc.personById(p.personId)?.name ?? '?'} · '
                            '${fmtCents(p.amount)}',
                          ),
                          subtitle: Text(
                            [
                              Dates.format(p.date),
                              p.method,
                              if (p.note.isNotEmpty) p.note,
                              if (!e.isIncome &&
                                  !me.contains(p.personId) &&
                                  fc.otherAccount != null)
                                'receita gerada no orçamento',
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar pagamento',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => editOtherPayment(
                                  context,
                                  e,
                                  personId: p.personId,
                                  payment: p,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Excluir pagamento',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final ok = await confirmDialog(
                                    context,
                                    title: 'Excluir pagamento?',
                                    message:
                                        'A receita de reembolso ligada a ele '
                                        'também sai do orçamento.',
                                    confirm: 'Excluir',
                                    destructive: true,
                                  );
                                  if (!ok || !context.mounted) return;
                                  await runAction(
                                    context,
                                    () => fc.deleteOtherPayment(e, p),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          SectionCard(
            title: 'Histórico',
            child: Column(
              children: [
                for (final h in e.history.reversed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history, size: 18),
                    title: Text(h.text),
                    subtitle: Text(
                      '${Dates.format(h.at)} '
                      '${h.at.hour.toString().padLeft(2, '0')}:'
                      '${h.at.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, OtherEntry e) async {
    final fc = context.read<FinanceController>();
    final ok = await confirmDialog(
      context,
      title: 'Excluir "${e.description}"?',
      message: e.payments.isEmpty
          ? 'Ele sai da linha do orçamento do mês. Você pode restaurá-lo '
                'depois em "Excluídos".'
          : 'Este lançamento tem ${e.payments.length} '
                '${e.payments.length == 1 ? 'pagamento registrado' : 'pagamentos registrados'}. '
                'Ele sai da linha do orçamento do mês, mas os pagamentos, as '
                'receitas de reembolso e o histórico são mantidos. Você pode '
                'restaurá-lo depois em "Excluídos".',
      confirm: 'Excluir',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await runAction(
      context,
      () => fc.deleteOtherEntry(e),
      success: 'Lançamento excluído',
    );
  }
}

class _ShareTile extends StatelessWidget {
  final OtherEntry entry;
  final PersonShare share;
  final bool isMe;
  const _ShareTile({
    required this.entry,
    required this.share,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final p = fc.personById(share.personId);
    final s = share;
    final noCharge = isMe && !entry.isIncome;
    return ListTile(
      key: ValueKey('oe-share-${s.personId}'),
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: Color(p?.color ?? 0xFF9E9E9E),
        child: Text(
          (p?.name.isNotEmpty ?? false) ? p!.name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      title: Text(
        '${p?.name ?? '?'}${isMe ? ' (eu)' : ''}'
        '${s.percent == null ? '' : ' · ${_OtherEntryFormState._pct(s.percent!)}%'}',
      ),
      subtitle: Text(
        noCharge
            ? 'Parte: ${fmtCents(s.owed)} · sua parte, não é cobrada'
            : 'Deve ${fmtCents(s.owed)} · pagou ${fmtCents(s.paid)} · '
                  'saldo ${fmtCents(s.balance)}',
      ),
      trailing: noCharge
          ? null
          : Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                payStatusPill(context, s.status),
                if (!entry.isDeleted)
                  IconButton(
                    key: ValueKey('oe-pay-${s.personId}'),
                    tooltip: 'Registrar pagamento',
                    icon: const Icon(Icons.add_card),
                    onPressed: () =>
                        editOtherPayment(context, entry, personId: s.personId),
                  ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Pagamento

Future<void> editOtherPayment(
  BuildContext context,
  OtherEntry e, {
  required String personId,
  OtherPayment? payment,
}) async {
  final fc = context.read<FinanceController>();
  final share = e.shares().where((s) => s.personId == personId).firstOrNull;
  final suggested = payment?.amount ?? (share?.balance ?? 0);
  final r = await showDialog<OtherPayment>(
    context: context,
    builder: (_) => _PaymentDialog(
      payment:
          payment ??
          OtherPayment(
            id: newId('pay_'),
            personId: personId,
            amount: suggested > 0 ? suggested : 0,
            date: Dates.today(),
          ),
      personName: fc.personById(personId)?.name ?? '?',
      balance: share?.balance,
    ),
  );
  if (r == null || !context.mounted) return;
  await runAction(
    context,
    () => fc.saveOtherPayment(e, r),
    success: 'Pagamento salvo',
  );
}

class _PaymentDialog extends StatefulWidget {
  final OtherPayment payment;
  final String personName;
  final int? balance;
  const _PaymentDialog({
    required this.payment,
    required this.personName,
    this.balance,
  });

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final p = widget.payment;
  late final amount = TextEditingController(
    text: p.amount > 0 ? Money(p.amount).formatPlain() : '',
  );
  late final note = TextEditingController(text: p.note);
  late DateTime date = p.date;
  late String method = paymentMethods.contains(p.method)
      ? p.method
      : paymentMethods.last;
  String? error;

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Pagamento de ${widget.personName}'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.balance != null)
            Text(
              'Saldo em aberto: ${fmtCents(widget.balance!)}. Pode registrar '
              'um valor parcial.',
              style: context.text.bodySmall,
            ),
          const SizedBox(height: 8),
          MoneyField(
            key: const ValueKey('oe-pay-amount'),
            controller: amount,
            label: 'Valor pago',
          ),
          const SizedBox(height: 12),
          DateField(
            label: 'Data do pagamento',
            value: date,
            onChanged: (v) => setState(() => date = v ?? date),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'Forma de pagamento'),
            items: [
              for (final m in paymentMethods)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => method = v ?? method),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Observação'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('oe-pay-save'),
        onPressed: () {
          final v = Money.tryEval(amount.text)?.cents ?? 0;
          if (v <= 0) {
            setState(() => error = 'Informe o valor pago');
            return;
          }
          Navigator.pop(
            context,
            p.copyWith(
              amount: v,
              date: date,
              method: method,
              note: note.text.trim(),
            ),
          );
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}
