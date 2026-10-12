import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/money.dart';
import '../../../domain/engine/shared_engine.dart';
import '../../../domain/models/entities.dart';
import '../../../domain/models/shared.dart';
import '../../../state/shared_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'group_screen.dart';
import 'shared_widgets.dart';

/// Compartilha um lançamento ([tx]) ou uma regra recorrente ([rule]) num
/// grupo: escolhe grupo e categoria, revisa a divisão antes de salvar e,
/// se quiser, ajusta os percentuais só desta despesa.
Future<bool> showShareDialog(
  BuildContext context, {
  FinTransaction? tx,
  RecurringRule? rule,
}) async {
  final sc = context.read<SharedController>();
  if (!sc.available) {
    showMessage(
      context,
      'Despesas compartilhadas só funcionam com a conta na nuvem',
      error: true,
    );
    return false;
  }
  if (!sc.loaded) await sc.refresh();
  if (!context.mounted) return false;
  if (sc.managedGroups.isEmpty) {
    final go = await confirmDialog(
      context,
      title: 'Nenhum grupo',
      message:
          'Crie um grupo (casa, casal, família…) e convide quem divide as '
          'despesas com você. Depois é só compartilhar.',
      confirm: 'Criar grupo',
    );
    if (go && context.mounted) await createGroupFlow(context);
    return false;
  }
  return await showDialog<bool>(
        context: context,
        builder: (_) => _ShareDialog(tx: tx, rule: rule),
      ) ??
      false;
}

class _ShareDialog extends StatefulWidget {
  final FinTransaction? tx;
  final RecurringRule? rule;
  const _ShareDialog({this.tx, this.rule});

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  late SharedController sc = context.read<SharedController>();
  late ShareGroup group = sc.managedGroups.first;
  ShareCategory? category;
  bool custom = false;
  Map<String, int> customShares = {};
  String? customError;
  bool updateDefault = false;
  final notes = TextEditingController();
  bool busy = false;

  String? get budgetCategoryId =>
      widget.tx?.categoryId ?? widget.rule?.categoryId;
  int get total => (widget.tx?.amount ?? widget.rule!.amount).cents;

  @override
  void initState() {
    super.initState();
    category = sc.suggestCategory(group, budgetCategoryId);
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Map<String, int> get shares =>
      custom ? customShares : (category?.percentages ?? const {});

  String? get error {
    if (category == null) return 'Escolha a categoria do grupo';
    if (custom) return customError;
    return ShareMath.checkPercentages(shares, group.splitIds) == null
        ? null
        : 'Os percentuais desta categoria estão incompletos. Ajuste-os no '
              'grupo ou use uma divisão só para esta despesa.';
  }

  Future<void> _save() async {
    setState(() => busy = true);
    final ok = await runAction(context, () async {
      if (widget.rule != null) {
        await sc.shareRule(
          widget.rule!,
          group: group,
          category: category!,
          override: custom ? customShares : null,
        );
      } else {
        await sc.shareTransaction(
          widget.tx!,
          group: group,
          category: category!,
          override: custom ? customShares : null,
          updateDefault: custom && updateDefault,
          notes: notes.text.trim(),
        );
      }
    }, success: 'Despesa compartilhada com ${group.name}');
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final groups = sc.managedGroups;
    final cats = group.activeCategories;
    final err = error;
    final preview = err == null
        ? ShareMath.allocate(total, shares, order: group.splitIds)
        : const <ShareAllocation>[];
    final title = widget.rule != null
        ? 'Compartilhar recorrência'
        : 'Compartilhar despesa';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.tx?.description ?? widget.rule!.description} · '
                '${Money(total).format()}'
                '${widget.rule != null ? ' por ocorrência' : ''}',
                style: context.text.titleSmall,
              ),
              if (widget.tx?.isCardTransaction ?? widget.rule?.cardId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Compra no cartão: continua uma única vez na sua fatura; '
                    'os outros veem só "Cartão de crédito" e a parte deles.',
                    style: context.text.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: group.id,
                decoration: const InputDecoration(labelText: 'Grupo'),
                items: [
                  for (final g in groups)
                    DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: (id) => setState(() {
                  group = groups.firstWhere((g) => g.id == id);
                  category = sc.suggestCategory(group, budgetCategoryId);
                  custom = false;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(group.id),
                initialValue: category?.id,
                decoration: const InputDecoration(
                  labelText: 'Categoria do grupo',
                ),
                items: [
                  for (final c in cats)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (id) => setState(
                  () => category = cats.firstWhere((c) => c.id == id),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Divisão diferente só nesta despesa'),
                value: custom,
                onChanged: group.myRole.canManage
                    ? (v) => setState(() {
                        custom = v;
                        customShares = Map.of(category?.percentages ?? {});
                        customError = ShareMath.checkPercentages(
                          customShares,
                          group.splitIds,
                        );
                      })
                    : null,
              ),
              if (custom) ...[
                PercentEditor(
                  key: ValueKey('${group.id}/${category?.id}'),
                  ids: group.splitIds,
                  nameOf: group.splitLabel,
                  onInvite: group.myRole == ShareRole.owner
                      ? () async {
                          if (await inviteToGroup(context, group)) {
                            setState(() => group = sc.group(group.id) ?? group);
                          }
                        }
                      : null,
                  initial: customShares,
                  total: total,
                  onChanged: (v, e) => setState(() {
                    customShares = v;
                    customError = e;
                  }),
                ),
                if (widget.rule == null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: updateDefault,
                    title: const Text('Usar também como padrão da categoria'),
                    subtitle: const Text('Vale para as próximas despesas'),
                    onChanged: (v) => setState(() => updateDefault = v!),
                  ),
              ] else ...[
                Text('Divisão', style: context.text.labelLarge),
                const SizedBox(height: 4),
                for (final a in preview)
                  InfoRow.text(
                    '${group.nameOf(a.userId)} (${bpLabel(a.bp)})',
                    Money(a.amount).format(),
                  ),
              ],
              if (err != null && !custom)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    err,
                    style: TextStyle(color: context.fin.negative),
                  ),
                ),
              if (widget.tx != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'Observação para o grupo (opcional)',
                  ),
                ),
              ],
              if (group.splitIds.length < 2)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Este grupo só tem você. Convide quem divide as despesas '
                    '(a pessoa precisa ter conta no app) em Grupos ou em '
                    '"Divisão diferente só nesta despesa".',
                    style: context.text.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => push(context, GroupScreen(groupId: group.id)),
          child: const Text('Configurar grupo'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: busy || err != null ? null : _save,
          child: const Text('Compartilhar'),
        ),
      ],
    );
  }
}
