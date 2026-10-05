// Lançamentos vindos do WhatsApp: valida o rascunho lido pela IA contra as
// contas, cartões e categorias do usuário e gera os documentos no mesmo
// formato que o app grava (ver lib/domain/models/entities.dart).

const crypto = require('crypto');

const TIME_ZONE = 'America/Sao_Paulo';
const MAX_INSTALLMENTS = 48;
const NOTE = 'Lançado pelo WhatsApp';

/// Mesmo formato de `newId` do app: timestamp em base 36 + 8 aleatórios.
function newId(prefix) {
  const ts = (BigInt(Date.now()) * 1000n).toString(36);
  let rnd = '';
  for (const b of crypto.randomBytes(8)) rnd += (b % 36).toString(36);
  return `${prefix}${ts}${rnd}`;
}

/// Data de hoje (AAAA-MM-DD) no fuso de Brasília.
function todayIso(now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}

const ISO_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

function validIso(s) {
  const m = ISO_RE.exec(String(s ?? ''));
  if (!m) return false;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  return d.getUTCMonth() === +m[2] - 1 && d.getUTCDate() === +m[3];
}

/// Soma meses mantendo o dia (limitado ao fim do mês), como Dates.addMonths.
function addMonths(iso, months) {
  const [y, m, d] = iso.split('-').map(Number);
  const first = new Date(Date.UTC(y, m - 1 + months, 1));
  const last = new Date(
    Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0),
  ).getUTCDate();
  const day = Math.min(d, last);
  return `${first.getUTCFullYear()}-${String(first.getUTCMonth() + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

/// Divide em centavos exatos; as sobras vão para as primeiras parcelas.
function splitCents(cents, parts) {
  const base = Math.floor(cents / parts);
  const rest = cents - base * parts;
  return Array.from({ length: parts }, (_, i) => base + (i < rest ? 1 : 0));
}

/**
 * Dados do usuário usados para ler e validar lançamentos.
 * @param {Array<{coll: string, data: any}>} docs
 */
function buildContext(docs, now = new Date()) {
  const of = (coll) => docs.filter((d) => d.coll === coll).map((d) => d.data);
  return {
    today: todayIso(now),
    accounts: of('accounts')
      .filter((a) => a.active !== false)
      .map((a) => ({ id: a.id, name: a.name, institution: a.institution ?? '' })),
    cards: of('cards')
      .filter((c) => c.active !== false)
      .map((c) => ({ id: c.id, name: c.name, bank: c.bank ?? '' })),
    categories: of('categories').map((c) => ({
      id: c.id,
      name: c.name,
      kind: c.kind === 'income' ? 'income' : 'expense',
      parentId: c.parentId ?? null,
    })),
  };
}

/**
 * Confere e completa o que a IA devolveu. Retorna `{draft}` pronto para
 * confirmar ou `{error}` com uma mensagem para o usuário.
 */
function normalizeDraft(raw, ctx) {
  if (!raw || raw.is_transaction !== true) {
    return { error: String(raw?.reply ?? '').trim() || null };
  }
  const type = raw.type === 'income' ? 'income' : 'expense';
  const amount = Math.round(Number(raw.amount) * 100);
  if (!Number.isFinite(amount) || amount <= 0) {
    return { error: 'Não encontrei o valor. Pode mandar de novo com o valor? Ex.: "mercado 45,90".' };
  }
  const description =
    String(raw.description ?? '').trim().slice(0, 120) ||
    (type === 'income' ? 'Receita' : 'Despesa');
  const date = validIso(raw.date) ? raw.date : ctx.today;

  const category = ctx.categories.find(
    (c) => c.id === raw.category_id && c.kind === type,
  );
  let card = type === 'expense' ? ctx.cards.find((c) => c.id === raw.card_id) : null;
  let account = card ? null : ctx.accounts.find((a) => a.id === raw.account_id);
  if (!card && !account) {
    account = ctx.accounts[0];
    if (!account && type === 'expense') card = ctx.cards[0];
  }
  if (!card && !account) {
    return { error: 'Cadastre uma conta no app antes de lançar pelo WhatsApp.' };
  }

  let installments = Math.trunc(Number(raw.installments) || 1);
  if (type !== 'expense') installments = 1;
  installments = Math.max(1, Math.min(MAX_INSTALLMENTS, installments));
  if (installments > amount) installments = 1;

  return {
    draft: {
      type,
      amount,
      description,
      date,
      categoryId: category?.id ?? null,
      accountId: account?.id ?? null,
      cardId: card?.id ?? null,
      installments,
      notes: String(raw.notes ?? '').trim().slice(0, 500),
    },
  };
}

function baseTx(draft, now) {
  const ts = now.toISOString();
  return {
    type: draft.type,
    description: draft.description,
    categoryId: draft.categoryId,
    date: draft.date,
    accountId: draft.accountId,
    cardId: draft.cardId,
    destinationAccountId: null,
    projectId: null,
    notes: draft.notes ? `${draft.notes}\n${NOTE}` : NOTE,
    recurringId: null,
    occurrenceDate: null,
    installmentGroupId: null,
    installmentNumber: null,
    installmentCount: null,
    externalId: null,
    createdAt: ts,
    updatedAt: ts,
  };
}

/**
 * Documentos a gravar em app_docs para um rascunho confirmado. Segue as
 * regras do formulário do app: no cartão a compra fica pendente (acompanha a
 * fatura); na conta, data futura = planejada, senão concluída.
 */
function buildDocs(draft, today, now = new Date()) {
  const isCard = draft.cardId != null;
  const statusFor = (date) =>
    isCard ? 'pending' : date > today ? 'planned' : 'completed';

  if (draft.installments < 2) {
    const id = newId('tx_');
    return [
      {
        coll: 'transactions',
        id,
        data: { id, ...baseTx(draft, now), amount: draft.amount, status: statusFor(draft.date) },
      },
    ];
  }

  const groupId = newId('ig_');
  const ts = now.toISOString();
  const base = baseTx(draft, now);
  const firstStatus = statusFor(draft.date);
  const docs = [
    {
      coll: 'installmentGroups',
      id: groupId,
      data: {
        id: groupId,
        description: draft.description,
        totalAmount: draft.amount,
        count: draft.installments,
        purchaseDate: draft.date,
        accountId: draft.accountId,
        cardId: draft.cardId,
        categoryId: draft.categoryId,
        projectId: null,
        notes: base.notes,
        createdAt: ts,
        updatedAt: ts,
      },
    },
  ];
  splitCents(draft.amount, draft.installments).forEach((cents, i) => {
    const number = i + 1;
    const date = isCard ? draft.date : addMonths(draft.date, i);
    let status;
    if (number === 1) status = firstStatus;
    else if (!isCard && date <= today) status = firstStatus;
    else status = 'planned';
    const id = newId('tx_');
    docs.push({
      coll: 'transactions',
      id,
      data: {
        id,
        ...base,
        amount: cents,
        date,
        status,
        installmentGroupId: groupId,
        installmentNumber: number,
        installmentCount: draft.installments,
      },
    });
  });
  return docs;
}

const brl = (cents) =>
  (cents / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

const brDate = (iso) => iso.split('-').reverse().join('/');

/// Resumo mostrado no WhatsApp antes de confirmar.
function formatSummary(draft, ctx) {
  const lines = [
    `${draft.type === 'income' ? '💰 Receita' : '💸 Despesa'}: *${brl(draft.amount)}*`,
    `📝 ${draft.description}`,
  ];
  const cat = ctx.categories.find((c) => c.id === draft.categoryId);
  lines.push(`🏷️ ${cat ? cat.name : 'Sem categoria'}`);
  if (draft.cardId) {
    const c = ctx.cards.find((x) => x.id === draft.cardId);
    lines.push(`💳 Cartão ${c?.name ?? ''}`.trim());
  } else {
    const a = ctx.accounts.find((x) => x.id === draft.accountId);
    lines.push(`🏦 Conta ${a?.name ?? ''}`.trim());
  }
  lines.push(`📅 ${brDate(draft.date)}`);
  if (draft.installments > 1) {
    const first = splitCents(draft.amount, draft.installments)[0];
    lines.push(`🔢 ${draft.installments}x de ${brl(first)}`);
  }
  if (draft.notes) lines.push(`🗒️ ${draft.notes}`);
  return lines.join('\n');
}

module.exports = {
  newId,
  todayIso,
  addMonths,
  splitCents,
  buildContext,
  normalizeDraft,
  buildDocs,
  formatSummary,
  brl,
};
