import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart' show YearMonth;
import '../../../core/money.dart';
import '../../../domain/engine/shared_engine.dart';
import '../../../domain/models/shared.dart';
import '../../../state/shared_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';

/// Simulação da divisão do grupo: outros percentuais, pessoas entrando ou
/// saindo, valores maiores/menores e novas despesas recorrentes. Tudo em
/// memória: nada muda nas despesas, faturas ou divisões reais.
class SharedSimulationScreen extends StatefulWidget {
  final String groupId;
  const SharedSimulationScreen({super.key, required this.groupId});

  @override
  State<SharedSimulationScreen> createState() => _SharedSimulationScreenState();
}

class _SharedSimulationScreenState extends State<SharedSimulationScreen> {
  ShareGroup? group;
  late Map<String, Map<String, int>> pct;
  late List<String> people;
  final Map<String, String> extraNames = {};
  double globalPct = 0;
  final List<SimSharedItem> extra = [];
  YearMonth from = YearMonth.now();
  int months = 12;

  @override
  void initState() {
    super.initState();
    group = context.read<SharedController>().group(widget.groupId);
    if (group != null) _reset();
  }

  void _reset() {
    final s = SharedScenario.of(group!);
    pct = s.percentages;
    people = [...s.participants];
    extraNames.clear();
    extra.clear();
    globalPct = 0;
  }

  String nameOf(String id) => extraNames[id] ?? group!.nameOf(id);

  SharedScenario get scenario => SharedScenario(
    percentages: pct,
    participants: people,
    globalScale: 1 + globalPct / 100,
    extra: extra,
  );

