import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../../state/shared_controller.dart';
import '../../widgets/remembered_filters.dart';
import '../shared/shared_screen.dart';
import '../simulations/other_entries.dart';
import 'transactions_screen.dart';

/// O que a tela de lançamentos mostra (botões no topo).
enum EntriesView {
  all('Todos', Icons.list_alt),
  own('Transações', Icons.receipt_long_outlined),
  other('Outras despesas', Icons.call_split),
  otherIncome('Outras receitas', Icons.call_merge),
  shared('Compartilhadas', Icons.groups_outlined);

  final String label;
  final IconData icon;
  const EntriesView(this.label, this.icon);
}

/// Tela única de lançamentos: Transações, Outras despesas e Compartilhadas
/// num lugar só, com botões para alternar. "Todos" é a grade completa do
/// orçamento (inclui as linhas geradas por outras despesas e
/// compartilhadas); "Transações" mostra só as lançadas pelo usuário.
///
/// Os botões são dinâmicos: "Outras receitas" só aparece quando existe
/// alguma, e "Compartilhadas" só com login na nuvem (com o número de
/// convites pendentes).
class EntriesScreen extends StatefulWidget {
  const EntriesScreen({super.key});

  /// Pedido de abrir num botão específico (menus antigos, atalhos).
  static final requested = ValueNotifier<EntriesView?>(null);

  @override
  State<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends State<EntriesScreen> with RememberedFilters {
  EntriesView view = EntriesView.all;

  /// Painéis já abertos (mantêm o estado ao alternar).
  final _opened = <int>{};

  @override
  String get filterKey => 'entries';

  @override
  Map<String, Object?> filtersToJson() => {'view': view.name};

  @override
  void restoreFilters(Map<String, Object?> saved, FinanceController fc) =>
      view = FilterJson.enumOrNull(EntriesView.values, saved['view']) ?? view;

  @override
  void initState() {
    super.initState();
    _takeRequest();
    EntriesScreen.requested.addListener(_takeRequest);
  }

  @override
  void dispose() {
    EntriesScreen.requested.removeListener(_takeRequest);
    super.dispose();
  }

  void _takeRequest() {
    final r = EntriesScreen.requested.value;
    if (r == null) return;
    EntriesScreen.requested.value = null;
    if (!mounted) return;
    if (r != view) setFilters(() => view = r);
  }

  SharedController? _shared(BuildContext context) {
    try {
      return context.watch<SharedController>();
    } on ProviderNotFoundException {
      return null; // testes sem despesas compartilhadas
    }
  }

  /// Painel de cada botão: "Todos" e "Transações" usam a mesma grade.
  static int _panel(EntriesView v) => switch (v) {
    EntriesView.all || EntriesView.own => 0,
    EntriesView.other => 1,
    EntriesView.otherIncome => 2,
    EntriesView.shared => 3,
  };

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final sc = _shared(context);
    final hasOtherIncome = fc.otherEntries.any(
      (e) => e.type == TransactionType.income && !e.isDeleted,
    );
    final visible = [
      EntriesView.all,
      EntriesView.own,
      EntriesView.other,
      if (hasOtherIncome || view == EntriesView.otherIncome)
        EntriesView.otherIncome,
      if (sc != null && sc.available) EntriesView.shared,
    ];
    final current = visible.contains(view) ? view : EntriesView.all;
    final panel = _panel(current);
    _opened.add(panel);
    final invites = sc != null && sc.available ? sc.state.invites.length : 0;

    Widget lazy(int i, Widget Function() build) =>
        _opened.contains(i) ? build() : const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimentações'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              key: const ValueKey('entries-views'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              children: [
                for (final v in visible)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: ValueKey('entries-${v.name}'),
                      avatar: Icon(v.icon, size: 18),
                      label: v == EntriesView.shared && invites > 0
                          ? Badge(
                              label: Text('$invites'),
                              offset: const Offset(14, -6),
                              child: Text(v.label),
                            )
                          : Text(v.label),
                      selected: current == v,
                      showCheckmark: false,
                      onSelected: (_) => setFilters(() => view = v),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: panel,
        children: [
          lazy(
            0,
            () => TransactionsScreen(
              embedded: true,
              ownOnly: current == EntriesView.own,
            ),
          ),
          lazy(1, () => const OtherEntriesView(type: TransactionType.expense)),
          lazy(2, () => const OtherEntriesView(type: TransactionType.income)),
          lazy(3, () => const SharedScreen(embedded: true)),
        ],
      ),
    );
  }
}
