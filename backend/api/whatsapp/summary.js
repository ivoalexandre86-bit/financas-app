// Resumo financeiro pelo WhatsApp ("resumo", "resumo mês passado"…).
//
// Segue as regras do app (lib/domain/engine): recorrências viram ocorrências
// virtuais deduplicadas pelas já gravadas; transferências não contam; compras
// no cartão entram no mês em que a fatura é paga (o saldo em aberto, no
// vencimento; pagamento em partes divide as compras proporcionalmente) e a
// parcela N cai N − 1 faturas depois da compra; pagamento de fatura não é
// despesa; o que não foi concluído em conta/cartão inativo fica fora; mês
// fechado ou ajustado no app usa os valores do fechamento. Ou seja: os mesmos
// números da Projeção do app sem filtros.

const { brl } = require('./ledger');

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

// Regime de caixa (lib/domain/engine/financial_engine.dart) ---------------------

/// Arredonda como o Dart (metade para longe do zero).
const roundAway = (x) => Math.sign(x) * Math.round(Math.abs(x));
const signedOf = (t) => (t.type === 'income' ? -t.amount : t.amount);

/**
 * Partes da fatura por mês de caixa: cada pagamento no mês em que foi feito;
 * o saldo em aberto no mês do vencimento (Invoice._buildSlices).
 */
function invoiceSlices(total, payments, due) {
  if (total <= 0) {
    const settled = payments.length > 0;
    const date = settled ? payments.map((p) => p.date).sort().at(-1) : due;
    return [{ month: ym(date), date, amount: total, settled }];
  }
  const sorted = [...payments].sort((a, b) => a.date.localeCompare(b.date));
  const out = [];
  const byMonth = new Map();
  let left = total;
  for (const p of sorted) {
    if (left <= 0) break;
    const a = Math.min(p.amount, left);
    if (a <= 0) continue;
    left -= a;
    const m = ym(p.date);
    const prev = byMonth.get(m);
    const s = { month: m, date: p.date, amount: (prev?.amount ?? 0) + a, settled: true };
    if (prev) out.splice(out.indexOf(prev), 1);
    byMonth.set(m, s);
    out.push(s);
  }
  if (left > 0) out.push({ month: ym(due), date: due, amount: left, settled: false });
  return out;
}

/// Divide cada compra entre as partes da fatura (Invoice._buildShares).
function invoiceShares(txs, total, sl) {
  const out = new Map();
  if (sl.length === 1 || total === 0) {
    for (const t of txs) out.set(t.id, [{ slice: sl.at(-1), amount: signedOf(t) }]);
    return out;
  }
  const ordered = [...txs].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const r = (cum, part) => roundAway((cum * part) / total);
  let cum = 0;
  for (const t of ordered) {
    const a = signedOf(t);
    const next = cum + a;
    const list = [];
    let used = 0;
    for (let j = 0; j < sl.length - 1; j++) {
      const v = r(next, sl[j].amount) - r(cum, sl[j].amount);
      used += v;
      if (v !== 0) list.push({ slice: sl[j], amount: v });
    }
    const rest = a - used;
    if (rest !== 0 || !list.length) list.push({ slice: sl.at(-1), amount: rest });
    out.set(t.id, list);
    cum = next;
  }
  return out;
}

/// Faturas de todos os cartões (mesmo inativos), como o índice do app.
function buildInvoices(docs, all) {
  const cards = docs.cards ?? [];
  const cardById = new Map(cards.map((c) => [c.id, c]));
  const txs = new Map();
  for (const t of all) {
    if (!t.cardId) continue;
    const card = cardById.get(t.cardId);
    if (!card) continue;
    const key = `${card.id}|${invoiceForTx(card, t)}`;
    (txs.get(key) ?? txs.set(key, []).get(key)).push(t);
  }
  const pays = new Map();
  for (const p of docs.invoicePayments ?? []) {
    if (!cardById.has(p.cardId) || !p.invoiceKey) continue;
    const key = `${p.cardId}|${p.invoiceKey}`;
    (pays.get(key) ?? pays.set(key, []).get(key)).push(p);
  }
  const out = [];
  for (const key of new Set([...txs.keys(), ...pays.keys()])) {
    const [cardId, inv] = key.split('|');
    const card = cardById.get(cardId);
    const list = txs.get(key) ?? [];
    const due = invoiceDue(card, inv);
    const payments = (pays.get(key) ?? []).map((p) => ({ ...p, date: p.date ?? due }));
    const total = list.reduce((a, t) => a + signedOf(t), 0);
    const paid = payments.reduce((a, p) => a + p.amount, 0);
    const slices = invoiceSlices(total, payments, due);
    out.push({
      card, key: inv, due, total, paid, slices,
      transactions: list,
      shares: invoiceShares(list, total, slices),
      isEmpty: !list.length && !payments.length,
    });
  }
  return out;
}

