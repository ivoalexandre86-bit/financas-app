import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/tx_grid.dart';
import 'month_closing_ui.dart';

/// Ajustar o resultado mês a mês, numa grade como a da Projeção: os meses
/// nas colunas, os valores calculados pelos lançamentos e uma linha
/// **Ajuste** onde o usuário digita quanto somar (ou tirar, com "-") do
/// resultado de cada mês. Salvar grava todos os meses alterados de uma vez
/// ([FinanceController.saveMonthAdjustments]); ajuste zero reabre o mês.
class MonthAdjustScreen extends StatefulWidget {
  final MonthRange range;

  /// Mês que recebe o foco ao abrir (ex.: o mês tocado na Projeção).
  final YearMonth? focus;

  const MonthAdjustScreen({super.key, required this.range, this.focus});

  @override
  State<MonthAdjustScreen> createState() => _MonthAdjustScreenState();
}

class _MonthAdjustScreenState extends State<MonthAdjustScreen> {
  late MonthRange range = widget.range;
  final _ctrls = <YearMonth, TextEditingController>{};
  final _initial = <YearMonth, Money>{};
  final _focus = <YearMonth, FocusNode>{};
  bool _saving = false;

  static const _rowH = 44.0;
  static const _headerH = 46.0;
  static const _minCellW = 124.0;

