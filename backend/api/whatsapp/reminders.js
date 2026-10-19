// Lembretes diários pelo WhatsApp: contas e faturas que vencem hoje e
// amanhã, o que ficou em atraso e os orçamentos que chegaram no limite.
//
// O usuário liga cada aviso no app (Configurações › WhatsApp); as escolhas
// ficam nas preferências (`settings/app`: whatsappReminders e
// whatsappBudgetAlerts). Cada aviso é enviado uma única vez
// (tabela whatsapp_reminders_sent).

const { brl, todayIso } = require('./ledger');
const { computeSummary, invoiceForTx } = require('./summary');

const SEND_HOUR = 8; // horário de Brasília
const pad = (n) => String(n).padStart(2, '0');
const ym = (s) => s.slice(0, 7);

function addDays(s, days) {
  const [y, m, d] = s.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}

function closingDate(card, inv) {
  const [y, m] = inv.split('-').map(Number);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return `${inv}-${pad(Math.min(card.closingDay, last))}`;
}

/**
 * Gasto já realizado no mês por categoria raiz (visão de caixa
 * simplificada: lançamentos concluídos no mês e compras de faturas já
 * fechadas que vencem no mês).
 */
function realizedByRoot(docs, month, today) {
  const parent = new Map((docs.categories ?? []).map((c) => [c.id, c.parentId ?? null]));
  const root = (id) => (id && parent.get(id)) || id || null;
  const out = new Map();
  const add = (cat, cents) => {
    const r = root(cat);
    out.set(r, (out.get(r) ?? 0) + cents);
    if (r !== cat && cat) out.set(cat, (out.get(cat) ?? 0) + cents);
  };
  const cards = new Map((docs.cards ?? []).map((c) => [c.id, c]));
  for (const t of docs.transactions ?? []) {
    if (t.status === 'cancelled' || t.type === 'transfer') continue;
    const sign = t.type === 'income' ? -1 : 1;
    if (t.cardId) {
      const card = cards.get(t.cardId);
      if (!card) continue;
      const inv = invoiceForTx(card, t);
      if (closingDate(card, inv) > today) continue; // fatura ainda aberta
      const dueMonth = card.dueDay > card.closingDay ? inv : nextYm(inv);
      if (dueMonth !== month) continue;
      add(t.categoryId, sign * t.amount);
    } else if (t.type === 'expense' && t.status === 'completed' && ym(t.date) === month) {
      add(t.categoryId, t.amount);
    }
  }
  return out;
}

