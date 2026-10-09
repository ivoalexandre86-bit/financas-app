// Resumo financeiro pelo WhatsApp ("resumo", "resumo mês passado"…).
//
// Segue as regras do app (lib/domain/engine): recorrências viram ocorrências
// virtuais deduplicadas pelas já gravadas; transferências não contam; compras
// no cartão entram no mês em que a fatura vence (visão de caixa) e a parcela N
// cai N − 1 faturas depois da compra; pagamento de fatura não é despesa.

const { addMonths, brl } = require('./ledger');

const MONTHS = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];
const UPCOMING_DAYS = 7;
const MAX_LIST = 6;

// Datas ISO (AAAA-MM-DD) ------------------------------------------------------

const pad = (n) => String(n).padStart(2, '0');
const iso = (y, m, d) => `${y}-${pad(m)}-${pad(d)}`;
const parts = (s) => s.split('-').map(Number);
const ym = (s) => s.slice(0, 7);
const lastDay = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();
const clamped = (y, m, d) => iso(y, m, Math.min(d, lastDay(y, m)));
const brDate = (s) => `${s.slice(8, 10)}/${s.slice(5, 7)}`;

function addDays(s, days) {
  const [y, m, d] = parts(s);
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return iso(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
}

/// Mês "AAAA-MM" somado de n meses.
function addYm(key, n) {
  const [y, m] = parts(key);
  const t = new Date(Date.UTC(y, m - 1 + n, 1));
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}`;
}

// Recorrências (lib/domain/engine/recurrence.dart) -----------------------------

function step(r) {
  const n = Math.max(1, r.interval ?? 1);
  switch (r.frequency) {
    case 'weekly': return [0, 7];
    case 'quarterly': return [3, 0];
    case 'yearly': return [12, 0];
    case 'custom':
      if (r.unit === 'days') return [0, n];
      if (r.unit === 'weeks') return [0, 7 * n];
      return [n, 0];
    default: return [1, 0];
  }
}

function firstOccurrence(r) {
  const start = r.startDate;
  const [months] = step(r);
  if (months > 0 && r.dayOfMonth != null) {
    const [y, m] = parts(start);
    const candidate = clamped(y, m, r.dayOfMonth);
    if (candidate < start) {
      const [ny, nm] = parts(addYm(ym(start), 1));
      return clamped(ny, nm, r.dayOfMonth);
    }
    return candidate;
  }
  return start;
}

const paused = (r, d) =>
  (r.pauses ?? []).some((p) => d >= p.from && (p.to == null || d < p.to));

/// Ocorrências da regra até [to] (inclusive).
function occurrences(r, to) {
  if (!r.startDate) return [];
  const first = firstOccurrence(r);
  const end = r.endDate && r.endDate < to ? r.endDate : to;
  const out = [];
  const [months, days] = step(r);
  const anchor = r.dayOfMonth ?? parts(first)[2];
  for (let k = 0; k < 5000; k++) {
    let d;
    if (months > 0) {
      const [y, m] = parts(addYm(ym(first), k * months));
      d = clamped(y, m, anchor);
    } else {
      d = addDays(first, k * days);
    }
    if (d > end) break;
    if (!paused(r, d)) out.push(d);
  }
  return out;
}

// Cartões (lib/domain/engine/billing_cycle.dart) -------------------------------

const closingDate = (card, inv) => {
  const [y, m] = parts(inv);
  return clamped(y, m, card.closingDay);
};

function invoiceDue(card, inv) {
  const dueMonth = card.dueDay > card.closingDay ? inv : addYm(inv, 1);
  const [y, m] = parts(dueMonth);
  return clamped(y, m, card.dueDay);
}

function invoiceForTx(card, t) {
  const inv = t.date < closingDate(card, ym(t.date)) ? ym(t.date) : addYm(ym(t.date), 1);
  const n = t.installmentGroupId ? t.installmentNumber ?? 1 : 1;
  return n > 1 ? addYm(inv, n - 1) : inv;
}

// Resumo -------------------------------------------------------------------------

/**
 * Lançamentos gravados + ocorrências virtuais de recorrências até [until].
 */
function expand(docs, until) {
  const txs = docs.transactions ?? [];
  const done = new Set(
    txs.filter((t) => t.recurringId && t.occurrenceDate)
      .map((t) => `${t.recurringId}|${t.occurrenceDate}`),
  );
  const out = [...txs];
  for (const r of docs.recurringTransactions ?? []) {
    for (const d of occurrences(r, until)) {
      if (done.has(`${r.id}|${d}`)) continue;
      const offset = r.dueOffsetDays ?? 0;
      out.push({
        id: `v:${r.id}:${d}`,
        type: r.type,
        amount: r.amount,
        description: r.description,
        categoryId: r.categoryId,
        date: d,
        accountId: r.accountId,
        cardId: r.cardId,
        status: 'planned',
        dueDate: offset && r.type === 'expense' && !r.cardId ? addDays(d, offset) : null,
      });
    }
  }
  return out.filter((t) => t.status !== 'cancelled' && t.type !== 'transfer');
}

/**
 * Números do mês [month] ("AAAA-MM") na visão de caixa.
 * @param {Record<string, any[]>} docs documentos do usuário por coleção
 */
function computeSummary(docs, month, today) {
  const [y, m] = parts(month);
  const monthEnd = iso(y, m, lastDay(y, m));
  const soon = addDays(today, UPCOMING_DAYS);
  // Horizonte para cobrir faturas que vencem no mês e os próximos dias.
  const horizon = [monthEnd, soon].sort()[1];
  const all = expand(docs, addMonths(horizon, 1));
  const cards = (docs.cards ?? []).filter((c) => c.active !== false);
  const catName = new Map((docs.categories ?? []).map((c) => [c.id, c.name]));

  const s = {
    month,
    income: { done: 0, open: 0 },
    expense: { done: 0, open: 0 },
    invoices: [],
    byCategory: new Map(),
    upcoming: [],
    overdue: { count: 0, total: 0 },
  };
  const addCat = (id, cents) =>
    s.byCategory.set(id ?? null, (s.byCategory.get(id ?? null) ?? 0) + cents);

  for (const t of all) {
    if (t.cardId) continue;
    const isIncome = t.type === 'income';
    const paid = t.status === 'completed';
    if (ym(t.date) === month) {
      const bucket = isIncome ? s.income : s.expense;
      bucket[paid ? 'done' : 'open'] += t.amount;
      if (!isIncome) addCat(t.categoryId, t.amount);
    }
    if (isIncome || paid) continue;
    const due = t.dueDate ?? t.date;
    if (due < today) {
      if (ym(due) !== ym(today)) continue; // como na tela inicial: só o mês
      s.overdue.count++;
      s.overdue.total += t.amount;
    } else if (due <= soon) {
      s.upcoming.push({ date: due, label: t.description, amount: t.amount });
    }
  }

  for (const card of cards) {
    const byInv = new Map();
    for (const t of all) {
      if (t.cardId !== card.id) continue;
      const inv = invoiceForTx(card, t);
      const list = byInv.get(inv) ?? [];
      list.push(t);
      byInv.set(inv, list);
    }
    const paidBy = new Map();
    for (const p of docs.invoicePayments ?? []) {
      if (p.cardId !== card.id) continue;
      paidBy.set(p.invoiceKey, (paidBy.get(p.invoiceKey) ?? 0) + p.amount);
    }
    for (const inv of new Set([...byInv.keys(), ...paidBy.keys()])) {
      const due = invoiceDue(card, inv);
      const txs = byInv.get(inv) ?? [];
      const total = txs.reduce((a, t) => a + (t.type === 'income' ? -t.amount : t.amount), 0);
      const remaining = total - (paidBy.get(inv) ?? 0);
      if (ym(due) === month && total > 0) {
        s.invoices.push({ card: card.name, due, total, remaining });
        for (const t of txs) {
          addCat(t.categoryId, t.type === 'income' ? -t.amount : t.amount);
        }
      }
      if (remaining <= 0) continue;
      if (due < today) {
        if (ym(due) !== ym(today)) continue;
        s.overdue.count++;
        s.overdue.total += remaining;
      } else if (due <= soon) {
        s.upcoming.push({ date: due, label: `Fatura ${card.name}`, amount: remaining });
      }
    }
  }

  s.invoices.sort((a, b) => a.due.localeCompare(b.due));
  s.upcoming.sort((a, b) => a.date.localeCompare(b.date) || b.amount - a.amount);
  s.topCategories = [...s.byCategory.entries()]
    .filter(([, v]) => v > 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([id, v]) => ({ name: catName.get(id) ?? 'Sem categoria', amount: v }));
  return s;
}

/// Texto do resumo para o WhatsApp.
function formatMonthSummary(s, today) {
  const [y, m] = parts(s.month);
  const current = s.month === ym(today);
  const invTotal = s.invoices.reduce((a, i) => a + i.total, 0);
  const incomes = s.income.done + s.income.open;
  const expenses = s.expense.done + s.expense.open + invTotal;
  const result = incomes - expenses;
  const lines = [
    `📊 *Resumo de ${MONTHS[m - 1]}/${y}*`,
    '',
    `💰 Receitas: *${brl(incomes)}*`,
    `   ${brl(s.income.done)} recebidas · ${brl(s.income.open)} a receber`,
    `💸 Despesas: *${brl(expenses)}*`,
    `   ${brl(s.expense.done)} pagas · ${brl(s.expense.open)} a pagar` +
      (invTotal ? ` · ${brl(invTotal)} em faturas` : ''),
    `${result >= 0 ? '🟢' : '🔴'} Resultado previsto: *${brl(result)}*`,
  ];
  if (s.invoices.length) {
    lines.push('', '💳 Faturas do mês:');
    for (const i of s.invoices) {
      const state = i.remaining <= 0 ? 'paga ✅' : i.remaining < i.total ? `falta ${brl(i.remaining)}` : 'em aberto';
      lines.push(`• ${i.card}: ${brl(i.total)}, vence ${brDate(i.due)} (${state})`);
    }
  }
  if (s.topCategories.length) {
    lines.push('', '🏷️ Onde mais gastou:');
    for (const c of s.topCategories) lines.push(`• ${c.name}: ${brl(c.amount)}`);
  }
  if (current) {
    lines.push('', `⏰ Próximos ${UPCOMING_DAYS} dias:`);
    if (!s.upcoming.length) lines.push('• Nada a vencer 🙌');
    for (const u of s.upcoming.slice(0, MAX_LIST)) {
      lines.push(`• ${brDate(u.date)} ${u.label}: ${brl(u.amount)}`);
    }
    if (s.upcoming.length > MAX_LIST) lines.push(`• e mais ${s.upcoming.length - MAX_LIST}`);
    if (s.overdue.count) {
      lines.push(`⚠️ Em atraso neste mês: ${s.overdue.count} (${brl(s.overdue.total)})`);
    }
  }
  return lines.join('\n');
}

/**
 * Lê um pedido de resumo. Retorna o mês ("AAAA-MM") ou null se a mensagem
 * não for um pedido de resumo.
 */
function parseSummaryRequest(text, today) {
  const t = String(text ?? '').trim().toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '');
  const mm = /^(resumo|extrato|relatorio|balanco)\b\s*(.*)$/.exec(t);
  if (!mm) return null;
  const rest = mm[2].replace(/^(do|de|da)\s+/, '').replace(/[?.!]+$/, '').trim();
  const now = ym(today);
  if (!rest || /^(mes|mes atual|este mes|esse mes|hoje|atual)$/.test(rest)) return now;
  if (/^(mes )?(passado|anterior)$/.test(rest)) return addYm(now, -1);
  if (/^(proximo( mes)?|mes que vem)$/.test(rest)) return addYm(now, 1);
  const names = MONTHS.map((n) => n.normalize('NFD').replace(/[̀-ͯ]/g, ''));
  const named = /^([a-z]+)(?:\s*(?:de|\/)?\s*(\d{4}))?$/.exec(rest);
  const idx = named ? names.findIndex((n) => n === named[1] || n.slice(0, 3) === named[1]) : -1;
  if (idx >= 0) {
    const year = named[2] ? Number(named[2]) : Number(now.slice(0, 4));
    return `${year}-${pad(idx + 1)}`;
  }
  const num = /^(\d{1,2})\/(\d{4})$/.exec(rest);
  if (num && +num[1] >= 1 && +num[1] <= 12) return `${num[2]}-${pad(+num[1])}`;
  return now;
}

module.exports = {
  computeSummary,
  formatMonthSummary,
  parseSummaryRequest,
  occurrences,
  invoiceDue,
  invoiceForTx,
};
