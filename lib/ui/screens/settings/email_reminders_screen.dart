import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../data/cloud/api_client.dart';
import '../../../data/cloud/cloud_auth_service.dart';
import '../../../data/web_env.dart';
import '../../../state/auth_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Preferências dos lembretes de fatura por e-mail (GET /email/reminders).
class EmailReminderPrefs {
  final bool enabled;
  final int daysBefore;
  final bool overdue;
  final String timeZone;
  final int sendHour;
  const EmailReminderPrefs({
    this.enabled = false,
    this.daysBefore = 3,
    this.overdue = true,
    this.timeZone = 'America/Sao_Paulo',
    this.sendHour = 8,
  });

  factory EmailReminderPrefs.fromJson(Map<String, Object?> j) =>
      EmailReminderPrefs(
        enabled: j['enabled'] == true,
        daysBefore: (j['daysBefore'] as num?)?.toInt() ?? 3,
        overdue: j['overdue'] != false,
        timeZone: (j['timeZone'] as String?) ?? 'America/Sao_Paulo',
        sendHour: (j['sendHour'] as num?)?.toInt() ?? 8,
      );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'daysBefore': daysBefore,
    'overdue': overdue,
    'timeZone': timeZone,
    'sendHour': sendHour,
  };

  EmailReminderPrefs copyWith({
    bool? enabled,
    int? daysBefore,
    bool? overdue,
    String? timeZone,
    int? sendHour,
  }) => EmailReminderPrefs(
    enabled: enabled ?? this.enabled,
    daysBefore: daysBefore ?? this.daysBefore,
    overdue: overdue ?? this.overdue,
    timeZone: timeZone ?? this.timeZone,
    sendHour: sendHour ?? this.sendHour,
  );
}

/// Aviso já enviado (os mais recentes).
class SentEmailReminder {
  final String cardId;
  final String invoiceKey;
  final String due;
  final String phase;
  final DateTime? sentAt;
  final int amount;
  const SentEmailReminder(
    this.cardId,
    this.invoiceKey,
    this.due,
    this.phase,
    this.sentAt,
    this.amount,
  );
}

class EmailReminderStatus {
  /// O servidor tem um provedor de e-mail configurado.
  final bool available;

  /// Provedor de teste: nada sai do servidor.
  final bool sandbox;
  final String email;
  final bool verified;
  final EmailReminderPrefs prefs;
  final List<SentEmailReminder> recent;
  const EmailReminderStatus({
    required this.available,
    required this.sandbox,
    required this.email,
    required this.verified,
    required this.prefs,
    this.recent = const [],
  });

