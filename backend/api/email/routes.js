// E-mail: confirmação do endereço e preferências dos lembretes de fatura
// (Configurações › Preferências › Lembretes por e-mail no app).

const jwt = require('jsonwebtoken');
const {
  createInvoiceEmailJob,
  validTimeZone,
  DEFAULT_APP_URL,
  DEFAULT_TIME_ZONE,
} = require('./invoice_reminders');

const VERIFY_DAYS = 3;
const RESEND_SECONDS = 60;

const esc = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

function page(title, body, appUrl) {
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title></head>
<body style="font-family:Arial,Helvetica,sans-serif;color:#1b2a4a;max-width:480px;margin:48px auto;padding:0 16px">
<h1 style="font-size:22px">${esc(title)}</h1><p>${esc(body)}</p>
<p><a href="${esc(appUrl)}" style="display:inline-block;background:#1b2a4a;color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none">Abrir o Finanças</a></p>
</body></html>`;
}

/**
 * @param {{email?: {transport?: object|null, appUrl?: string, publicUrl?: string,
 *   startJob?: boolean, now?: () => Date}}} deps
 */
function mountEmail(app, { pool, authed, wrap, HttpError, jwtSecret, email = {} }) {
  const transport = email.transport ?? null;
  const appUrl = email.appUrl || DEFAULT_APP_URL;
  const lastVerifySend = new Map();

  const job = createInvoiceEmailJob({ pool, transport, appUrl, now: email.now, onClaimed: email.onClaimed });
  app.locals.invoiceEmails = job;
  if (transport && email.startJob) job.start();

  const isVerified = (u) => !!u.email_verified && u.email_verified === u.email;

  async function prefsOf(userId) {
    const { rows } = await pool.query('select * from email_reminder_prefs where user_id = $1', [userId]);
    const p = rows[0];
    return {
      enabled: p?.enabled ?? false,
      daysBefore: p?.days_before ?? 3,
      overdue: p?.overdue ?? true,
      timeZone: p?.time_zone ?? DEFAULT_TIME_ZONE,
      sendHour: p?.send_hour ?? 8,
    };
  }

  async function status(user) {
    const { rows } = await pool.query(
      `select key, sent_at, amount from email_reminders_sent
        where user_id = $1 and status = 'sent' order by sent_at desc limit 5`,
      [user.id],
    );
    return {
      available: !!transport,
      sandbox: !!transport?.sandbox,
      email: user.email,
      verified: isVerified(user),
      prefs: await prefsOf(user.id),
      recent: rows.map((r) => {
        const [, cardId, invoiceKey, due, phase] = r.key.split(':');
        return { cardId, invoiceKey, due, phase, sentAt: r.sent_at, amount: Number(r.amount ?? 0) };
      }),
    };
  }

  app.get('/email/reminders', authed, wrap(async (req, res) => {
    res.json(await status(req.user));
  }));

  app.patch('/email/reminders', authed, wrap(async (req, res) => {
    const b = req.body ?? {};
    const cur = await prefsOf(req.user.id);
    const next = {
      enabled: b.enabled ?? cur.enabled,
      daysBefore: b.daysBefore ?? cur.daysBefore,
      overdue: b.overdue ?? cur.overdue,
      timeZone: b.timeZone ?? cur.timeZone,
      sendHour: b.sendHour ?? cur.sendHour,
    };
    if (typeof next.enabled !== 'boolean' || typeof next.overdue !== 'boolean') {
      throw new HttpError(400, 'Valor inválido');
    }
    if (!Number.isInteger(next.daysBefore) || next.daysBefore < 0 || next.daysBefore > 15) {
      throw new HttpError(400, 'Escolha de 0 a 15 dias antes do vencimento.');
    }
    if (!Number.isInteger(next.sendHour) || next.sendHour < 0 || next.sendHour > 23) {
      throw new HttpError(400, 'Hora inválida');
    }
    if (!validTimeZone(next.timeZone)) throw new HttpError(400, 'Fuso horário inválido');
    if (next.enabled && !isVerified(req.user)) {
      throw new HttpError(400, 'Confirme seu e-mail antes de ligar os lembretes.');
    }
    await pool.query(
      `insert into email_reminder_prefs (user_id, enabled, days_before, overdue, time_zone, send_hour)
       values ($1, $2, $3, $4, $5, $6)
       on conflict (user_id) do update set enabled = $2, days_before = $3, overdue = $4,
         time_zone = $5, send_hour = $6, updated_at = now()`,
      [req.user.id, next.enabled, next.daysBefore, next.overdue, next.timeZone, next.sendHour],
    );
    res.json(await status(req.user));
  }));

  /// Manda o link de confirmação para o e-mail da conta.
  app.post('/email/verify/send', authed, wrap(async (req, res) => {
    if (!transport) throw new HttpError(503, 'O envio de e-mails ainda não está ligado no servidor.');
    if (isVerified(req.user)) return res.json({ sent: false, verified: true });
    const last = lastVerifySend.get(req.user.id) ?? 0;
    if (Date.now() - last < RESEND_SECONDS * 1000) {
      throw new HttpError(429, 'Aguarde um minuto para pedir outro e-mail.');
    }
    lastVerifySend.set(req.user.id, Date.now());
    const token = jwt.sign({ sub: req.user.id, email: req.user.email, p: 'verify-email' }, jwtSecret, {
      algorithm: 'HS256',
      expiresIn: `${VERIFY_DAYS}d`,
    });
    const base = email.publicUrl || `${req.protocol}://${req.get('host')}`;
    const link = `${base.replace(/\/$/, '')}/email/verify?token=${encodeURIComponent(token)}`;
    const first = String(req.user.name ?? '').split(/\s+/)[0];
    try {
      await transport.send({
        to: req.user.email,
        subject: 'Confirme seu e-mail no Finanças',
        text: [
          first ? `Olá, ${first}!` : 'Olá!',
          '',
          'Para receber os lembretes de fatura por e-mail, confirme este endereço:',
          link,
          '',
          `O link vale por ${VERIFY_DAYS} dias. Se não foi você que pediu, ignore esta mensagem.`,
        ].join('\n'),
        html: `<p>${esc(first ? `Olá, ${first}!` : 'Olá!')}</p>
<p>Para receber os lembretes de fatura por e-mail, confirme este endereço:</p>
<p><a href="${esc(link)}" style="display:inline-block;background:#1b2a4a;color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none">Confirmar e-mail</a></p>
<p style="color:#777;font-size:12px">O link vale por ${VERIFY_DAYS} dias. Se não foi você que pediu, ignore esta mensagem.</p>`,
      });
    } catch (e) {
      lastVerifySend.delete(req.user.id);
      console.error('E-mail de confirmação:', e.message);
      throw new HttpError(502, 'Não consegui enviar o e-mail agora. Tente de novo mais tarde.');
    }
    res.json({ sent: true, sandbox: !!transport.sandbox });
  }));

  /// Link do e-mail de confirmação (abre no navegador, sem login).
  app.get('/email/verify', wrap(async (req, res) => {
    res.type('html');
    let claims;
    try {
      claims = jwt.verify(String(req.query.token ?? ''), jwtSecret, { algorithms: ['HS256'] });
    } catch {
      claims = null;
    }
    if (!claims || claims.p !== 'verify-email') {
      return res.status(400).send(page('Link inválido ou vencido', 'Peça um novo e-mail de confirmação no app, em Configurações › Preferências › Lembretes por e-mail.', appUrl));
    }
    const { rowCount } = await pool.query(
      `update users set email_verified = email, email_verified_at = now()
        where id = $1 and email = $2`,
      [claims.sub, claims.email],
    );
    if (!rowCount) {
      return res.status(400).send(page('Link inválido', 'O e-mail da conta mudou depois deste pedido. Peça uma nova confirmação no app.', appUrl));
    }
    res.send(page('E-mail confirmado', `Pronto! ${claims.email} vai receber os lembretes de fatura que você ligar no app.`, appUrl));
  }));

  return job;
}

module.exports = { mountEmail };
