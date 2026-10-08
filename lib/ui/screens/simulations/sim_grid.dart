import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter/services.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/simulation_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../domain/models/simulation.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'sim_common.dart';
import 'sim_item_dialog.dart';

const _leftW = 260.0;
const _fundW = 150.0;
const _classW = 104.0;
const _monthW = 112.0;
const _totalW = 124.0;
const _actW = 44.0;
const _rowH = 46.0;

enum _Filter { all, income, expense }

enum _Sort { standard, description, total, category, changed }

enum _RowKind { header, item, subtotal, net, accumulated, baseNet, diff }

class _Row {
  final _RowKind kind;
  final SimItem? item;
  final bool income;
  final String label;
  const _Row(this.kind, {this.item, this.income = false, this.label = ''});
}

enum _ItemAct { edit, duplicate, restore, delete }

/// Planilha da simulação: linhas (receitas e despesas) × meses, com edição
/// direto na célula (Enter/↓ desce, Tab avança, Esc cancela; aceita
/// expressões como "1200+300").
class SimGrid extends StatefulWidget {
  final FinanceController fc;
  final Simulation sim;
  final ValueChanged<List<SimItem>> onChanged;
  const SimGrid({
    super.key,
    required this.fc,
    required this.sim,
    required this.onChanged,
  });

  @override
  State<SimGrid> createState() => _SimGridState();
}

