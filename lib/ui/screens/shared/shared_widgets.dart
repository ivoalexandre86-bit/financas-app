import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/money.dart';
import '../../../domain/engine/shared_engine.dart';
import '../../../domain/models/shared.dart';
import '../../../state/shared_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../simulations/other_entries.dart' show payStatusPill;

export '../simulations/other_entries.dart' show payStatusPill, payStatusColor;

/// Campos de percentual por participante, com soma e validação ao vivo.
class PercentEditor extends StatefulWidget {
  final List<String> ids;
  final String Function(String id) nameOf;
  final Map<String, int> initial;

  /// Valor de referência para mostrar quanto cabe a cada um (centavos).
  final int? total;
  final void Function(Map<String, int> value, String? error) onChanged;
  const PercentEditor({
    super.key,
    required this.ids,
    required this.nameOf,
    required this.initial,
    required this.onChanged,
    this.total,
  });

  @override
  State<PercentEditor> createState() => _PercentEditorState();
}

class _PercentEditorState extends State<PercentEditor> {
  late final Map<String, TextEditingController> ctrl = {
    for (final id in widget.ids)
      id: TextEditingController(
        text: bpLabel(widget.initial[id] ?? 0).replaceAll('%', ''),
      ),
  };
  Map<String, int> value = {};
  String? error;

  @override
  void initState() {
    super.initState();
    _read(notify: false);
  }

  @override
  void dispose() {
    for (final c in ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _read({bool notify = true}) {
    final v = <String, int>{};
    String? err;
    for (final id in widget.ids) {
      final bp = parseBp(ctrl[id]!.text);
      if (bp == null) {
        err = 'Percentual inválido para ${widget.nameOf(id)}';
      } else if (bp > 0) {
        v[id] = bp;
      }
    }
    err ??= ShareMath.checkPercentages(v, widget.ids);
    setState(() {
      value = v;
      error = err;
    });
    if (notify) widget.onChanged(v, err);
  }

  void _equal() {
    final eq = ShareMath.equal(widget.ids);
    for (final id in widget.ids) {
      ctrl[id]!.text = bpLabel(eq[id]!).replaceAll('%', '');
    }
    _read();
  }

  @override
  Widget build(BuildContext context) {
    final sum = value.values.fold(0, (a, b) => a + b);
    final preview = widget.total != null && error == null
        ? {
            for (final a in ShareMath.allocate(
              widget.total!,
              value,
              order: widget.ids,
            ))
              a.userId: a.amount,
          }
        : const <String, int>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in widget.ids)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(widget.nameOf(id))),
                if (widget.total != null)
                  SizedBox(
                    width: 110,
                    child: Text(
                      preview[id] == null ? '' : Money(preview[id]!).format(),
                      textAlign: TextAlign.right,
                      style: context.text.bodySmall,
                    ),
                  ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: ctrl[id],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      suffixText: '%',
                      isDense: true,
                    ),
                    onChanged: (_) => _read(),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                error ?? 'Total: ${bpLabel(sum)}',
                style: context.text.bodySmall?.copyWith(
                  color: error == null
                      ? context.fin.positive
                      : context.fin.negative,
                ),
              ),
            ),
            TextButton(
              onPressed: _equal,
              child: const Text('Dividir igualmente'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Tabela de partes de uma despesa: %, valor, pago, em aberto, situação.
class SharesTable extends StatelessWidget {
  final ShareGroup group;
  final SharedExpense expense;
  final void Function(ParticipantShare s)? onPay;
  const SharesTable({
    super.key,
    required this.group,
    required this.expense,
    this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final rows = expense.shares;
    return Column(
      children: [
        for (final s in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              group.nameOf(s.userId) + (s.isPayer ? ' · pagou a conta' : ''),
            ),
            subtitle: Text(
              '${bpLabel(s.bp)} = ${Money(s.owed).format()}'
              '${s.isPayer ? '' : ' · pago ${Money(s.paid).format()} · em aberto ${Money(s.outstanding).format()}'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                payStatusPill(context, s.status),
                if (onPay != null && s.outstanding > 0 && !expense.isDeleted)
                  IconButton(
                    tooltip: 'Registrar pagamento',
                    icon: const Icon(Icons.payments_outlined),
                    onPressed: () => onPay!(s),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Mensagem para quem usa o app sem a conta na nuvem.
class SharedUnavailable extends StatelessWidget {
  const SharedUnavailable({super.key});

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.cloud_off_outlined,
    title: 'Disponível com a conta na nuvem',
    message:
        'Despesas compartilhadas reúnem usuários diferentes do app, então '
        'funcionam só com o login na nuvem (não na demonstração).',
  );
}

/// Controlador das compartilhadas, quando existe na árvore (telas usadas
/// fora do app completo, como em testes, seguem sem ele).
SharedController? watchShared(BuildContext context) {
  try {
    return context.watch<SharedController>();
  } on ProviderNotFoundException {
    return null;
  }
}
