import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../domain/models/dashboard.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import 'dashboard_view.dart';

/// Painéis personalizados: escolher, criar, editar, duplicar, renomear,
/// definir padrão e excluir; no modo "Personalizar", adicionar, remover,
/// redimensionar e reorganizar gráficos.
class DashboardsScreen extends StatefulWidget {
  final String? dashboardId;
  final bool startEditing;
  final YearMonth? reference;
  const DashboardsScreen({
    super.key,
    this.dashboardId,
    this.startEditing = false,
    this.reference,
  });

  @override
  State<DashboardsScreen> createState() => _DashboardsScreenState();
}

class _DashboardsScreenState extends State<DashboardsScreen> {
  late String? currentId = widget.dashboardId;
  late bool editing = widget.startEditing;
  late YearMonth reference = widget.reference ?? YearMonth.now();

  Future<String?> _askName(String title, {String initial = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome do painel'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() f, [String? ok]) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await f();
      if (ok != null) m.showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      m.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst(RegExp(r'^\w+Error: '), '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fc = context.watch<FinanceController>();
    final d = fc.dashboardById(currentId) ?? fc.defaultDashboard;
    if (d == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<String>(
          tooltip: 'Trocar de painel',
          onSelected: (id) => setState(() => currentId = id),
          itemBuilder: (_) => [
            for (final x in fc.dashboards)
              CheckedPopupMenuItem(
                value: x.id,
                checked: x.id == d.id,
                child: Text(x.isDefault ? '${x.name} · padrão' : x.name),
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(d.name, overflow: TextOverflow.ellipsis)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          if (!editing)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: const Text('Personalizar'),
                onPressed: () => setState(() => editing = true),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Concluir'),
                onPressed: () {
                  setState(() => editing = false);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Painel salvo')));
                },
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Gerenciar painéis',
            onSelected: (v) async {
              switch (v) {
                case 'new':
                  final name = await _askName('Novo painel');
                  if (name == null) return;
                  final n = await fc.createDashboard(name);
                  setState(() {
                    currentId = n.id;
                    editing = true;
                  });
                case 'rename':
                  final name = await _askName(
                    'Renomear painel',
                    initial: d.name,
                  );
                  if (name == null) return;
                  await _run(
                    () => fc.renameDashboard(d, name),
                    'Painel renomeado',
                  );
                case 'dup':
                  final n = await fc.duplicateDashboard(d);
                  setState(() => currentId = n.id);
                case 'default':
                  await _run(
                    () => fc.setDefaultDashboard(d),
                    '"${d.name}" agora aparece na tela inicial',
                  );
                case 'delete':
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Excluir painel?'),
                      content: Text(
                        '"${d.name}" e seus gráficos serão removidos. '
                        'Suas transações não são afetadas.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Excluir'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await _run(() async {
                      await fc.deleteDashboard(d);
                      setState(() => currentId = null);
                    }, 'Painel excluído');
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('Novo painel')),
              const PopupMenuItem(value: 'rename', child: Text('Renomear')),
              const PopupMenuItem(value: 'dup', child: Text('Duplicar')),
              if (!d.isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Text('Definir como padrão'),
                ),
              if (fc.dashboards.length > 1)
                const PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ],
      ),
      floatingActionButton: editing
          ? FloatingActionButton.extended(
              heroTag: 'fab-add-chart',
              icon: const Icon(Icons.add_chart),
              label: const Text('Adicionar gráfico'),
              onPressed: () =>
                  DashboardGrid.addChart(context, fc, d, reference),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (editing)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: context.colors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: context.colors.primary),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Modo de edição: arraste pela alça ao lado do título para reorganizar, '
                          'toque em largura/altura para redimensionar e use o menu '
                          'de cada gráfico para configurar, duplicar ou remover. '
                          'As alterações são salvas automaticamente.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          PanelFilterBar(
            dashboard: d,
            reference: reference,
            onReference: (m) => setState(() => reference = m),
          ),
          const SizedBox(height: 12),
          DashboardGrid(dashboard: d, reference: reference, editing: editing),
        ],
      ),
    );
  }
}

/// Atalho para outras telas abrirem o painel no modo de edição.
DashboardsScreen customizeDashboard(Dashboard? d, YearMonth reference) =>
    DashboardsScreen(
      dashboardId: d?.id,
      startEditing: true,
      reference: reference,
    );
