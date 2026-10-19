import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/engine/networth_engine.dart';
import '../../../domain/models/asset.dart';
import '../../../state/finance_controller.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/plan_upsell.dart';
import '../../widgets/remembered_filters.dart';
import '../../widgets/sort_grid.dart';
import '../../widgets/tx_grid.dart';
import '../../widgets/view_mode.dart';

/// Bens e dívidas que o plano Grátis permite.
const gratisAssetLimit = 2;

IconData assetIcon(AssetKind k) => switch (k) {
  AssetKind.realEstate => Icons.home_outlined,
  AssetKind.vehicle => Icons.directions_car_outlined,
  AssetKind.investment => Icons.trending_up,
  AssetKind.other => Icons.category_outlined,
  AssetKind.financing => Icons.account_balance_outlined,
  AssetKind.loan => Icons.request_quote_outlined,
  AssetKind.otherDebt => Icons.money_off_outlined,
};

/// Patrimônio líquido: contas + bens − dívidas − cartões − parcelas.
class NetWorthScreen extends StatefulWidget {
  const NetWorthScreen({super.key});
  @override
  State<NetWorthScreen> createState() => _NetWorthScreenState();
}

class _NetWorthScreenState extends State<NetWorthScreen>
    with RememberedFilters {
  ViewMode view = ViewMode.cards;

  @override
  String get filterKey => 'networth';

  @override
  Map<String, Object?> filtersToJson() => {'view': view.name};

  @override
  void restoreFilters(Map<String, Object?> saved, FinanceController fc) =>
      view = FilterJson.enumOrNull(ViewMode.values, saved['view']) ?? view;

  void _new(BuildContext context, {bool liability = false}) {
    final fc = context.read<FinanceController>();
    if (isGratisPlan(context, listen: false) &&
        fc.assets.length >= gratisAssetLimit) {
      showPlanUpsell(
        context,
        feature:
            'No plano Grátis você pode registrar $gratisAssetLimit bens ou '
            'dívidas. Assine o Básico para acompanhar todo o seu patrimônio.',
      );
      return;
    }
    push(context, AssetFormScreen(liability: liability));
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final nwe = fc.netWorthEngine;
    final nw = nwe.compute(fc.assets);
    final points = nwe.history(fc.assets);
    final goods = fc.assets.where((a) => !a.isLiability).toList();
    final debts = fc.assets.where((a) => a.isLiability).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patrimônio'),
        actions: [
          ViewModeToggle(
            keyPrefix: 'networth',
            mode: view,
            onChanged: (v) => setFilters(() => view = v),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-asset',
        onPressed: () => _new(context),
        icon: const Icon(Icons.add),
        label: const Text('Novo bem'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          NetWorthSummary(netWorth: nw),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Evolução',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 160, child: NetWorthChart(points: points)),
                const SizedBox(height: 8),
                Text(
                  'Meses anteriores: saldo das contas + bens − dívidas pelo '
                  'histórico de valores. O mês atual inclui cartões e '
                  'parcelas.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (fc.assets.isEmpty)
            SectionCard(
              title: 'Bens e dívidas',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Registre imóveis, veículos e investimentos, e também '
                    'financiamentos e empréstimos que não estão no app.',
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _new(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar bem'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _new(context, liability: true),
                        icon: const Icon(Icons.remove),
                        label: const Text('Adicionar dívida'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else if (view == ViewMode.grid)
            AssetsGrid(assets: fc.assets)
          else ...[
            _Group(
              title: 'Bens',
              items: goods,
              onAdd: () => _new(context),
              addLabel: 'Adicionar bem',
            ),
            const SizedBox(height: 12),
            _Group(
              title: 'Dívidas',
              items: debts,
              onAdd: () => _new(context, liability: true),
              addLabel: 'Adicionar dívida',
            ),
          ],
        ],
      ),
    );
  }
}

/// Total e de onde ele vem, bloco a bloco.
class NetWorthSummary extends StatelessWidget {
  final NetWorth netWorth;
  const NetWorthSummary({super.key, required this.netWorth});

  @override
  Widget build(BuildContext context) {
    final nw = netWorth;
    Widget line(String key, String label, Money v, {bool minus = false}) =>
        Padding(
          key: ValueKey('networth-line-$key'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  minus ? '−' : '+',
                  style: context.text.bodyMedium?.copyWith(
                    color: minus ? context.fin.negative : context.fin.positive,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(child: Text(label, style: context.text.bodyMedium)),
              MoneyText(v, style: context.text.bodyMedium),
            ],
          ),
        );
    return SectionCard(
      title: 'Patrimônio líquido',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MoneyText(
            nw.total,
            key: const ValueKey('networth-total'),
            colorize: true,
            style: context.text.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          line('accounts', 'Saldo das contas ativas', nw.accounts),
          line('assets', 'Bens', nw.assets),
          line(
            'liabilities',
            'Dívidas registradas',
            nw.liabilities,
            minus: true,
          ),
          line(
            'invoices',
            'Faturas de cartão em aberto',
            nw.cardInvoices,
            minus: true,
          ),
          line(
            'installments',
            'Parcelas a vencer',
            nw.installments,
            minus: true,
          ),
          const Divider(),
          Row(
            children: [
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Total',
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              MoneyText(
                nw.total,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barras do patrimônio no fim de cada mês (negativas para baixo).
class NetWorthChart extends StatelessWidget {
  final List<NetWorthPoint> points;
  const NetWorthChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final style = context.text.labelSmall?.copyWith(color: context.fin.subtle);
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _BarsPainter(
              [for (final p in points) p.value.cents.toDouble()],
              positive: context.fin.positive,
              negative: context.fin.negative,
              axis: context.fin.gridLine,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final p in points)
              Expanded(
                child: Text(
                  p.month.shortLabel,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: style,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<double> values;
  final Color positive, negative, axis;
  _BarsPainter(
    this.values, {
    required this.positive,
    required this.negative,
    required this.axis,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var hi = 0.0, lo = 0.0;
    for (final v in values) {
      if (v > hi) hi = v;
      if (v < lo) lo = v;
    }
    final span = (hi - lo) == 0 ? 1.0 : hi - lo;
    final zero = size.height * hi / span;
    canvas.drawLine(
      Offset(0, zero),
      Offset(size.width, zero),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );
    final slot = size.width / values.length;
    final bar = (slot * 0.6).clamp(4.0, 40.0);
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final h = size.height * v.abs() / span;
      final x = slot * i + (slot - bar) / 2;
      final rect = v >= 0
          ? Rect.fromLTWH(x, zero - h, bar, h)
          : Rect.fromLTWH(x, zero, bar, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = v >= 0 ? positive : negative,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.positive != positive;
}

class _Group extends StatelessWidget {
  final String title;
  final List<Asset> items;
  final VoidCallback onAdd;
  final String addLabel;
  const _Group({
    required this.title,
    required this.items,
    required this.onAdd,
    required this.addLabel,
  });

  @override
  Widget build(BuildContext context) {
    final total = items.fold(Money.zero, (a, x) => a + x.value);
    return SectionCard(
      title: title,
      trailing: MoneyText(
        total,
        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          for (final a in items) AssetTile(asset: a),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: Text(addLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AssetTile extends StatelessWidget {
  final Asset asset;
  const AssetTile({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    final a = asset;
    final color = a.isLiability ? context.fin.negative : context.fin.positive;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(assetIcon(a.kind), color: color, size: 20),
      ),
      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${a.kind.label} · atualizado em ${Dates.format(a.updatedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: MoneyText(
        a.signed,
        colorize: true,
        style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      onTap: () => push(context, AssetDetailsScreen(assetId: a.id)),
    );
  }
}

/// Bens e dívidas no padrão de grade, com o total líquido.
class AssetsGrid extends StatelessWidget {
  final List<Asset> assets;
  const AssetsGrid({super.key, required this.assets});

  @override
  Widget build(BuildContext context) {
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final strong = context.text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
    );
    int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    Money net(List<Asset> l) => l.fold(Money.zero, (a, x) => a + x.signed);
    Widget money(Money v, {TextStyle? style}) =>
        MoneyText(v, colorize: true, style: style);
    return SortGrid<Asset>(
      keyPrefix: 'networth',
      rows: assets,
      rowId: (a) => a.id,
      accent: (context, a) =>
          a.isLiability ? context.fin.negative : context.fin.positive,
      onOpen: (a) => push(context, AssetDetailsScreen(assetId: a.id)),
      initialSort: 'name',
      tieBreak: (a, b) => text(a.name, b.name),
      columns: [
        SortCol(
          id: 'name',
          label: 'Nome',
          width: 220,
          minWidth: 140,
          flexible: true,
          fill: true,
          compare: (a, b) => text(a.name, b.name),
          cell: (context, a) => GridCell(
            child: Row(
              children: [
                Icon(assetIcon(a.kind), size: 18, color: context.fin.subtle),
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
          id: 'kind',
          label: 'Tipo',
          width: 140,
          compare: (a, b) => a.kind.index.compareTo(b.kind.index),
          cell: (context, a) => GridCell(child: Text(a.kind.label)),
        ),
        SortCol(
          id: 'updated',
          label: 'Atualizado',
          width: 110,
          compare: (a, b) => a.updatedAt.compareTo(b.updatedAt),
          cell: (context, a) =>
              GridCell(child: Text(Dates.format(a.updatedAt), style: subtle)),
        ),
        SortCol(
          id: 'value',
          label: 'Valor',
          width: 140,
          right: true,
          highlight: true,
          compare: (a, b) => a.signed.compareTo(b.signed),
          cell: (context, a) =>
              GridCell(right: true, child: money(a.signed, style: strong)),
          footer: (context, l) => money(net(l), style: strong),
        ),
      ],
      compactRow: (context, a) => Row(
        children: [
          Icon(assetIcon(a.kind), size: 20, color: context.fin.subtle),
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
                  '${a.kind.label} · ${Dates.format(a.updatedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          money(a.signed, style: strong),
        ],
      ),
      footerLabel: (context, l) => Text(
        'Total · ${l.length} ${l.length == 1 ? 'item' : 'itens'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: gridFooterLabelStyle(context),
      ),
      compactFooter: (context, l) => money(net(l), style: strong),
    );
  }
}

class AssetDetailsScreen extends StatelessWidget {
  final String assetId;
  const AssetDetailsScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final a = fc.assets.where((x) => x.id == assetId).firstOrNull;
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Item excluído')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(a.name),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => push(context, AssetFormScreen(asset: a)),
          ),
          IconButton(
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirmDialog(
                context,
                title: 'Excluir ${a.isLiability ? 'dívida' : 'bem'}?',
                message: 'O item e o histórico de valores serão apagados.',
              )) {
                return;
              }
              if (!context.mounted) return;
              final ok = await runAction(context, () => fc.deleteAsset(a));
              if (ok && context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-asset-value',
        onPressed: () => _valueDialog(context, a),
        icon: const Icon(Icons.update),
        label: const Text('Atualizar valor'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.kind.label,
                  style: context.text.bodySmall?.copyWith(
                    color: context.fin.subtle,
                  ),
                ),
                const SizedBox(height: 4),
                MoneyText(
                  a.signed,
                  colorize: true,
                  style: context.text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (a.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(a.notes, style: context.text.bodyMedium),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Histórico de valores',
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                for (final (i, h) in a.history.indexed.toList().reversed)
                  ListTile(
                    dense: true,
                    title: MoneyText(h.value),
                    subtitle: Text(Dates.format(h.date)),
                    trailing: i == 0
                        ? null
                        : _Delta(h.value - a.history[i - 1].value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Delta extends StatelessWidget {
  final Money delta;
  const _Delta(this.delta);
  @override
  Widget build(BuildContext context) => MoneyText(
    delta,
    colorize: true,
    showPlus: true,
    style: context.text.bodySmall,
  );
}

Future<void> _valueDialog(BuildContext context, Asset a) async {
  final fc = context.read<FinanceController>();
  final amount = TextEditingController(text: a.value.formatPlain());
  var date = fc.today;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Atualizar valor'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MoneyField(
                controller: amount,
                autofocus: true,
                allowZero: true,
                label: a.isLiability ? 'Saldo devedor' : 'Valor atual',
              ),
              const SizedBox(height: 12),
              DateField(
                value: date,
                onChanged: (d) => setState(() => date = d ?? date),
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
              final v = Money.tryEval(amount.text) ?? Money.zero;
              final ok = await runAction(
                ctx,
                () => fc.updateAssetValue(a, v, date: date),
                success: 'Valor atualizado',
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

class AssetFormScreen extends StatefulWidget {
  final Asset? asset;
  final bool liability;
  const AssetFormScreen({super.key, this.asset, this.liability = false});
  @override
  State<AssetFormScreen> createState() => _AssetFormScreenState();
}

class _AssetFormScreenState extends State<AssetFormScreen> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.asset?.name ?? '');
  late final value = TextEditingController(
    text: widget.asset?.value.formatPlain() ?? '',
  );
  late final notes = TextEditingController(text: widget.asset?.notes ?? '');
  late bool liability = widget.asset?.isLiability ?? widget.liability;
  late AssetKind kind =
      widget.asset?.kind ??
      (liability ? AssetKind.financing : AssetKind.realEstate);

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    final isNew = widget.asset == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isNew
              ? (liability ? 'Nova dívida' : 'Novo bem')
              : (liability ? 'Editar dívida' : 'Editar bem'),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Bem'),
                  icon: Icon(Icons.add),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Dívida'),
                  icon: Icon(Icons.remove),
                ),
              ],
              selected: {liability},
              onSelectionChanged: (s) => setState(() {
                liability = s.first;
                if (kind.liability != liability) {
                  kind = AssetKind.of(liability: liability).first;
                }
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: name,
              decoration: InputDecoration(
                labelText: 'Nome',
                hintText: liability
                    ? 'Ex.: Financiamento do apartamento'
                    : 'Ex.: Apartamento, Carro, Tesouro Direto',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AssetKind>(
              key: ValueKey('asset-kind-$liability'),
              initialValue: kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                for (final k in AssetKind.of(liability: liability))
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => setState(() => kind = v ?? kind),
            ),
            const SizedBox(height: 12),
            MoneyField(
              controller: value,
              allowZero: true,
              label: liability ? 'Saldo devedor' : 'Valor atual',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                final v = Money.tryEval(value.text) ?? Money.zero;
                final a =
                    (widget.asset ??
                            Asset(
                              id: newId('asset_'),
                              name: name.text.trim(),
                              kind: kind,
                              value: v,
                            ))
                        .copyWith(
                          name: name.text.trim(),
                          kind: kind,
                          value: v,
                          notes: notes.text.trim(),
                        );
                final ok = await runAction(
                  context,
                  () => fc.saveAsset(a),
                  success: liability ? 'Dívida salva' : 'Bem salvo',
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
