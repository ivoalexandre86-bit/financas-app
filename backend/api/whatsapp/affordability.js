// Assistente de compras pelo WhatsApp: "cabe uma compra de 2.400 em 12x?".
//
// Projeta a sobra de cada mês na visão de caixa (a mesma do resumo):
// receitas − despesas já previstas (lançamentos, recorrências, parcelas e
// faturas de cartão no mês do vencimento) − gastos do dia a dia que ainda
// devem acontecer (o maior entre o orçamento da categoria e a média dos
// últimos 3 meses). Depois encaixa as parcelas e diz se cabe, com folga de
// 10% da receita do mês, e sugere alternativas quando não cabe.

const { brl } = require('./ledger');
const { expand, invoiceDue, invoiceForTx } = require('./summary');

const MONTHS = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];
/** Folga mínima para considerar "cabe com tranquilidade" (fração da receita). */
const CUSHION = 0.1;
/** Meses de histórico usados para estimar os gastos do dia a dia. */
const HISTORY_MONTHS = 3;
const MAX_INSTALLMENTS = 48;
/** Quantidades de parcelas testadas nas sugestões. */
const COUNT_OPTIONS = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 18, 20, 24];
/** Até quantos meses para frente procurar um início que caiba. */
const MAX_DELAY = 12;

const pad = (n) => String(n).padStart(2, '0');
const ym = (s) => s.slice(0, 7);
const parts = (s) => s.split('-').map(Number);