/**
 * Eventos reconhecidos (receitas +, despesas −) até o fim de [until], como
 * FinancialEngine.recognizedEvents sem filtros: transferências e cancelados
 * ficam fora; o que não foi concluído em conta inativa também; compras no
 * cartão contam no mês de pagamento da fatura (saldo em aberto no
 * vencimento), e de cartão inativo só o que já foi pago.
 */
function recognizedEvents(docs, until, all, invoices) {
  const accounts = new Map((docs.accounts ?? []).map((a) => [a.id, a]));
  const out = [];
  for (const t of all) {
    if (t.cardId) continue;
    if (t.status !== 'completed' && accounts.get(t.accountId)?.active === false) continue;
    const m = ym(t.date);
    if (m > until) continue;
    out.push({ tx: t, month: m, date: t.date, signed: t.type === 'income' ? t.amount : -t.amount, settled: t.status === 'completed' });
  }
  for (const inv of invoices) {
    if (inv.slices.every((s) => s.month > until)) continue;
    const inactive = inv.card.active === false;
    for (const t of inv.transactions) {
      for (const sh of inv.shares.get(t.id) ?? []) {
        if (sh.slice.month > until || sh.amount === 0) continue;
        if (inactive && !sh.slice.settled) continue;
        out.push({ tx: t, invoice: inv, month: sh.slice.month, date: sh.slice.date, signed: -sh.amount, settled: sh.slice.settled });
      }
    }
  }
  return out;
}

/**
 * Números do mês [month] ("AAAA-MM") na visão de caixa, iguais aos da
 * Projeção do app sem filtros (inclusive fechamentos e ajustes do mês).
 * @param {Record<string, any[]>} docs documentos do usuário por coleção
 */
