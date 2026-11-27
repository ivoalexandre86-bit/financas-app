// Lembretes por e-mail de faturas de cartão com saldo em aberto.
//
// Cada pessoa liga os lembretes para si (tabela email_reminder_prefs): quantos
// dias antes do vencimento avisar, se avisa também depois de vencida, o fuso
// horário e a hora do envio. Só recebe quem confirmou o e-mail, e só as
// faturas dos cartões que enxerga no orçamento (acesso limitado: ver
// doc_visible em schema.sql).
//
// O saldo segue as regras do app (whatsapp/summary.js → buildInvoices):
// total das compras da fatura menos os pagamentos; pagamento parcial deixa o
// restante; fatura quitada não gera aviso.
//
// Envio sem repetição: cada aviso tem uma chave (cartão, fatura, vencimento,
// fase) reservada na tabela email_reminders_sent antes do envio. Logo antes
// de enviar, o servidor confere de novo o saldo e o acesso da pessoa; se a
// fatura foi paga ou o acesso mudou, o aviso é descartado.

const crypto = require('crypto');
const { brl, brDate } = require('../whatsapp/ledger');
const { expand, buildInvoices } = require('../whatsapp/summary');

const DEFAULT_APP_URL = 'https://ivoalexandre86-bit.github.io/financas-app/';
const DEFAULT_TIME_ZONE = 'America/Sao_Paulo';
/** Dias depois do vencimento em que o aviso de atraso ainda é enviado. */
const OVERDUE_WINDOW_DAYS = 5;
/** Reserva de envio abandonada (servidor caiu no meio) pode ser retomada. */
const STALE_CLAIM_MINUTES = 30;

const pad = (n) => String(n).padStart(2, '0');

function addDays(s, days) {
  const [y, m, d] = s.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}

const daysBetween = (a, b) =>
  Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 864e5);

