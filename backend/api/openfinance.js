// Open Finance (Pluggy) no servidor: registra as conexões de cada usuário,
// guarda as transações recebidas (uma linha por ID do provedor, então
// repetir a busca nunca duplica), acompanha o estado da conexão e mantém
// tudo atualizado sozinho:
//
// - webhook: a Pluggy avisa quando a conexão foi atualizada (sincronização
//   automática diária dela) ou quando transações foram criadas, alteradas
//   ou removidas;
// - varredura periódica: se um aviso se perder, o servidor busca de novo;
// - "Sincronizar agora": pede à Pluggy uma atualização na hora.
//
// O app lê daqui só o que mudou desde a última leitura (cursor) e concilia
// com os lançamentos do usuário. As credenciais da Pluggy nunca saem do
// servidor.

const crypto = require('crypto');
const { toAppTransaction, toAppAccount, PluggyError } = require('./pluggy');

const ITEM_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const DEFAULT_SYNC_DAYS = 90;
// Revisita alguns dias antes da última busca (lançamentos que o banco
// confirma com atraso).
const OVERLAP_DAYS = 10;
// Até onde buscar lançamentos futuros (agendados, parcelas a vencer).
const FUTURE_DAYS = 400;
// Consentimento perto de vencer: avisa com esta antecedência.
const EXPIRING_DAYS = 7;
// Varredura: conexões sem busca há mais de STALE_MS são atualizadas.
const STALE_MS = 6 * 3600 * 1000;
const SWEEP_MS = 60 * 60 * 1000;
// A Pluggy espera resposta do webhook em até 10 s.
const WEBHOOK_WAIT_MS = 8000;
// Margem do cursor: gravações concorrentes não escapam da próxima leitura.
const CURSOR_MARGIN_MS = 60 * 1000;

// Situações em que só o usuário resolve, refazendo a autorização no banco.
const RENEW_EXECUTION = new Set([
  'USER_AUTHORIZATION_REVOKED',
  'USER_AUTHORIZATION_NOT_GRANTED',
  'INVALID_CREDENTIALS',
  'INVALID_CREDENTIALS_MFA',
  'ACCOUNT_CREDENTIALS_RESET',
  'ACCOUNT_NEEDS_ACTION',
  'ACCOUNT_LOCKED',
]);

const isoDay = (d) => new Date(d).toISOString().slice(0, 10);
const brDate = (d) => {
  const [y, m, day] = isoDay(d).split('-');
  return `${day}/${m}/${y}`;
};

/**
 * Situação da conexão para o app: ok, updating, error, expiring (aviso),
 * renew (renovar o consentimento / refazer o login) ou action (o banco
 * aguarda uma confirmação do usuário).
 */
function itemHealth(row, now = new Date()) {
  const exp = row.consent_expires_at ? new Date(row.consent_expires_at) : null;
  if (row.status === 'DELETED') {
    return { state: 'renew', message: 'A conexão foi removida no provedor. Conecte o banco de novo.' };
  }
  if (exp && exp <= now) {
    return {
      state: 'renew',
      message: `O consentimento venceu em ${brDate(exp)}. Renove para voltar a receber os dados.`,
    };
  }
  if (row.status === 'LOGIN_ERROR' || RENEW_EXECUTION.has(row.execution_status)) {
    return {
      state: 'renew',
      message: 'O banco não aceitou mais o acesso. Renove o consentimento para voltar a sincronizar.',
    };
  }
  if (row.status === 'WAITING_USER_INPUT' || row.execution_status === 'USER_AUTHORIZATION_PENDING') {
    return { state: 'action', message: 'O banco está aguardando sua confirmação para continuar.' };
  }
  if (row.status === 'UPDATING') {
    return { state: 'updating', message: 'O banco está enviando os dados atualizados.' };
  }
  if (row.status === 'OUTDATED' || row.fetch_error) {
    return {
      state: 'error',
      message: row.error_message || row.fetch_error ||
        'A última atualização falhou. Uma nova tentativa é feita automaticamente.',
    };
  }
  if (exp && exp - now <= EXPIRING_DAYS * 864e5) {
    return { state: 'expiring', message: `O consentimento vence em ${brDate(exp)}. Renove para não interromper.` };
  }
  return { state: 'ok', message: null };
}

