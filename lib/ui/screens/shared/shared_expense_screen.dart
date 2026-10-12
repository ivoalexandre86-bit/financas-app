import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/shared_engine.dart';
import '../../../domain/models/shared.dart';
import '../../../state/shared_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'payment_dialogs.dart';
import 'shared_widgets.dart';

/// Detalhe de uma despesa compartilhada: total, categoria, participantes,
/// percentuais, valores, situação de cada parte e pagamentos.
class SharedExpenseScreen extends StatelessWidget {
  final String expenseId;
  const SharedExpenseScreen({super.key, required this.expenseId});

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SharedController>();
    final e = sc.state.expense(expenseId);
    final g = sc.group(e?.groupId);
    if (e == null || g == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Despesa compartilhada')),
        body: sc.loading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Despesa não encontrada',
                message: 'Ela pode ter sido excluída ou você saiu do grupo.',
              ),
      );
    }
    final me = sc.me;
    final manage = g.myRole.canManage;
    final canEdit = (e.ownerId == me || manage) && !e.isDeleted;
    bool canPay(ParticipantShare s) =>
        s.userId == me || e.ownerId == me || manage;
    final rec = g.recurrence(e.recurrenceId);
    final mine = e.shareOf(me);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Despesa compartilhada'),
        actions: [
          if (canEdit)
            PopupMenuButton<String>(
              onSelected: (v) => _menu(context, g, e, v),
              itemBuilder: (_) => [
                if (manage)
                  const PopupMenuItem(
                    value: 'split',
                    child: Text('Ajustar divisão desta despesa'),
                  ),
                if (manage && e.overridden)
                  const PopupMenuItem(
                    value: 'reset',
                    child: Text('Voltar ao padrão da categoria'),
                  ),
                const PopupMenuItem(
                  value: 'category',
                  child: Text('Trocar categoria'),
                ),
                const PopupMenuItem(value: 'notes', child: Text('Observação')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Excluir do grupo'),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.description, style: context.text.titleLarge),
                const SizedBox(height: 4),
                MoneyText(Money(e.total), style: context.text.headlineSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    payStatusPill(context, e.status),
                    if (e.isDeleted)
                      Pill('Excluída', color: context.fin.negative),
                    if (e.overridden)
                      Pill('Divisão manual', color: context.colors.primary),
                    if (rec != null)
                      Pill(
                        'Recorrente',
                        color: context.colors.primary,
                        icon: Icons.autorenew,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                InfoRow.text('Grupo', g.name),
                InfoRow.text('Categoria', e.categoryName),
                InfoRow.text('Pago por', g.nameOf(e.ownerId)),
                InfoRow.text('Origem', e.sourceLabel),
                InfoRow.text('Data', Dates.format(e.date)),
                if (e.dueDate != null && e.dueDate != e.date)
                  InfoRow.text(
                    e.source == 'card' ? 'Pagamento da fatura' : 'Vencimento',
                    Dates.format(e.dueDate!),
                  ),
                if (mine != null && e.ownerId != me)
                  InfoRow.text(
                    'Minha parte',
                    '${bpLabel(mine.bp)} = ${Money(mine.owed).format()}',
                  ),
                if (e.ownerId == me)
                  InfoRow.text(
                    'A receber dos outros',
                    Money(e.outstanding).format(),
                  ),
                if (e.notes.isNotEmpty) InfoRow.text('Observação', e.notes),
              ],
            ),
          ),
          SectionCard(
            title: 'Divisão',
            child: SharesTable(
              group: g,
              expense: e,
              onPay: (s) => canPay(s)
                  ? showPaymentDialog(context, g, e, s)
                  : showMessage(
                      context,
                      'Só a própria pessoa, quem pagou a conta ou um gestor '
                      'registram este pagamento',
                    ),
            ),
          ),
          SectionCard(
            title: 'Pagamentos',
            child: e.payments.isEmpty
                ? Text(
                    'Nenhum pagamento registrado. A parte de quem pagou a '
                    'conta já conta como paga; a dos outros fica pendente '
                    'até ser registrada aqui ou num acerto.',
                    style: context.text.bodySmall,
                  )
                : Column(
                    children: [
                      for (final p in e.payments)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            p.settlementId != null
                                ? Icons.swap_horiz
                                : Icons.payments_outlined,
                          ),
                          title: Text(
                            '${g.nameOf(p.userId)} → ${g.nameOf(e.ownerId)}',
                          ),
                          subtitle: Text(
                            [
                              Dates.format(p.date),
                              if (p.settlementId != null) 'via acerto',
                              if (p.note.isNotEmpty) p.note,
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MoneyText(Money(p.amount)),
                              if (p.settlementId == null &&
                                  (p.userId == me || e.ownerId == me || manage))
                                IconButton(
                                  tooltip: 'Excluir pagamento',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    if (await confirmDialog(
                                          context,
                                          title: 'Excluir pagamento?',
                                          message: 'A parte volta a ficar em aberto.',
                                          confirm: 'Excluir',
                                          destructive: true,
                                        ) &&
                                        context.mounted) {
                                      await runAction(
                                        context,
                                        () => sc.deletePayment(p),
                                      );
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _menu(
    BuildContext context,
    ShareGroup g,
    SharedExpense e,
    String v,
  ) async {
    final sc = context.read<SharedController>();
    switch (v) {
      case 'split':
        await _override(context, g, e);
      case 'reset':
        await runAction(
          context,
          () => sc.updateExpense(e, resetOverride: true),
          success: 'Divisão padrão aplicada',
        );
      case 'category':
        final id = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Categoria do grupo'),
            children: [
              for (final c in g.activeCategories)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c.id),
                  child: Text(c.name),
                ),
            ],
          ),
        );
        if (id != null && context.mounted) {
          await runAction(context, () => sc.updateExpense(e, categoryId: id));
        }
      case 'notes':
        final c = TextEditingController(text: e.notes);
        final text = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Observação'),
            content: TextField(controller: c, maxLines: 3),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('Salvar'),
              ),
            ],
          ),
        );
        if (text != null && context.mounted) {
          await runAction(context, () => sc.updateExpense(e, notes: text));
        }
      case 'delete':
        if (await confirmDialog(
              context,
              title: 'Excluir do grupo?',
              message:
                  'A despesa continua no seu orçamento, mas deixa de ser '
                  'dividida. Pagamentos já registrados ficam no histórico.',
              confirm: 'Excluir',
              destructive: true,
            ) &&
            context.mounted) {
          final ok = await runAction(context, () => sc.deleteExpense(e));
          if (ok && context.mounted) Navigator.pop(context);
        }
    }
  }

  Future<void> _override(
    BuildContext context,
    ShareGroup g,
    SharedExpense e,
  ) async {
    final sc = context.read<SharedController>();
    var value = {
      for (final a in e.allocations)
        if (g.splitIds.contains(a.userId)) a.userId: a.bp,
    };
    String? error = ShareMath.checkPercentages(value, g.splitIds);
    var updateDefault = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Divisão desta despesa'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PercentEditor(
                    ids: g.splitIds,
                    nameOf: g.splitLabel,
                    initial: value,
                    total: e.total,
                    onChanged: (v, err) {
                      value = v;
                      set(() => error = err);
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: updateDefault,
                    title: Text('Usar como padrão de ${e.categoryName}'),
                    subtitle: const Text(
                      'Sem marcar, a mudança vale só para esta despesa',
                    ),
                    onChanged: (v) => set(() => updateDefault = v!),
                  ),
                  if (e.payments.isNotEmpty)
                    Text(
                      'Esta despesa já tem pagamentos: eles continuam '
                      'registrados e o saldo em aberto é recalculado.',
                      style: ctx.text.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: error != null
                  ? null
                  : () async {
                      final ok = await runAction(
                        ctx,
                        () => sc.updateExpense(
                          e,
                          override: value,
                          updateDefault: updateDefault,
                        ),
                        success: 'Divisão atualizada',
                      );
                      if (ok && ctx.mounted) Navigator.pop(ctx);
                    },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