function validTimeZone(tz) {
  if (!tz || typeof tz !== 'string' || tz.length > 64) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** Data (AAAA-MM-DD) e hora local de [at] no fuso [tz]. */
function localNow(at, tz) {
  const f = new Intl.DateTimeFormat('en-CA', {
    timeZone: validTimeZone(tz) ? tz : DEFAULT_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    hourCycle: 'h23',
  });
  const p = Object.fromEntries(f.formatToParts(at).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, hour: Number(p.hour) % 24 };
}

/** Apelido do cartão com os 4 últimos dígitos mascarados. */
function cardLabel(card) {
  const name = String(card.name ?? '').trim() || 'Cartão';
  const last = String(card.lastFour ?? '').replace(/\D/g, '').slice(-4);
  return last ? `${name} •••• ${last}` : name;
}

/**
 * Avisos de fatura para hoje ([today] na data local da pessoa).
 * @param {Record<string, any[]>} docs documentos que a pessoa enxerga
 * @param {{daysBefore: number, overdue: boolean}} prefs
 * @returns {{key: string, phase: 'antes'|'atraso', cardId: string,
 *   invoiceKey: string, due: string, total: number, paid: number,
 *   remaining: number, label: string, daysLeft: number}[]}
 */
function buildInvoiceReminders(docs, today, { daysBefore = 3, overdue = true } = {}) {
  const [y, m] = today.split('-').map(Number);
  // Faturas que vencem até daysBefore dias à frente: compras e recorrências
  // até o fim do 3º mês seguinte cobrem qualquer ciclo de cartão.
  const until = new Date(Date.UTC(y, m + 3, 0)).toISOString().slice(0, 10);
  const all = expand(docs, until);
  const out = [];
  for (const inv of buildInvoices(docs, all)) {
    if (inv.card.active === false || inv.isEmpty) continue;
    const remaining = inv.total - inv.paid;
    if (remaining <= 0) continue;
    const daysLeft = daysBetween(today, inv.due);
    let phase = null;
    if (daysLeft >= 0 && daysLeft <= daysBefore) phase = 'antes';
    else if (overdue && daysLeft < 0 && -daysLeft <= OVERDUE_WINDOW_DAYS) phase = 'atraso';
    if (!phase) continue;
    out.push({
      key: `fatura:${inv.card.id}:${inv.key}:${inv.due}:${phase}`,
      phase,
      cardId: inv.card.id,
      invoiceKey: inv.key,
      due: inv.due,
      total: inv.total,
      paid: inv.paid,
      remaining,
      label: cardLabel(inv.card),
      daysLeft,
    });
  }
  return out.sort((a, b) => a.due.localeCompare(b.due) || a.key.localeCompare(b.key));
}

const esc = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

/** Link que abre a fatura no app (pede login se a sessão não estiver aberta). */
function invoiceLink(appUrl, item) {
  const u = new URL(appUrl || DEFAULT_APP_URL);
  u.searchParams.set('fatura', item.cardId);
  u.searchParams.set('mes', item.invoiceKey);
  return u.toString();
}

/** Assunto, texto e HTML do e-mail (pt-BR, R$ e dd/mm/aaaa). */
function renderInvoiceEmail(item, { name, appUrl } = {}) {
  const due = brDate(item.due);
  const when =
    item.phase === 'atraso'
      ? `venceu em ${due} e ainda está em aberto`
      : item.daysLeft === 0
        ? `vence hoje (${due})`
        : item.daysLeft === 1
          ? `vence amanhã (${due})`
          : `vence em ${item.daysLeft} dias (${due})`;
  const subject =
    item.phase === 'atraso'
      ? `Fatura ${item.label} em atraso: ${brl(item.remaining)}`
      : `Fatura ${item.label} ${when.replace(/ \(.*\)$/, '')}: ${brl(item.remaining)}`;
  const partial = item.paid > 0
    ? `Já foram pagos ${brl(item.paid)} de ${brl(item.total)}. Falta pagar ${brl(item.remaining)}.`
    : null;
  const link = invoiceLink(appUrl, item);
  const hello = name ? `Olá, ${String(name).split(/\s+/)[0]}!` : 'Olá!';
  const footer =
    'Você recebe este aviso porque ligou os lembretes de fatura por e-mail no app ' +
    '(Configurações › Preferências › Lembretes por e-mail). Para parar, desligue por lá.';
  const text = [
    hello,
    '',
    `A fatura do cartão ${item.label} ${when}.`,
    `Valor em aberto: ${brl(item.remaining)}`,
    `Vencimento: ${due}`,
    ...(partial ? [partial] : []),
    '',
    `Abrir a fatura no app: ${link}`,
    '',
    footer,
  ].join('\n');
  const html = `<!doctype html><html lang="pt-BR"><body style="font-family:Arial,Helvetica,sans-serif;color:#1b2a4a;max-width:520px">
<p>${esc(hello)}</p>
<p>A fatura do cartão <b>${esc(item.label)}</b> ${esc(when)}.</p>
<table style="border-collapse:collapse;margin:12px 0">
<tr><td style="padding:4px 12px 4px 0">Valor em aberto</td><td style="padding:4px 0"><b>${esc(brl(item.remaining))}</b></td></tr>
<tr><td style="padding:4px 12px 4px 0">Vencimento</td><td style="padding:4px 0">${esc(due)}</td></tr>
${partial ? `<tr><td colspan="2" style="padding:4px 0;color:#555">${esc(partial)}</td></tr>` : ''}
</table>
<p><a href="${esc(link)}" style="display:inline-block;background:#1b2a4a;color:#fff;padding:10px 16px;border-radius:6px;text-decoration:none">Abrir a fatura no app</a></p>
<p style="color:#777;font-size:12px">${esc(footer)}</p>
</body></html>`;
  return { subject, text, html, link };
}

/**
 * Tarefa que roda a cada [intervalMs] e manda os lembretes do dia de cada
 * pessoa a partir da hora escolhida, no fuso dela. Pode rodar em mais de uma
 * instância e quantas vezes for preciso: cada aviso sai uma única vez.
 * @param {{pool: import('pg').Pool, transport: {send: Function, name: string},
 *   appUrl?: string, now?: () => Date, onClaimed?: Function}} deps
 *   `onClaimed(userId, key)`: chamado depois da reserva e antes da
 *   conferência final (testes simulam pagamento ou perda de acesso).
 */
function createInvoiceEmailJob({ pool, transport, appUrl, now = () => new Date(), onClaimed }) {
  async function recipients() {
    const { rows } = await pool.query(
      `select u.id, u.email, u.name, p.days_before, p.overdue, p.time_zone, p.send_hour
         from email_reminder_prefs p join users u on u.id = p.user_id
        where p.enabled and u.email_verified = u.email`,
    );
    return rows;
  }

  async function recipient(userId) {
    const { rows } = await pool.query(
      `select u.id, u.email, u.name, p.days_before, p.overdue, p.time_zone, p.send_hour
         from email_reminder_prefs p join users u on u.id = p.user_id
        where u.id = $1 and p.enabled and u.email_verified = u.email`,
      [userId],
    );
    return rows[0] ?? null;
  }

  /// Cartões, compras e pagamentos que a pessoa enxerga agora.
  async function visibleDocs(userId) {
    const { rows } = await pool.query(
      `select coll, data from app_docs
        where user_id = data_owner($1) and not deleted and doc_visible($1, coll, id, data)
          and coll in ('transactions', 'recurringTransactions', 'cards', 'invoicePayments')`,
      [userId],
    );
    const docs = {};
    for (const r of rows) (docs[r.coll] ??= []).push(r.data);
    return docs;
  }

  const prefsOf = (r) => ({ daysBefore: r.days_before, overdue: r.overdue });

  async function itemsFor(r, today) {
    return buildInvoiceReminders(await visibleDocs(r.id), today, prefsOf(r));
  }

  const idempotencyKey = (userId, key) =>
    crypto.createHash('sha256').update(`${userId}|${key}`).digest('hex').slice(0, 40);

  async function claim(userId, key) {
    const { rows } = await pool.query(
      `insert into email_reminders_sent (user_id, key) values ($1, $2)
       on conflict (user_id, key) do update
         set claimed_at = now(), attempts = email_reminders_sent.attempts + 1
         where email_reminders_sent.status = 'sending'
           and email_reminders_sent.claimed_at < now() - make_interval(mins => $3)
       returning key`,
      [userId, key, STALE_CLAIM_MINUTES],
    );
    return rows.length > 0;
  }

  const release = (userId, key) =>
    pool.query(
      `delete from email_reminders_sent where user_id = $1 and key = $2 and status = 'sending'`,
      [userId, key],
    );

  /**
   * Uma rodada. Retorna quantos e-mails saíram, quantos foram descartados na
   * conferência final e quantos falharam (tentam de novo na próxima rodada).
   */
  async function runOnce() {
    const stats = { sent: 0, suppressed: 0, failed: 0 };
    if (!transport) return stats;
    const at = now();
    for (const r of await recipients()) {
      try {
        const local = localNow(at, r.time_zone);
        if (local.hour < r.send_hour) continue;
        const items = await itemsFor(r, local.date);
        if (!items.length) continue;
        const { rows: done } = await pool.query(
          `select key from email_reminders_sent where user_id = $1 and key = any($2) and status = 'sent'`,
          [r.id, items.map((i) => i.key)],
        );
        const seen = new Set(done.map((d) => d.key));
        for (const item of items) {
          if (seen.has(item.key)) continue;
          if (!(await claim(r.id, item.key))) continue;
          try {
            await onClaimed?.(r.id, item.key);
            // Conferência final: e-mail confirmado, lembretes ligados, acesso
            // ao cartão e saldo em aberto, tudo lido de novo agora.
            const fresh = await recipient(r.id);
            const current = fresh
              ? (await itemsFor(fresh, localNow(now(), fresh.time_zone).date)).find((i) => i.key === item.key)
              : null;
            if (!current) {
              await release(r.id, item.key);
              stats.suppressed++;
              continue;
            }
            const msg = renderInvoiceEmail(current, { name: fresh.name, appUrl });
            const res = await transport.send({
              to: fresh.email,
              subject: msg.subject,
              text: msg.text,
              html: msg.html,
              idempotencyKey: idempotencyKey(r.id, item.key),
            });
            await pool.query(
              `update email_reminders_sent
                  set status = 'sent', sent_at = now(), email = $3, amount = $4, provider_id = $5
                where user_id = $1 and key = $2`,
              [r.id, item.key, fresh.email, current.remaining, res?.id ?? null],
            );
            stats.sent++;
          } catch (e) {
            await release(r.id, item.key).catch(() => {});
            stats.failed++;
            console.error(`Lembrete de fatura por e-mail: falha (${transport.name})`, e.message);
          }
        }
      } catch (e) {
        stats.failed++;
        console.error('Lembretes de fatura por e-mail:', e.message);
      }
    }
    return stats;
  }

  return {
    runOnce,
    start(intervalMs = 10 * 60 * 1000) {
      const tick = () => runOnce().catch((e) => console.error('Lembretes por e-mail:', e.message));
      setTimeout(tick, 45 * 1000).unref?.();
      setInterval(tick, intervalMs).unref?.();
    },
  };
}

module.exports = {
  buildInvoiceReminders,
  renderInvoiceEmail,
  createInvoiceEmailJob,
  invoiceLink,
  cardLabel,
  localNow,
  validTimeZone,
  DEFAULT_APP_URL,
  DEFAULT_TIME_ZONE,
  OVERDUE_WINDOW_DAYS,
};