const iso = (v) => (v ? new Date(v).toISOString() : null);

function toItemJson(row, now) {
  const health = itemHealth(row, now);
  return {
    id: row.item_id,
    institution: row.institution ?? null,
    status: row.status ?? null,
    executionStatus: row.execution_status ?? null,
    providerUpdatedAt: iso(row.provider_updated_at),
    consentExpiresAt: iso(row.consent_expires_at),
    nextAutoSyncAt: iso(row.next_auto_sync_at),
    fetchedAt: iso(row.fetched_at),
    health: health.state,
    message: health.message,
    needsRenewal: health.state === 'renew' || health.state === 'action',
  };
}

/**
 * @param {{pool: import('pg').Pool, pluggy: object|null, jwtSecret: string,
 *   publicUrl?: string, now?: () => Date}} opts
 */
function createOpenFinance({ pool, pluggy, jwtSecret, publicUrl, now = () => new Date() }) {
  // Segredo do endereço do webhook (a Pluggy não assina os avisos que vêm
  // do webhookUrl da conexão): derivado do JWT_SECRET, nada a configurar.
  const webhookToken = crypto
    .createHmac('sha256', jwtSecret)
    .update('pluggy-webhook')
    .digest('hex')
    .slice(0, 40);
  const webhookUrl = publicUrl
    ? `${publicUrl.replace(/\/+$/, '')}/openfinance/webhook/${webhookToken}`
    : undefined;

  async function saveItemStatus(itemId, item) {
    await pool.query(
      `update of_items set
         institution = coalesce($2, institution),
         status = $3, execution_status = $4,
         error_code = $5, error_message = $6,
         provider_updated_at = $7, consent_expires_at = $8,
         next_auto_sync_at = $9
       where item_id = $1`,
      [
        itemId,
        item.connector?.name ?? null,
        item.status ?? null,
        item.executionStatus ?? null,
        item.error?.code ?? null,
        item.error?.message ?? null,
        item.lastUpdatedAt ?? null,
        item.consentExpiresAt ?? null,
        item.nextAutoSyncAt ?? null,
      ],
    );
  }

  /// Grava transações da Pluggy; só muda a linha (e o updated_at, que move
  /// o cursor do app) quando algo mudou de fato.
  async function upsertTransactions(itemId, accountId, txs) {
    if (!txs.length) return 0;
    const rows = txs.map((t) => toAppTransaction(t));
    const r = await pool.query(
      `insert into of_transactions (tx_id, item_id, account_id, date, data, pending, deleted, updated_at)
       select t.id, $1, $2, t.date::date, t.data, t.pending, false, now()
       from unnest($3::text[], $4::text[], $5::jsonb[], $6::bool[]) as t(id, date, data, pending)
       on conflict (tx_id) do update
         set date = excluded.date, data = excluded.data, pending = excluded.pending,
             deleted = false, account_id = excluded.account_id, updated_at = now()
         where (of_transactions.data, of_transactions.pending, of_transactions.deleted)
           is distinct from (excluded.data, excluded.pending, false)`,
      [
        itemId,
        accountId,
        rows.map((x) => x.id),
        rows.map((x) => x.date),
        rows.map((x) => JSON.stringify(x)),
        rows.map((x) => x.pending),
      ],
    );
    return r.rowCount;
  }

  async function markDeleted(itemId, ids) {
    if (!ids.length) return 0;
    const r = await pool.query(
      `update of_transactions set deleted = true, updated_at = now()
       where item_id = $1 and tx_id = any($2::text[]) and not deleted`,
      [itemId, ids],
    );
    return r.rowCount;
  }

  /// Relê transações pelo ID; as que a Pluggy não devolve mais foram
  /// removidas no banco.
  async function refetchByIds(itemId, accountId, ids) {
    if (!ids.length) return;
    const got = await pluggy.listTransactionsByIds(accountId, ids);
    await upsertTransactions(itemId, accountId, got);
    const seen = new Set(got.map((t) => t.id));
    await markDeleted(itemId, ids.filter((id) => !seen.has(id)));
  }

  const running = new Map();

  /// Atualiza o estado da conexão e busca as transações (com janela que
  /// cobre o que o banco confirmou com atraso e os lançamentos futuros).
  /// Chamadas simultâneas para a mesma conexão compartilham a mesma busca.
  function refreshItem(itemId, { from } = {}) {
    if (running.has(itemId)) return running.get(itemId);
    const job = (async () => {
      try {
        const item = await pluggy.getItem(itemId);
        await saveItemStatus(itemId, item);
        const { rows: [row] } = await pool.query(
          'select fetched_at from of_items where item_id = $1',
          [itemId],
        );
        const today = now();
        const base = row?.fetched_at
          ? new Date(new Date(row.fetched_at).getTime() - OVERLAP_DAYS * 864e5)
          : new Date(today.getTime() - DEFAULT_SYNC_DAYS * 864e5);
        let since = isoDay(base);
        if (from && from < since) since = from;
        const until = isoDay(today.getTime() + FUTURE_DAYS * 864e5);
        for (const acc of await pluggy.listAccounts(itemId)) {
          const txs = await pluggy.listTransactions(acc.id, since, until);
          await upsertTransactions(itemId, acc.id, txs);
          // Lançamentos ainda previstos de antes da janela: confere se já
          // foram confirmados ou cancelados.
          const seen = new Set(txs.map((t) => t.id));
          const { rows: open } = await pool.query(
            `select tx_id from of_transactions
             where item_id = $1 and account_id = $2 and pending and not deleted`,
            [itemId, acc.id],
          );
          const stale = open.map((r) => r.tx_id).filter((id) => !seen.has(id));
          if (stale.length && pluggy.listTransactionsByIds) {
            await refetchByIds(itemId, acc.id, stale);
          }
        }
        await pool.query(
          'update of_items set fetched_at = now(), fetch_error = null where item_id = $1',
          [itemId],
        );
      } catch (e) {
        if (e instanceof PluggyError && e.status === 404) {
          await pool.query("update of_items set status = 'DELETED' where item_id = $1", [itemId]);
        } else {
          await pool.query('update of_items set fetch_error = $2 where item_id = $1', [
            itemId,
            String(e.message ?? e).slice(0, 300),
          ]);
        }
        throw e;
      } finally {
        running.delete(itemId);
      }
    })();
    running.set(itemId, job);
    return job;
  }

  /// Processa um aviso da Pluggy. Devolve o que foi feito (para os testes).
  async function processEvent(ev) {
    const itemId = String(ev?.itemId ?? '');
    const { rows } = await pool.query('select 1 from of_items where item_id = $1', [itemId]);
    if (!rows.length) return 'ignored';
    switch (ev.event) {
      case 'item/deleted':
        await pool.query("update of_items set status = 'DELETED' where item_id = $1", [itemId]);
        return 'deleted';
      case 'item/error':
      case 'item/waiting_user_input':
      case 'item/waiting_user_action':
        await saveItemStatus(itemId, await pluggy.getItem(itemId));
        return 'status';
      case 'transactions/deleted':
        await markDeleted(itemId, (ev.transactionIds ?? []).map(String));
        return 'transactions';
      case 'transactions/updated':
        if (ev.accountId && pluggy.listTransactionsByIds) {
          await refetchByIds(itemId, String(ev.accountId), (ev.transactionIds ?? []).map(String));
          return 'transactions';
        }
        await refreshItem(itemId);
        return 'refreshed';
      case 'transactions/created': {
        const min = String(ev.transactionsMinDate ?? '').slice(0, 10);
        await refreshItem(itemId, { from: DATE_RE.test(min) ? min : undefined });
        return 'refreshed';
      }
      case 'item/created':
      case 'item/updated':
      case 'item/login_succeeded':
        await refreshItem(itemId);
        return 'refreshed';
      default:
        return 'ignored';
    }
  }

  /// Recebe o webhook: confere o segredo do endereço, descarta repetidos
  /// (eventId) e responde dentro do prazo da Pluggy.
  async function receiveWebhook(token, ev) {
    const a = Buffer.from(String(token ?? ''));
    const b = Buffer.from(webhookToken);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return { status: 401 };
    const eventId = ev?.eventId ? String(ev.eventId) : null;
    if (eventId) {
      const r = await pool.query(
        'insert into of_webhook_events (event_id) values ($1) on conflict do nothing',
        [eventId],
      );
      if (!r.rowCount) return { status: 200, result: 'duplicate' };
    }
    const work = processEvent(ev).catch(async (e) => {
      // Libera o evento para a nova tentativa da Pluggy.
      if (eventId) await pool.query('delete from of_webhook_events where event_id = $1', [eventId]);
      throw e;
    });
    let timer;
    const timeout = new Promise((resolve) => {
      timer = setTimeout(() => resolve('pending'), WEBHOOK_WAIT_MS);
      timer.unref?.();
    });
    try {
      const result = await Promise.race([work, timeout]);
      if (result === 'pending') {
        work.catch((e) => console.error('Pluggy webhook:', e.message));
      }
      return { status: 200, result };
    } catch (e) {
      console.error('Pluggy webhook:', e.message);
      return { status: 500 };
    } finally {
      clearTimeout(timer);
    }
  }

  /// Rede de segurança: atualiza as conexões sem busca recente.
  async function sweep() {
    const { rows } = await pool.query(
      `select item_id from of_items
       where coalesce(status, '') <> 'DELETED'
         and (fetched_at is null or fetched_at < $1)
       order by fetched_at nulls first limit 50`,
      [new Date(now().getTime() - STALE_MS)],
    );
    let ok = 0;
    for (const { item_id: id } of rows) {
      try {
        await refreshItem(id);
        ok++;
      } catch (e) {
        console.error(`Open Finance: falha ao atualizar ${id}:`, e.message);
      }
    }
    return ok;
  }

  return {
    webhookToken,
    webhookUrl,
    saveItemStatus,
    refreshItem,
    processEvent,
    receiveWebhook,
    sweep,
    start(intervalMs = SWEEP_MS) {
      const tick = () => sweep().catch((e) => console.error('Open Finance:', e.message));
      setTimeout(tick, 60 * 1000).unref?.();
      setInterval(tick, intervalMs).unref?.();
    },
  };
}