  @override
  Widget build(BuildContext context) {
    final g = group;
    if (g == null) {
      return Scaffold(appBar: AppBar(title: const Text('Simulação')));
    }
    final sc = scenario;
    final err = sc.error(g);
    final result = err == null
        ? SharedSimulation.run(g, sc, from: from, months: months)
        : const <SimMonth>[];
    final everyone = {
      ...people,
      for (final m in result) ...m.current.keys,
    }.toList();
    int sum(Map<String, int> Function(SimMonth) f, String id) =>
        result.fold(0, (a, m) => a + (f(m)[id] ?? 0));
    return Scaffold(
      appBar: AppBar(
        title: Text('Simulação · ${g.name}'),
        actions: [
          TextButton(
            onPressed: () => setState(_reset),
            child: const Text('Restaurar'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: context.colors.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Simulação isolada: nada aqui altera despesas, faturas ou '
                'divisões reais. Base: despesas já compartilhadas no período '
                '(inclui as próximas ocorrências recorrentes).',
              ),
            ),
          ),
          SectionCard(
            title: 'Participantes do cenário',
            trailing: TextButton.icon(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Pessoa hipotética'),
              onPressed: _addPerson,
            ),
            child: Wrap(
              spacing: 6,
              children: [
                for (final id in {...g.activeIds, ...extraNames.keys})
                  FilterChip(
                    label: Text(nameOf(id)),
                    selected: people.contains(id),
                    onSelected: (v) => setState(() {
                      if (v) {
                        people.add(id);
                      } else if (people.length > 1) {
                        _removePerson(id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          SectionCard(
            title: 'Percentuais por categoria',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 12,
                    dataRowMinHeight: 44,
                    dataRowMaxHeight: 52,
                    columns: [
                      const DataColumn(label: Text('Categoria')),
                      for (final id in people)
                        DataColumn(numeric: true, label: Text(nameOf(id))),
                      const DataColumn(numeric: true, label: Text('Soma')),
                    ],
                    rows: [
                      for (final c in g.activeCategories)
                        DataRow(
                          cells: [
                            DataCell(Text(c.name)),
                            for (final id in people)
                              DataCell(
                                SizedBox(
                                  width: 84,
                                  child: TextFormField(
                                    key: ValueKey(
                                      '${c.id}/$id/${people.length}',
                                    ),
                                    initialValue: bpLabel(pct[c.id]?[id] ?? 0)
                                        .replaceAll('%', ''),
                                    textAlign: TextAlign.right,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      suffixText: '%',
                                    ),
                                    onChanged: (v) {
                                      final bp = parseBp(v);
                                      if (bp == null) return;
                                      setState(
                                        () => (pct[c.id] ??= {})[id] = bp,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            DataCell(_sumCell(c.id)),
                          ],
                        ),
                    ],
                  ),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      err,
                      style: TextStyle(color: context.fin.negative),
                    ),
                  ),
              ],
            ),
          ),
          SectionCard(
            title: 'Valores',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Variação de todas as despesas: '
                  '${globalPct >= 0 ? '+' : ''}${globalPct.round()}%',
                ),
                Slider(
                  value: globalPct,
                  min: -50,
                  max: 100,
                  divisions: 30,
                  label: '${globalPct.round()}%',
                  onChanged: (v) => setState(() => globalPct = v),
                ),
                for (final (i, x) in extra.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.autorenew),
                    title: Text(x.description),
                    subtitle: Text(
                      '${g.category(x.categoryId)?.name ?? ''} · '
                      '${Money(x.monthly).format()} por mês',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => extra.removeAt(i)),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Nova despesa recorrente'),
                    onPressed: () => _addExtra(g),
                  ),
                ),
              ],
            ),
          ),
          if (err == null) ...[
            SectionCard(
              title: 'Impacto em $months meses (desde ${from.shortLabel})',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('Pessoa')),
                    DataColumn(numeric: true, label: Text('Hoje')),
                    DataColumn(numeric: true, label: Text('Simulado')),
                    DataColumn(numeric: true, label: Text('Diferença')),
                  ],
                  rows: [
                    for (final id in everyone)
                      _deltaRow(
                        nameOf(id),
                        sum((m) => m.current, id),
                        sum((m) => m.sim, id),
                      ),
                    _deltaRow(
                      'Grupo (total)',
                      result.fold(0, (a, m) => a + m.currentTotal),
                      result.fold(0, (a, m) => a + m.simTotal),
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
            SectionCard(
              title: 'Mês a mês (simulado)',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  columns: [
                    const DataColumn(label: Text('Mês')),
                    const DataColumn(numeric: true, label: Text('Total')),
                    for (final id in everyone)
                      DataColumn(numeric: true, label: Text(nameOf(id))),
                  ],
                  rows: [
                    for (final m in result)
                      DataRow(
                        cells: [
                          DataCell(Text(m.month.shortLabel)),
                          DataCell(Text(Money(m.simTotal).format())),
                          for (final id in everyone)
                            DataCell(
                              Text(
                                Money(m.sim[id] ?? 0).format(),
                                style: TextStyle(
                                  color: (m.sim[id] ?? 0) > (m.current[id] ?? 0)
                                      ? context.fin.negative
                                      : (m.sim[id] ?? 0) < (m.current[id] ?? 0)
                                      ? context.fin.positive
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sumCell(String catId) {
    final s = people.fold(0, (a, id) => a + (pct[catId]?[id] ?? 0));
    return Text(
      bpLabel(s),
      style: TextStyle(
        color: s == fullBp ? context.fin.positive : context.fin.negative,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  DataRow _deltaRow(String name, int now, int sim, {bool bold = false}) {
    final d = sim - now;
    final st = bold ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return DataRow(
      cells: [
        DataCell(Text(name, style: st)),
        DataCell(Text(Money(now).format(), style: st)),
        DataCell(Text(Money(sim).format(), style: st)),
        DataCell(
          Text(
            '${d > 0 ? '+' : ''}${Money(d).format()}',
            style: (st ?? const TextStyle()).copyWith(
              color: d > 0
                  ? context.fin.negative
                  : d < 0
                  ? context.fin.positive
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  /// Tira a pessoa do cenário e reparte o percentual dela entre os demais.
  void _removePerson(String id) {
    people.remove(id);
    for (final p in pct.values) {
      final bp = p.remove(id) ?? 0;
      if (bp == 0) continue;
      final rest = people.where((x) => (p[x] ?? 0) > 0).toList();
      final targets = rest.isEmpty ? people : rest;
      final eq = ShareMath.equal(targets);
      for (final t in targets) {
        p[t] = (p[t] ?? 0) + bp * eq[t]! ~/ fullBp;
      }
      final diff = fullBp - p.values.fold<int>(0, (a, b) => a + b);
      p[targets.first] = (p[targets.first] ?? 0) + diff;
    }
  }

  Future<void> _addPerson() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pessoa hipotética'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() {
      final id = 'sim:${DateTime.now().microsecondsSinceEpoch}';
      extraNames[id] = name;
      people.add(id);
      // Começa com divisão igual entre todos (ajuste depois na tabela).
      final eq = ShareMath.equal(people);
      for (final c in group!.activeCategories) {
        pct[c.id] = Map.of(eq);
      }
    });
  }

  Future<void> _addExtra(ShareGroup g) async {
    final desc = TextEditingController();
    final amount = TextEditingController();
    var cat = g.activeCategories.firstOrNull?.id;
    final item = await showDialog<SimSharedItem>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nova despesa recorrente'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: desc,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                ),
                const SizedBox(height: 12),
                MoneyField(controller: amount, label: 'Valor mensal'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: cat,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: [
                    for (final c in g.activeCategories)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => set(() => cat = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final v = Money.tryEval(amount.text);
                if (v == null || !v.isPositive || cat == null) return;
                Navigator.pop(
                  ctx,
                  SimSharedItem(
                    desc.text.trim().isEmpty
                        ? 'Nova despesa'
                        : desc.text.trim(),
                    cat!,
                    v.cents,
                  ),
                );
              },
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
    if (item != null) setState(() => extra.add(item));
  }
}