class _SimGridState extends State<SimGrid> {
  final _h = ScrollController();
  final _hHead = ScrollController();
  final _ctrl = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _onKey);
  String query = '';
  _Filter filter = _Filter.all;
  _Sort sort = _Sort.standard;
  bool onlyChanged = false;
  String? editId;
  YearMonth? editMonth;
  bool _switching = false;

  Simulation get sim => widget.sim;
  late Map<String, SimItem> _base;

  @override
  void initState() {
    super.initState();
    _h.addListener(() {
      if (_hHead.hasClients && _hHead.offset != _h.offset) {
        _hHead.jumpTo(_h.offset);
      }
    });
    _focus.addListener(() {
      if (!_focus.hasFocus && editId != null && !_switching) _commit();
    });
  }

  @override
  void dispose() {
    _h.dispose();
    _hHead.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _changed(SimItem i) {
    final b = _base[i.id];
    if (b == null) return true;
    if (!i.sameFieldsAs(b)) return true;
    return sim.months.any((m) => i.valueAt(m) != b.valueAt(m));
  }

  List<SimItem> get _visible {
    final q = query.trim().toLowerCase();
    final list = sim.items.where((i) {
      if (filter == _Filter.income && !i.isIncome) return false;
      if (filter == _Filter.expense && i.isIncome) return false;
      if (onlyChanged && !_changed(i)) return false;
      if (q.isEmpty) return true;
      return i.description.toLowerCase().contains(q) ||
          categoryLabel(widget.fc, i.categoryId).toLowerCase().contains(q);
    }).toList();
    final months = sim.months;
    int cmp(SimItem a, SimItem b) => switch (sort) {
      _Sort.standard => 0,
      _Sort.description => a.description.toLowerCase().compareTo(
        b.description.toLowerCase(),
      ),
      _Sort.total => b.totalIn(months).compareTo(a.totalIn(months)),
      _Sort.category => categoryLabel(
        widget.fc,
        a.categoryId,
      ).compareTo(categoryLabel(widget.fc, b.categoryId)),
      _Sort.changed => (_changed(b) ? 1 : 0) - (_changed(a) ? 1 : 0),
    };
    if (sort != _Sort.standard) {
      // Ordenação estável dentro de receitas / despesas.
      final idx = {for (var k = 0; k < list.length; k++) list[k].id: k};
      list.sort((a, b) {
        final c = cmp(a, b);
        return c != 0 ? c : idx[a.id]!.compareTo(idx[b.id]!);
      });
    }
    return list;
  }

  // ---------------------------------------------------------------------------
  // Edição

  void _replace(SimItem next) =>
      widget.onChanged([for (final i in sim.items) i.id == next.id ? next : i]);

  void _startEdit(SimItem i, YearMonth m) {
    if (editId != null) _commit();
    final v = i.valueAt(m);
    _switching = true;
    setState(() {
      editId = i.id;
      editMonth = m;
      _ctrl.text = v == 0 ? '' : Money(v).formatPlain();
      _ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _ctrl.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
      _switching = false;
    });
  }

  /// Grava a célula em edição. Retorna `false` se o valor for inválido.
  bool _commit() {
    final id = editId, m = editMonth;
    if (id == null || m == null) return true;
    final text = _ctrl.text.trim();
    final v = text.isEmpty ? Money.zero : Money.tryEval(text);
    if (v == null) {
      showMessage(context, 'Valor inválido: $text', error: true);
      return false;
    }
    setState(() {
      editId = null;
      editMonth = null;
    });
    final item = sim.items.where((i) => i.id == id).firstOrNull;
    if (item != null && item.valueAt(m) != v.cents.abs()) {
      _replace(item.withValue(m, v.cents.abs()));
    }
    return true;
  }

  void _cancelEdit() => setState(() {
    editId = null;
    editMonth = null;
  });

  void _move(int dRow, int dCol) {
    final id = editId, m = editMonth;
    if (id == null || m == null) return;
    if (!_commit()) return;
    final rows = _visible;
    final months = sim.months;
    final r = rows.indexWhere((i) => i.id == id);
    final c = months.indexOf(m);
    var nr = r + dRow, nc = c + dCol;
    if (nc >= months.length) {
      nc = 0;
      nr++;
    } else if (nc < 0) {
      nc = months.length - 1;
      nr--;
    }
    if (nr < 0 || nr >= rows.length) return;
    _startEdit(rows[nr], months[nc]);
    _scrollToMonth(nc, onlyIfHidden: true);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (k == LogicalKeyboardKey.tab) {
      _move(0, shift ? -1 : 1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _move(1, 0);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1, 0);
    } else if (k == LogicalKeyboardKey.escape) {
      _cancelEdit();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _scrollToMonth(int index, {bool onlyIfHidden = false}) {
    if (!_h.hasClients) return;
    final x = _fundW + _classW + index * _monthW;
    final view = _h.position.viewportDimension;
    if (onlyIfHidden && x >= _h.offset && x + _monthW <= _h.offset + view) {
      return;
    }
    _h.animateTo(
      (x - 24).clamp(0, _h.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openItem({SimItem? item, TransactionType? type}) async {
    if (editId != null) _commit();
    final r = await showDialog<SimItem>(
      context: context,
      builder: (_) => SimItemDialog(
        fc: widget.fc,
        sim: sim,
        item: item,
        type: type ?? TransactionType.expense,
      ),
    );
    if (r == null) return;
    if (item == null) {
      final next = [...sim.items, r];
      // Mantém receitas antes das despesas.
      final inc = next.where((i) => i.isIncome).toList();
      final exp = next.where((i) => !i.isIncome).toList();
      widget.onChanged([...inc, ...exp]);
    } else {
      final next = [for (final i in sim.items) i.id == r.id ? r : i];
      if (r.type != item.type) SimulationEngine.sortItems(next);
      widget.onChanged(next);
    }
  }

  void _itemAction(SimItem i, _ItemAct a) {
    switch (a) {
      case _ItemAct.edit:
        _openItem(item: i);
      case _ItemAct.duplicate:
        final copy = i.copyWith(
          id: newId('si_'),
          description: '${i.description} (cópia)',
          origin: SimOrigin.added,
          sourceKey: null,
          refs: const {},
        );
        final idx = sim.items.indexWhere((x) => x.id == i.id);
        widget.onChanged([...sim.items]..insert(idx + 1, copy));
      case _ItemAct.restore:
        final b = _base[i.id];
        if (b != null) _replace(b);
      case _ItemAct.delete:
        widget.onChanged(sim.items.where((x) => x.id != i.id).toList());
    }
  }

  Future<void> _showRemoved(List<SimItem> removed) async {
    final picked = await showModalBottomSheet<SimItem>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Linhas removidas da simulação')),
          for (final b in removed)
            ListTile(
              leading: Icon(
                b.isIncome ? Icons.trending_up : Icons.trending_down,
                color: b.isIncome ? ctx.fin.income : ctx.fin.expense,
              ),
              title: Text(b.description),
              subtitle: Text(
                '${fmtCents(b.totalIn(sim.months))} no período no orçamento base',
              ),
              trailing: TextButton(
                onPressed: () => Navigator.pop(ctx, b),
                child: const Text('Restaurar'),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    final next = [...sim.items, picked];
    SimulationEngine.sortItems(next);
    widget.onChanged(next);
  }

  // ---------------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    _base = {for (final b in sim.baseItems) b.id: b};
    final months = sim.months;
    final visible = _visible;
    final totals = SimTotals.of(sim.items, months, sim.opening);
    final baseTotals = SimTotals.of(sim.baseItems, months, sim.opening);
    final itemIds = {for (final i in sim.items) i.id};
    final removed = sim.baseItems
        .where((b) => !itemIds.contains(b.id))
        .toList();

    final rows = <_Row>[];
    for (final income in [true, false]) {
      if (filter == _Filter.income && !income) continue;
      if (filter == _Filter.expense && income) continue;
      rows.add(
        _Row(
          _RowKind.header,
          income: income,
          label: income ? 'Receitas' : 'Despesas',
        ),
      );
      for (final i in visible.where((i) => i.isIncome == income)) {
        rows.add(_Row(_RowKind.item, item: i, income: income));
      }
      rows.add(
        _Row(
          _RowKind.subtotal,
          income: income,
          label: income ? 'Total de receitas' : 'Total de despesas',
        ),
      );
    }
    rows.addAll(const [
      _Row(_RowKind.net, label: 'Resultado do mês (simulado)'),
      _Row(_RowKind.accumulated, label: 'Saldo acumulado (simulado)'),
      _Row(_RowKind.baseNet, label: 'Resultado no orçamento base'),
      _Row(_RowKind.diff, label: 'Diferença (simulado − base)'),
    ]);

    final rightW = _fundW + _classW + months.length * _monthW + _totalW + _actW;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(context, months, removed),
        const Divider(height: 1),
        // Cabeçalho fixo
        Container(
          color: context.fin.stickyColumn,
          height: 36,
          child: Row(
            children: [
              _headCell(context, 'Descrição / categoria', _leftW, left: true),
              Expanded(
                child: SingleChildScrollView(
                  controller: _hHead,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      _headCell(context, 'Conta / cartão', _fundW, left: true),
                      _headCell(context, 'Classificação', _classW, left: true),
                      for (final m in months)
                        _headCell(context, m.shortLabel, _monthW),
                      _headCell(context, 'Total', _totalW),
                      const SizedBox(width: _actW),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _leftW,
                  child: Column(
                    children: [for (final r in rows) _leftCell(context, r)],
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    controller: _h,
                    child: SingleChildScrollView(
                      controller: _h,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: rightW,
                        child: Column(
                          children: [
                            for (final r in rows)
                              _rightRow(context, r, months, totals, baseTotals),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toolbar(
    BuildContext context,
    List<YearMonth> months,
    List<SimItem> removed,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.tonalIcon(
            key: const ValueKey('sim-add-expense'),
            onPressed: () => _openItem(type: TransactionType.expense),
            icon: const Icon(Icons.remove_circle_outline),
            label: const Text('Despesa'),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('sim-add-income'),
            onPressed: () => _openItem(type: TransactionType.income),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Receita'),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar linha',
                isDense: true,
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          SegmentedButton<_Filter>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Filter.all, label: Text('Tudo')),
              ButtonSegment(value: _Filter.income, label: Text('Receitas')),
              ButtonSegment(value: _Filter.expense, label: Text('Despesas')),
            ],
            selected: {filter},
            onSelectionChanged: (s) => setState(() => filter = s.first),
          ),
          FilterChip(
            label: const Text('Só alteradas'),
            selected: onlyChanged,
            onSelected: (v) => setState(() => onlyChanged = v),
          ),
          PopupMenuButton<_Sort>(
            tooltip: 'Ordenar',
            initialValue: sort,
            onSelected: (s) => setState(() => sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.standard, child: Text('Ordem padrão')),
              PopupMenuItem(
                value: _Sort.description,
                child: Text('Descrição (A–Z)'),
              ),
              PopupMenuItem(value: _Sort.total, child: Text('Maior total')),
              PopupMenuItem(value: _Sort.category, child: Text('Categoria')),
              PopupMenuItem(
                value: _Sort.changed,
                child: Text('Alteradas primeiro'),
              ),
            ],
            child: const Chip(
              avatar: Icon(Icons.sort, size: 18),
              label: Text('Ordenar'),
            ),
          ),
          PopupMenuButton<int>(
            tooltip: 'Ir para o mês',
            onSelected: _scrollToMonth,
            itemBuilder: (_) => [
              for (var k = 0; k < months.length; k++)
                PopupMenuItem(value: k, child: Text(months[k].longLabel)),
            ],
            child: const Chip(
              avatar: Icon(Icons.calendar_month, size: 18),
              label: Text('Ir para o mês'),
            ),
          ),
          if (removed.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.restore, size: 18),
              label: Text('Removidas (${removed.length})'),
              onPressed: () => _showRemoved(removed),
            ),
        ],
      ),
    );
  }

  Widget _headCell(
    BuildContext context,
    String text,
    double w, {
    bool left = false,
  }) => SizedBox(
    width: w,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        text,
        textAlign: left ? TextAlign.left : TextAlign.right,
        style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  BoxDecoration _rowDeco(BuildContext context, _Row r) {
    final line = BorderSide(color: context.fin.gridLine);
    Color? bg;
    switch (r.kind) {
      case _RowKind.header:
        bg = context.colors.surfaceContainerHighest.withValues(alpha: 0.5);
      case _RowKind.subtotal:
      case _RowKind.net:
      case _RowKind.accumulated:
        bg = context.colors.surfaceContainerHigh.withValues(alpha: 0.6);
      case _RowKind.baseNet:
      case _RowKind.diff:
        bg = context.colors.surfaceContainerLow;
      case _RowKind.item:
        bg = null;
    }
    return BoxDecoration(
      color: bg,
      border: Border(bottom: line),
    );
  }

  Widget _leftCell(BuildContext context, _Row r) {
    final deco = _rowDeco(context, r);
    if (r.kind != _RowKind.item) {
      return Container(
        height: _rowH,
        decoration: deco,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Text(
          r.label,
          style: context.text.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: r.kind == _RowKind.header
                ? (r.income ? context.fin.income : context.fin.expense)
                : null,
          ),
        ),
      );
    }
    final i = r.item!;
    final added = !_base.containsKey(i.id);
    final changed = !added && _changed(i);
    return Container(
      height: _rowH,
      decoration: deco,
      child: InkWell(
        onTap: () => _openItem(item: i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 26,
                decoration: BoxDecoration(
                  color: added
                      ? context.colors.primary
                      : changed
                      ? context.fin.warning
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium,
                    ),
                    Text(
                      [
                        categoryLabel(widget.fc, i.categoryId),
                        if (i.recurrence != SimRecurrence.once)
                          i.recurrence.label,
                        if (added) 'nova',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: context.fin.subtle,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _num(
    BuildContext context,
    int cents,
    double w, {
    Color? color,
    bool bold = false,
    String? text,
  }) => SizedBox(
    width: w,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        text ?? (cents == 0 ? '–' : Money(cents).formatPlain()),
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodySmall?.copyWith(
          color: color,
          fontWeight: bold ? FontWeight.w700 : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );

  Widget _rightRow(
    BuildContext context,
    _Row r,
    List<YearMonth> months,
    SimTotals totals,
    SimTotals baseTotals,
  ) {
    final deco = _rowDeco(context, r);
    final pad = const SizedBox(width: _fundW + _classW);
    Widget row(List<Widget> cells) => Container(
      height: _rowH,
      decoration: deco,
      child: Row(children: cells),
    );
    final fin = context.fin;
    switch (r.kind) {
      case _RowKind.header:
        return row(const []);
      case _RowKind.subtotal:
        final vals = [
          for (final m in totals.months) r.income ? m.income : m.expenses,
        ];
        final color = r.income ? fin.income : fin.expense;
        return row([
          pad,
          for (final v in vals)
            _num(context, v, _monthW, color: color, bold: true),
          _num(
            context,
            vals.fold(0, (a, v) => a + v),
            _totalW,
            color: color,
            bold: true,
          ),
        ]);
      case _RowKind.net:
        return row([
          pad,
          for (final m in totals.months)
            _num(
              context,
              m.net,
              _monthW,
              bold: true,
              color: m.net < 0 ? fin.negative : fin.positive,
            ),
          _num(
            context,
            totals.net,
            _totalW,
            bold: true,
            color: totals.net < 0 ? fin.negative : fin.positive,
          ),
        ]);
      case _RowKind.accumulated:
        return row([
          pad,
          for (final m in totals.months)
            _num(
              context,
              m.accumulated,
              _monthW,
              bold: true,
              color: m.accumulated < 0 ? fin.negative : null,
            ),
          _num(context, totals.finalBalance, _totalW, bold: true),
        ]);
      case _RowKind.baseNet:
        return row([
          pad,
          for (final m in baseTotals.months)
            _num(context, m.net, _monthW, color: fin.subtle),
          _num(context, baseTotals.net, _totalW, color: fin.subtle),
        ]);
      case _RowKind.diff:
        return row([
          pad,
          for (var k = 0; k < months.length; k++)
            _diffCell(
              context,
              totals.months[k].net - baseTotals.months[k].net,
              _monthW,
            ),
          _diffCell(context, totals.net - baseTotals.net, _totalW),
        ]);
      case _RowKind.item:
        final i = r.item!;
        final b = _base[i.id];
        return row([
          SizedBox(
            width: _fundW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                fundingLabel(widget.fc, i.accountId, i.cardId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
            ),
          ),
          SizedBox(
            width: _classW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                i.classification.isEmpty ? '—' : i.classification,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
            ),
          ),
          for (final m in months) _valueCell(context, i, b, m),
          _num(
            context,
            i.totalIn(months),
            _totalW,
            bold: true,
            color: i.isIncome ? fin.income : fin.expense,
          ),
          SizedBox(
            width: _actW,
            child: PopupMenuButton<_ItemAct>(
              tooltip: 'Ações da linha',
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (a) => _itemAction(i, a),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _ItemAct.edit,
                  child: Text('Editar / preencher período'),
                ),
                const PopupMenuItem(
                  value: _ItemAct.duplicate,
                  child: Text('Duplicar linha'),
                ),
                if (b != null && _changed(i))
                  const PopupMenuItem(
                    value: _ItemAct.restore,
                    child: Text('Restaurar valores da base'),
                  ),
                const PopupMenuItem(
                  value: _ItemAct.delete,
                  child: Text('Remover da simulação'),
                ),
              ],
            ),
          ),
        ]);
    }
  }

  Widget _diffCell(BuildContext context, int diff, double w) => SizedBox(
    width: w,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: FittedBox(fit: BoxFit.scaleDown, child: DiffText(diff)),
      ),
    ),
  );

  Widget _valueCell(BuildContext context, SimItem i, SimItem? b, YearMonth m) {
    final v = i.valueAt(m);
    final baseV = b?.valueAt(m) ?? 0;
    final editing = editId == i.id && editMonth == m;
    if (editing) {
      return SizedBox(
        width: _monthW,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: TextField(
            key: const ValueKey('sim-cell-editor'),
            controller: _ctrl,
            focusNode: _focus,
            textAlign: TextAlign.right,
            style: context.text.bodySmall,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _move(1, 0),
          ),
        ),
      );
    }
    final diff = v != baseV;
    final cell = InkWell(
      key: ValueKey('sim-cell-${i.id}-${m.key}'),
      onTap: () => _startEdit(i, m),
      child: Container(
        width: _monthW,
        height: _rowH,
        color: diff ? context.fin.warning.withValues(alpha: 0.14) : null,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          v == 0 ? '–' : Money(v).formatPlain(),
          style: context.text.bodySmall?.copyWith(
            fontWeight: diff ? FontWeight.w700 : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    if (!diff) return cell;
    return Tooltip(message: 'Orçamento base: ${fmtCents(baseV)}', child: cell);
  }
}
