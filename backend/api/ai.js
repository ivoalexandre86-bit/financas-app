// IA dentro do app: leitura de cupom/comprovante (foto, PDF ou texto) para
// preencher o lançamento e o assistente que responde perguntas sobre as
// finanças do usuário.
//
// O assistente recebe um retrato das finanças já calculado pelo app (o
// mesmo motor das telas, na visão de caixa) e só responde com base nele.

const Anthropic = require('@anthropic-ai/sdk');
const { buildContext, normalizeDraft } = require('./whatsapp/ledger');
const { accessOf } = require('./billing');

/** Usos da IA por mês por usuário (administradores não têm limite). */
const MONTHLY_LIMIT = 300;
const FREE_MONTHLY_LIMIT = 10;
const MAX_SNAPSHOT = 20_000;
const MAX_HISTORY = 8;
const ASSISTANT_MODEL = 'claude-haiku-5-5';
const MEDIA_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'application/pdf',
]);

const ASSISTANT_SYSTEM = `Você é o assistente financeiro do app Finanças, de finanças pessoais, e conversa em português do Brasil.

Responda apenas com base no retrato das finanças do usuário que vem na mensagem (valores em reais, visão de caixa: compras no cartão contam no mês de pagamento da fatura). Se a informação não estiver no retrato, diga que não tem esse dado e sugira onde ver no app (Transações, Faturas, Projeção, Orçamentos, Metas).

Seja direto e curto: no máximo uns 200 palavras, em parágrafos curtos ou listas, valores no formato R$ 1.234,56. Pode fazer contas, comparar meses, apontar gastos que cresceram e sugerir cortes ou metas realistas. Não invente lançamentos, não dê recomendação de investimento específico (produto, ação, fundo) e não fale de assuntos fora das finanças do usuário.`;

const CONTRACT_MODEL = 'claude-sonnet-5-5';

// Campos de um contrato de empréstimo/financiamento lidos do arquivo. Tudo
// opcional (null quando não aparece); o app mostra para o usuário revisar.
const CONTRACT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: [
    'name', 'lender', 'kind', 'system', 'monthlyRatePercent',
    'annualRatePercent', 'originalPrincipal', 'contractDate', 'termMonths',
    'outstanding', 'balanceDate', 'remainingMonths', 'nextDueDate',
    'currentPayment', 'monthlyFees', 'index', 'notes',
  ],
  properties: {
    name: { type: ['string', 'null'] },
    lender: { type: ['string', 'null'] },
    kind: {
      type: ['string', 'null'],
      enum: ['personalLoan', 'payroll', 'vehicle', 'realEstate', 'student', 'other', null],
    },
    system: { type: ['string', 'null'], enum: ['price', 'sac', null] },
    monthlyRatePercent: { type: ['number', 'null'] },
    annualRatePercent: { type: ['number', 'null'] },
    originalPrincipal: { type: ['number', 'null'] },
    contractDate: { type: ['string', 'null'] },
    termMonths: { type: ['integer', 'null'] },
    outstanding: { type: ['number', 'null'] },
    balanceDate: { type: ['string', 'null'] },
    remainingMonths: { type: ['integer', 'null'] },
    nextDueDate: { type: ['string', 'null'] },
    currentPayment: { type: ['number', 'null'] },
    monthlyFees: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'amount'],
        properties: { name: { type: 'string' }, amount: { type: 'number' } },
      },
    },
    index: {
      type: ['string', 'null'],
      enum: ['none', 'tr', 'ipca', 'igpm', 'incc', 'cdi', 'other', null],
    },
    notes: { type: ['string', 'null'] },
  },
};

const CONTRACT_SYSTEM = `Você lê contratos e extratos de empréstimos e financiamentos brasileiros (CCB, financiamento de veículo ou imóvel, consignado) e devolve só os dados que aparecem no documento, no JSON pedido.

Regras: valores em reais com ponto decimal (1234.56). Datas no formato AAAA-MM-DD. Taxas em porcentagem (1.5 = 1,5%). "system": "price" para parcelas fixas (Tabela Price) e "sac" para amortização constante. "outstanding" é o saldo devedor atual, "currentPayment" a parcela sem seguros e taxas, que vão em "monthlyFees". Não invente: use null para o que não estiver escrito. Em "notes", diga em uma frase o que não ficou claro (ex.: regras de amortização antecipada, CET).`;

/** Centavos a partir de reais (número), ou null. */
const cents = (v) =>
  typeof v === 'number' && Number.isFinite(v) && v >= 0 ? Math.round(v * 100) : null;
const isoDate = (v) =>
  typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null;
const posInt = (v) => (Number.isInteger(v) && v > 0 && v <= 600 ? v : null);

/**
 * Converte a leitura da IA nos campos do DebtContract do app: centavos,
 * taxa mensal como fração. Taxa anual vira mensal equivalente quando a
 * mensal não vem. `fields` lista o que foi preenchido.
 */
