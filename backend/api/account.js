// Conta com vários usuários: o dono convida outras pessoas (pelo e-mail) para
// usar o mesmo orçamento, cada uma com o próprio login. Quem aceita passa a
// ler e gravar os dados do dono (a função SQL data_owner resolve qual conta
// cada usuário enxerga). Os dados próprios de quem entrou ficam guardados e
// voltam quando a pessoa sai da conta.
//
// Regras:
// * Só o dono convida e remove pessoas; quem entrou pode sair quando quiser.
// * Cada pessoa usa no máximo uma conta de outra pessoa, e quem já divide a
//   própria conta não entra em outra (evita cadeias de contas).
// * Quem entrou usa o plano do dono quando ele é melhor que o seu.

const MAX_MEMBERS = 5;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const normEmail = (e) => String(e ?? '').trim().toLowerCase();

/**
 * Completa a linha do usuário com a conta de outra pessoa em que ele entrou
 * (`account_owner`: linha do dono) e a quantidade de convites pendentes.
 */
async function attachAccount(db, user) {
  const { rows } = await db.query(
    `select o.*
       from account_members m join users o on o.id = m.account_id
      where m.user_id = $1 and m.status = 'active'`,
    [user.id],
  );
  user.account_owner = rows[0] ?? null;
  const inv = await db.query(
    `select count(*)::int as n from account_members
      where email = $1 and status = 'invited'`,
    [user.email],
  );
  user.pending_invites = inv.rows[0].n;
  return user;
}

/** Conta que o usuário enxerga, para o app (`null` = a própria). */
const accountOf = (u) =>
  u.account_owner
    ? { id: u.account_owner.id, ownerName: u.account_owner.name, ownerEmail: u.account_owner.email }
    : null;

