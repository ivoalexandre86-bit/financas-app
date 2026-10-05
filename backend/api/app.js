// Finanças · API: login (e-mail + senha, token JWT), gestão de usuários pelo
// administrador e sincronização dos dados do app (documentos JSON por
// usuário). Cada usuário só acessa os próprios dados.

const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { toAppTransaction, toAppAccount, PluggyError } = require('./pluggy');
const { mountWhatsApp } = require('./whatsapp/routes');

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const TOKEN_DAYS = 30;
const MAX_BATCH = 1000;
const ITEM_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const DEFAULT_SYNC_DAYS = 90;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const normEmail = (e) => String(e ?? '').trim().toLowerCase();

function checkEmail(email) {
  if (!EMAIL_RE.test(email)) throw new HttpError(400, 'E-mail inválido');
}

function checkPassword(p) {
  p = String(p ?? '');
  if (p.length < 8) {
    throw new HttpError(400, 'A senha deve ter ao menos 8 caracteres');
  }
  if (!/[A-Za-z]/.test(p) || !/\d/.test(p)) {
    throw new HttpError(400, 'Use letras e números');
  }
}

function checkName(n) {
  if (!String(n ?? '').trim()) throw new HttpError(400, 'Informe o nome');
}

const toUser = (r) => ({
  id: r.id,
  name: r.name,
  email: r.email,
  isAdmin: r.is_admin,
});

/// Limita tentativas de login por IP + e-mail (proteção contra força bruta).
function loginLimiter({ max = 10, windowMs = 15 * 60 * 1000 } = {}) {
  const hits = new Map();
  return (key) => {
    const now = Date.now();
    const h = hits.get(key);
    if (!h || now - h.start > windowMs) {
      hits.set(key, { start: now, count: 1 });
      return;
    }
    h.count++;
    if (h.count > max) {
      throw new HttpError(429, 'Muitas tentativas. Tente de novo em alguns minutos.');
    }
  };
}

/**
 * @param {{pool: import('pg').Pool, jwtSecret: string, allowedOrigins?: string[],
 *   pluggy?: ReturnType<typeof import('./pluggy').createPluggy> | null,
 *   whatsapp?: object}} opts  `whatsapp`: ver whatsapp/routes.js (opcional)
 */