  factory EmailReminderStatus.fromJson(Map<String, Object?> j) =>
      EmailReminderStatus(
        available: j['available'] == true,
        sandbox: j['sandbox'] == true,
        email: (j['email'] as String?) ?? '',
        verified: j['verified'] == true,
        prefs: EmailReminderPrefs.fromJson(
          (j['prefs'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
        recent: [
          for (final r in (j['recent'] as List? ?? const []))
            if (r is Map)
              SentEmailReminder(
                '${r['cardId']}',
                '${r['invoiceKey']}',
                '${r['due']}',
                '${r['phase']}',
                DateTime.tryParse('${r['sentAt']}')?.toLocal(),
                (r['amount'] as num?)?.toInt() ?? 0,
              ),
        ],
      );
}

/// Fusos oferecidos (Brasil primeiro). O padrão vem do fuso do aparelho.
const emailTimeZones = <String, String>{
  'America/Sao_Paulo': 'Brasília (UTC−3)',
  'America/Manaus': 'Amazonas, MT, MS, RO, RR (UTC−4)',
  'America/Rio_Branco': 'Acre (UTC−5)',
  'America/Noronha': 'Fernando de Noronha (UTC−2)',
  'Europe/Lisbon': 'Lisboa',
  'America/New_York': 'Nova York',
  'UTC': 'UTC',
};

/// Fuso do aparelho: o do navegador (IANA) ou o do Brasil que bate com o
/// deslocamento atual.
String deviceTimeZone([DateTime? now]) {
  final tz = now == null ? browserTimeZone() : null;
  if (tz != null) return tz;
  final h = (now ?? DateTime.now()).timeZoneOffset.inHours;
  return switch (h) {
    -2 => 'America/Noronha',
    -4 => 'America/Manaus',
    -5 => 'America/Rio_Branco',
    _ => 'America/Sao_Paulo',
  };
}

/// Configurações › Lembretes por e-mail: aviso das faturas de cartão em
/// aberto antes do vencimento (e, se quiser, depois de vencidas).
class EmailRemindersScreen extends StatefulWidget {
  /// Cliente da API (padrão: o da sessão na nuvem).
  final ApiClient? api;
  const EmailRemindersScreen({super.key, this.api});

  @override
  State<EmailRemindersScreen> createState() => _EmailRemindersScreenState();
}

class _EmailRemindersScreenState extends State<EmailRemindersScreen> {
  EmailReminderStatus? status;
  Object? error;
  bool busy = false;
  bool verifySent = false;

  ApiClient get api =>
      widget.api ??
      (context.read<AuthController>().service as CloudAuthService).api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final s = EmailReminderStatus.fromJson(await api.get('email/reminders'));
      if (mounted) setState(() => status = s);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> _save(EmailReminderPrefs p) async {
    setState(() => busy = true);
    await runAction(context, () async {
      final s = EmailReminderStatus.fromJson(
        await api.patch('email/reminders', p.toJson()),
      );
      if (mounted) setState(() => status = s);
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _sendVerify() async {
    setState(() => busy = true);
    await runAction(context, () async {
      await api.post('email/verify/send');
      if (mounted) setState(() => verifySent = true);
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    return Scaffold(
      appBar: AppBar(title: const Text('Lembretes por e-mail')),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$error', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
            )
          : s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Receba um e-mail quando uma fatura de cartão estiver para '
                    'vencer com saldo em aberto. Se você pagar uma parte, o '
                    'aviso mostra só o que falta; fatura quitada não gera aviso.',
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (!s.available)
                    const _Note(
                      icon: Icons.info_outline,
                      text:
                          'O envio de e-mails ainda não foi ligado no servidor. '
                          'Você já pode deixar tudo configurado.',
                    ),
                  if (s.sandbox)
                    const _Note(
                      icon: Icons.science_outlined,
                      text:
                          'Servidor em modo de teste: os e-mails são '
                          'registrados, mas não são entregues.',
                    ),
                  const SizedBox(height: 8),
                  ..._emailCard(s),
                  const SizedBox(height: 16),
                  ..._prefsCard(s),
                  if (s.recent.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Últimos avisos', style: context.text.titleSmall),
                    const SizedBox(height: 8),
                    for (final r in s.recent) _recentTile(r),
                  ],
                ],
              ),
            ),
    );
  }

  List<Widget> _emailCard(EmailReminderStatus s) => [
    Card(
      child: ListTile(
        key: const ValueKey('email-status'),
        leading: Icon(
          s.verified ? Icons.mark_email_read_outlined : Icons.email_outlined,
          color: s.verified ? context.fin.positive : null,
        ),
        title: Text(s.email),
        subtitle: Text(
          s.verified
              ? 'E-mail confirmado.'
              : verifySent
              ? 'Enviamos o link de confirmação. Abra o e-mail e toque em '
                    'Confirmar e-mail; depois volte aqui e atualize.'
              : 'Confirme o e-mail para receber os lembretes.',
        ),
        trailing: s.verified
            ? null
            : verifySent
            ? IconButton(
                tooltip: 'Atualizar',
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              )
            : null,
      ),
    ),
    if (!s.verified) ...[
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const ValueKey('email-verify'),
        icon: const Icon(Icons.send_outlined),
        label: Text(
          verifySent ? 'Enviar de novo' : 'Enviar e-mail de confirmação',
        ),
        onPressed: busy || !s.available ? null : _sendVerify,
      ),
    ],
  ];

  List<Widget> _prefsCard(EmailReminderStatus s) {
    final p = s.prefs;
    final zones = {
      ...emailTimeZones,
      if (!emailTimeZones.containsKey(p.timeZone)) p.timeZone: p.timeZone,
    };
    return [
      Card(
        child: Column(
          children: [
            SwitchListTile(
              key: const ValueKey('email-enabled'),
              title: const Text('Lembrete de fatura em aberto'),
              subtitle: Text(
                s.verified
                    ? 'Vale para as faturas dos cartões que você vê no app.'
                    : 'Disponível depois de confirmar o e-mail.',
              ),
              value: p.enabled,
              onChanged: busy || !s.verified
                  ? null
                  : (v) => _save(
                      p.copyWith(
                        enabled: v,
                        // 1ª vez: usa o fuso do aparelho.
                        timeZone: v && p.timeZone == 'America/Sao_Paulo'
                            ? deviceTimeZone()
                            : null,
                      ),
                    ),
            ),
            ListTile(
              title: const Text('Avisar antes do vencimento'),
              trailing: DropdownButton<int>(
                key: const ValueKey('email-days'),
                value: p.daysBefore,
                onChanged: busy
                    ? null
                    : (v) => _save(p.copyWith(daysBefore: v)),
                items: [
                  for (final d in const [0, 1, 2, 3, 5, 7, 10, 15])
                    DropdownMenuItem(
                      value: d,
                      child: Text(
                        d == 0
                            ? 'No dia'
                            : d == 1
                            ? '1 dia antes'
                            : '$d dias antes',
                      ),
                    ),
                  if (!const [0, 1, 2, 3, 5, 7, 10, 15].contains(p.daysBefore))
                    DropdownMenuItem(
                      value: p.daysBefore,
                      child: Text('${p.daysBefore} dias antes'),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              key: const ValueKey('email-overdue'),
              title: const Text('Avisar também se vencer sem pagar'),
              subtitle: const Text(
                'Um aviso depois do vencimento (até 5 dias), com o saldo que falta.',
              ),
              value: p.overdue,
              onChanged: busy ? null : (v) => _save(p.copyWith(overdue: v)),
            ),
            ListTile(
              title: const Text('Horário do envio'),
              trailing: DropdownButton<int>(
                key: const ValueKey('email-hour'),
                value: p.sendHour,
                onChanged: busy ? null : (v) => _save(p.copyWith(sendHour: v)),
                items: [
                  for (var h = 0; h < 24; h++)
                    DropdownMenuItem(
                      value: h,
                      child: Text('${h.toString().padLeft(2, '0')}:00'),
                    ),
                ],
              ),
            ),
            ListTile(
              title: const Text('Fuso horário'),
              subtitle: DropdownButton<String>(
                key: const ValueKey('email-tz'),
                isExpanded: true,
                value: p.timeZone,
                onChanged: busy ? null : (v) => _save(p.copyWith(timeZone: v)),
                items: [
                  for (final e in zones.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _recentTile(SentEmailReminder r) {
    final due = DateTime.tryParse(r.due);
    final sent = r.sentAt;
    return ListTile(
      dense: true,
      leading: Icon(
        r.phase == 'atraso' ? Icons.warning_amber_outlined : Icons.schedule,
      ),
      title: Text(
        '${r.phase == 'atraso' ? 'Atraso' : 'Vence'} '
        '${due == null ? r.due : Dates.format(due)} · '
        '${Money(r.amount).format()}',
      ),
      subtitle: sent == null
          ? null
          : Text(
              'Enviado em ${Dates.format(sent)} às '
              '${sent.hour.toString().padLeft(2, '0')}:${sent.minute.toString().padLeft(2, '0')}',
            ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Note({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.fin.subtle),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: context.text.bodyMedium)),
      ],
    ),
  );
}
