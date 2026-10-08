import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../core/dates.dart';
import '../../../data/cloud/pluggy_connect.dart';
import '../../../data/open_finance.dart';
import '../../../domain/models/entities.dart';
import '../../../state/auth_controller.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Conexões Open Finance: consentimento, sincronização, importação,
/// detecção de duplicidade e conciliação.
class OpenFinanceScreen extends StatelessWidget {
  const OpenFinanceScreen({super.key});

  Future<void> _connect(BuildContext context, FinanceController fc) async {
    if (fc.openFinance.connectsByItemId) return _connectByItem(context, fc);
    final insts = await fc.openFinance.institutions();
    if (!context.mounted) return;
    final inst = await showModalBottomSheet<OFInstitution>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Você será redirecionado ao ambiente da instituição para autorizar o compartilhamento. '
                'O app nunca pede sua senha bancária.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ),
            for (final i in insts)
              ListTile(
                leading: const Icon(Icons.account_balance),
                title: Text(i.name),
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (inst != null && context.mounted) {
      await runAction(
        context,
        () => fc.connectInstitution(inst),
        success: 'Consentimento autorizado: ${inst.name}',
      );
    }
  }

  /// Provedor real (Pluggy): assistente em passos. Na web, a janela da
  /// Pluggy abre dentro do app e devolve a conexão sem copiar IDs.
  Future<void> _connectByItem(
    BuildContext context,
    FinanceController fc,
  ) async {
    var configured = false;
    final ok = await runAction(
      context,
      () async => configured = await fc.openFinance.isConfigured(),
    );
    if (!ok || !context.mounted) return;
    if (!configured) return _notConfigured(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => const _ConnectGuide(),
    );
    if (choice == null || !context.mounted) return;
    String? itemId;
    if (choice == 'window' && pluggyConnectSupported) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final ok = await runAction(context, () async {
        final token = await fc.openFinance.connectToken();
        itemId = await openPluggyConnect(token, dark: dark);
      });
      if (!ok) return;
    } else {
      if (!context.mounted) return;
      itemId = await _askItemId(context);
    }
    final id = itemId;
    if (id == null || id.trim().isEmpty || !context.mounted) return;
    var added = 0;
    final linked = await runAction(
      context,
      () async => added = await fc.connectItem(id),
    );
    if (linked && context.mounted) await _connected(context, added);
  }

