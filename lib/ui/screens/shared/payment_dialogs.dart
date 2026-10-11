import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/shared_engine.dart';
import '../../../domain/models/shared.dart';
import '../../../state/shared_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';

/// Registra o pagamento (total ou parcial) da parte de um participante.
Future<void> showPaymentDialog(
  BuildContext context,
  ShareGroup group,
  SharedExpense e,
  ParticipantShare s,
) async {
  final amount = TextEditingController(
    text: Money(s.outstanding).formatPlain(),
  );
  final note = TextEditingController();
  var date = Dates.today();
  final sc = context.read<SharedController>();
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('Pagamento de ${group.nameOf(s.userId)}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${e.description}: parte de ${Money(s.owed).format()}, '
                'em aberto ${Money(s.outstanding).format()}. '
                'Pago a ${group.nameOf(e.ownerId)}.',
              ),
              const SizedBox(height: 12),
              MoneyField(controller: amount, label: 'Valor pago'),
              const SizedBox(height: 12),
              DateField(
                value: date,
                label: 'Data do pagamento',
                onChanged: (d) => set(() => date = d ?? date),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Observação (ex.: Pix)',
                ),
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
              final v = Money.tryEval(amount.text);
              if (v == null || !v.isPositive) {
                showMessage(ctx, 'Informe o valor', error: true);
                return;
              }
              final ok = await runAction(
                ctx,
                () => sc.addPayment(
                  e,
                  userId: s.userId,
                  amount: v.cents,
                  date: date,
                  note: note.text.trim(),
                ),
                success: 'Pagamento registrado',
              );
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    ),
  );
}

/// Acerto entre participantes: quem deve transfere para quem pagou contas.
/// O valor quita as partes em aberto mais antigas.
Future<void> showSettlementDialog(
  BuildContext context,
  ShareGroup group, {
  String? from,
  String? to,
}) async {
  final sc = context.read<SharedController>();
  final ids = group.members
      .where((m) => m.isActive || m.status == 'left' || m.status == 'revoked')
      .map((m) => m.userId)
      .toList();
  if (ids.length < 2) {
    showMessage(context, 'O grupo precisa de ao menos duas pessoas');
    return;
  }
  var fromId = from ?? (ids.contains(sc.me) ? sc.me : ids.first);
  var toId = to ?? ids.firstWhere((i) => i != fromId);
  final amount = TextEditingController();
  final note = TextEditingController();
  var date = Dates.today();
  int open() => SharedReport.owedBetween(group.expenses, fromId, toId);
  amount.text = Money(open()).formatPlain();
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        DropdownButtonFormField<String> who(
          String label,
          String value,
          ValueChanged<String> on,
        ) => DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final id in ids)
              DropdownMenuItem(value: id, child: Text(group.nameOf(id))),
          ],
          onChanged: (v) => set(() {
            on(v!);
            amount.text = Money(open()).formatPlain();
          }),
        );
        return AlertDialog(
          title: const Text('Acertar contas'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                who('Quem paga', fromId, (v) => fromId = v),
                const SizedBox(height: 12),
                who('Quem recebe', toId, (v) => toId = v),
                const SizedBox(height: 8),
                Text(
                  fromId == toId
                      ? 'Escolha duas pessoas diferentes'
                      : 'Em aberto: ${Money(open()).format()}',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: 12),
                MoneyField(controller: amount, label: 'Valor transferido'),
                const SizedBox(height: 12),
                DateField(
                  value: date,
                  label: 'Data',
                  onChanged: (d) => set(() => date = d ?? date),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'O acerto quita as partes mais antigas primeiro. Ele não '
                  'entra como nova despesa: só marca as partes como pagas.',
                  style: context.text.bodySmall,
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
                final v = Money.tryEval(amount.text);
                if (v == null || !v.isPositive) {
                  showMessage(ctx, 'Informe o valor', error: true);
                  return;
                }
                final ok = await runAction(
                  ctx,
                  () => sc.settle(
                    group,
                    fromUserId: fromId,
                    toUserId: toId,
                    amount: v.cents,
                    date: date,
                    note: note.text.trim(),
                  ),
                  success: 'Acerto registrado',
                );
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Registrar'),
            ),
          ],
        );
      },
    ),
  );
}
