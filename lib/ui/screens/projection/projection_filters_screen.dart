import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';

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

  Widget _section(String title, List<Widget> chips) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.titleSmall),
        const SizedBox(height: 8),
        chips.isEmpty
            ? Text(
                'Nenhum cadastro',
                style: TextStyle(color: context.fin.subtle),
              )
            : Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    ),
  );

  FilterChip _chip<T>(String label, Set<T> set, T v) => FilterChip(
    label: Text(label),
    selected: set.contains(v),
    onSelected: (s) => setState(() => s ? set.add(v) : set.remove(v)),
  );

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
          _section('Tipo de transação', [
            _chip('Receitas', types, TransactionType.income),
            _chip('Despesas', types, TransactionType.expense),
          ]),
          _section('Status', [
            for (final s in TransactionStatus.values)
              _chip(s.label, statuses, s),
          ]),
          _section('Origem', [
            _chip('Recorrentes', sources, EventSource.recurring),
            _chip('Parcelamentos', sources, EventSource.installment),
            _chip('Compras no cartão', sources, EventSource.card),
            _chip('Outras', sources, EventSource.other),
          ]),
          _section('Contas', [
            for (final a in d.accounts) _chip(a.name, accounts, a.id),
          ]),
          _section('Cartões de crédito', [
            for (final c in d.cards) _chip(c.name, cards, c.id),
          ]),
          _section('Categorias (inclui subcategorias)', [
            for (final c in d.categories.where((c) => c.parentId == null))
              _chip(c.name, categories, c.id),
          ]),
          _section('Projetos', [
            for (final p in d.projects) _chip(p.name, projects, p.id),
          ]),
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