function normalizeContract(raw) {
  if (!raw || typeof raw !== 'object') return null;
  let monthly =
    typeof raw.monthlyRatePercent === 'number' && raw.monthlyRatePercent >= 0 && raw.monthlyRatePercent < 50
      ? raw.monthlyRatePercent / 100
      : null;
  if (monthly == null && typeof raw.annualRatePercent === 'number' &&
      raw.annualRatePercent >= 0 && raw.annualRatePercent < 1000) {
    monthly = Math.pow(1 + raw.annualRatePercent / 100, 1 / 12) - 1;
  }
  const out = {
    name: typeof raw.name === 'string' ? raw.name.slice(0, 80) : null,
    lender: typeof raw.lender === 'string' ? raw.lender.slice(0, 80) : null,
    kind: raw.kind ?? null,
    system: raw.system ?? null,
    monthlyRate: monthly == null ? null : Math.round(monthly * 1e8) / 1e8,
    originalPrincipal: cents(raw.originalPrincipal),
    contractDate: isoDate(raw.contractDate),
    termMonths: posInt(raw.termMonths),
    outstanding: cents(raw.outstanding),
    balanceDate: isoDate(raw.balanceDate),
    remainingMonths: posInt(raw.remainingMonths),
    nextDueDate: isoDate(raw.nextDueDate),
    currentPayment: cents(raw.currentPayment),
    fees: (Array.isArray(raw.monthlyFees) ? raw.monthlyFees : [])
      .map((f) => ({ name: String(f?.name ?? 'Encargo').slice(0, 60), monthly: cents(f?.amount) }))
      .filter((f) => f.monthly != null && f.monthly > 0)
      .slice(0, 6),
    index: raw.index ?? null,
    notes: typeof raw.notes === 'string' ? raw.notes.slice(0, 500) : '',
  };
  out.fields = Object.entries(out)
    .filter(([k, v]) => k !== 'notes' && v != null && !(Array.isArray(v) && !v.length))
    .map(([k]) => k);
  return out.fields.length ? out : null;
}

/**
 * @param {{apiKey: string, model?: string, extract: Function,
 *   log?: (line: string) => void}} opts
 */
function createAi({ apiKey, model = ASSISTANT_MODEL, extract, log = console.log }) {
  const client = new Anthropic({ apiKey, timeout: 60_000, maxRetries: 2 });

  async function ask({ question, snapshot, history = [] }) {
    const messages = [];
    for (const h of history.slice(-MAX_HISTORY)) {
      messages.push({
        role: h.role === 'assistant' ? 'assistant' : 'user',
        content: String(h.text ?? '').slice(0, 4000) || '...',
      });
    }
    // A conversa começa sempre pelo usuário e alterna os papéis.
    while (messages.length && messages[0].role !== 'user') messages.shift();
    const merged = [];
    for (const m of messages) {
      const last = merged[merged.length - 1];
      if (last && last.role === m.role) last.content += `\n\n${m.content}`;
      else merged.push({ ...m });
    }
    const content =
      `Retrato das finanças do usuário:\n${snapshot}\n\nPergunta:\n${question}`;
    if (merged.length && merged[merged.length - 1].role === 'user') {
      merged.push({ role: 'assistant', content: 'Certo.' });
    }
    merged.push({ role: 'user', content });
    const res = await client.messages.create({
      model,
      max_tokens: 4000,
      system: ASSISTANT_SYSTEM,
      messages: merged,
    });
    log(
      `Assistente IA: ${res.model ?? model} in=${res.usage?.input_tokens ?? 0} ` +
        `out=${res.usage?.output_tokens ?? 0}`,
    );
    if (res.stop_reason === 'refusal') return null;
    const cut = res.stop_reason === 'max_tokens' ? '\n\n(Resposta cortada por ser longa. Peça um resumo.)' : '';
    return res.content
      .filter((b) => b.type === 'text')
      .map((b) => b.text)
      .join('')
      .trim() + cut;
  }

  async function readContract({ media, text }) {
    const content = [];
    if (media) {
      const data = media.data.toString('base64');
      content.push(
        media.mimeType === 'application/pdf'
          ? { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data } }
          : { type: 'image', source: { type: 'base64', media_type: media.mimeType, data } },
      );
    }
    content.push({
      type: 'text',
      text: text ? `Texto do contrato ou extrato:\n${text}` : 'Leia o documento acima.',
    });
    const res = await client.messages.create({
      model: CONTRACT_MODEL,
      max_tokens: 4000,
      output_config: { format: { type: 'json_schema', schema: CONTRACT_SCHEMA } },
      system: CONTRACT_SYSTEM,
      messages: [{ role: 'user', content }],
    });
    log(
      `Contrato IA: ${res.model ?? CONTRACT_MODEL} in=${res.usage?.input_tokens ?? 0} ` +
        `out=${res.usage?.output_tokens ?? 0}`,
    );
    if (res.stop_reason === 'refusal' || res.stop_reason === 'max_tokens') return null;
    const out = res.content.find((b) => b.type === 'text');
    return out ? JSON.parse(out.text) : null;
  }

  return { extract, ask, readContract };
}

