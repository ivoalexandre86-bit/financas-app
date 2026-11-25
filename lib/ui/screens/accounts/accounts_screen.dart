import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/dependents_editor.dart';
import '../../widgets/active_filter.dart';
import '../../widgets/filters_panel.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/remembered_filters.dart';
import '../../widgets/sort_grid.dart';
import '../../widgets/transaction_tile.dart';
import '../../widgets/tx_grid.dart';
import '../../widgets/view_mode.dart';
import '../transactions/transaction_details_screen.dart';
import '../transactions/transaction_form_screen.dart';

IconData accountIcon(AccountType t) => switch (t) {
  AccountType.checking => Icons.account_balance_outlined,
  AccountType.savings => Icons.savings_outlined,
  AccountType.digital => Icons.phone_iphone,
  AccountType.cash => Icons.payments_outlined,
  AccountType.investment => Icons.trending_up,
};

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen>
    with RememberedFilters {
  ViewMode view = ViewMode.cards;
  ActiveFilter situation = ActiveFilter.active;

  @override
  String get filterKey => 'accounts';

  @override
  Map<String, Object?> filtersToJson() => {
    'view': view.name,
    'situation': situation.name,
  };

  @override
  void restoreFilters(Map<String, Object?> saved, FinanceController fc) {
    view = FilterJson.enumOrNull(ViewMode.values, saved['view']) ?? view;
    situation =
        FilterJson.enumOrNull(ActiveFilter.values, saved['situation']) ??
        situation;
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final all = fc.data.accounts;
    final accounts = [...all.where((x) => situation.matches(x.active))]
      ..sort(
        (a, b) => a.active == b.active
            ? a.name.compareTo(b.name)
            : (a.active ? -1 : 1),
      );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas'),
        actions: [
          ViewModeToggle(
            keyPrefix: 'accounts',
            mode: view,
            onChanged: (v) => setFilters(() => view = v),
          ),
          FilterButton(
            keyPrefix: 'accounts',
            active: situation.count,
            panel: FilterPanel(
              keyPrefix: 'accounts',
              active: situation.count,
              onClear: () => setFilters(() => situation = ActiveFilter.active),
              fields: (_) => [
                ActiveFilterField(
                  keyName: 'accounts-situation',
                  value: situation,
                  onChanged: (v) => setFilters(() => situation = v),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-acc',
        onPressed: () => push(context, const AccountFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nova conta'),
      ),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.account_balance_outlined,
              title: 'Nenhuma conta cadastrada',
              message: 'Cadastre suas contas para acompanhar saldos.',
              actionLabel: 'Nova conta',
              onAction: () => push(context, const AccountFormScreen()),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                SectionCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Saldo total (contas ativas)',
                          style: context.text.bodyMedium,
                        ),
                      ),
                      MoneyText(
                        fc.engine.currentBalance,
                        colorize: true,
                        style: context.text.titleMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (accounts.isEmpty)
                  EmptyState(
                    icon: Icons.filter_alt_outlined,
                    title: situation == ActiveFilter.inactive
                        ? 'Nenhuma conta inativa'
                        : 'Nenhuma conta ativa',
                    actionLabel: 'Mostrar todas',
                    onAction: () =>
                        setFilters(() => situation = ActiveFilter.all),
                  )
                else if (view == ViewMode.grid)
                  AccountsGrid(accounts: accounts)
                else
                  Card(
                    child: Column(
                      children: [
                        for (final a in accounts)
                          ListTile(
                            onTap: () => push(
                              context,
                              AccountDetailsScreen(accountId: a.id),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: Color(a.color)
                                  .withValues(alpha: 0.12),
                              child: Icon(
                                accountIcon(a.type),
                                color: Color(a.color),
                              ),
                            ),
                            title: Text(a.name),
                            subtitle: Text(
                              [
                                a.type.label,
                                if (a.institution.isNotEmpty ||
                                    a.institutionCode.isNotEmpty)
                                  institutionLabel(
                                    a.institutionCode,
                                    a.institution,
                                  ),
                                if (!a.active) 'Inativa',
                              ].join(' · '),
                            ),
                            trailing: MoneyText(
                              fc.engine.accountBalance(a.id),
                              colorize: true,
                              style: context.text.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Contas no padrão de grade de Faturas: ordenável, com saldo total.
class AccountsGrid extends StatelessWidget {
  final List<Account> accounts;
  const AccountsGrid({super.key, required this.accounts});

  @override
  Widget build(BuildContext context) {
    final e = context.watch<FinanceController>().engine;
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final strong = context.text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
    );
    int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    String inst(Account a) => a.institution.isEmpty && a.institutionCode.isEmpty
        ? ''
        : institutionLabel(a.institutionCode, a.institution);
    Money balance(Account a) => e.accountBalance(a.id);
    Widget money(Money v, {TextStyle? style}) => Text(
      v.format(),
      style: style?.copyWith(color: v.cents < 0 ? context.fin.negative : null),
    );
    Widget status(Account a) => NeonStatus(
      label: a.active ? 'Ativa' : 'Inativa',
      color: a.active ? context.fin.positive : context.fin.subtle,
      done: !a.active,
    );
    Money activeTotal(List<Account> l) =>
        l.where((a) => a.active).map(balance).sum();

    return SortGrid<Account>(
      keyPrefix: 'acc',
      rows: accounts,
      rowId: (a) => a.id,
      accent: (context, a) => Color(a.color),
      dimmed: (a) => !a.active,
      onOpen: (a) => push(context, AccountDetailsScreen(accountId: a.id)),
      initialSort: 'name',
      tieBreak: (a, b) => text(a.name, b.name),
      columns: [
        SortCol(
          id: 'name',
          label: 'Conta',
          width: 200,
          minWidth: 130,
          flexible: true,
          fill: true,
          compare: (a, b) =>
              a.active == b.active ? text(a.name, b.name) : (a.active ? -1 : 1),
          cell: (context, a) => GridCell(
            child: Row(
              children: [
                Icon(accountIcon(a.type), size: 18, color: Color(a.color)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SortCol(
          id: 'type',
          label: 'Tipo',
          width: 130,
          minWidth: 100,
          flexible: true,
          compare: (a, b) => text(a.type.label, b.type.label),
          cell: (context, a) => GridCell(
            child: Text(
              a.type.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          ),
        ),
        SortCol(
          id: 'institution',
          label: 'Instituição',
          width: 180,
          minWidth: 110,
          flexible: true,
          compare: (a, b) => text(inst(a), inst(b)),
          cell: (context, a) => GridCell(
            child: Text(
              inst(a).isEmpty ? '—' : inst(a),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtle,
            ),
          ),
        ),
        SortCol(
          id: 'initial',
          label: 'Saldo inicial',
          width: 124,
          right: true,
          compare: (a, b) => a.initialBalance.compareTo(b.initialBalance),
          cell: (context, a) => GridCell(
            right: true,
            child: money(a.initialBalance, style: context.text.bodySmall),
          ),
        ),
        SortCol(
          id: 'balance',
          label: 'Saldo atual',
          width: 132,
          right: true,
          highlight: true,
          compare: (a, b) => balance(a).compareTo(balance(b)),
          cell: (context, a) =>
              GridCell(right: true, child: money(balance(a), style: strong)),
          footer: (context, l) => money(activeTotal(l), style: strong),
        ),
        SortCol(
          id: 'status',
          label: 'Situação',
          width: 112,
          compare: (a, b) => (a.active ? 0 : 1).compareTo(b.active ? 0 : 1),
          cell: (context, a) => GridCell(child: status(a)),
        ),
      ],
      compactRow: (context, a) => Row(
        children: [
          Icon(accountIcon(a.type), size: 20, color: Color(a.color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    a.type.label,
                    if (inst(a).isNotEmpty) inst(a),
                    if (!a.active) 'Inativa',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          money(balance(a), style: strong),
        ],
      ),
      footerLabel: (context, l) => Text(
        'Saldo das ativas · ${l.length} ${l.length == 1 ? 'conta' : 'contas'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: gridFooterLabelStyle(context),
      ),
      compactFooter: (context, l) => money(activeTotal(l), style: strong),
    );
  }
}

class AccountDetailsScreen extends StatelessWidget {
  final String accountId;
  const AccountDetailsScreen({super.key, required this.accountId});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final a = fc.data.accountById[accountId];
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.delete, title: 'Conta removida'),
      );
    }
    final e = fc.engine;
    final history =
        fc.data.transactions
            .where((t) => t.accountId == a.id || t.destinationAccountId == a.id)
            .toList()
          ..sort((x, y) => y.date.compareTo(x.date));
    final payments = fc.data.invoicePayments.where((p) => p.accountId == a.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(a.name),
        actions: [
          IconButton(
            tooltip: 'Ajustar saldo',
            icon: const Icon(Icons.tune),
            onPressed: () => showAdjustBalanceDialog(context, a),
          ),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => push(context, AccountFormScreen(account: a)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-acc-tx',
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Transferir'),
        onPressed: () => push(
          context,
          const TransactionFormScreen(initialType: TransactionType.transfer),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SectionCard(
              child: Column(
                children: [
                  InfoRow(
                    'Saldo atual',
                    MoneyText(
                      e.accountBalance(a.id),
                      colorize: true,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  InfoRow('Saldo inicial', MoneyText(a.initialBalance)),
                  InfoRow.text('Tipo', a.type.label),
                  if (a.institution.isNotEmpty || a.institutionCode.isNotEmpty)
                    InfoRow.text(
                      'Instituição',
                      institutionLabel(a.institutionCode, a.institution),
                    ),
                  InfoRow.text('Situação', a.active ? 'Ativa' : 'Inativa'),
                  if (payments.isNotEmpty)
                    InfoRow(
                      'Pagamentos de fatura',
                      MoneyText(payments.map((p) => p.amount).sum()),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('acc-adjust-balance'),
                      icon: const Icon(Icons.tune),
                      label: const Text('Ajustar saldo'),
                      onPressed: () => showAdjustBalanceDialog(context, a),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SectionCard(
              child: DependentsEditor(
                key: const ValueKey('acc-dependents'),
                value: a.dependents,
                usage: fc.dependentUsage,
                onChanged: (v) => runAction(
                  context,
                  () => fc.saveAccount(a.copyWith(dependents: v)),
                  success: 'Dependentes salvos',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Histórico', style: context.text.titleMedium),
          ),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sem movimentações.'),
            )
          else
            for (final t in history)
              TransactionTile(
                tx: t,
                engine: e,
                onTap: () => push(context, TransactionDetailsScreen(tx: t)),
              ),
        ],
      ),
    );
  }
}

class AccountFormScreen extends StatefulWidget {
  final Account? account;
  const AccountFormScreen({super.key, this.account});
  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.account?.name ?? '');
  late Institution inst = (
    code: widget.account?.institutionCode ?? '',
    name: widget.account?.institution ?? '',
  );
  late final initial = TextEditingController(
    text: widget.account?.initialBalance.formatPlain() ?? '0,00',
  );
  late AccountType type = widget.account?.type ?? AccountType.checking;
  late bool active = widget.account?.active ?? true;
  late int color = widget.account?.color ?? palette.first;
  late List<Dependent> dependents = widget.account?.dependents ?? const [];

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final a = widget.account;
    return Scaffold(
      appBar: AppBar(
        title: Text(a == null ? 'Nova conta' : 'Editar conta'),
        actions: [
          if (a != null)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (fc.accountInUse(a.id)) {
                  showMessage(
                    context,
                    'A conta possui lançamentos. Desative-a em vez de excluir.',
                    error: true,
                  );
                  return;
                }
                final ok = await confirmDialog(
                  context,
                  title: 'Excluir conta?',
                  message: 'Esta ação não pode ser desfeita.',
                  confirm: 'Excluir',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                final done = await runAction(
                  context,
                  () => fc.deleteAccount(a),
                  success: 'Conta excluída',
                );
                if (done && context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome da conta'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 12),
            BankField(
              label: 'Instituição',
              value: inst,
              onChanged: (v) => setState(() => inst = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AccountType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                for (final t in AccountType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) => setState(() => type = t!),
            ),
            const SizedBox(height: 12),
            MoneyField(
              controller: initial,
              label: 'Saldo inicial',
              allowZero: true,
              allowNegative: true,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in palette)
                  GestureDetector(
                    onTap: () => setState(() => color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: color == c
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            DependentsEditor(
              value: dependents,
              askLastFour: false,
              usage: fc.dependentUsage,
              onChanged: (v) => setState(() => dependents = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Conta ativa'),
              subtitle: const Text('Contas inativas não somam no saldo atual'),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                final acc = (a ?? Account(id: newId('acc_'), name: name.text))
                    .copyWith(
                      name: name.text.trim(),
                      institution: inst.name,
                      institutionCode: inst.code,
                      type: type,
                      initialBalance: Money.tryEval(initial.text)!,
                      active: active,
                      color: color,
                      dependents: dependents,
                    );
                final ok = await runAction(
                  context,
                  () => fc.saveAccount(acc),
                  success: 'Conta salva',
                );
                if (ok && context.mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ajustar saldo: o usuário informa o saldo que o banco mostra hoje e o app
/// lança a diferença (receita ou despesa "Ajuste de saldo", concluída, na
/// data de hoje). Para desfazer, basta excluir esse lançamento.
Future<void> showAdjustBalanceDialog(BuildContext context, Account a) async {
  final fc = context.read<FinanceController>();
  final current = fc.engine.accountBalance(a.id);
  final ctrl = TextEditingController(text: current.formatPlain());
  final key = GlobalKey<FormState>();
  final target = await showDialog<Money>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Ajustar saldo · ${a.name}'),
      content: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo no app hoje: ${current.format()}'),
            const SizedBox(height: 8),
            const Text(
              'Informe o saldo real (o que o banco mostra). O app lança a '
              'diferença como "Ajuste de saldo"; para desfazer, exclua esse '
              'lançamento.',
            ),
            const SizedBox(height: 12),
            MoneyField(
              key: const ValueKey('acc-adjust-value'),
              controller: ctrl,
              label: 'Saldo real',
              allowZero: true,
              allowNegative: true,
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
          key: const ValueKey('acc-adjust-ok'),
          onPressed: () {
            if (key.currentState!.validate()) {
              Navigator.pop(ctx, Money.tryEval(ctrl.text));
            }
          },
          child: const Text('Ajustar'),
        ),
      ],
    ),
  );
  if (target == null || !context.mounted) return;
  final diff = target - current;
  if (diff.isZero) {
    showMessage(context, 'O saldo já está certo.');
    return;
  }
  await runAction(
    context,
    () => fc.saveTransaction(
      FinTransaction(
        id: newId('tx_'),
        type: diff.isNegative
            ? TransactionType.expense
            : TransactionType.income,
        amount: diff.abs(),
        description: 'Ajuste de saldo',
        date: fc.today,
        accountId: a.id,
        notes: 'Saldo ajustado de ${current.format()} para ${target.format()}.',
      ),
    ),
    success: 'Saldo ajustado para ${target.format()}',
  );
}
