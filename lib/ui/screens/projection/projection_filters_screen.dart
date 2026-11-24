import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/filters_panel.dart';

class ProjectionFilterResult {
  final ProjectionFilter filter;
  final MonthRange range;
  const ProjectionFilterResult(this.filter, this.range);
}

/// Filtros avançados e combináveis da projeção.
class ProjectionFiltersScreen extends StatefulWidget {
  final ProjectionFilter initial;
  final MonthRange range;
  const ProjectionFiltersScreen({
    super.key,
    required this.initial,
    required this.range,
  });
  @override
  State<ProjectionFiltersScreen> createState() =>
      _ProjectionFiltersScreenState();
}

class _ProjectionFiltersScreenState extends State<ProjectionFiltersScreen> {
  late Set<String> accounts = {...widget.initial.accountIds};
  late Set<String> cards = {...widget.initial.cardIds};
  late Set<String> categories = {...widget.initial.categoryIds};
  late Set<String> projects = {...widget.initial.projectIds};
  late Set<TransactionType> types = {...widget.initial.types};
  late Set<TransactionStatus> statuses = {...widget.initial.statuses};
  late Set<EventSource> sources = {...widget.initial.sources};
  late YearMonth from = widget.range.from;
  late YearMonth to = widget.range.to;

  /// Um grupo de filtros: chips (modelo original) ou lista com caixas e
  /// Limpar próprio. Limpar volta para [reset] (padrão: nada marcado).
  Widget _section<T extends Object>(
    String key,
    String title,
    Set<T> set,
    Map<T, String> options, {
    Set<T> reset = const {},
  }) {
    if (filterStyleOf(context) == FilterStyle.checklist) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FilterCheckList(
          keyName: 'proj-filter-$key',
          label: title,
          width: double.infinity,
          active: !(set.length == reset.length && set.containsAll(reset)),
          onClear: () => setState(
            () => set
              ..clear()
              ..addAll(reset),
          ),
          options: [
            for (final MapEntry(key: v, :value) in options.entries)
              (
                key: v is Enum ? v.name : '$v',
                label: value,
                color: null,
                selected: set.contains(v),
                onTap: () => setState(
                  () => set.contains(v) ? set.remove(v) : set.add(v),
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleSmall),
          const SizedBox(height: 8),
          options.isEmpty
              ? Text(
                  'Nenhum cadastro',
                  style: TextStyle(color: context.fin.subtle),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final MapEntry(key: v, :value) in options.entries)
                      FilterChip(
                        label: Text(value),
                        selected: set.contains(v),
                        onSelected: (s) =>
                            setState(() => s ? set.add(v) : set.remove(v)),
                      ),
                  ],
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final d = fc.data;
    final months = [for (var i = 0; i < 97; i++) YearMonth.now().add(i - 36)];
    final validRange = from <= to && from.monthsUntil(to) < 60;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filtros da projeção'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              accounts.clear();
              cards.clear();
              categories.clear();
              projects.clear();
              types.clear();
              sources.clear();
              statuses = {...ProjectionFilter.defaultStatuses};
            }),
            child: const Text('Limpar'),
          ),
          const FilterStyleToggle(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Período', style: context.text.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<YearMonth>(
                  initialValue: months.contains(from) ? from : null,
                  menuMaxHeight: 320,
                  decoration: const InputDecoration(labelText: 'De'),
                  items: [
                    for (final m in months)
                      DropdownMenuItem(value: m, child: Text(m.shortLabel)),
                  ],
                  onChanged: (m) => setState(() => from = m!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<YearMonth>(
                  initialValue: months.contains(to) ? to : null,
                  menuMaxHeight: 320,
                  decoration: const InputDecoration(labelText: 'Até'),
                  items: [
                    for (final m in months)
                      DropdownMenuItem(value: m, child: Text(m.shortLabel)),
                  ],
                  onChanged: (m) => setState(() => to = m!),
                ),
              ),
            ],
          ),
          if (!validRange)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Período inválido (1 a 60 meses).',
                style: TextStyle(color: context.colors.error),
              ),
            ),
          const SizedBox(height: 20),
          _section('types', 'Tipo de transação', types, {
            TransactionType.income: 'Receitas',
            TransactionType.expense: 'Despesas',
          }),
          _section('statuses', 'Status', statuses, {
            for (final s in TransactionStatus.values) s: s.label,
          }, reset: ProjectionFilter.defaultStatuses),
          _section('sources', 'Origem', sources, {
            EventSource.recurring: 'Recorrentes',
            EventSource.installment: 'Parcelamentos',
            EventSource.card: 'Compras no cartão',
            EventSource.other: 'Outras',
          }),
          _section('accounts', 'Contas', accounts, {
            for (final a in d.accounts) a.id: a.name,
          }),
          _section('cards', 'Cartões de crédito', cards, {
            for (final c in d.cards) c.id: c.name,
          }),
          _section(
            'categories',
            'Categorias (inclui subcategorias)',
            categories,
            {
              for (final c in d.categories.where((c) => c.parentId == null))
                c.id: c.name,
            },
          ),
          _section('projects', 'Projetos', projects, {
            for (final p in d.projects) p.id: p.name,
          }),
          Text(
            'Filtros de categoria, projeto, tipo, origem ou status mostram o acumulado do recorte '
            'a partir de zero; filtros só de conta/cartão mantêm o saldo real como ponto de partida.',
            style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: !validRange || statuses.isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    ProjectionFilterResult(
                      ProjectionFilter(
                        accountIds: accounts,
                        cardIds: cards,
                        categoryIds: categories,
                        projectIds: projects,
                        types: types,
                        statuses: statuses,
                        sources: sources,
                      ),
                      MonthRange(from, to),
                    ),
                  ),
            child: const Text('Aplicar filtros'),
          ),
        ),
      ),
    );
  }
}