function nextYm(key) {
  const [y, m] = key.split('-').map(Number);
  const t = new Date(Date.UTC(y, m, 1));
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}`;
}

/**
 * Avisos do dia para um usuário.
 * @returns {{key: string, text: string}[]} cada aviso com sua chave única
 */
function buildReminders(docs, today, { bills = true, budgets = true } = {}) {
  const out = [];
  if (bills) {
    const s = computeSummary(docs, ym(today), today);
    const tomorrow = addDays(today, 1);
    const soon = s.upcoming.filter((u) => u.date <= tomorrow);
    if (soon.length || s.overdue.count) {
      const parts = soon.slice(0, 6).map(
        (u) => `${u.date === today ? 'hoje' : 'amanhã'} ${u.label} ${brl(u.amount)}`,
      );
      if (soon.length > 6) parts.push(`e mais ${soon.length - 6}`);
      if (s.overdue.count) {
        parts.push(`em atraso no mês: ${s.overdue.count} (${brl(s.overdue.total)})`);
      }
      out.push({ key: `bills:${today}`, text: `Contas a vencer: ${parts.join('; ')}.` });
    }
  }
  if (budgets && (docs.budgets ?? []).length) {
    const month = ym(today);
    const spent = realizedByRoot(docs, month, today);
    const names = new Map((docs.categories ?? []).map((c) => [c.id, c.name]));
    for (const b of docs.budgets) {
      if (!(b.amount > 0)) continue;
      const v = spent.get(b.categoryId) ?? 0;
      const pct = Math.floor((v * 100) / b.amount);
      const alert = b.alertPercent ?? 80;
      const level = pct >= 100 ? 100 : pct >= alert ? alert : null;
      if (level == null) continue;
      const name = names.get(b.categoryId) ?? 'categoria';
      out.push({
        key: `budget:${b.id}:${month}:${level}`,
        text: level >= 100
          ? `Orçamento de ${name} estourado: ${brl(v)} de ${brl(b.amount)} (${pct}%).`
          : `Orçamento de ${name} em ${pct}%: ${brl(v)} de ${brl(b.amount)}. Restam ${brl(b.amount - v)}.`,
      });
    }
  }
  return out;
}

/**
 * Tarefa que roda a cada [intervalMs] e envia os avisos do dia a partir das
 * 8h (Brasília). Idempotente: pode rodar em mais de uma instância.
 * @param {{pool: import('pg').Pool, getMeta: () => any, template?: string}} deps
 */
function createReminderJob({ pool, getMeta, template, now = () => new Date() }) {
  async function send(meta, to, text) {
    if (!template) return meta.sendText(to, text);
    // Fora da janela de 24h a Meta só entrega modelos aprovados. O parâmetro
    // não aceita quebras de linha.
    return meta.sendTemplate(to, template, [text.replace(/\s*\n+\s*/g, ' · ')]);
  }

  async function runOnce() {
    const meta = getMeta();
    if (!meta) return 0;
    const at = now();
    const hour = Number(
      new Intl.DateTimeFormat('en-GB', {
        timeZone: 'America/Sao_Paulo',
        hour: '2-digit',
        hour12: false,
      }).format(at),
    );
    if (hour < SEND_HOUR) return 0;
    const today = todayIso(at);
    const { rows: links } = await pool.query(
      `select l.wa_id, l.user_id, d.data as settings
         from whatsapp_links l
         join app_docs d on d.user_id = l.user_id and d.coll = 'settings'
                        and d.id = 'app' and not d.deleted
        where coalesce((d.data->>'whatsappReminders')::boolean, false)
           or coalesce((d.data->>'whatsappBudgetAlerts')::boolean, false)`,
    );
    let sent = 0;
    for (const link of links) {
      try {
        sent += await remindUser(meta, link, today);
      } catch (e) {
        console.error(`Lembretes: falha para ${link.user_id}`, e.message);
      }
    }
    return sent;
  }

  async function remindUser(meta, link, today) {
    const { rows } = await pool.query(
      `select coll, data from app_docs
        where user_id = $1 and not deleted
          and coll in ('transactions', 'recurringTransactions', 'cards',
                       'categories', 'invoicePayments', 'budgets')`,
      [link.user_id],
    );
    const docs = {};
    for (const r of rows) (docs[r.coll] ??= []).push(r.data);
    const items = buildReminders(docs, today, {
      bills: link.settings?.whatsappReminders === true,
      budgets: link.settings?.whatsappBudgetAlerts === true,
    });
    if (!items.length) return 0;
    const { rows: done } = await pool.query(
      'select key from whatsapp_reminders_sent where user_id = $1 and key = any($2)',
      [link.user_id, items.map((i) => i.key)],
    );
    const seen = new Set(done.map((r) => r.key));
    const fresh = items.filter((i) => !seen.has(i.key));
    if (!fresh.length) return 0;
    // Reserva as chaves antes de enviar: outra instância não repete.
    const { rows: claimed } = await pool.query(
      `insert into whatsapp_reminders_sent (user_id, key)
       select $1, unnest($2::text[]) on conflict do nothing returning key`,
      [link.user_id, fresh.map((i) => i.key)],
    );
    const mine = new Set(claimed.map((r) => r.key));
    const text = fresh.filter((i) => mine.has(i.key)).map((i) => i.text);
    if (!text.length) return 0;
    try {
      await send(meta, link.wa_id, `⏰ ${text.join('\n')}`);
    } catch (e) {
      // Não enviado: libera para tentar de novo na próxima rodada.
      await pool.query(
        'delete from whatsapp_reminders_sent where user_id = $1 and key = any($2)',
        [link.user_id, [...mine]],
      );
      throw e;
    }
    return 1;
  }

  return {
    runOnce,
    start(intervalMs = 10 * 60 * 1000) {
      const tick = () => runOnce().catch((e) => console.error('Lembretes:', e.message));
      setTimeout(tick, 30 * 1000).unref?.();
      setInterval(tick, intervalMs).unref?.();
    },
  };
}

module.exports = { buildReminders, createReminderJob, realizedByRoot };