function computeSummary(docs, month, today) {
  const [y, m] = parts(month);
  const monthEnd = iso(y, m, lastDay(y, m));
  const soon = addDays(today, UPCOMING_DAYS);
  const horizon = [monthEnd, soon].sort()[1];
  // Faturas que fecham até dois meses depois (pagamento antecipado).
  const [hy, hm] = parts(addYm(ym(horizon), 2));
  const all = expand(docs, iso(hy, hm, lastDay(hy, hm)));
  const invoices = buildInvoices(docs, all);
  const accounts = new Map((docs.accounts ?? []).map((a) => [a.id, a]));
  const catName = new Map((docs.categories ?? []).map((c) => [c.id, c.name]));
  const closings = new Map((docs.monthClosings ?? []).map((c) => [c.month ?? c.id, c]));

  const s = {
    month,
    income: { done: 0, open: 0 },
    expense: { done: 0, open: 0 },
    cardExpenses: 0,
    invoices: [],
    byCategory: new Map(),
    upcoming: [],
    overdue: { count: 0, total: 0 },
    closing: null,
    accumulated: 0,
  };
  const addCat = (id, cents) =>
    s.byCategory.set(id ?? null, (s.byCategory.get(id ?? null) ?? 0) + cents);

  // Saldo acumulado: saldos iniciais + resultado de cada mês até [month]
  // (mês fechado usa o valor do fechamento).
  let accumulated = (docs.accounts ?? []).reduce((a, c) => a + (c.initialBalance ?? 0), 0);
  const invByKey = new Map();
  for (const e of recognizedEvents(docs, month, all, invoices)) {
    if (!closings.has(e.month)) accumulated += e.signed;
    if (e.month !== month) continue;
    const bucket = e.signed > 0 ? s.income : s.expense;
    bucket[e.settled ? 'done' : 'open'] += Math.abs(e.signed);
    if (e.signed < 0) addCat(e.tx.categoryId, -e.signed);
    else if (e.invoice) addCat(e.tx.categoryId, -e.signed); // estorno no cartão
    if (e.invoice) {
      s.cardExpenses -= e.signed;
      const k = `${e.invoice.card.id}|${e.invoice.key}`;
      const row = invByKey.get(k) ?? { card: e.invoice.card.name, due: e.invoice.due, inMonth: 0, total: e.invoice.total, remaining: Math.max(0, e.invoice.total - e.invoice.paid) };
      row.inMonth -= e.signed;
      invByKey.set(k, row);
    }
  }
  for (const [k, c] of closings) if (k <= month) accumulated += (c.income ?? 0) - (c.expenses ?? 0);
  s.accumulated = accumulated;
  s.invoices = [...invByKey.values()].filter((i) => i.inMonth !== 0);

  const closing = closings.get(month);
  if (closing) {
    s.closing = {
      income: closing.income ?? 0,
      expenses: closing.expenses ?? 0,
      // Receitas/despesas calculadas ao fechar (o ajuste manual é a diferença
      // e aparece numa linha própria).
      frozenIncome: closing.computedIncome ?? closing.income ?? 0,
      frozenExpenses: closing.computedExpenses ?? closing.expenses ?? 0,
      computedIncome: s.income.done + s.income.open,
      computedExpenses: s.expense.done + s.expense.open,
      note: closing.note ?? null,
    };
  }

  // A vencer e em atraso (o que ainda não foi pago).
  for (const t of all) {
    if (t.cardId || t.type === 'income' || t.status === 'completed') continue;
    if (accounts.get(t.accountId)?.active === false) continue;
    const due = t.dueDate ?? t.date;
    if (due < today) {
      if (ym(due) !== ym(today)) continue; // como na tela inicial: só o mês
      s.overdue.count++;
      s.overdue.total += t.amount;
    } else if (due <= soon) {
      s.upcoming.push({ date: due, label: t.description, amount: t.amount });
    }
  }
  for (const inv of invoices) {
    if (inv.card.active === false || inv.isEmpty) continue;
    const remaining = inv.total - inv.paid;
    if (remaining <= 0) continue;
    if (inv.due < today) {
      if (ym(inv.due) !== ym(today)) continue;
      s.overdue.count++;
      s.overdue.total += remaining;
    } else if (inv.due <= soon) {
      s.upcoming.push({ date: inv.due, label: `Fatura ${inv.card.name}`, amount: remaining });
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
  const computedIncome = s.income.done + s.income.open;
  const computedExpenses = s.expense.done + s.expense.open;
  const incomes = s.closing ? s.closing.frozenIncome : computedIncome;
  const expenses = s.closing ? s.closing.frozenExpenses : computedExpenses;
  const adjustment = s.closing
    ? s.closing.income - s.closing.expenses - (incomes - expenses)
    : 0;
  const result = incomes - expenses + adjustment;
  const lines = [`📊 *Resumo de ${MONTHS[m - 1]}/${y}*`, ''];
  if (s.closing) {
    lines.push(
      `🔒 Mês fechado/ajustado no app: valem os valores do fechamento.`,
      `💰 Receitas: *${brl(incomes)}*`,
      `💸 Despesas: *${brl(expenses)}*`,
    );
    if (adjustment !== 0) {
      lines.push(`✏️ Ajuste manual: *${adjustment > 0 ? '+' : ''}${brl(adjustment)}*`);
    }
    lines.push(`${result >= 0 ? '🟢' : '🔴'} Resultado: *${brl(result)}*`);
    if (computedIncome !== incomes || computedExpenses !== expenses) {
      lines.push(
        `   Pelos lançamentos de hoje seria ${brl(computedIncome)} − ${brl(computedExpenses)} = ` +
          `${brl(computedIncome - computedExpenses)}`,
      );
    }
    if (s.closing.note) lines.push(`   📝 ${s.closing.note}`);
  } else {
    const card = s.cardExpenses;
    lines.push(
      `💰 Receitas: *${brl(incomes)}*`,
      `   ${brl(s.income.done)} recebidas · ${brl(s.income.open)} a receber`,
      `💸 Despesas: *${brl(expenses)}*`,
      `   ${brl(s.expense.done)} pagas · ${brl(s.expense.open)} a pagar` +
        (card > 0 ? ` (${brl(card)} de cartões)` : ''),
      `${result >= 0 ? '🟢' : '🔴'} Resultado ${current || s.month > ym(today) ? 'previsto' : 'do mês'}: *${brl(result)}*`,
    );
  }
  lines.push(`🏦 Saldo acumulado no fim do mês: *${brl(s.accumulated)}*`);
  if (s.invoices.length) {
    lines.push('', '💳 Faturas no mês:');
    for (const i of s.invoices) {
      const state = i.remaining <= 0 ? 'paga ✅' : i.remaining < i.total ? `falta ${brl(i.remaining)}` : 'em aberto';
      const part = i.inMonth !== i.total ? ` (${brl(i.inMonth)} neste mês)` : '';
      lines.push(`• ${i.card}: ${brl(i.total)}${part}, vence ${brDate(i.due)} (${state})`);
    }
  }
  if (s.topCategories.length) {
    lines.push('', s.closing ? '🏷️ Onde mais gastou (pelos lançamentos):' : '🏷️ Onde mais gastou:');
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

const fold = (text) => String(text ?? '').trim().toLowerCase()
  .normalize('NFD').replace(/[̀-ͯ]/g, '');

// Frases que pedem um resumo: "resumo", "manda o extrato do mês", "como está
// meu mês?", "quanto gastei esse mês", "qual o saldo de outubro"…
const SUMMARY_WORDS = /\b(resumo|resumao|extrato|relatorio|balanco|fechamento)\b/;
const SUMMARY_PHRASES = [
  /\bcomo (e que )?(esta|estao|esta indo|ficou|fica|foi|vai|anda|andam|estou|to|tou|tamo|estamos)\b.*\b(mes|meses|financas|contas|orcamento|gastos|dinheiro|saldo)\b/,
  /\bquanto (eu )?(ja )?(gastei|gastamos|recebi|recebemos|sobrou|sobra|vai sobrar|tenho|entrou|saiu)\b.*\b(mes|janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\b/,
  /\b(qual|como)( e| esta)? (o |meu |a |minha )?(saldo|resultado|situacao)\b/,
  /\b(receitas|entradas) e (despesas|saidas|gastos)\b/,
  /\b(meus )?(gastos|numeros) do mes\b/,
];

/// Mês citado em [t] (texto já sem acentos), ou null.
function monthIn(t, today) {
  const now = ym(today);
  if (/\b(mes (passado|anterior)|ultimo mes)\b/.test(t)) return addYm(now, -1);
  if (/\b(proximo mes|mes que vem|mes seguinte)\b/.test(t)) return addYm(now, 1);
  const num = /\b(\d{1,2})\/(\d{4})\b/.exec(t);
  if (num && +num[1] >= 1 && +num[1] <= 12) return `${num[2]}-${pad(+num[1])}`;
  const names = MONTHS.map((n) => fold(n));
  const re = new RegExp(`\\b(${names.join('|')}|${names.map((n) => n.slice(0, 3)).filter((n) => n !== 'dez').join('|')})\\b(?:\\s*(?:de|/)?\\s*(\\d{4}))?`);
  const named = re.exec(t);
  if (named) {
    const idx = names.findIndex((n) => n === named[1] || n.slice(0, 3) === named[1]);
    let year = named[2] ? Number(named[2]) : Number(now.slice(0, 4));
    // "resumo de dezembro" em janeiro: o dezembro que passou.
    if (!named[2] && /\b(passado|anterior|ultimo)\b/.test(t) && `${year}-${pad(idx + 1)}` > now) year--;
    return `${year}-${pad(idx + 1)}`;
  }
  return null;
}

/**
 * Lê um pedido de resumo em linguagem natural. Retorna o mês ("AAAA-MM") ou
 * null se a mensagem não for um pedido de resumo (ex.: um gasto a lançar).
 */
function parseSummaryRequest(text, today) {
  const t = fold(text).replace(/[?.!,;:]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (!t || t.length > 160) return null;
  // Valores em dinheiro indicam um gasto ("gastei 50 no mercado").
  if (/r\$|\b\d+[.,]\d{2}\b|\b\d+ ?(reais|conto|pila)\b/.test(t)) return null;
  const asks = SUMMARY_WORDS.test(t) || SUMMARY_PHRASES.some((re) => re.test(t));
  if (!asks) return null;
  // "fechamento" sozinho pode ser de cartão ("quando é o fechamento do nubank").
  if (!/\b(resumo|resumao|extrato|relatorio|balanco)\b/.test(t) &&
      /\b(fatura|cartao|nubank|itau|inter|c6|bradesco|santander|xp)\b/.test(t)) return null;
  return monthIn(t, today) ?? ym(today);
}

module.exports = {
  expand,
  recognizedEvents,
  buildInvoices,
  computeSummary,
  formatMonthSummary,
  parseSummaryRequest,
  occurrences,
  invoiceDue,
  invoiceForTx,
};
