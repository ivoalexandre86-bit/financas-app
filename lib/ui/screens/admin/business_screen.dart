import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/money.dart';
import '../../../data/cloud/api_client.dart';
import '../../../data/cloud/cloud_auth_service.dart';
import '../../../state/auth_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Leitura e gravação do painel do negócio no servidor.
abstract class BusinessApi {
  Future<Map<String, Object?>> metrics(int days);
  Future<void> saveSpend(String month, String channel, int cents);
}

class HttpBusinessApi implements BusinessApi {
  final ApiClient api;
  HttpBusinessApi(this.api);
  @override
  Future<Map<String, Object?>> metrics(int days) =>
      api.get('admin/metrics?days=$days&months=6');
  @override
  Future<void> saveSpend(String month, String channel, int cents) => api.post(
    'admin/spend',
    {'month': month, 'channel': channel, 'amountCents': cents},
  );
}

/// Painel do negócio (administradores): MRR, assinantes, CAC, conversão do
/// teste, cancelamentos, funil, receita e CAC por canal e retenção por safra.
class BusinessScreen extends StatefulWidget {
  final BusinessApi? api;
  const BusinessScreen({super.key, this.api});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  int days = 30;
  BusinessApi? _api;
  Future<Map<String, Object?>>? _data;

  @override
  void initState() {
    super.initState();
    _api = widget.api;
    if (_api == null) {
      final s = context.read<AuthController>().service;
      if (s is CloudAuthService) _api = HttpBusinessApi(s.api);
    }
    _data = _api?.metrics(days);
  }

  void _reload() => setState(() {
    _data = _api?.metrics(days);
  });

  @override
  Widget build(BuildContext context) {
    final body = _api == null
        ? const EmptyState(
            icon: Icons.insights_outlined,
            title: 'Disponível com a conta na nuvem',
            message: 'Os números do negócio vêm do servidor.',
          )
        : FutureBuilder<Map<String, Object?>>(
            future: _data,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return ErrorState(message: '${snap.error}', onRetry: _reload);
              }
              return _Report(
                data: snap.data!,
                days: days,
                onDays: (d) {
                  days = d;
                  _reload();
                },
                onSpend: _editSpend,
              );
            },
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel do negócio'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _api == null ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }

  Future<void> _editSpend() async {
    final now = DateTime.now();
    final month = TextEditingController(
      text: '${now.year}-${now.month.toString().padLeft(2, '0')}',
    );
    final channel = TextEditingController();
    final value = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Investimento em divulgação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: month,
              decoration: const InputDecoration(labelText: 'Mês (AAAA-MM)'),
            ),
            TextField(
              controller: channel,
              decoration: const InputDecoration(
                labelText: 'Canal',
                helperText: 'Igual ao utm_source do link (ex.: instagram)',
              ),
            ),
            TextField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor investido',
                helperText: '0 apaga o lançamento',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cents = value.text.trim() == '0'
        ? 0
        : Money.tryParse(value.text)?.cents;
    if (cents == null) {
      showMessage(context, 'Valor inválido', error: true);
      return;
    }
    final saved = await runAction(
      context,
      () => _api!.saveSpend(month.text.trim(), channel.text.trim(), cents),
      success: 'Investimento salvo',
    );
    if (saved) _reload();
  }
}

String _money(Object? cents) =>
    cents is num ? Money(cents.round()).formatVisible() : '—';
String _pct(Object? v) =>
    v is num ? '${v.toStringAsFixed(1).replaceAll('.', ',')}%' : '—';
int _int(Object? v) => v is num ? v.toInt() : 0;
List<Map<String, Object?>> _list(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is Map) e.cast<String, Object?>(),
];

String _monthLabel(String ym) {
  const names = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];
  final p = ym.split('-');
  if (p.length != 2) return ym;
  final m = int.tryParse(p[1]) ?? 1;
  return '${names[(m - 1).clamp(0, 11)]}/${p[0].substring(2)}';
}

class _Report extends StatelessWidget {
  final Map<String, Object?> data;
  final int days;
  final ValueChanged<int> onDays;
  final VoidCallback onSpend;
  const _Report({
    required this.data,
    required this.days,
    required this.onDays,
    required this.onSpend,
  });

