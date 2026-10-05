// Cliente mínimo da API da Pluggy (agregador Open Finance autorizado pelo
// Banco Central). Usado pelo servidor; as credenciais nunca vão para o app.
// Referência: SDK oficial `pluggy-sdk` (auth, items, accounts, v2/transactions).

const DEFAULT_BASE = 'https://api.pluggy.ai';
// A chave da Pluggy vale 2 horas; renovamos antes disso.
const KEY_TTL_MS = 90 * 60 * 1000;
const MAX_PAGES = 50;

class PluggyError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/**
 * @param {{clientId: string, clientSecret: string, baseUrl?: string,
 *   fetch?: typeof fetch}} opts
 */
function createPluggy({ clientId, clientSecret, baseUrl = DEFAULT_BASE, fetch: f = fetch }) {
  let apiKey = null;
  let apiKeyAt = 0;

  async function request(method, path, { body, query, auth = true } = {}) {
    const url = new URL(path, baseUrl);
    for (const [k, v] of Object.entries(query ?? {})) {
      if (v != null) url.searchParams.set(k, String(v));
    }
    const headers = { Accept: 'application/json' };
    if (body) headers['Content-Type'] = 'application/json';
    if (auth) headers['X-API-KEY'] = await key();
    const res = await f(url, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    let json = {};
    try {
      json = text ? JSON.parse(text) : {};
    } catch {
      // resposta fora do padrão
    }
    if (!res.ok) {
      if (auth && res.status === 401) apiKey = null;
      throw new PluggyError(res.status, json.message || `Pluggy respondeu ${res.status}`);
    }
    return json;
  }

  async function key() {
    if (apiKey && Date.now() - apiKeyAt < KEY_TTL_MS) return apiKey;
    const r = await request('POST', '/auth', {
      body: { clientId, clientSecret, nonExpiring: false },
      auth: false,
    });
    if (!r.apiKey) throw new PluggyError(502, 'Pluggy não devolveu a chave de acesso');
    apiKey = r.apiKey;
    apiKeyAt = Date.now();
    return apiKey;
  }

  return {
    /** Token de 30 min para abrir a janela Pluggy Connect no app. */
    async createConnectToken(clientUserId) {
      const r = await request('POST', '/connect_token', {
        body: { options: { clientUserId } },
      });
      if (!r.accessToken) throw new PluggyError(502, 'Pluggy não devolveu o token de conexão');
      return r.accessToken;
    },
    getItem: (id) => request('GET', `/items/${encodeURIComponent(id)}`),
    getAccount: (id) => request('GET', `/accounts/${encodeURIComponent(id)}`),
    async listAccounts(itemId) {
      const r = await request('GET', '/accounts', { query: { itemId } });
      return r.results ?? [];
    },
    /** Todas as transações da conta desde `dateFrom` (AAAA-MM-DD). */
    async listTransactions(accountId, dateFrom) {
      const out = [];
      let after = null;
      for (let i = 0; i < MAX_PAGES; i++) {
        const r = await request('GET', '/v2/transactions', {
          query: { accountId, dateFrom, after },
        });
        out.push(...(r.results ?? []));
        after = r.next ? new URL(r.next, baseUrl).searchParams.get('after') : null;
        if (!after) break;
      }
      return out;
    },
  };
}

/** Transação da Pluggy no formato que o app usa (valor com sinal). */
function toAppTransaction(t) {
  const abs = Math.abs(Number(t.amountInAccountCurrency ?? t.amount) || 0);
  const m = t.creditCardMetadata;
  let description = String(t.description ?? t.descriptionRaw ?? '').trim() || 'Sem descrição';
  if (m?.totalInstallments > 1 && m.installmentNumber) {
    description += ` (${m.installmentNumber}/${m.totalInstallments})`;
  }
  return {
    id: t.id,
    date: String(t.date).slice(0, 10),
    // DEBIT = dinheiro saindo; CREDIT = entrando.
    amountCents: Math.round(abs * 100) * (t.type === 'DEBIT' ? -1 : 1),
    description,
    pending: t.status === 'PENDING',
  };
}

function toAppAccount(a, item) {
  const name = String(a.marketingName || a.name || 'Conta').trim();
  const tail = String(a.number ?? '').replace(/\D/g, '').slice(-4);
  return {
    id: a.id,
    itemId: a.itemId ?? item?.id,
    kind: a.type === 'CREDIT' ? 'credit_card' : 'bank',
    name,
    label: [item?.connector?.name, name + (tail ? ` ••${tail}` : '')]
      .filter(Boolean)
      .join(' · '),
    balanceCents: Math.round((Number(a.balance) || 0) * 100),
  };
}

module.exports = { createPluggy, toAppTransaction, toAppAccount, PluggyError };