/**
 * Rotas /ai/*. Sem `ai` (sem ANTHROPIC_API_KEY), respondem 503.
 */
function mountAi(app, { pool, authed, wrap, HttpError, ai }) {
  const needAi = () => {
    if (!ai) throw new HttpError(503, 'A IA não está configurada no servidor.');
  };

  async function count(user) {
    if (user.is_admin) return;
    const limit =
      accessOf(user).plan === 'gratis' ? FREE_MONTHLY_LIMIT : MONTHLY_LIMIT;
    const { rows } = await pool.query(
      `insert into ai_usage (user_id, month, calls) values ($1, $2, 1)
       on conflict (user_id, month) do update set calls = ai_usage.calls + 1
       returning calls`,
      [user.id, new Date().toISOString().slice(0, 7)],
    );
    if (rows[0].calls > limit) {
      throw new HttpError(
        429,
        `Você usou os ${limit} pedidos à IA deste mês. O limite volta no dia 1º.`,
      );
    }
  }

  app.get(
    '/ai/status',
    authed,
    wrap(async (req, res) => {
      res.json({ enabled: !!ai });
    }),
  );

  // Lê um cupom, nota, comprovante ou texto e devolve o rascunho do
  // lançamento (o app abre o formulário preenchido para conferir).
  app.post(
    '/ai/receipt',
    authed,
    wrap(async (req, res) => {
      needAi();
      const { text, media, mimeType } = req.body ?? {};
      if (!text && !media) throw new HttpError(400, 'Envie uma foto, PDF ou texto.');
      if (media && !MEDIA_TYPES.has(mimeType)) {
        throw new HttpError(400, 'Formato não suportado. Use foto (JPG/PNG) ou PDF.');
      }
      const data = media ? Buffer.from(String(media), 'base64') : null;
      if (data && data.length > 8 * 1024 * 1024) {
        throw new HttpError(413, 'Arquivo grande demais (máximo 8 MB).');
      }
      await count(req.user);
      const { rows } = await pool.query(
        `select coll, data from app_docs
         where user_id = data_owner($1) and not deleted and doc_visible($1, coll, id, data)
           and coll in ('accounts', 'cards', 'categories')`,
        [req.user.id],
      );
      const ctx = buildContext(rows);
      const raw = await ai.extract({
        text: text ? String(text).slice(0, 4000) : undefined,
        media: data ? { data, mimeType } : undefined,
        ctx,
      });
      const { draft, error } = normalizeDraft(raw, ctx);
      if (!draft) {
        throw new HttpError(
          422,
          error || 'Não consegui ler um lançamento nesse arquivo.',
        );
      }
      res.json({ draft });
    }),
  );

  // Lê um contrato ou extrato de empréstimo/financiamento e devolve os
  // campos encontrados para o usuário revisar antes de salvar.
  app.post(
    '/ai/contract',
    authed,
    wrap(async (req, res) => {
      needAi();
      const { text, media, mimeType } = req.body ?? {};
      if (!text && !media) throw new HttpError(400, 'Envie o PDF, uma foto ou o texto do contrato.');
      if (media && !MEDIA_TYPES.has(mimeType)) {
        throw new HttpError(400, 'Formato não suportado. Use PDF ou foto (JPG/PNG).');
      }
      const data = media ? Buffer.from(String(media), 'base64') : null;
      if (data && data.length > 8 * 1024 * 1024) {
        throw new HttpError(413, 'Arquivo grande demais (máximo 8 MB).');
      }
      await count(req.user);
      const contract = normalizeContract(
        await ai.readContract({
          text: text ? String(text).slice(0, 20000) : undefined,
          media: data ? { data, mimeType } : undefined,
        }),
      );
      if (!contract) {
        throw new HttpError(422, 'Não encontrei dados de contrato nesse arquivo.');
      }
      res.json({ contract });
    }),
  );

  app.post(
    '/ai/ask',
    authed,
    wrap(async (req, res) => {
      needAi();
      const { question, snapshot, history } = req.body ?? {};
      const q = String(question ?? '').trim();
      if (!q) throw new HttpError(400, 'Escreva uma pergunta.');
      await count(req.user);
      const answer = await ai.ask({
        question: q.slice(0, 2000),
        snapshot: String(snapshot ?? '').slice(0, MAX_SNAPSHOT),
        history: Array.isArray(history) ? history : [],
      });
      if (!answer) throw new HttpError(422, 'Não consegui responder essa pergunta.');
      res.json({ answer });
    }),
  );
}

module.exports = { createAi, mountAi, ASSISTANT_MODEL, normalizeContract, CONTRACT_SCHEMA };