function createApp({ pool, jwtSecret, allowedOrigins = [], pluggy = null, whatsapp }) {
  if (!jwtSecret || jwtSecret.length < 32) {
    throw new Error('JWT_SECRET ausente ou curto demais (mínimo 32 caracteres)');
  }
  const app = express();
  app.disable('x-powered-by');
  app.use(
    cors({
      origin: (origin, cb) =>
        cb(null, !origin || allowedOrigins.includes(origin)),
      methods: ['GET', 'POST', 'PATCH', 'DELETE'],
      allowedHeaders: ['Authorization', 'Content-Type'],
      maxAge: 86400,
    }),
  );
  app.use(
    express.json({
      limit: '10mb',
      // Corpo original para conferir a assinatura dos webhooks da Meta.
      verify: (req, res, buf) => {
        if (req.url.startsWith('/whatsapp/webhook')) req.rawBody = buf;
      },
    }),
  );

  const limit = loginLimiter();
  const wrap = (fn) => (req, res, next) =>
    Promise.resolve(fn(req, res)).catch(next);

  const sign = (user) =>
    jwt.sign({ sub: user.id }, jwtSecret, {
      algorithm: 'HS256',
      expiresIn: `${TOKEN_DAYS}d`,
    });

  /// Usuário autenticado (lido do banco a cada requisição, para refletir
  /// exclusões e mudança de papel na hora).
  const authed = (req, res, next) => {
    (async () => {
      const h = req.get('authorization') ?? '';
      const token = h.startsWith('Bearer ') ? h.slice(7) : null;
      const expired = new HttpError(401, 'Sessão expirada. Entre novamente.');
      if (!token) throw expired;
      let sub;
      try {
        sub = jwt.verify(token, jwtSecret, { algorithms: ['HS256'] }).sub;
      } catch {
        throw expired;
      }
      const { rows } = await pool.query('select * from users where id = $1', [
        sub,
      ]);
      if (!rows.length) throw expired;
      req.user = rows[0];
    })().then(() => next(), next);
  };
  const admin = (req, res, next) =>
    authed(req, res, (err) => {
      if (err) return next(err);
      if (!req.user.is_admin) {
        return next(new HttpError(403, 'Somente administradores gerenciam usuários'));
      }
      next();
    });

  async function insertUser(client, { name, email, password, isAdmin }) {
    checkName(name);
    const e = normEmail(email);
    checkEmail(e);
    checkPassword(password);
    const hash = await bcrypt.hash(String(password), 10);
    try {
      const { rows } = await client.query(
        `insert into users (name, email, password_hash, is_admin)
         values ($1, $2, $3, $4) returning *`,
        [String(name).trim(), e, hash, !!isAdmin],
      );
      return rows[0];
    } catch (err) {
      if (err.code === '23505') {
        throw new HttpError(409, 'Já existe uma conta com este e-mail');
      }
      throw err;
    }
  }

  /// Impede deixar o servidor sem administrador enquanto houver outras contas.
  async function checkNotLastAdmin(client, id) {
    const { rows } = await client.query(
      `select
         (select is_admin from users where id = $1) as target_admin,
         (select count(*) from users where is_admin)::int as admins,
         (select count(*) from users)::int as total`,
      [id],
    );
    const r = rows[0];
    if (r.target_admin && r.admins === 1 && r.total > 1) {
      throw new HttpError(
        409,
        'Este é o único administrador. Torne outro usuário administrador antes.',
      );
    }
  }

  async function inTx(fn) {
    const client = await pool.connect();
    try {
      await client.query('begin');
      // Serializa mudanças de usuários (1º cadastro, último admin).
      await client.query("select pg_advisory_xact_lock(hashtext('users'))");
      const out = await fn(client);
      await client.query('commit');
      return out;
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }
  }

  // Saúde -------------------------------------------------------------------

  app.get('/health', wrap(async (req, res) => {
    await pool.query('select 1');
    res.json({ ok: true });
  }));

  // Login e conta -----------------------------------------------------------

  app.get('/auth/has-users', wrap(async (req, res) => {
    const { rows } = await pool.query('select exists (select 1 from users) as e');
    res.json({ hasUsers: rows[0].e });
  }));

  /// Cadastro aberto: só na 1ª conta do servidor, que vira administradora.
  app.post('/auth/register', wrap(async (req, res) => {
    const user = await inTx(async (c) => {
      const { rows } = await c.query('select exists (select 1 from users) as e');
      if (rows[0].e) {
        throw new HttpError(403, 'Novas contas são criadas pelo administrador, em Usuários.');
      }
      return insertUser(c, { ...req.body, isAdmin: true });
    });
    res.status(201).json({ token: sign(user), user: toUser(user) });
  }));

  app.post('/auth/login', wrap(async (req, res) => {
    const email = normEmail(req.body?.email);
    limit(`${req.ip}|${email}`);
    const { rows } = await pool.query('select * from users where email = $1', [
      email,
    ]);
    const ok =
      rows.length &&
      (await bcrypt.compare(String(req.body?.password ?? ''), rows[0].password_hash));
    if (!ok) throw new HttpError(401, 'E-mail ou senha incorretos');
    res.json({ token: sign(rows[0]), user: toUser(rows[0]) });
  }));

  app.get('/me', authed, (req, res) => res.json({ user: toUser(req.user) }));

  app.post('/me/password', authed, wrap(async (req, res) => {
    const ok = await bcrypt.compare(
      String(req.body?.current ?? ''),
      req.user.password_hash,
    );
    if (!ok) throw new HttpError(400, 'Senha atual incorreta');
    checkPassword(req.body?.password);
    await pool.query('update users set password_hash = $2 where id = $1', [
      req.user.id,
      await bcrypt.hash(String(req.body.password), 10),
    ]);
    res.status(204).end();
  }));

  app.delete('/me', authed, wrap(async (req, res) => {
    await inTx(async (c) => {
      await checkNotLastAdmin(c, req.user.id);
      await c.query('delete from users where id = $1', [req.user.id]);
    });
    res.status(204).end();
  }));

  // Gestão de usuários (administradores) ---------------------------------------

  app.get('/users', admin, wrap(async (req, res) => {
    const { rows } = await pool.query('select * from users order by lower(name)');
    res.json({ users: rows.map(toUser) });
  }));

  app.post('/users', admin, wrap(async (req, res) => {
    const u = await inTx((c) => insertUser(c, req.body ?? {}));
    res.status(201).json({ user: toUser(u) });
  }));

  app.patch('/users/:id', admin, wrap(async (req, res) => {
    const { name, email, isAdmin } = req.body ?? {};
    checkName(name);
    const e = normEmail(email);
    checkEmail(e);
    const u = await inTx(async (c) => {
      if (!isAdmin) await checkNotLastAdmin(c, req.params.id);
      try {
        const { rows } = await c.query(
          `update users set name = $2, email = $3, is_admin = $4
           where id = $1 returning *`,
          [req.params.id, String(name).trim(), e, !!isAdmin],
        );
        if (!rows.length) throw new HttpError(404, 'Usuário não encontrado');
        return rows[0];
      } catch (err) {
        if (err.code === '23505') {
          throw new HttpError(409, 'Já existe uma conta com este e-mail');
        }
        throw err;
      }
    });
    res.json({ user: toUser(u) });
  }));

  app.post('/users/:id/password', admin, wrap(async (req, res) => {
    checkPassword(req.body?.password);
    const { rowCount } = await pool.query(
      'update users set password_hash = $2 where id = $1',
      [req.params.id, await bcrypt.hash(String(req.body.password), 10)],
    );
    if (!rowCount) throw new HttpError(404, 'Usuário não encontrado');
    res.status(204).end();
  }));

  app.delete('/users/:id', admin, wrap(async (req, res) => {
    if (req.params.id === req.user.id) {
      throw new HttpError(400, 'Para excluir a própria conta, use Configurações.');
    }
    await inTx(async (c) => {
      await checkNotLastAdmin(c, req.params.id);
      await c.query('delete from users where id = $1', [req.params.id]);
    });
    res.status(204).end();
  }));

  // Dados -------------------------------------------------------------------

  /// Todos os documentos do usuário (os excluídos não voltam).
  app.get('/docs', authed, wrap(async (req, res) => {
    const { rows } = await pool.query(
      `select coll, id, data from app_docs
       where user_id = $1 and not deleted order by coll, id`,
      [req.user.id],
    );
    res.json({ docs: rows });
  }));

  /// Grava um lote (upsert). `data: null` ou `deleted: true` exclui.
  app.post('/docs/batch', authed, wrap(async (req, res) => {
    const docs = req.body?.docs;
    if (!Array.isArray(docs) || docs.length > MAX_BATCH) {
      throw new HttpError(400, `Envie de 1 a ${MAX_BATCH} documentos`);
    }
    for (const d of docs) {
      if (typeof d?.coll !== 'string' || typeof d?.id !== 'string' ||
          !d.coll || !d.id || d.coll.length > 64 || d.id.length > 200) {
        throw new HttpError(400, 'Documento inválido');
      }
    }
    if (docs.length) {
      const deleted = docs.map((d) => d.deleted === true || d.data == null);
      await pool.query(
        `insert into app_docs (user_id, coll, id, data, deleted, updated_at)
         select $1, t.coll, t.id, t.data, t.deleted, now()
         from unnest($2::text[], $3::text[], $4::jsonb[], $5::bool[])
           as t(coll, id, data, deleted)
         on conflict (user_id, coll, id) do update
           set data = excluded.data, deleted = excluded.deleted,
               updated_at = now()`,
        [
          req.user.id,
          docs.map((d) => d.coll),
          docs.map((d) => d.id),
          docs.map((d, i) => (deleted[i] ? null : JSON.stringify(d.data))),
          deleted,
        ],
      );
    }
    res.json({ saved: docs.length });
  }));

  // Open Finance (Pluggy) ---------------------------------------------------

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
  const ownsItem = async (userId, itemId) => {
    const { rows } = await pool.query(
      'select 1 from of_items where item_id = $1 and user_id = $2',
      [itemId, userId],
    );
    return rows.length > 0;
  };

  app.get('/openfinance/status', authed, (req, res) =>
    res.json({ provider: 'pluggy', configured: !!pluggy }));

  /// Registra uma conexão (item) da Pluggy para o usuário e devolve as
  /// contas dela.
  app.post('/openfinance/items', authed, wrap(async (req, res) => {
    const p = needPluggy();
    const itemId = String(req.body?.itemId ?? '').trim();
    if (!ITEM_ID_RE.test(itemId)) {
      throw new HttpError(400, 'ID da conexão inválido (formato esperado: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).');
    }
    const item = await fromPluggy(() => p.getItem(itemId));
    const { rows } = await pool.query(
      `insert into of_items (item_id, user_id) values ($1, $2)
       on conflict (item_id) do update set item_id = excluded.item_id
       returning user_id`,
      [itemId, req.user.id],
    );
    if (rows[0].user_id !== req.user.id) {
      throw new HttpError(409, 'Esta conexão já está vinculada a outro usuário.');
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

  app.delete('/openfinance/items/:itemId', authed, wrap(async (req, res) => {
    await pool.query('delete from of_items where item_id = $1 and user_id = $2', [
      req.params.itemId,
      req.user.id,
    ]);
    res.status(204).end();
  }));

  /// Transações de uma conta, desde `from` (AAAA-MM-DD; padrão: 90 dias).
  app.get('/openfinance/accounts/:accountId/transactions', authed, wrap(async (req, res) => {
    const p = needPluggy();
    const from = String(req.query.from ?? '');
    if (from && !DATE_RE.test(from)) throw new HttpError(400, 'Data inválida');
    const account = await fromPluggy(() => p.getAccount(req.params.accountId));
    if (!account.itemId || !(await ownsItem(req.user.id, account.itemId))) {
      throw new HttpError(404, 'Conta não encontrada');
    }
    const since = from ||
      new Date(Date.now() - DEFAULT_SYNC_DAYS * 864e5).toISOString().slice(0, 10);
    const txs = await fromPluggy(() => p.listTransactions(account.id, since));
    res.json({ transactions: txs.map(toAppTransaction) });
  }));

  mountWhatsApp(app, { pool, authed, wrap, HttpError, whatsapp });

  // Erros -------------------------------------------------------------------

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err instanceof HttpError) {
      return res.status(err.status).json({ error: err.message });
    }
    if (err?.type === 'entity.too.large') {
      return res.status(413).json({ error: 'Lote grande demais' });
    }
    if (err?.code === '22P02') {
      return res.status(404).json({ error: 'Usuário não encontrado' });
    }
    console.error(err);
    res.status(500).json({ error: 'Erro interno do servidor' });
  });

  return app;
}

async function migrate(pool) {
  const sql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  await pool.query(sql);
}

module.exports = { createApp, migrate };
