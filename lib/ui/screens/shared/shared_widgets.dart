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

/// Divisão por pessoa, uma linha por participante: escolhe a pessoa, digita
/// o percentual (ou o valor em R$, quando há [total]) e remove com o X.
/// "Adicionar pessoa" inclui quem ainda não está na divisão; com todos já
/// incluídos e [onInvite] presente, oferece convidar alguém para o grupo.
class PercentEditor extends StatefulWidget {
  /// Quem pode entrar na divisão (participantes ativos do grupo).
  final List<String> ids;
  final String Function(String id) nameOf;
  final Map<String, int> initial;

  /// Valor de referência para mostrar quanto cabe a cada um (centavos).
  final int? total;

  /// Convida uma pessoa nova para o grupo (ela entra na divisão depois de
  /// aceitar o convite).
  final Future<void> Function()? onInvite;
  final void Function(Map<String, int> value, String? error) onChanged;
  const PercentEditor({
    super.key,
    required this.ids,
    required this.nameOf,
    required this.initial,
    required this.onChanged,
    this.total,
    this.onInvite,
  });

  @override
  State<PercentEditor> createState() => _PercentEditorState();
}

class _ShareRow {
  String? id;
  bool money = false;
  final TextEditingController ctl;
  _ShareRow(this.id, String text) : ctl = TextEditingController(text: text);
}

class _PercentEditorState extends State<PercentEditor> {
  late final List<_ShareRow> rows = [
    for (final id in widget.ids)
      if ((widget.initial[id] ?? 0) > 0)
        _ShareRow(id, bpLabel(widget.initial[id]!).replaceAll('%', '')),
  ];
  Map<String, int> value = {};
  String? error;

  @override
  void initState() {
    super.initState();
    if (rows.isEmpty && widget.ids.isNotEmpty) {
      rows.add(_ShareRow(widget.ids.first, '100'));
    }
    _read(notify: false);
  }

  @override
  void dispose() {
    for (final r in rows) {
      r.ctl.dispose();
    }
    super.dispose();
  }

  /// Valor em R$ digitado → pontos-base do total.
  int? _moneyBp(String text) {
    final total = widget.total;
    if (total == null || total <= 0) return null;
    if (text.trim().isEmpty) return 0;
    final cents = Money.tryEval(text)?.cents;
    if (cents == null || cents < 0 || cents > total) return null;
    return (cents * fullBp / total).round();
  }

  void _read({bool notify = true}) {
    final v = <String, int>{};
    String? err;
    var allMoney = rows.isNotEmpty;
    var cents = 0;
    for (final r in rows) {
      final name = r.id == null ? '' : widget.nameOf(r.id!);
      final bp = r.money ? _moneyBp(r.ctl.text) : parseBp(r.ctl.text);
      if (r.id == null) {
        err ??= 'Escolha a pessoa de cada linha';
      } else if (v.containsKey(r.id)) {
        err ??= '$name aparece mais de uma vez';
      } else if (bp == null) {
        err ??= r.money
            ? 'Valor inválido para $name'
            : 'Percentual inválido para $name';
      } else if (bp > 0) {
        v[r.id!] = bp;
      }
      if (r.money) {
        cents += Money.tryEval(r.ctl.text)?.cents ?? 0;
      } else {
        allMoney = false;
      }
    }
    // Tudo em R$ fechando o total: o arredondamento não pode deixar a soma
    // em 99,99%.
    if (err == null && allMoney && cents == widget.total && v.isNotEmpty) {
      final top = v.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      v[top] =
          fullBp -
          v.entries
              .where((e) => e.key != top)
              .fold<int>(0, (a, e) => a + e.value);
    }
    err ??= ShareMath.checkPercentages(v, widget.ids);
    setState(() {
      value = v;
      error = err;
    });
    if (notify) widget.onChanged(v, err);
  }

  void _equal() {
    final ids = {
      for (final r in rows)
        if (r.id != null) r.id!,
    }.toList();
    if (ids.isEmpty) return;
    final eq = ShareMath.equal(ids);
    rows.removeWhere((r) => r.id == null);
    for (final r in rows) {
      r.money = false;
      r.ctl.text = bpLabel(eq[r.id]!).replaceAll('%', '');
    }
    _read();
  }

