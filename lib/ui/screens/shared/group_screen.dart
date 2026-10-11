import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/models/shared.dart';
import '../../../state/shared_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'payment_dialogs.dart';
import 'shared_simulation_screen.dart';
import 'shared_widgets.dart';

/// Cria um grupo e abre a tela dele.
Future<void> createGroupFlow(BuildContext context) async {
  final name = TextEditingController();
  var kind = GroupKind.household;
  final sc = context.read<SharedController>();
  final id = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Novo grupo'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome (ex.: Casa, Apartamento 302)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GroupKind>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final k in GroupKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (k) => set(() => kind = k!),
              ),
              const SizedBox(height: 12),
              Text(
                'O grupo começa com categorias padrão (moradia, luz e água, '
                'internet, mercado…). Depois você convida as pessoas e define '
                'os percentuais.',
                style: ctx.text.bodySmall,
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
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              try {
                final id = await sc.createGroup(name.text.trim(), kind);
                if (ctx.mounted) Navigator.pop(ctx, id);
              } catch (e) {
                if (ctx.mounted) showMessage(ctx, '$e', error: true);
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    ),
  );
  if (id != null && context.mounted) {
    await push(context, GroupScreen(groupId: id));
  }
}

/// Grupo: participantes, percentuais por categoria, recorrências, acertos.
class GroupScreen extends StatelessWidget {
  final String groupId;
  const GroupScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SharedController>();
    final g = sc.group(groupId);
    if (g == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Grupo')),
        body: const EmptyState(
          icon: Icons.group_off_outlined,
          title: 'Grupo indisponível',
          message: 'Você não participa mais deste grupo.',
        ),
      );
    }
    final owner = g.myRole == ShareRole.owner;
    final manage = g.myRole.canManage;
    return Scaffold(
      appBar: AppBar(
        title: Text(g.name),
        actions: [
          IconButton(
            tooltip: 'Simular',
            icon: const Icon(Icons.science_outlined),
            onPressed: () =>
                push(context, SharedSimulationScreen(groupId: g.id)),
          ),
          IconButton(
            tooltip: 'Histórico',
            icon: const Icon(Icons.history),
            onPressed: () => push(context, ShareHistoryScreen(groupId: g.id)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, g, v),
            itemBuilder: (_) => [
              if (owner)
                const PopupMenuItem(value: 'rename', child: Text('Renomear')),
              if (owner)
                PopupMenuItem(
                  value: 'archive',
                  child: Text(g.archived ? 'Reativar grupo' : 'Arquivar grupo'),
                ),
              if (!owner)
                const PopupMenuItem(
                  value: 'leave',
                  child: Text('Sair do grupo'),
                ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: sc.refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              '${g.kind.label} · você é ${g.myRole.label.toLowerCase()}',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: 8),
            SectionCard(
              title: 'Participantes',
              trailing: owner
                  ? TextButton.icon(
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Convidar'),
                      onPressed: () => _invite(context, g),
                    )
                  : null,
              child: Column(
                children: [
                  for (final m in g.members.where(
                    (m) => m.status != 'former' || owner,
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(
                          m.name.isEmpty ? '?' : m.name[0].toUpperCase(),
                        ),
                      ),
                      title: Text(
                        m.userId == sc.me ? '${m.name} (você)' : m.name,
                      ),
                      subtitle: Text(
                        [
                          m.role.label,
                          if (!m.isActive) m.statusLabel,
                          ?m.email,
                        ].join(' · '),
                      ),
                      trailing:
                          owner &&
                              m.role != ShareRole.owner &&
                              (m.isActive || m.status == 'invited')
                          ? PopupMenuButton<String>(
                              onSelected: (v) => _member(context, g, m, v),
                              itemBuilder: (_) => [
                                if (m.role != ShareRole.manager)
                                  const PopupMenuItem(
                                    value: 'manager',
                                    child: Text('Tornar gestor'),
                                  ),
                                if (m.role != ShareRole.member)
                                  const PopupMenuItem(
                                    value: 'member',
                                    child: Text('Tornar participante'),
                                  ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remover do grupo'),
                                ),
                              ],
                            )
                          : null,
                    ),
                  Text(
                    'Gestores lançam despesas e ajustam percentuais; '
                    'participantes veem as despesas do grupo e registram o '
                    'pagamento da própria parte. Ninguém vê o seu orçamento '
                    'particular (contas, cartões, receitas).',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            SectionCard(
              title: 'Percentuais por categoria',
              trailing: manage
                  ? TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Categoria'),
                      onPressed: () => showCategoryDialog(context, g),
                    )
                  : null,
              child: _PercentMatrix(group: g, editable: manage),
            ),
            if (g.recurrences.isNotEmpty)
              SectionCard(
                title: 'Recorrências compartilhadas',
                child: Column(
                  children: [
                    for (final r in g.recurrences)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.autorenew),
                        title: Text(r.description),
                        subtitle: Text(
                          [
                            g.category(r.categoryId)?.name ?? 'Sem categoria',
                            if (r.override != null)
                              'divisão própria: ${r.override!.entries.map((e) => '${g.nameOf(e.key)} ${bpLabel(e.value)}').join(', ')}',
                            'por ${g.nameOf(r.ownerId)}',
                            if (r.paused) 'pausada',
                          ].join(' · '),
                        ),
                        trailing: r.ownerId == sc.me || owner
                            ? PopupMenuButton<String>(
                                onSelected: (v) => _recurrence(context, r, v),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'pause',
                                    child: Text(
                                      r.paused ? 'Retomar' : 'Pausar',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'cancel',
                                    child: Text('Encerrar compartilhamento'),
                                  ),
                                ],
                              )
                            : null,
                      ),
                  ],
                ),
              ),
            SectionCard(
              title: 'Acertos',
              trailing: TextButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Acertar contas'),
                onPressed: () => showSettlementDialog(context, g),
              ),
              child: g.settlements.isEmpty
                  ? Text(
                      'Nenhum acerto registrado.',
                      style: context.text.bodySmall,
                    )
                  : Column(
                      children: [
                        for (final s in g.settlements.reversed)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.swap_horiz),
                            title: Text(
                              '${g.nameOf(s.fromUserId)} → ${g.nameOf(s.toUserId)}',
                            ),
                            subtitle: Text(
                              [
                                Dates.format(s.date),
                                if (s.note.isNotEmpty) s.note,
                              ].join(' · '),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MoneyText(Money(s.amount)),
                                if (manage ||
                                    s.fromUserId == sc.me ||
                                    s.toUserId == sc.me)
                                  IconButton(
                                    tooltip: 'Desfazer acerto',
                                    icon: const Icon(Icons.undo),
                                    onPressed: () async {
                                      if (await confirmDialog(
                                        context,
                                        title: 'Desfazer acerto?',
                                        message: 'As partes quitadas por ele voltam a ficar em aberto.',
                                        confirm: 'Desfazer',
                                        destructive: true,
                                      )) {
                                        if (context.mounted) {
                                          await runAction(
                                            context,
                                            () => sc.deleteSettlement(s),
                                          );
                                        }
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
      ),
    );
  }

  Future<void> _menu(BuildContext context, ShareGroup g, String v) async {
    final sc = context.read<SharedController>();
    switch (v) {
      case 'rename':
        final name = await _askText(context, 'Renomear grupo', g.name);
        if (name != null && context.mounted) {
          await runAction(context, () => sc.updateGroup(g, name: name));
        }
      case 'archive':
        await runAction(
          context,
          () => sc.updateGroup(g, archived: !g.archived),
        );
      case 'leave':
        if (await confirmDialog(
              context,
              title: 'Sair do grupo?',
              message: 'Você deixa de ver as despesas do grupo. Pagamentos já feitos continuam no seu orçamento.',
              confirm: 'Sair',
              destructive: true,
            ) &&
            context.mounted) {
          final ok = await runAction(context, () => sc.removeMember(g, sc.me));
          if (ok && context.mounted) Navigator.pop(context);
        }
    }
  }

  Future<void> _invite(BuildContext context, ShareGroup g) async {
    final email = TextEditingController();
    var role = ShareRole.member;
    final sc = context.read<SharedController>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Convidar participante'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail da conta no app',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ShareRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Papel'),
                  items: const [
                    DropdownMenuItem(
                      value: ShareRole.member,
                      child: Text('Participante'),
                    ),
                    DropdownMenuItem(
                      value: ShareRole.manager,
                      child: Text('Gestor'),
                    ),
                  ],
                  onChanged: (r) => set(() => role = r!),
                ),
                const SizedBox(height: 12),
                Text(
                  'A pessoa precisa ter conta no app. Ela vê o convite em '
                  'Despesas compartilhadas e decide se aceita.',
                  style: ctx.text.bodySmall,
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
              onPressed: () async {
                final ok = await runAction(
                  ctx,
                  () => sc.invite(g, email.text, role),
                  success: 'Convite enviado',
                );
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Convidar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _member(
    BuildContext context,
    ShareGroup g,
    ShareMember m,
    String v,
  ) async {
    final sc = context.read<SharedController>();
    if (v == 'remove') {
      if (await confirmDialog(
            context,
            title: 'Remover ${m.name}?',
            message: 'O percentual dela nas categorias passa para você. As divisões já lançadas e os pagamentos continuam no histórico.',
            confirm: 'Remover',
            destructive: true,
          ) &&
          context.mounted) {
        await runAction(context, () => sc.removeMember(g, m.userId));
      }
      return;
    }
    await runAction(context, () => sc.setRole(g, m.userId, ShareRole.parse(v)));
  }

  Future<void> _recurrence(
    BuildContext context,
    ShareRecurrence r,
    String v,
  ) async {
    final sc = context.read<SharedController>();
    if (v == 'pause') {
      await runAction(context, () => sc.setRecurrencePaused(r, !r.paused));
      return;
    }
    if (await confirmDialog(
          context,
          title: 'Encerrar compartilhamento?',
          message: 'As próximas ocorrências sem pagamento saem do grupo. As já lançadas e pagas ficam no histórico. A recorrência continua no seu orçamento.',
          confirm: 'Encerrar',
          destructive: true,
        ) &&
        context.mounted) {
      await runAction(context, () => sc.cancelRecurrence(r));
    }
  }
}

Future<String?> _askText(BuildContext context, String title, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim()),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}

/// Tabela categoria × participante com os percentuais atuais.
class _PercentMatrix extends StatelessWidget {
  final ShareGroup group;
  final bool editable;
  const _PercentMatrix({required this.group, required this.editable});

  @override
  Widget build(BuildContext context) {
    final ids = group.activeIds;
    final cats = group.activeCategories;
    final archived = group.categories.where((c) => c.archived).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 18,
            headingRowHeight: 36,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 44,
            showCheckboxColumn: false,
            columns: [
              const DataColumn(label: Text('Categoria')),
              for (final id in ids)
                DataColumn(numeric: true, label: Text(group.nameOf(id))),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (final c in cats)
                DataRow(
                  onSelectChanged: editable
                      ? (_) => showCategoryDialog(context, group, category: c)
                      : null,
                  cells: [
                    DataCell(Text(c.name)),
                    for (final id in ids)
                      DataCell(Text(bpLabel(c.percentages[id] ?? 0))),
                    DataCell(
                      _sumOk(c, ids)
                          ? const SizedBox.shrink()
                          : Tooltip(
                              message: 'Percentuais não somam 100%',
                              child: Icon(
                                Icons.warning_amber,
                                size: 18,
                                color: context.fin.warning,
                              ),
                            ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (editable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Toque numa categoria para alterar. Mudanças valem para as '
              'próximas despesas; as já lançadas mantêm a divisão original '
              '(você pode recalcular as que ainda não têm pagamento).',
              style: context.text.bodySmall,
            ),
          ),
        if (archived.isNotEmpty && editable)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Arquivadas (${archived.length})'),
            children: [
              for (final c in archived)
                ListTile(
                  title: Text(c.name),
                  trailing: TextButton(
                    onPressed: () => runAction(
                      context,
                      () => context.read<SharedController>().archiveCategory(
                        c,
                        false,
                      ),
                    ),
                    child: const Text('Reativar'),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  static bool _sumOk(ShareCategory c, List<String> ids) =>
      ids.fold(0, (a, id) => a + (c.percentages[id] ?? 0)) == fullBp;
}

/// Cria ou edita uma categoria do grupo e os percentuais dela.
Future<void> showCategoryDialog(
  BuildContext context,
  ShareGroup g, {
  ShareCategory? category,
}) async {
  final sc = context.read<SharedController>();
  final name = TextEditingController(text: category?.name ?? '');
  var value = Map.of(category?.percentages ?? {sc.me: fullBp});
  String? error;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(category == null ? 'Nova categoria' : 'Editar categoria'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 16),
                Text('Quanto cada um paga', style: ctx.text.labelLarge),
                const SizedBox(height: 8),
                PercentEditor(
                  ids: g.activeIds,
                  nameOf: g.nameOf,
                  initial: value,
                  onChanged: (v, e) {
                    value = v;
                    set(() => error = e);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (category != null)
            TextButton(
              onPressed: () async {
                final ok = await runAction(
                  ctx,
                  () => sc.archiveCategory(category, true),
                );
                if (ok && ctx.mounted) Navigator.pop(ctx, false);
              },
              child: const Text('Arquivar'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: error != null || ShareMathCheck.invalid(value, g)
                ? null
                : () async {
                    if (name.text.trim().isEmpty) {
                      showMessage(ctx, 'Informe o nome', error: true);
                      return;
                    }
                    final ok = await runAction(
                      ctx,
                      () => sc.saveCategory(
                        g,
                        category: category,
                        name: name.text.trim(),
                        percentages: value,
                      ),
                    );
                    if (ok && ctx.mounted) Navigator.pop(ctx, true);
                  },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
  if (saved != true || category == null || !context.mounted) return;
  // Despesas ainda sem pagamento podem passar para os novos percentuais.
  final pending = g.liveExpenses.where(
    (e) => e.categoryId == category.id && !e.overridden && e.payments.isEmpty,
  );
  if (pending.isEmpty) return;
  final again = await confirmDialog(
    context,
    title: 'Recalcular despesas em aberto?',
    message:
        '${pending.length} despesa(s) de ${category.name} ainda não têm '
        'pagamento. Aplicar os novos percentuais a elas? As já pagas não '
        'mudam.',
    confirm: 'Recalcular',
  );
  if (again && context.mounted) {
    await runAction(context, () async {
      final n = await sc.recalculate(g, categoryId: category.id);
      if (context.mounted) showMessage(context, '$n despesa(s) recalculada(s)');
    });
  }
}

/// Validação rápida para habilitar o botão Salvar.
class ShareMathCheck {
  static bool invalid(Map<String, int> v, ShareGroup g) =>
      v.values.fold(0, (a, b) => a + b) != fullBp ||
      v.keys.any((id) => !g.activeIds.contains(id));
}

/// Histórico (auditoria) do grupo.
class ShareHistoryScreen extends StatelessWidget {
  final String groupId;
  const ShareHistoryScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SharedController>();
    final g = sc.group(groupId);
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico do grupo')),
      body: g == null
          ? const SizedBox.shrink()
          : FutureBuilder<List<ShareAuditEntry>>(
              future: sc.history(g),
              builder: (context, snap) {
                if (snap.hasError) return ErrorState(message: '${snap.error}');
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.history,
                    title: 'Sem histórico',
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final h = list[i];
                    return ListTile(
                      leading: Icon(_icon(h.action)),
                      title: Text(describeAudit(h, g)),
                      subtitle: Text(
                        '${h.actorName ?? 'Ex-usuário'} · '
                        '${Dates.format(h.at)} ${h.at.hour.toString().padLeft(2, '0')}:${h.at.minute.toString().padLeft(2, '0')}',
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  static IconData _icon(String a) => switch (a.split('.').first) {
    'member' => Icons.person_outline,
    'category' => Icons.percent,
    'allocation' || 'allocations' => Icons.call_split,
    'payment' => Icons.payments_outlined,
    'settlement' => Icons.swap_horiz,
    'recurrence' => Icons.autorenew,
    'expense' => Icons.receipt_long_outlined,
    _ => Icons.group_outlined,
  };
}

/// Frase legível para uma entrada do histórico.
String describeAudit(ShareAuditEntry h, ShareGroup g) {
  final d = h.details;
  String who(Object? id) => id is String ? g.nameOf(id) : '';
  String money(Object? c) => c is num ? Money(c.toInt()).format() : '';
  String pct(Object? m) => m is Map
      ? m.entries
            .map((e) => '${who(e.key)} ${bpLabel((e.value as num).toInt())}')
            .join(', ')
      : '';
  return switch (h.action) {
    'group.created' => 'Criou o grupo "${d['name']}"',
    'group.updated' => 'Alterou o grupo',
    'member.invited' => 'Convidou ${d['name']}',
    'member.accepted' => '${d['name']} aceitou o convite',
    'member.rejected' => '${d['name']} recusou o convite',
    'member.role' => 'Mudou o papel de ${who(d['userId'])}',
    'member.revoked' => 'Removeu ${who(d['userId'])}',
    'member.left' => '${who(d['userId'])} saiu do grupo',
    'category.created' =>
      'Criou a categoria ${d['name']} (${pct(d['percentages'])})',
    'category.updated' =>
      '${d['name']}: ${pct(d['before'])} → ${pct(d['after'])}'
          '${d['archived'] == true ? ' (arquivada)' : ''}',
    'allocations.recalculated' =>
      'Recalculou ${d['updated']} despesa(s) em aberto',
    'allocation.override' => 'Divisão manual em "${d['description']}"',
    'expense.created' =>
      'Compartilhou "${d['description']}" (${money(d['total'])}, ${d['category']})',
    'expense.updated' => 'Alterou "${d['description']}"',
    'expense.deleted' => 'Excluiu "${d['description']}" (${money(d['total'])})',
    'payment.recorded' =>
      'Pagamento de ${who(d['userId'])}: ${money(d['amount'])} em "${d['description']}"',
    'payment.deleted' =>
      'Excluiu pagamento de ${who(d['userId'])} (${money(d['amount'])})',
    'settlement.recorded' =>
      'Acerto: ${who(d['fromUserId'])} → ${who(d['toUserId'])} ${money(d['amount'])}',
    'settlement.deleted' =>
      'Desfez acerto ${who(d['fromUserId'])} → ${who(d['toUserId'])} ${money(d['amount'])}',
    'recurrence.created' => 'Compartilhou a recorrência "${d['description']}"',
    'recurrence.updated' => 'Alterou a recorrência "${d['description']}"',
    'recurrence.paused' => 'Pausou a recorrência "${d['description']}"',
    'recurrence.resumed' => 'Retomou a recorrência "${d['description']}"',
    'recurrence.canceled' =>
      'Encerrou a recorrência "${d['description']}" (${d['removedFuture']} futura(s) removida(s))',
    _ => h.action,
  };
}
