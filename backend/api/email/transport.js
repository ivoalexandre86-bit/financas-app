// Envio de e-mails. O provedor vem do ambiente:
//
// * EMAIL_TRANSPORT=brevo + BREVO_API_KEY: Brevo (aceita remetente verificado
//   por e-mail, sem domínio próprio).
// * EMAIL_TRANSPORT=resend + RESEND_API_KEY: Resend (exige domínio
//   verificado para mandar a outras pessoas).
// * EMAIL_TRANSPORT=log: sandbox; nada sai do servidor, a mensagem só vai
//   para o log (sem o conteúdo).
// * Sem EMAIL_TRANSPORT: e-mails desligados.
//
// EMAIL_FROM é o remetente ("Finanças <avisos@exemplo.com>" ou só o e-mail).
//
// Todo transporte recebe {to, subject, text, html, idempotencyKey} e devolve
// {id} (id da mensagem no provedor).

function parseFrom(from) {
  const m = /^\s*(.*?)\s*<([^>]+)>\s*$/.exec(from ?? '');
  if (m) return { name: m[1].replace(/^"|"$/g, '') || 'Finanças', email: m[2] };
  return { name: 'Finanças', email: String(from ?? '').trim() };
}

class EmailError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

async function postJson(fetchImpl, url, headers, body) {
  const res = await fetchImpl(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json = {};
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    // resposta fora do padrão
  }
  if (!res.ok) {
    throw new EmailError(`Provedor de e-mail respondeu ${res.status}: ${json.message ?? text.slice(0, 200)}`, res.status);
  }
  return json;
}

function createBrevoTransport({ apiKey, from, fetchImpl = fetch }) {
  const sender = parseFrom(from);
  return {
    name: 'brevo',
    sandbox: false,
    async send({ to, subject, text, html, idempotencyKey }) {
      const r = await postJson(fetchImpl, 'https://api.brevo.com/v3/smtp/email', { 'api-key': apiKey }, {
        sender,
        to: [{ email: to }],
        subject,
        textContent: text,
        htmlContent: html,
        headers: idempotencyKey ? { 'X-Financas-Key': idempotencyKey } : undefined,
      });
      return { id: r.messageId ?? null };
    },
  };
}

function createResendTransport({ apiKey, from, fetchImpl = fetch }) {
  return {
    name: 'resend',
    sandbox: false,
    async send({ to, subject, text, html, idempotencyKey }) {
      const r = await postJson(
        fetchImpl,
        'https://api.resend.com/emails',
        {
          authorization: `Bearer ${apiKey}`,
          // O Resend descarta repetições com a mesma chave por 24 h.
          ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
        },
        { from, to: [to], subject, text, html },
      );
      return { id: r.id ?? null };
    },
  };
}

/** Sandbox: guarda as mensagens na memória (testes) e não envia nada. */
function createMemoryTransport({ fail } = {}) {
  const sent = [];
  let n = 0;
  return {
    name: 'memory',
    sandbox: true,
    sent,
    async send(msg) {
      if (fail?.(msg)) throw new EmailError('falha simulada', 503);
      const id = `mem-${++n}`;
      sent.push({ ...msg, id });
      return { id };
    },
  };
}

/** Sandbox em produção: registra no log que haveria um envio. */
function createLogTransport({ log = console.log } = {}) {
  let n = 0;
  return {
    name: 'log',
    sandbox: true,
    async send({ subject, idempotencyKey }) {
      const id = `log-${Date.now()}-${++n}`;
      log(`E-mail (sandbox, não enviado): "${subject}" [${idempotencyKey ?? '-'}]`);
      return { id };
    },
  };
}

/** Transporte configurado no ambiente, ou null (e-mails desligados). */
function transportFromEnv(env) {
  const kind = (env.EMAIL_TRANSPORT ?? '').trim().toLowerCase();
  const from = env.EMAIL_FROM;
  if (kind === 'log') return createLogTransport();
  if (kind === 'brevo' && env.BREVO_API_KEY && from) {
    return createBrevoTransport({ apiKey: env.BREVO_API_KEY, from });
  }
  if (kind === 'resend' && env.RESEND_API_KEY && from) {
    return createResendTransport({ apiKey: env.RESEND_API_KEY, from });
  }
  if (kind) console.error(`E-mail: EMAIL_TRANSPORT=${kind} sem chave ou EMAIL_FROM; e-mails desligados`);
  return null;
}

module.exports = {
  createBrevoTransport,
  createResendTransport,
  createMemoryTransport,
  createLogTransport,
  transportFromEnv,
  parseFrom,
  EmailError,
};
