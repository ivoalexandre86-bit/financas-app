import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../data/open_finance.dart';
import '../../../domain/models/entities.dart';
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

  /// Provedor real: o usuário autoriza os bancos no Meu Pluggy e cola aqui
  /// o ID da conexão.
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
    if (!configured) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Open Finance não configurado'),
          content: const Text(
            'O servidor ainda não tem as credenciais da Pluggy. No painel do Render, '
            'em financas-api › Environment, preencha PLUGGY_CLIENT_ID e '
            'PLUGGY_CLIENT_SECRET (do dashboard.pluggy.ai) e tente de novo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final ctrl = TextEditingController();
    final itemId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conectar banco'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Em meu.pluggy.ai, conecte seus bancos (a autorização é feita no app do banco).\n'
              '2. Em dashboard.pluggy.ai, conecte o Meu Pluggy à sua aplicação e copie o ID da conexão (Item ID).\n'
              '3. Cole o ID abaixo. Cada conta e cartão da conexão aparece aqui para vincular.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'ID da conexão (Item ID)',
                hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
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
    if (itemId == null || itemId.trim().isEmpty || !context.mounted) return;
    var added = 0;
    await runAction(context, () async => added = await fc.connectItem(itemId));
    if (context.mounted) {
      showMessage(
        context,
        added == 0
            ? 'Nenhuma conta nova nesta conexão'
            : '$added ${added == 1 ? 'conta conectada' : 'contas conectadas'}. Vincule cada uma e sincronize.',
      );
    }
  }

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
          if (fc.connections.isEmpty)
            const EmptyState(
              icon: Icons.hub_outlined,
              title: 'Nenhuma conexão',
              message: 'Conecte uma instituição para importar transações e conciliar com seus lançamentos.',
            ),
          for (final c in fc.connections) _ConnectionCard(connection: c),
          if (pending.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
              child: Text(
                'Transações para revisar (${pending.length})',
                style: context.text.titleMedium,
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
              decoration: const InputDecoration(
                labelText: 'Vincular a conta/cartão',
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
