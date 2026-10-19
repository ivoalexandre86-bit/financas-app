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

Seja direto e curto: no máximo uns 8 parágrafos curtos ou listas, valores no formato R$ 1.234,56. Pode fazer contas, comparar meses, apontar gastos que cresceram e sugerir cortes ou metas realistas. Não invente lançamentos, não dê recomendação de investimento específico (produto, ação, fundo) e não fale de assuntos fora das finanças do usuário.`;

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
      max_tokens: 1500,
      system: ASSISTANT_SYSTEM,
      messages: merged,
    });
    log(
      `Assistente IA: ${res.model ?? model} in=${res.usage?.input_tokens ?? 0} ` +
        `out=${res.usage?.output_tokens ?? 0}`,
    );
    if (res.stop_reason === 'refusal') return null;
    return res.content
      .filter((b) => b.type === 'text')
      .map((b) => b.text)
      .join('')
      .trim();
  }

  return { extract, ask };
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
         where user_id = $1 and not deleted
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

module.exports = { createAi, mountAi, ASSISTANT_MODEL };