function addYm(key, n) {
  const [y, m] = parts(key);
  const t = new Date(Date.UTC(y, m - 1 + n, 1));
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}`;
}

const lastDayIso = (key) => {
  const [y, m] = parts(key);
  return `${key}-${pad(new Date(Date.UTC(y, m, 0)).getUTCDate())}`;
};

/// "dez/2026"
function monthLabel(key) {
  const [y, m] = parts(key);
  return `${MONTHS[m - 1].slice(0, 3)}/${y}`;
}

const plain = (s) => String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

// Leitura da pergunta ---------------------------------------------------------------

const TRIGGER =
  /\b(cabe|cabem|caberia|posso|poderia|consigo|conseguiria|da (pra|para)|daria (pra|para)|devo|vale a pena|compensa|viavel|aguento|aguenta|e possivel|tenho condic\w*|simul\w*)\b/;
const PURCHASE = /\b(compr\w*|parcel\w*|gast\w*|financ\w*|pagar)\b/;
/** Mensagens que relatam um gasto feito: seguem para o lançamento. */
const REPORT = /^(gastei|paguei|comprei|recebi|lanca|lancar|lance)\b/;
const MONEY = String.raw`(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)(\s*(?:mil|k)\b)?`;
const MONTH_NAMES = MONTHS.map(plain);
// "dez" fica de fora das abreviações: quase sempre é o número (dez vezes).
const MONTH_RE = `(${MONTH_NAMES.map((n) => (n === 'dezembro' ? n : `${n}|${n.slice(0, 3)}`)).join('|')})`;
const NUMBER_WORDS = {
  duas: 2, dois: 2, tres: 3, quatro: 4, cinco: 5, seis: 6, sete: 7, oito: 8, nove: 9,
  dez: 10, onze: 11, doze: 12, quinze: 15, dezoito: 18, vinte: 20, 'vinte e quatro': 24,
  trinta: 30, 'trinta e seis': 36, 'quarenta e oito': 48,
};
const NUMBER_RE = new RegExp(
  String.raw`\b(${Object.keys(NUMBER_WORDS).sort((a, b) => b.length - a.length).join('|')})\s+(?=(vezes|parcelas?|prestac\w*|meses)\b)`,
  'g',
);

function money(num, mult) {
  let s = num;
  if (/^\d{1,3}(\.\d{3})+(,\d{1,2})?$/.test(s)) s = s.replace(/\./g, '').replace(',', '.');
  else s = s.replace(',', '.');
  const v = Number(s) * (mult ? 1000 : 1);
  return Number.isFinite(v) && v > 0 ? Math.round(v * 100) : null;
}

/**
 * Lê "cabe uma compra de X em N parcelas?". Retorna null quando a mensagem
 * não é essa pergunta; { missing: 'amount' } quando falta o valor.
 * @returns {null | {missing: string} | {total: number, installments: number,
 *   parcel: number|null, startMonth: string|null, text: string, card: boolean,
 *   noCard: boolean}}
 */
function parsePurchaseQuestion(text, today) {
  let t = plain(text).replace(/\s+/g, ' ').trim()
    .replace(NUMBER_RE, (_, w) => `${NUMBER_WORDS[w]} `);
  if (!t || REPORT.test(t) || !TRIGGER.test(t)) return null;
  const countRe = new RegExp(
    String.raw`(\d{1,2})\s*(?:x|vezes|parcelas?|prestac(?:oes|ao)|meses)\b` +
      String.raw`(?:\s*(?:de|no valor de|por)\s*(?:r\$\s*)?${MONEY})?`,
  );
  const hasCount = countRe.test(t);
  if (!hasCount && !PURCHASE.test(t)) return null;
  const original = t;

  // Mês da primeira parcela.
  let startMonth = null;
  const startRe = new RegExp(
    String.raw`(?:a partir de|comecando(?: em| no| na)?|comecar(?: em| no| na)?|primeira parcela(?: so)?(?: em| para| pra| no)?|1a parcela(?: em| para| pra| no)?|so (?:em|no|a partir de)|para|pra|em)\s+${MONTH_RE}(?:\s*(?:de|/)?\s*(\d{4}))?\b`,
  );
  const sm = startRe.exec(t);
  const now = ym(today);
  if (sm) {
    const idx = MONTH_NAMES.findIndex((n) => n === sm[1] || n.slice(0, 3) === sm[1]);
    let year = sm[2] ? Number(sm[2]) : Number(now.slice(0, 4));
    let key = `${year}-${pad(idx + 1)}`;
    if (!sm[2] && key < now) key = `${++year}-${pad(idx + 1)}`;
    startMonth = key;
    t = t.replace(sm[0], ' ');
  } else if (/\b(mes que vem|proximo mes)\b/.test(t)) {
    startMonth = addYm(now, 1);
    t = t.replace(/\b(mes que vem|proximo mes)\b/, ' ');
  }

  let installments = 1;
  let parcel = null;
  const cm = countRe.exec(t);
  if (cm) {
    installments = Number(cm[1]);
    if (cm[2]) parcel = money(cm[2], cm[3]);
    t = t.replace(cm[0], ' ');
  }
  const pm = new RegExp(String.raw`parcelas?\s+(?:de|no valor de)\s*(?:r\$\s*)?${MONEY}`).exec(t);
  if (pm && parcel == null) {
    parcel = money(pm[1], pm[2]);
    t = t.replace(pm[0], ' ');
  }
  const tm = new RegExp(String.raw`(?:r\$\s*)?${MONEY}`).exec(t);
  let total = tm ? money(tm[1], tm[2]) : null;
  if (installments < 1 || installments > MAX_INSTALLMENTS) return null;
  // Com o valor da parcela, paga-se parcela × N (pode ter juros).
  const listPrice = total;
  if (parcel != null) total = parcel * installments;
  if (!total) return { missing: 'amount' };
  return {
    total,
    listPrice: listPrice && listPrice !== total ? listPrice : null,
    installments,
    parcel,
    startMonth,
    text: original,
    card: /\bcart(ao|oes)\b/.test(original),
    noCard: /\b(boleto|pix|carne|crediario|debito|a vista no dinheiro)\b/.test(original),
  };
}

/// Cartão citado na pergunta (pelo nome ou banco); só "cartão" = o primeiro.
function pickCard(q, cards) {
  if (q.noCard) return null;
  const active = cards.filter((c) => c.active !== false && c.closingDay && c.dueDay);
  const named = active.find((c) =>
    [c.name, c.bank].some((n) => {
      const p = plain(n).trim();
      return p.length >= 3 && new RegExp(`\\b${p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`).test(q.text);
    }),
  );
  if (named) return named;
  return q.card && active.length ? active[0] : null;
}

// Projeção -----------------------------------------------------------------------

/**
 * Sobra prevista por mês ("AAAA-MM") de [from] até [to].
 * @param {Record<string, any[]>} docs
 */
function projectMargins(docs, today, from, to) {
  const histFrom = addYm(ym(today), -HISTORY_MONTHS);
  const all = expand(docs, lastDayIso(addYm(to, 2)));
  const cards = new Map(
    (docs.cards ?? []).filter((c) => c.active !== false).map((c) => [c.id, c]),
  );
  const parentOf = new Map((docs.categories ?? []).map((c) => [c.id, c.parentId ?? null]));
  const root = (id) => (id == null ? null : parentOf.get(id) ?? id);

  const flows = new Map();
  const flow = (k) => {
    if (!flows.has(k)) {
      flows.set(k, { income: 0, expense: 0, byCat: new Map(), oneoff: new Map(), count: 0 });
    }
    return flows.get(k);
  };
  const add = (map, k, v) => map.set(k, (map.get(k) ?? 0) + v);

  for (const t of all) {
    let month;
    if (t.cardId) {
      const card = cards.get(t.cardId);
      if (!card) continue;
      month = card.closingDay && card.dueDay ? ym(invoiceDue(card, invoiceForTx(card, t))) : ym(t.date);
    } else {
      month = ym(t.date);
    }
    if (month < histFrom || month > to) continue;
    const f = flow(month);
    f.count++;
    if (t.type === 'income' && !t.cardId) {
      f.income += t.amount;
      continue;
    }
    const v = t.type === 'income' ? -t.amount : t.amount;
    f.expense += v;
    add(f.byCat, t.categoryId ?? null, v);
    const recurring = t.recurringId || String(t.id).startsWith('v:');
    if (!recurring && !t.installmentGroupId) add(f.oneoff, root(t.categoryId), v);
  }

  // Média dos gastos avulsos (sem recorrência nem parcelamento) por categoria.
  const avg = new Map();
  const hist = [];
  for (let i = 1; i <= HISTORY_MONTHS; i++) {
    const f = flows.get(addYm(ym(today), -i));
    if (f?.count) hist.push(f);
  }
  for (const f of hist) {
    for (const [k, v] of f.oneoff) add(avg, k, v / hist.length);
  }

  const budgets = (docs.budgets ?? []).filter((b) => b.amount > 0 && b.categoryId);
  const out = [];
  for (let k = from; k <= to; k = addYm(k, 1)) {
    const f = flows.get(k) ?? flow(k);
    const spentIn = (catId) => {
      let s = 0;
      for (const [c, v] of f.byCat) if (c === catId || parentOf.get(c) === catId) s += v;
      return s;
    };
    // Por categoria raiz: o maior entre o que falta do orçamento e o que falta
    // para chegar na média dos gastos avulsos.
    const gap = new Map();
    for (const b of budgets) add(gap, root(b.categoryId), Math.max(0, b.amount - spentIn(b.categoryId)));
    for (const [c, a] of avg) {
      const hgap = Math.max(0, Math.round(a) - (f.oneoff.get(c) ?? 0));
      if (hgap > (gap.get(c) ?? 0)) gap.set(c, hgap);
    }
    const variable = [...gap.values()].reduce((a, v) => a + v, 0);
    out.push({
      month: k,
      income: f.income,
      expense: f.expense,
      variable,
      margin: f.income - f.expense - variable,
      cushion: Math.round(f.income * CUSHION),
    });
  }
  return out;
}

/// Divide em centavos exatos; as sobras vão para as primeiras parcelas.
function splitCents(cents, n) {
  const base = Math.floor(cents / n);
  const rest = cents - base * n;
  return Array.from({ length: n }, (_, i) => base + (i < rest ? 1 : 0));
}

/**
 * Encaixa N parcelas a partir de [first] na projeção.
 * level: 'ok' (sobra ≥ folga em todos os meses), 'tight' (não fica negativo)
 * ou 'no' (algum mês no vermelho).
 */
function evaluate(margins, first, n, total) {
  const byMonth = new Map(margins.map((m) => [m.month, m]));
  let level = 'ok';
  let worst = null;
  let negative = 0;
  splitCents(total, n).forEach((p, i) => {
    const m = byMonth.get(addYm(first, i));
    if (!m) return;
    const after = m.margin - p;
    if (after < 0) {
      negative++;
      level = 'no';
    } else if (after < m.cushion && level === 'ok') {
      level = 'tight';
    }
    if (!worst || after - m.cushion < worst.after - worst.cushion) {
      worst = { month: m.month, before: m.margin, after, cushion: m.cushion, parcel: p };
    }
  });
  return { level, worst, negative };
}

const RANK = { ok: 2, tight: 1, no: 0 };
const fits = (e, target) => RANK[e.level] >= RANK[target];

/**
 * Analisa a compra e monta as alternativas.
 * @param {Record<string, any[]>} docs documentos do usuário por coleção
 */
function analyzePurchase(docs, q, today) {
  const card = pickCard(q, docs.cards ?? []);
  const now = ym(today);
  let first;
  if (q.startMonth) first = q.startMonth;
  else if (card) first = ym(invoiceDue(card, invoiceForTx(card, { date: today })));
  else first = addYm(now, 1);
  const n = q.installments;
  const horizon = addYm(first, Math.max(n, Math.max(...COUNT_OPTIONS)) + MAX_DELAY);
  const margins = projectMargins(docs, today, now < first ? now : first, horizon);
  const window = margins.filter((m) => m.month >= first && m.month < addYm(first, n));
  const result = evaluate(margins, first, n, q.total);
  const a = {
    total: q.total,
    listPrice: q.listPrice,
    installments: n,
    parcel: splitCents(q.total, n)[0],
    first,
    card: card ? card.name : null,
    result,
    noIncome: window.every((m) => m.income <= 0),
    alreadyNegative: window.filter((m) => m.margin < 0).length,
    minMargin: Math.min(...window.map((m) => m.margin)),
    maxMargin: Math.max(...window.map((m) => m.margin)),
    alternatives: [],
  };

  // Maior valor que cabe com folga nessas mesmas condições.
  const room = (target) =>
    Math.min(...window.map((m) => m.margin - (target === 'ok' ? m.cushion : 0)));
  const maxTotal = (target) => {
    const perMonth = room(target);
    if (perMonth <= 0) return 0;
    return Math.floor((perMonth * n) / 1000) * 1000; // múltiplos de R$ 10
  };
  a.maxTotal = maxTotal('ok');
  if (result.level === 'ok') return a;

  for (const target of ['ok', 'tight']) {
    const alts = [];
    const counts = COUNT_OPTIONS.filter((c) => c !== n && c <= MAX_INSTALLMENTS)
      .filter((c) => fits(evaluate(margins, first, c, q.total), target));
    // Menos parcelas que cabem (termina antes) ou o mínimo de parcelas a mais.
    const more = counts.find((c) => c > n);
    const fewer = counts.filter((c) => c < n).pop();
    if (fewer) alts.push({ kind: 'count', installments: fewer, parcel: splitCents(q.total, fewer)[0] });
    if (more) alts.push({ kind: 'count', installments: more, parcel: splitCents(q.total, more)[0] });
    const value = maxTotal(target);
    if (value >= Math.max(5000, q.total * 0.1) && value < q.total) {
      alts.push({ kind: 'value', total: value, installments: n, parcel: splitCents(value, n)[0] });
    }
    for (let d = 1; d <= MAX_DELAY; d++) {
      const start = addYm(first, d);
      if (fits(evaluate(margins, start, n, q.total), target)) {
        alts.push({ kind: 'later', first: start, installments: n, parcel: splitCents(q.total, n)[0] });
        break;
      }
    }
    if (alts.length) {
      a.alternatives = alts;
      a.alternativesLevel = target;
      break;
    }
  }
  return a;
}

// Resposta -----------------------------------------------------------------------

function formatAnalysis(a) {
  const { result: r } = a;
  const head = {
    ok: '✅ *Cabe no orçamento*',
    tight: '⚠️ *Cabe, mas fica apertado*',
    no: '❌ *Nessas condições não é viável*',
  }[r.level];
  const parcelTxt = a.installments > 1 ? `${a.installments}x de ${brl(a.parcel)}` : 'à vista';
  const lines = [
    head,
    `Compra de ${brl(a.total)} em ${parcelTxt}` +
      `, ${a.installments > 1 ? '1ª parcela' : 'pagamento'} em ${monthLabel(a.first)}` +
      (a.card ? ` (fatura do ${a.card})` : '') + '.',
  ];
  if (a.listPrice) {
    lines.push(`Com juros: você pagaria ${brl(a.total - a.listPrice)} a mais que os ${brl(a.listPrice)} à vista.`);
  }
  lines.push('');

  if (a.noIncome) {
    lines.push(
      'Não encontrei receitas previstas nesses meses, então não consigo medir a sua sobra. ' +
        'Cadastre o salário como recorrente no app e me pergunte de novo.',
    );
    return lines.join('\n');
  }

  const span = a.installments > 1 ? `nos ${a.installments} meses da compra` : `em ${monthLabel(a.first)}`;
  if (a.minMargin === a.maxMargin) {
    lines.push(`Sua sobra prevista ${span} é de ${brl(a.minMargin)}.`);
  } else {
    lines.push(`Sua sobra prevista ${span} vai de ${brl(a.minMargin)} a ${brl(a.maxMargin)} por mês.`);
  }
  if (a.alreadyNegative) {
    lines.push(`⚠️ Mesmo sem a compra, ${a.alreadyNegative === 1 ? '1 mês já fecha' : `${a.alreadyNegative} meses já fecham`} no vermelho.`);
  }
  const w = r.worst;
  if (r.level === 'ok') {
    lines.push(`Com a parcela, o mês mais justo é ${monthLabel(w.month)}: ainda sobram ${brl(w.after)}.`);
    if (a.maxTotal > a.total) {
      lines.push(`Com folga, caberia até ${brl(a.maxTotal)} em ${a.installments}x.`);
    }
  } else if (r.level === 'tight') {
    lines.push(
      `Não fica no vermelho, mas em ${monthLabel(w.month)} sobrariam só ${brl(w.after)}, ` +
        `menos que a reserva de 10% da renda (${brl(w.cushion)}).`,
    );
  } else {
    lines.push(
      `Com a parcela, ${r.negative === 1 ? '1 mês ficaria' : `${r.negative} meses ficariam`} no vermelho; ` +
        `o pior é ${monthLabel(w.month)}: ${brl(w.after)}.`,
    );
  }

  if (r.level !== 'ok') {
    lines.push('');
    if (a.alternatives.length) {
      lines.push(a.alternativesLevel === 'ok' ? '💡 *Opções que cabem com folga:*' : '💡 *Opções que pelo menos não deixam no vermelho:*');
      for (const alt of a.alternatives) {
        if (alt.kind === 'count') {
          lines.push(
            alt.installments === 1
              ? `• À vista, ${brl(a.total)}`
              : `• ${alt.installments}x de ${brl(alt.parcel)}` +
                  (alt.installments > a.installments ? ' (se for sem juros)' : ''),
          );
        } else if (alt.kind === 'value') {
          lines.push(`• Valor de até ${brl(alt.total)} em ${alt.installments}x de ${brl(alt.parcel)}`);
        } else {
          lines.push(`• Deixar a 1ª parcela para ${monthLabel(alt.first)} (${alt.installments}x de ${brl(alt.parcel)})`);
        }
      }
    } else {
      lines.push(
        '💡 Não achei um jeito de encaixar essa compra nos próximos meses. ' +
          'Vale juntar o dinheiro antes ou rever os gastos fixos.',
      );
    }
  }
  lines.push(
    '',
    '_Considerei receitas, contas fixas, parcelas e faturas já lançadas, seus orçamentos ' +
      'por categoria e a média dos gastos do dia a dia._',
  );
  return lines.join('\n');
}

module.exports = {
  parsePurchaseQuestion,
  analyzePurchase,
  formatAnalysis,
  projectMargins,
  evaluate,
};