  @override
  void initState() {
    super.initState();
    final f = widget.focus;
    if (f != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus[f]?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Ajuste já gravado: diferença entre o resultado que vale para o mês e o
  /// calculado agora pelos lançamentos.
  Money _saved(FinanceController fc, YearMonth m) {
    final c = fc.closingOf(m);
    if (c == null) return Money.zero;
    return c.net - fc.engine.computedMonthTotals(ProjectionFilter.none, m).net;
  }

  TextEditingController _ctrl(FinanceController fc, YearMonth m) =>
      _ctrls.putIfAbsent(m, () {
        final v = _saved(fc, m);
        _initial[m] = v;
        return TextEditingController(text: v.isZero ? '' : v.formatPlain());
      });

  /// Valor digitado (vazio = zero; nulo = inválido).
  Money? _typed(YearMonth m) {
    final t = _ctrls[m]?.text.trim() ?? '';
    if (t.isEmpty) return Money.zero;
    return Money.tryEval(t);
  }

  Map<YearMonth, Money> get _changes => {
    for (final m in _ctrls.keys)
      if (_typed(m) case final v? when v != _initial[m]) m: v,
  };

  bool get _hasInvalid => _ctrls.keys.any((m) => _typed(m) == null);

  Future<void> _save() async {
    if (_hasInvalid) {
      showMessage(context, 'Corrija os valores em vermelho.');
      return;
    }
    final changes = _changes;
    if (changes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    final fc = context.read<FinanceController>();
    final nav = Navigator.of(context);
    final ok = await runAction(
      context,
      () => fc.saveMonthAdjustments(changes),
      success: changes.length == 1
          ? 'Ajuste de ${changes.keys.single.longLabel} salvo'
          : 'Ajustes de ${changes.length} meses salvos',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) nav.pop();
  }

  Future<bool> _confirmLeave() async {
    if (_changes.isEmpty) return true;
    return confirmDialog(
      context,
      title: 'Sair sem salvar?',
      message: 'Os ajustes digitados serão perdidos.',
      confirm: 'Sair',
      destructive: true,
    );
  }

  /// Detalhe do mês (receitas, despesas e observação) no diálogo antigo.
  Future<void> _detail(FinanceController fc, YearMonth m) async {
    await showAdjustMonthDialog(context, m);
    if (!mounted) return;
    final v = _saved(fc, m);
    _initial[m] = v;
    _ctrls[m]?.text = v.isZero ? '' : v.formatPlain();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final e = fc.engine;
    final months = range.months;
    final computed = {
      for (final m in months)
        m: e.computedMonthTotals(ProjectionFilter.none, m),
    };
    final opening = e.projection(range).columns.first.opening;
    final adj = {for (final m in months) m: _typed(m) ?? Money.zero};
    final finals = {for (final m in months) m: computed[m]!.net + adj[m]!};
    final accumulated = <YearMonth, Money>{};
    var run = opening;
    for (final m in months) {
      run += finals[m]!;
      accumulated[m] = run;
    }
    final changed = _changes.length;

    final p = GridPalette.of(context);
    final fin = context.fin;
    final headerStyle = context.text.labelSmall?.copyWith(
      color: p.headerText,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );
    final now = YearMonth.now();

    Widget money(Money v, {bool strong = false, bool signed = true}) => Text(
      v.formatPlain(),
      maxLines: 1,
      style: context.text.bodyMedium?.copyWith(
        fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
        color: signed && v.isNegative ? fin.negative : null,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    // (rótulo, cor da listra, célula do mês, destaque)
    final rows = <(String, Color, Widget Function(YearMonth), bool)>[
      (
        'Receitas',
        fin.income,
        (m) => money(computed[m]!.income, signed: false),
        false,
      ),
      (
        'Despesas',
        fin.expense,
        (m) => money(computed[m]!.expenses, signed: false),
        false,
      ),
      ('Resultado calculado', p.neon, (m) => money(computed[m]!.net), false),
      ('Ajuste (digite)', p.neon2, (m) => _adjustCell(fc, m), true),
      (
        'Resultado ajustado',
        p.neon,
        (m) => money(finals[m]!, strong: true),
        false,
      ),
      (
        'Saldo acumulado',
        p.neon2,
        (m) => money(accumulated[m]!, strong: true),
        false,
      ),
    ];

    Widget rowBg(int i, bool edit, Widget child) => Container(
      height: _rowH,
      decoration: BoxDecoration(
        color: edit ? p.valueBg : (i.isOdd ? p.zebra : null),
        border: Border(bottom: BorderSide(color: p.line, width: 0.6)),
      ),
      child: child,
    );

    Widget header(YearMonth m, double cellW) {
      final c = fc.closingOf(m);
      final status = c == null
          ? (m == now ? 'atual' : 'aberto')
          : (c.isAdjusted ? 'ajustado' : 'fechado');
      return InkWell(
        key: ValueKey('adjust-head-${m.key}'),
        onTap: () => _detail(fc, m),
        child: Container(
          width: cellW,
          height: _headerH,
          color: m == now ? p.neon.withValues(alpha: 0.10) : null,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                m.shortLabel.toUpperCase(),
                style: headerStyle?.copyWith(color: m == now ? p.neon : null),
              ),
              Text(
                status,
                style: context.text.labelSmall?.copyWith(
                  color: c != null ? p.neon2 : fin.subtle,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final grid = GridPanel(
      child: LayoutBuilder(
        builder: (context, box) {
          final labelW = box.maxWidth < 640 ? 150.0 : 180.0;
          final cellW = ((box.maxWidth - labelW) / months.length)
              .clamp(_minCellW, double.infinity)
              .toDouble();
          final table = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: labelW,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: p.line)),
                ),
                child: Column(
                  children: [
                    Container(
                      height: _headerH,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 13),
                      child: Text('INDICADOR', style: headerStyle),
                    ),
                    for (final (i, r) in rows.indexed)
                      rowBg(
                        i,
                        r.$4,
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: GridLayout.stripeW,
                              color: r.$2.withValues(alpha: 0.85),
                            ),
                            Expanded(
                              child: GridCell(
                                child: Text(
                                  r.$1,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodyMedium?.copyWith(
                                    fontWeight: r.$4
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [for (final m in months) header(m, cellW)]),
                      for (final (i, r) in rows.indexed)
                        rowBg(
                          i,
                          r.$4,
                          Row(
                            children: [
                              for (final m in months)
                                SizedBox(
                                  width: cellW,
                                  child: r.$4
                                      ? r.$3(m)
                                      : GridCell(right: true, child: r.$3(m)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
          return Stack(
            children: [
              // Cabeçalho escuro com sublinhado luminoso (como na Projeção).
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: _headerH,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: p.header),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              p.neon,
                              p.neon2,
                              p.neon.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              table,
            ],
          );
        },
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ajustar mês a mês'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                key: const ValueKey('adjust-grid-save'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check, size: 18),
                label: Text(changed == 0 ? 'Salvar' : 'Salvar ($changed)'),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'Na linha "Ajuste", digite quanto somar ao resultado de cada '
              'mês (use "-" para tirar, ex.: -500). O mês ajustado fica '
              'fechado com esse resultado. Apague o valor (ou deixe 0) para '
              'voltar ao cálculo automático. Toque no nome do mês para '
              'ajustar receitas e despesas separadamente.',
              style: context.text.bodySmall?.copyWith(color: fin.subtle),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Voltar 1 mês',
                  onPressed: () => setState(
                    () => range = MonthRange(
                      range.from.add(-1),
                      range.to.add(-1),
                    ),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${range.from.shortLabel} – ${range.to.shortLabel}',
                    textAlign: TextAlign.center,
                    style: context.text.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Avançar 1 mês',
                  onPressed: () => setState(
                    () =>
                        range = MonthRange(range.from.add(1), range.to.add(1)),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            grid,
          ],
        ),
      ),
    );
  }

  Widget _adjustCell(FinanceController fc, YearMonth m) {
    final ctrl = _ctrl(fc, m);
    final focus = _focus.putIfAbsent(m, FocusNode.new);
    final invalid = _typed(m) == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: TextField(
        key: ValueKey('adjust-cell-${m.key}'),
        controller: ctrl,
        focusNode: focus,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+\-*/()x ]')),
        ],
        textInputAction: TextInputAction.next,
        style: context.text.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: '0,00',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          border: const OutlineInputBorder(),
          errorText: invalid ? '' : null,
          errorStyle: const TextStyle(height: 0, fontSize: 0),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}