  List<String> get _free => [
    for (final id in widget.ids)
      if (!rows.any((r) => r.id == id)) id,
  ];

  void _add() {
    final sum = value.values.fold<int>(0, (a, b) => a + b);
    final left = (fullBp - sum).clamp(0, fullBp);
    rows.add(_ShareRow(_free.first, bpLabel(left).replaceAll('%', '')));
    _read();
  }

  void _remove(int i) {
    rows.removeAt(i).ctl.dispose();
    _read();
  }

  /// Uma linha da divisão. Em tela estreita (celular), a pessoa fica numa
  /// linha e o tipo/valor na de baixo.
  Widget _row(int i, _ShareRow r, int? total, Map<String, int> preview) {
    final person = DropdownButtonFormField<String>(
      key: ValueKey('share-person-$i'),
      initialValue: r.id,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Pessoa',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      items: [
        for (final id in widget.ids)
          if (id == r.id || !rows.any((o) => o.id == id))
            DropdownMenuItem(
              value: id,
              child: Text(widget.nameOf(id), overflow: TextOverflow.ellipsis),
            ),
      ],
      onChanged: (v) {
        r.id = v;
        _read();
      },
    );
    final toggle = total == null
        ? null
        : SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('%')),
              ButtonSegment(value: true, label: Text('R\$')),
            ],
            selected: {r.money},
            onSelectionChanged: (s) {
              // Converte o que já estava digitado.
              final bp = value[r.id] ?? 0;
              r.money = s.first;
              r.ctl.text = r.money
                  ? Money((preview[r.id] ?? (total * bp / fullBp).round()))
                        .formatPlain()
                  : bpLabel(bp).replaceAll('%', '');
              _read();
            },
          );
    final field = SizedBox(
      width: 84,
      child: TextField(
        key: ValueKey('share-value-$i'),
        controller: r.ctl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          isDense: true,
          suffixText: r.money ? null : '%',
          prefixText: r.money ? 'R\$ ' : null,
          helperText: total == null || r.id == null
              ? null
              : r.money
              ? bpLabel(value[r.id] ?? 0)
              : Money(preview[r.id] ?? 0).format(),
        ),
        onChanged: (_) => _read(),
      ),
    );
    final remove = IconButton(
      tooltip: 'Remover',
      icon: const Icon(Icons.close),
      onPressed: () => _remove(i),
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (toggle == null || c.maxWidth >= 440) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: person),
              if (toggle != null) ...[const SizedBox(width: 6), toggle],
              const SizedBox(width: 6),
              field,
              remove,
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: person),
                remove,
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                toggle,
                const Spacer(),
                field,
                const SizedBox(width: 48),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sum = value.values.fold<int>(0, (a, b) => a + b);
    final total = widget.total;
    final preview = total != null && error == null
        ? {
            for (final a in ShareMath.allocate(total, value, order: widget.ids))
              a.userId: a.amount,
          }
        : const <String, int>{};
    final ok = error == null;
    final over = sum > fullBp;
    final color = ok
        ? context.fin.positive
        : over
        ? context.fin.negative
        : Colors.amber.shade800;
    final footer = ok
        ? 'Tudo distribuído (${bpLabel(sum)})'
        : over
        ? 'A divisão passa de 100% (${bpLabel(sum)})'
        : sum < fullBp && error!.startsWith('A soma')
        ? 'Falta distribuir ${bpLabel(fullBp - sum)}'
        : error!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: rows.isEmpty ? null : _equal,
            child: const Text('Dividir igualmente'),
          ),
        ),
        for (final (i, r) in rows.indexed)
          Padding(
            key: ObjectKey(r),
            padding: const EdgeInsets.only(bottom: 8),
            child: _row(i, r, total, preview),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: _free.isNotEmpty
              ? TextButton.icon(
                  key: const ValueKey('share-add-person'),
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar pessoa'),
                )
              : widget.onInvite != null
              ? TextButton.icon(
                  key: const ValueKey('share-invite-person'),
                  onPressed: widget.onInvite,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Convidar pessoa para o grupo'),
                )
              : const SizedBox.shrink(),
        ),
        Row(
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.info_outline,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                footer,
                key: const ValueKey('share-footer'),
                style: context.text.bodySmall?.copyWith(color: color),
              ),
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