function mountAccount(app, { pool, authed, wrap, HttpError }) {
  const bad = (msg) => new HttpError(400, msg);
  const conflict = (msg) => new HttpError(409, msg);

  async function inTx(fn) {
    const c = await pool.connect();
    try {
      await c.query('begin');
      await c.query("select pg_advisory_xact_lock(hashtext('account_members'))");
      const out = await fn(c);
      await c.query('commit');
      return out;
    } catch (e) {
      await c.query('rollback');
      throw e;
    } finally {
      c.release();
    }
  }

  async function state(userId) {
    const { rows: me } = await pool.query('select * from users where id = $1', [userId]);
    const user = await attachAccount(pool, me[0]);
    const owner = user.account_owner ?? user;
    const { rows: members } = await pool.query(
      `select m.id, m.email, m.status, m.user_id, m.created_at, m.accepted_at, u.name
         from account_members m left join users u on u.id = m.user_id
        where m.account_id = $1
        order by m.status = 'active' desc, coalesce(u.name, m.email)`,
      [owner.id],
    );
    const { rows: invites } = await pool.query(
      `select m.id, m.created_at, o.id as owner_id, o.name as owner_name, o.email as owner_email
         from account_members m join users o on o.id = m.account_id
        where m.email = $1 and m.status = 'invited'
        order by m.created_at`,
      [user.email],
    );
    return {
      account: {
        id: owner.id,
        ownerName: owner.name,
        ownerEmail: owner.email,
        isOwner: owner.id === user.id,
      },
      members: [
        { id: null, userId: owner.id, name: owner.name, email: owner.email, status: 'owner' },
        ...members.map((m) => ({
          id: m.id,
          userId: m.user_id,
          name: m.name ?? null,
          email: m.email,
          status: m.status,
          invitedAt: m.created_at,
          acceptedAt: m.accepted_at,
        })),
      ],
      invites: invites.map((i) => ({
        id: i.id,
        ownerId: i.owner_id,
        ownerName: i.owner_name,
        ownerEmail: i.owner_email,
        invitedAt: i.created_at,
      })),
      maxMembers: MAX_MEMBERS,
    };
  }

  app.get('/account', authed, wrap(async (req, res) => {
    res.json(await state(req.user.id));
  }));

  /// Convida uma pessoa (pelo e-mail) para usar a minha conta.
  app.post('/account/members', authed, wrap(async (req, res) => {
    const email = normEmail(req.body?.email);
    if (!EMAIL_RE.test(email)) throw bad('E-mail inválido');
    if (email === req.user.email) throw bad('Este é o seu próprio e-mail.');
    await inTx(async (c) => {
      const mine = await c.query(
        `select 1 from account_members where user_id = $1 and status = 'active'`,
        [req.user.id],
      );
      if (mine.rows.length) {
        throw conflict('Você está usando a conta de outra pessoa. Só o dono dela convida novos usuários.');
      }
      const { rows } = await c.query(
        'select email from account_members where account_id = $1',
        [req.user.id],
      );
      if (rows.some((r) => r.email === email)) {
        throw conflict('Esta pessoa já foi convidada.');
      }
      if (rows.length >= MAX_MEMBERS) {
        throw conflict(`A conta aceita até ${MAX_MEMBERS} pessoas além de você.`);
      }
      await c.query(
        `insert into account_members (account_id, email, invited_by) values ($1, $2, $1)`,
        [req.user.id, email],
      );
    });
    res.status(201).json(await state(req.user.id));
  }));

  /// Dono: remove uma pessoa ou cancela o convite. Quem entrou: sai da conta.
  app.delete('/account/members/:id', authed, wrap(async (req, res) => {
    if (!UUID_RE.test(req.params.id)) throw new HttpError(404, 'Não encontrado');
    const { rowCount } = await pool.query(
      `delete from account_members
        where id = $1 and (account_id = $2 or user_id = $2)`,
      [req.params.id, req.user.id],
    );
    if (!rowCount) throw new HttpError(404, 'Não encontrado');
    res.json(await state(req.user.id));
  }));

  /// Sai da conta de outra pessoa e volta a usar a própria.
  app.post('/account/leave', authed, wrap(async (req, res) => {
    await pool.query(
      `delete from account_members where user_id = $1 and status = 'active'`,
      [req.user.id],
    );
    res.json(await state(req.user.id));
  }));

  async function invite(c, id, user) {
    if (!UUID_RE.test(id)) throw new HttpError(404, 'Convite não encontrado');
    const { rows } = await c.query(
      `select * from account_members where id = $1 and email = $2 and status = 'invited'`,
      [id, user.email],
    );
    if (!rows.length) throw new HttpError(404, 'Convite não encontrado');
    return rows[0];
  }

  app.post('/account/invites/:id/accept', authed, wrap(async (req, res) => {
    await inTx(async (c) => {
      const inv = await invite(c, req.params.id, req.user);
      const shared = await c.query(
        `select 1 from account_members where account_id = $1 and status = 'active'`,
        [req.user.id],
      );
      if (shared.rows.length) {
        throw conflict('Outras pessoas usam a sua conta. Remova-as antes de entrar na conta de outra pessoa.');
      }
      // Trocar de conta: sai da anterior.
      await c.query(
        `delete from account_members where user_id = $1 and status = 'active'`,
        [req.user.id],
      );
      // Convites da minha própria conta deixam de valer (não há cadeia).
      await c.query(
        `delete from account_members where account_id = $1 and status = 'invited'`,
        [req.user.id],
      );
      await c.query(
        `update account_members set status = 'active', user_id = $2, accepted_at = now()
          where id = $1`,
        [inv.id, req.user.id],
      );
    });
    res.json(await state(req.user.id));
  }));

  app.post('/account/invites/:id/reject', authed, wrap(async (req, res) => {
    await inTx(async (c) => {
      const inv = await invite(c, req.params.id, req.user);
      await c.query('delete from account_members where id = $1', [inv.id]);
    });
    res.json(await state(req.user.id));
  }));
}

module.exports = { mountAccount, attachAccount, accountOf, MAX_MEMBERS };
