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
import '../../widgets/form_fields.dart';
import '../../widgets/transaction_tile.dart';
import '../transactions/transaction_details_screen.dart';
import '../transactions/transaction_form_screen.dart';

IconData accountIcon(AccountType t) => switch (t) {
  AccountType.checking => Icons.account_balance_outlined,
  AccountType.savings => Icons.savings_outlined,
  AccountType.digital => Icons.phone_iphone,
  AccountType.cash => Icons.payments_outlined,
  AccountType.investment => Icons.trending_up,
};

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final accounts = [...fc.data.accounts]
      ..sort(
        (a, b) => a.active == b.active
            ? a.name.compareTo(b.name)
            : (a.active ? -1 : 1),
      );
    return Scaffold(
      appBar: AppBar(title: const Text('Contas')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-acc',
        onPressed: () => push(context, const AccountFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nova conta'),
      ),
      body: accounts.isEmpty
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
                              if (a.institution.isNotEmpty) a.institution,
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
                  if (a.institution.isNotEmpty)
                    InfoRow.text('Instituição', a.institution),
                  InfoRow.text('Situação', a.active ? 'Ativa' : 'Inativa'),
                  if (payments.isNotEmpty)
                    InfoRow(
                      'Pagamentos de fatura',
                      MoneyText(payments.map((p) => p.amount).sum()),
                    ),
                ],
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
  late final inst = TextEditingController(
    text: widget.account?.institution ?? '',
  );
  late final initial = TextEditingController(
    text: widget.account?.initialBalance.formatPlain() ?? '0,00',
  );
  late AccountType type = widget.account?.type ?? AccountType.checking;
  late bool active = widget.account?.active ?? true;
  late int color = widget.account?.color ?? palette.first;

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
            TextFormField(
              controller: inst,
              decoration: const InputDecoration(labelText: 'Instituição'),
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
                      institution: inst.text.trim(),
                      type: type,
                      initialBalance: Money.tryEval(initial.text)!,
                      active: active,
                      color: color,
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