  @override
  Widget build(BuildContext context) {
    final k = (data['kpis'] as Map?)?.cast<String, Object?>() ?? const {};
    final subtle = context.text.bodySmall?.copyWith(color: context.fin.subtle);
    final funnel = _list(data['funnel']);
    final maxFunnel = funnel.fold<int>(
      1,
      (a, f) => _int(f['count']) > a ? _int(f['count']) : a,
    );
    final refs =
        (data['referrals'] as Map?)?.cast<String, Object?>() ?? const {};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Kpi(
              'MRR',
              _money(k['mrrCents']),
              'receita recorrente mensal',
              key: const ValueKey('kpi-mrr'),
            ),
            _Kpi(
              'Assinantes',
              '${_int(k['paying'])}',
              '${_int(k['premium'])} Premium · ${_int(k['basico'])} Básico',
            ),
            _Kpi('Ticket médio', _money(k['arpuCents']), 'por assinante'),
            _Kpi(
              'CAC',
              _money(k['cacCents']),
              'investido ÷ novos assinantes (6 meses)',
            ),
            _Kpi(
              'Conversão do teste',
              _pct(k['trialConversion']),
              '${_int(k['trialsEnded'])} testes terminaram em $days dias',
            ),
            _Kpi(
              'Cancelamentos',
              _pct(k['churn']),
              '${_int(k['cancellations'])} em $days dias',
            ),
            _Kpi(
              'Em teste',
              '${_int(k['trial'])}',
              '${_int(k['bonus'])} com Premium por indicação',
            ),
            _Kpi(
              'Grátis',
              '${_int(k['gratis'])}',
              '${_int(k['courtesy'])} cortesias/admins fora da conta',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Text('Funil', style: context.text.titleMedium)),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 dias')),
                ButtonSegment(value: 30, label: Text('30 dias')),
                ButtonSegment(value: 90, label: Text('90 dias')),
              ],
              selected: {days},
              onSelectionChanged: (s) => onDays(s.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final f in funnel)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(width: 130, child: Text('${f['label']}')),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _int(f['count']) / maxFunnel,
                      minHeight: 14,
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    '${_int(f['count'])}'
                    '${f['fromPrevious'] is num ? '  (${_pct(f['fromPrevious'])})' : ''}',
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        Text('Entre parênteses: % da etapa anterior.', style: subtle),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Por canal (6 meses)',
                style: context.text.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: onSpend,
              icon: const Icon(Icons.add),
              label: const Text('Investimento'),
            ),
          ],
        ),
        _Table(
          headers: const [
            'Canal',
            'Cadastros',
            'Assinantes',
            'Conversão',
            'Receita',
            'Investido',
            'CAC',
          ],
          rows: [
            for (final c in _list(data['channels']))
              [
                '${c['channel']}',
                '${_int(c['signups'])}',
                '${_int(c['paying'])}',
                _pct(c['conversion']),
                _money(c['revenueCents']),
                _money(c['spendCents']),
                _money(c['cacCents']),
              ],
          ],
        ),
        Text(
          'O canal vem do utm_source do link (ex.: ?utm_source=instagram). '
          'Sem ele: indicação, loja ou orgânico.',
          style: subtle,
        ),
        const SizedBox(height: 24),
        Text('Mês a mês', style: context.text.titleMedium),
        _Table(
          headers: const [
            'Mês',
            'Cadastros',
            '1ª cobrança',
            'Cancel.',
            'Receita',
            'Investido',
            'CAC',
          ],
          rows: [
            for (final m in _list(data['months']).reversed)
              [
                _monthLabel('${m['month']}'),
                '${_int(m['signups'])}',
                '${_int(m['firstCharges'])}',
                '${_int(m['cancellations'])}',
                _money(m['revenueCents']),
                _money(m['spendCents']),
                _money(m['cacCents']),
              ],
          ],
        ),
        const SizedBox(height: 24),
        Text('Retenção por mês de cadastro', style: context.text.titleMedium),
        _Table(
          headers: const [
            'Safra',
            'Pessoas',
            'Mês 0',
            'Mês 1',
            'Mês 2',
            'Mês 3',
            'Mês 4',
            'Mês 5',
          ],
          rows: [
            for (final c in _list(data['cohorts']).reversed)
              [
                _monthLabel('${c['month']}'),
                '${_int(c['size'])}',
                for (final r in (c['retention'] as List? ?? const []))
                  r is num ? _pct(r) : '',
              ],
          ],
        ),
        Text(
          '% de quem abriu o app em cada mês depois do cadastro.',
          style: subtle,
        ),
        const SizedBox(height: 24),
        Text('Indicações', style: context.text.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${_int(refs['rewarded'])} recompensadas · '
          '${_int(refs['pending'])} aguardando a 1ª cobrança · '
          '${_int(refs['rejected'])} recusadas pelo antifraude',
        ),
        const SizedBox(height: 16),
        Text(
          'MRR pelo preço de cada plano (Básico ${_money((data['prices'] as Map?)?['basico'])}, '
          'Premium ${_money((data['prices'] as Map?)?['premium'])}); receita '
          'bruta informada pelas lojas, antes da taxa.',
          style: subtle,
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  final String title;
  final String value;
  final String hint;
  const _Kpi(this.title, this.value, this.hint, {super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.labelLarge),
            const SizedBox(height: 4),
            Text(value, style: context.text.headlineSmall),
            Text(
              hint,
              style: context.text.bodySmall?.copyWith(
                color: context.fin.subtle,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Table extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;
  const _Table({required this.headers, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Ainda sem dados.'),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 40,
        columns: [for (final h in headers) DataColumn(label: Text(h))],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                for (var i = 0; i < headers.length; i++)
                  DataCell(Text(i < r.length ? r[i] : '')),
              ],
            ),
        ],
      ),
    );
  }
}