/**
 * Rotas /openfinance/*. Só quem tem acesso total ao orçamento (o dono ou
 * membro sem limite) usa as conexões; convidado com acesso limitado não.
 */
function mountOpenFinance(app, { pool, authed, wrap, HttpError, premium, pluggy, of }) {
  const needPluggy = () => {
    if (!pluggy) {
      throw new HttpError(
        503,
        'Open Finance ainda não configurado no servidor (faltam as credenciais da Pluggy).',
      );
    }
    return pluggy;
  };
  /// Erros da Pluggy viram mensagens claras para o app.
  const fromPluggy = async (fn) => {
    try {
      return await fn();
    } catch (e) {
      if (!(e instanceof PluggyError)) throw e;
      if (e.status === 404) throw new HttpError(404, 'Conexão não encontrada na Pluggy. Confira o ID.');
      if (e.status === 401 || e.status === 403) {
        throw new HttpError(502, 'A Pluggy recusou as credenciais do servidor.');
      }
      throw new HttpError(502, `Falha na Pluggy: ${e.message}`);
    }
  };
  const fullAccess = async (userId) => {
    const { rows } = await pool.query('select member_scope($1) as s', [userId]);
    if (rows[0].s != null) {
      throw new HttpError(403, 'Seu acesso a este orçamento é limitado; o Open Finance fica com quem compartilhou.');
    }
  };
  /// Conexão que o usuário pode usar: dele ou do dono do orçamento em que
  /// ele está com acesso total.
  const itemFor = async (userId, itemId) => {
    const { rows } = await pool.query(
      `select * from of_items
       where item_id = $1 and user_id in ($2, data_owner($2))
         and member_scope($2) is null`,
      [itemId, userId],
    );
    return rows[0] ?? null;
  };

  app.get('/openfinance/status', authed, (req, res) =>
    res.json({ provider: 'pluggy', configured: !!pluggy, autoSync: !!(pluggy && of.webhookUrl) }));

  /// "Me avise quando lançar": quem viu a demonstração (fora do Premium) e
  /// quer saber quando o Open Finance estiver disponível.
  app.post('/openfinance/interest', authed, wrap(async (req, res) => {
    await pool.query(
      'insert into openfinance_interest (user_id) values ($1) on conflict do nothing',
      [req.user.id],
    );
    res.status(204).end();
  }));

  /// Token para a janela Pluggy Connect: o usuário escolhe o banco ali
  /// mesmo. Com `itemId`, abre a renovação do consentimento dessa conexão.
  app.post('/openfinance/connect-token', premium, wrap(async (req, res) => {
    const p = needPluggy();
    await fullAccess(req.user.id);
    const itemId = req.body?.itemId ? String(req.body.itemId) : null;
    if (itemId && !(await itemFor(req.user.id, itemId))) {
      throw new HttpError(404, 'Conexão não encontrada');
    }
    const token = await fromPluggy(() =>
      p.createConnectToken(req.user.id, { itemId: itemId ?? undefined, webhookUrl: of.webhookUrl }));
    res.json({ connectToken: token });
  }));

  /// Registra uma conexão (item) da Pluggy para o usuário e devolve as
  /// contas dela.
  app.post('/openfinance/items', premium, wrap(async (req, res) => {
    const p = needPluggy();
    await fullAccess(req.user.id);
    const itemId = String(req.body?.itemId ?? '').trim();
    if (!ITEM_ID_RE.test(itemId)) {
      throw new HttpError(400, 'ID da conexão inválido (formato esperado: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).');
    }
    const item = await fromPluggy(() => p.getItem(itemId));
    // Conexão criada pela janela do app para outro usuário: não é sua.
    if (item.clientUserId && item.clientUserId !== req.user.id) {
      throw new HttpError(409, 'Esta conexão já está vinculada a outro usuário.');
    }
    const { rows } = await pool.query(
      `insert into of_items (item_id, user_id) values ($1, $2)
       on conflict (item_id) do update set item_id = excluded.item_id
       returning user_id`,
      [itemId, req.user.id],
    );
    if (rows[0].user_id !== req.user.id) {
      throw new HttpError(409, 'Esta conexão já está vinculada a outro usuário.');
    }
    await of.saveItemStatus(itemId, item);
    // Conexão colada à mão: passa a avisar o servidor também.
    if (of.webhookUrl && p.updateItem) {
      await p.updateItem(itemId, { webhookUrl: of.webhookUrl }).catch(() => {});
    }
    const accounts = await fromPluggy(() => p.listAccounts(itemId));
    res.status(201).json({
      item: {
        id: item.id,
        institution: item.connector?.name ?? 'Instituição',
        status: item.status ?? null,
        lastUpdatedAt: item.lastUpdatedAt ?? null,
        consentExpiresAt: item.consentExpiresAt ?? null,
      },
      accounts: accounts.map((a) => toAppAccount(a, item)),
    });
  }));

  /// Conexões do usuário com a situação de cada uma (última atualização,
  /// falha, consentimento a renovar).
  app.get('/openfinance/items', authed, wrap(async (req, res) => {
    const { rows } = await pool.query(
      `select * from of_items
       where user_id in ($1, data_owner($1)) and member_scope($1) is null
       order by created_at`,
      [req.user.id],
    );
    const t = new Date();
    res.json({ items: rows.map((r) => toItemJson(r, t)) });
  }));

  /// "Sincronizar agora": pede à Pluggy uma atualização da conexão e busca
  /// o que ela já tem. O que o banco mandar depois chega pelo webhook.
  app.post('/openfinance/items/:itemId/sync', authed, wrap(async (req, res) => {
    const p = needPluggy();
    const row = await itemFor(req.user.id, req.params.itemId);
    if (!row) throw new HttpError(404, 'Conexão não encontrada');
    let requested = false;
    if (p.updateItem) {
      // 409 = já atualizando; outras recusas (ex.: consentimento vencido)
      // aparecem no estado da conexão.
      requested = await p.updateItem(row.item_id, { webhookUrl: of.webhookUrl })
        .then(() => true, () => false);
    }
    try {
      await of.refreshItem(row.item_id);
    } catch (e) {
      if (!(e instanceof PluggyError)) throw e;
    }
    const { rows: [fresh] } = await pool.query('select * from of_items where item_id = $1', [row.item_id]);
    res.json({ requested, item: toItemJson(fresh, new Date()) });
  }));

  app.delete('/openfinance/items/:itemId', authed, wrap(async (req, res) => {
    await pool.query('delete from of_items where item_id = $1 and user_id = $2', [
      req.params.itemId,
      req.user.id,
    ]);
    res.status(204).end();
  }));

  /// Transações guardadas de uma conta. Com `since` (cursor devolvido na
  /// leitura anterior), só o que mudou desde então, incluindo removidas;
  /// sem ele, desde `from` (AAAA-MM-DD; padrão: 90 dias).
  app.get('/openfinance/accounts/:accountId/transactions', authed, wrap(async (req, res) => {
    const p = needPluggy();
    const from = String(req.query.from ?? '');
    if (from && !DATE_RE.test(from)) throw new HttpError(400, 'Data inválida');
    const since = req.query.since ? new Date(String(req.query.since)) : null;
    if (since && Number.isNaN(since.getTime())) throw new HttpError(400, 'Cursor inválido');
    const accountId = String(req.params.accountId);

    const { rows: known } = await pool.query(
      'select item_id from of_transactions where account_id = $1 limit 1',
      [accountId],
    );
    let itemId = known[0]?.item_id;
    if (!itemId) {
      const account = await fromPluggy(() => p.getAccount(accountId));
      itemId = account.itemId;
    }
    const row = itemId ? await itemFor(req.user.id, itemId) : null;
    if (!row) throw new HttpError(404, 'Conta não encontrada');
    // Primeira leitura de uma conexão antiga: busca na Pluggy agora.
    if (!row.fetched_at) await fromPluggy(() => of.refreshItem(itemId, { from: from || undefined }));

    const { rows: [{ t }] } = await pool.query('select now() as t');
    const cursor = new Date(new Date(t).getTime() - CURSOR_MARGIN_MS).toISOString();
    const startDay = from ||
      isoDay(Date.now() - DEFAULT_SYNC_DAYS * 864e5);
    const { rows } = since
      ? await pool.query(
          `select data, deleted from of_transactions
           where account_id = $1 and item_id = $2 and updated_at > $3 order by date, tx_id`,
          [accountId, itemId, since],
        )
      : await pool.query(
          `select data, deleted from of_transactions
           where account_id = $1 and item_id = $2 and (date >= $3 or pending)
           order by date, tx_id`,
          [accountId, itemId, startDay],
        );
    res.json({
      transactions: rows.map((r) => ({ ...r.data, deleted: r.deleted })),
      cursor,
    });
  }));

  /// Avisos da Pluggy (configurado como webhookUrl de cada conexão).
  app.post('/openfinance/webhook/:token', wrap(async (req, res) => {
    if (!pluggy) return res.status(503).end();
    const r = await of.receiveWebhook(req.params.token, req.body ?? {});
    res.status(r.status).json(r.result ? { result: r.result } : {});
  }));
}

module.exports = { createOpenFinance, mountOpenFinance, itemHealth, toItemJson };