  Future<void> _notConfigured(BuildContext context) {
    final admin = context.read<AuthController>().isAdmin;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Falta um ajuste no servidor'),
        content: Text(
          admin
              ? 'O servidor do app ainda não tem as chaves da Pluggy, a empresa autorizada '
                    'pelo Banco Central que busca os dados dos bancos.\n\n'
                    'Isso é feito uma vez só: no painel do Render, em financas-api › Environment, '
                    'preencha PLUGGY_CLIENT_ID e PLUGGY_CLIENT_SECRET (copiados de '
                    'dashboard.pluggy.ai › sua aplicação) e salve. Depois de 1 minuto, tente de novo.'
              : 'O Open Finance ainda não foi ativado neste app. Peça ao administrador '
                    'para configurar a Pluggy e tente de novo.',
        ),
        actions: [
          if (admin)
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://dashboard.render.com/web/srv-db1m3nfavr4c73cjgc80/env',
                ),
              ),
              child: const Text('Abrir Render'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  /// Plano B: colar o ID da conexão (Item ID) criado no dashboard da Pluggy.
  Future<String?> _askItemId(BuildContext context) async {
    final ctrl = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Colar ID da conexão'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No dashboard.pluggy.ai, abra sua aplicação, vá na conexão do Meu Pluggy '
              'e copie o "Item ID". Ele tem este formato: '
              'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'ID da conexão (Item ID)',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Conectar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return id;
  }

  Future<void> _connected(BuildContext context, int added) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.check_circle_outline),
      title: Text(
        added == 0
            ? 'Essas contas já estavam conectadas'
            : added == 1
            ? '1 conta conectada'
            : '$added contas conectadas',
      ),
      content: const Text(
        'Falta só um passo: em cada conta ou cartão da lista, escolha em '
        '"Vincular a conta/cartão" qual conta do app ela representa e toque em '
        'Sincronizar.\n\nOs lançamentos do banco chegam em "Transações para revisar". '
        'Os que você já tinha lançado à mão são reconhecidos e não duplicam.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );

  Future<void> _syncAll(BuildContext context, FinanceController fc) async {
    var added = 0, matched = 0, failed = 0;
    for (final c in fc.connections.where(
      (c) => c.consentStatus == ConsentStatus.active,
    )) {
      try {
        final r = await fc.syncConnection(c);
        added += r.added;
        matched += r.matched;
      } catch (_) {
        failed++;
      }
    }
    if (context.mounted) {
      showMessage(
        context,
        '$added novas transações · $matched conciliadas automaticamente'
        '${failed > 0 ? ' · $failed com erro' : ''}',
        error: failed > 0 && added == 0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final pending =
        fc.externalTransactions
            .where((e) => e.status == ExternalTxStatus.pending)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Finance'),
        actions: [
          if (fc.connections.length > 1)
            IconButton(
              tooltip: 'Sincronizar tudo',
              icon: const Icon(Icons.sync),
              onPressed: () => _syncAll(context, fc),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-of',
        onPressed: () => _connect(context, fc),
        icon: const Icon(Icons.add_link),
        label: const Text('Conectar banco'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (fc.openFinance.isSandbox)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.fin.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Provedor em modo sandbox: conexões e transações são simuladas. '
                'Entre com a conta na nuvem para usar o Open Finance real (Pluggy).',
                style: context.text.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          if (fc.connections.isEmpty && fc.openFinance.connectsByItemId)
            _HowItWorks(onStart: () => _connect(context, fc))
          else if (fc.connections.isEmpty)
            const EmptyState(
              icon: Icons.hub_outlined,
              title: 'Nenhuma conexão',
              message: 'Conecte uma instituição para importar transações e conciliar com seus lançamentos.',
            ),
          for (final c in fc.connections) _ConnectionCard(connection: c),
          if (pending.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transações para revisar (${pending.length})',
                    style: context.text.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toque em ⋮ em cada uma: "Importar como novo" cria o lançamento; '
                    '"Conciliar" liga a um lançamento que você já fez; "Ignorar" descarta '
                    '(use para pagamento de fatura e transferências entre suas contas).',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            Card(
              child: Column(
                children: [for (final e in pending) _ExternalTile(ext: e)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final OpenFinanceConnection connection;
  const _ConnectionCard({required this.connection});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final c = connection;
    final active = c.consentStatus == ConsentStatus.active;
    final items = fc.externalTransactions.where((e) => e.connectionId == c.id);
    final color = active ? context.fin.positive : context.fin.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        title: c.institutionName,
        trailing: Pill(c.consentStatus.label, color: color),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoRow.text(
              'Consentimento até',
              c.consentExpiresAt == null
                  ? '—'
                  : Dates.format(c.consentExpiresAt!),
            ),
            InfoRow.text(
              'Última sincronização',
              c.lastSyncAt == null
                  ? 'Nunca'
                  : '${Dates.format(c.lastSyncAt!)} ${c.lastSyncAt!.hour.toString().padLeft(2, '0')}:${c.lastSyncAt!.minute.toString().padLeft(2, '0')}',
            ),
            InfoRow.text('Transações recebidas', '${items.length}'),
            if (c.lastError != null)
              Text(
                'Erro: ${c.lastError}',
                style: TextStyle(color: context.fin.negative),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: c.linkedAccountId != null
                  ? 'a:${c.linkedAccountId}'
                  : c.linkedCardId != null
                  ? 'c:${c.linkedCardId}'
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Vincular a conta/cartão',
                helperText: c.linkedAccountId == null && c.linkedCardId == null
                    ? 'Escolha qual conta ou cartão do app é este'
                    : null,
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Não vinculado'),
                ),
                for (final a in fc.activeAccounts)
                  DropdownMenuItem(value: 'a:${a.id}', child: Text(a.name)),
                for (final k in fc.activeCards)
                  DropdownMenuItem(value: 'c:${k.id}', child: Text(k.name)),
              ],
              onChanged: (v) => fc.linkConnection(
                c,
                accountId: v != null && v.startsWith('a:')
                    ? v.substring(2)
                    : null,
                cardId: v != null && v.startsWith('c:') ? v.substring(2) : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar'),
                    onPressed: !active
                        ? null
                        : () async {
                            try {
                              final r = await fc.syncConnection(c);
                              if (context.mounted) {
                                showMessage(
                                  context,
                                  '${r.added} novas transações · ${r.matched} conciliadas automaticamente',
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                showMessage(context, '$e', error: true);
                              }
                            }
                          },
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'revoke') {
                      final ok = await confirmDialog(
                        context,
                        title: 'Revogar consentimento?',
                        message: 'A instituição deixará de compartilhar dados. Transações já importadas são mantidas.',
                        confirm: 'Revogar',
                        destructive: true,
                      );
                      if (ok && context.mounted) {
                        await runAction(
                          context,
                          () => fc.revokeConnection(c),
                          success: 'Consentimento revogado',
                        );
                      }
                    }
                    if (v == 'delete' && context.mounted) {
                      final ok = await confirmDialog(
                        context,
                        title: 'Remover conexão?',
                        message: 'Remove a conexão e as transações ainda não importadas. Lançamentos já importados permanecem.',
                        confirm: 'Remover',
                        destructive: true,
                      );
                      if (ok && context.mounted) {
                        await runAction(
                          context,
                          () => fc.deleteConnection(c),
                          success: 'Conexão removida',
                        );
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    if (active)
                      const PopupMenuItem(
                        value: 'revoke',
                        child: Text('Revogar consentimento'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Remover'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExternalTile extends StatelessWidget {
  final ExternalTransaction ext;
  const _ExternalTile({required this.ext});

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final conn = fc.connections
        .where((c) => c.id == ext.connectionId)
        .firstOrNull;
    return ListTile(
      title: Text(ext.description),
      subtitle: Text(
        '${Dates.format(ext.date)} · ${conn?.institutionName ?? ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoneyText(
            ext.signedAmount,
            colorize: true,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (conn == null) return;
              if (v == 'import') {
                await runAction(
                  context,
                  () => fc.importExternal(ext, conn),
                  success: 'Transação importada',
                );
              } else if (v == 'ignore') {
                await runAction(
                  context,
                  () => fc.ignoreExternal(ext),
                  success: 'Transação ignorada',
                );
              } else if (v == 'match') {
                final candidates =
                    fc.data.transactions
                        .where(
                          (t) =>
                              !t.isTransfer &&
                              t.externalId == null &&
                              (t.type == TransactionType.income) ==
                                  ext.signedAmount.isPositive &&
                              t.date.difference(ext.date).inDays.abs() <= 15,
                        )
                        .toList()
                      ..sort(
                        (a, b) => (a.amount - ext.signedAmount.abs()).cents
                            .abs()
                            .compareTo(
                              (b.amount - ext.signedAmount.abs()).cents.abs(),
                            ),
                      );
                final target = await showModalBottomSheet<FinTransaction>(
                  context: context,
                  showDragHandle: true,
                  builder: (ctx) => candidates.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Nenhum lançamento compatível nos últimos 15 dias.',
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final t in candidates.take(20))
                              ListTile(
                                title: Text(t.description),
                                subtitle: Text(
                                  '${Dates.format(t.date)} · ${fc.engine.locationLabel(t)}',
                                ),
                                trailing: Text(t.amount.format()),
                                onTap: () => Navigator.pop(ctx, t),
                              ),
                          ],
                        ),
                );
                if (target != null && context.mounted) {
                  await runAction(
                    context,
                    () => fc.reconcileExternal(ext, target),
                    success: 'Conciliado com “${target.description}”',
                  );
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Importar como novo')),
              PopupMenuItem(
                value: 'match',
                child: Text('Conciliar com lançamento'),
              ),
              PopupMenuItem(value: 'ignore', child: Text('Ignorar')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Explicação mostrada antes da primeira conexão.
class _HowItWorks extends StatelessWidget {
  final VoidCallback onStart;
  const _HowItWorks({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Traga os lançamentos do banco automaticamente',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pelo Open Finance, do Banco Central, o app lê o extrato das suas contas e '
            'cartões. Ele só lê: não faz pagamentos e nunca vê sua senha do banco. '
            'Você pode cancelar quando quiser.',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: 12),
          const _Step(
            n: 1,
            title: 'Autorize seus bancos no Meu Pluggy',
            text: 'Serviço gratuito e autorizado pelo Banco Central. Você escolhe o banco e aprova no app dele.',
          ),
          const _Step(
            n: 2,
            title: 'Traga para o Finanças',
            text: 'Na janela que abre aqui, escolha "MeuPluggy" e marque as contas e cartões.',
          ),
          const _Step(
            n: 3,
            title: 'Vincule e sincronize',
            text: 'Diga qual conta do app é cada conta do banco e toque em Sincronizar.',
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.add_link),
            label: const Text('Começar'),
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String title;
  final String text;
  const _Step({required this.n, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(text, style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Assistente de conexão: devolve 'window' (janela da Pluggy) ou 'id'
/// (colar o ID manualmente).
class _ConnectGuide extends StatelessWidget {
  const _ConnectGuide();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Conectar seus bancos', style: context.text.titleLarge),
            const SizedBox(height: 16),
            const _Step(
              n: 1,
              title: 'Seus bancos já estão no Meu Pluggy?',
              text:
                  'Se ainda não, abra o Meu Pluggy, crie a conta (pode ser com o Google), '
                  'toque em conectar conta, escolha o banco e aprove no app do banco. '
                  'Volte aqui quando terminar. Se já fez isso, pule para o passo 2.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir Meu Pluggy'),
                onPressed: () => launchUrl(Uri.parse('https://meu.pluggy.ai')),
              ),
            ),
            const SizedBox(height: 16),
            _Step(
              n: 2,
              title: 'Traga as contas para o Finanças',
              text: pluggyConnectSupported
                  ? 'Vai abrir uma janela da Pluggy. Nela, escolha "MeuPluggy", entre '
                        'com a mesma conta do passo 1 e marque as contas e cartões que quer ver aqui.'
                  : 'Cole o ID da conexão (Item ID) do dashboard da Pluggy.',
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                pluggyConnectSupported ? 'window' : 'id',
              ),
              child: const Text('Continuar'),
            ),
            if (pluggyConnectSupported)
              TextButton(
                onPressed: () => Navigator.pop(context, 'id'),
                child: const Text('Tenho um ID de conexão'),
              ),
          ],
        ),
      ),
    );
  }
}
