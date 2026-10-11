// Despesas compartilhadas: grupos, convites, percentuais por categoria,
// divisão das despesas, pagamentos das partes e acertos entre participantes.
//
// Privacidade: cada usuário só enxerga os grupos de que participa (ativo) e,
// neles, apenas o que foi compartilhado no grupo. Nada do orçamento
// particular (contas, cartões, receitas, outras despesas) passa por aqui.

const { types } = require('pg');
const { allocate, checkPercentages, toObject } = require('./allocation');

// Colunas `date` como texto (AAAA-MM-DD), sem conversão de fuso.
types.setTypeParser(1082, (v) => v);

const DEFAULT_CATEGORIES = [
  'Moradia e aluguel',
  'Luz e água',
  'Internet e telefonia',
  'Mercado e alimentação',
  'Transporte',
  'Saúde',
  'Educação',
  'Lazer e entretenimento',
  'Assinaturas',
  'Outras despesas',
];
const KINDS = ['household', 'couple', 'family', 'roommates', 'other'];
const ROLES = ['manager', 'member'];
const SOURCES = ['account', 'card', 'manual', 'import', 'recurring'];
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_CENTS = 1e12;

const iso = (d) => (d == null ? null : d instanceof Date ? d.toISOString().slice(0, 10) : String(d));

function mountShared(app, { pool, authed, wrap, HttpError }) {
  const bad = (msg) => new HttpError(400, msg);
  const notFound = () => new HttpError(404, 'Não encontrado ou sem acesso');

  const text = (v, field, max = 200) => {
    const s = String(v ?? '').trim();
    if (!s) throw bad(`Informe ${field}`);
    if (s.length > max) throw bad(`${field[0].toUpperCase()}${field.slice(1)} muito longo`);
    return s;
  };
  const cents = (v) => {
    const n = Number(v);
    if (!Number.isInteger(n) || n <= 0 || n > MAX_CENTS) throw bad('Valor inválido');
    return n;
  };
  const date = (v, field = 'a data') => {
    if (!DATE_RE.test(String(v ?? '')) || isNaN(Date.parse(v))) throw bad(`Informe ${field}`);
    return String(v);
  };
  const optDate = (v) => (v == null || v === '' ? null : date(v, 'uma data válida'));
  const uuid = (v) => {
    if (!UUID_RE.test(String(v ?? ''))) throw notFound();
    return String(v);
  };

  /// Transação com bloqueio por grupo (mudanças de um grupo em série).
  async function inGroupTx(groupId, fn) {
    const c = await pool.connect();
    try {
      await c.query('begin');
      if (groupId) {
        await c.query("select pg_advisory_xact_lock(hashtext('share:' || $1))", [groupId]);
      }
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

  async function audit(c, groupId, actorId, action, details = {}) {
    await c.query(
      'insert into share_audit (group_id, actor_id, action, details) values ($1, $2, $3, $4)',
      [groupId, actorId, action, JSON.stringify(details)],
    );
  }

  /// Participação ativa do usuário no grupo (ou 404: não revela grupos alheios).
  async function membership(c, groupId, userId) {
    const { rows } = await c.query(
      `select m.*, g.owner_id, g.archived, g.name as group_name
       from share_members m join share_groups g on g.id = m.group_id
       where m.group_id = $1 and m.user_id = $2 and m.status = 'active'`,
      [uuid(groupId), userId],
    );
    if (!rows.length) throw notFound();
    return rows[0];
  }
  const canManage = (m) => m.role === 'owner' || m.role === 'manager';
  function requireManager(m) {
    if (!canManage(m)) {
      throw new HttpError(403, 'Somente o dono do grupo ou um gestor pode fazer isso');
    }
  }
  function requireOwner(m) {
    if (m.role !== 'owner') throw new HttpError(403, 'Somente o dono do grupo pode fazer isso');
  }

  /// Ids dos participantes ativos, dono primeiro (ordem estável da divisão).
  async function activeIds(c, groupId) {
    const { rows } = await c.query(
      `select user_id from share_members where group_id = $1 and status = 'active'
       order by (role = 'owner') desc, created_at, user_id`,
      [groupId],
    );
    return rows.map((r) => r.user_id);
  }

  async function categoryOf(c, groupId, id) {
    const { rows } = await c.query(
      'select * from share_categories where id = $1 and group_id = $2',
      [uuid(id), groupId],
    );
    if (!rows.length) throw bad('Categoria não encontrada no grupo');
    return rows[0];
  }

  async function expenseFor(c, id, userId) {
    const { rows } = await c.query('select * from share_expenses where id = $1', [uuid(id)]);
    const e = rows[0];
    if (!e || e.deleted_at) throw notFound();
    const m = await membership(c, e.group_id, userId);
    return { e, m };
  }

  async function paidByUser(c, expenseId) {
    const { rows } = await c.query(
      `select user_id, sum(amount)::bigint as paid from share_payments
       where expense_id = $1 and deleted_at is null group by user_id`,
      [expenseId],
    );
    return Object.fromEntries(rows.map((r) => [r.user_id, Number(r.paid)]));
  }

  /// Regrava a divisão de uma despesa (percentuais + valores).
  async function writeAllocations(c, expenseId, total, shares) {
    await c.query('delete from share_allocations where expense_id = $1', [expenseId]);
    const rows = allocate(Number(total), shares);
    for (const r of rows) {
      await c.query(
        'insert into share_allocations (expense_id, user_id, bp, amount) values ($1, $2, $3, $4)',
        [expenseId, r.userId, r.bp, r.amount],
      );
    }
    return rows;
  }

  async function currentShares(c, expenseId) {
    const { rows } = await c.query(
      'select user_id, bp from share_allocations where expense_id = $1',
      [expenseId],
    );
    return rows.map((r) => ({ userId: r.user_id, bp: r.bp }));
  }

  /// Percentuais aplicáveis: exceção da despesa > da recorrência > categoria.
  async function defaultShares(c, groupId, category, recurrence) {
    const ids = await activeIds(c, groupId);
    const source = recurrence?.override ?? category.percentages;
    const r = checkPercentages(source, ids);
    if (r.error) {
      throw bad(`A categoria "${category.name}" está com percentuais inválidos: ${r.error}`);
    }
    return r.list;
  }

  // Estado -------------------------------------------------------------------

  /// Tudo o que o usuário pode ver: convites pendentes e os grupos ativos
  /// com participantes, categorias, recorrências, despesas e acertos.
  app.get('/shared/state', authed, wrap(async (req, res) => {
    const me = req.user.id;
    const { rows: mine } = await pool.query(
      `select m.group_id, m.role, m.status, m.category_map, g.name, g.kind, g.owner_id,
              g.archived, o.name as owner_name, i.name as inviter_name
       from share_members m
       join share_groups g on g.id = m.group_id
       join users o on o.id = g.owner_id
       left join users i on i.id = m.invited_by
       where m.user_id = $1 and m.status in ('active', 'invited')
       order by g.created_at`,
      [me],
    );
    const invites = mine
      .filter((m) => m.status === 'invited')
      .map((m) => ({
        groupId: m.group_id,
        groupName: m.name,
        ownerName: m.owner_name,
        invitedBy: m.inviter_name,
        role: m.role,
      }));
    const active = mine.filter((m) => m.status === 'active');
    const ids = active.map((m) => m.group_id);
    const out = { userId: me, invites, groups: [] };
    if (!ids.length) return res.json(out);

    const q = (sql) => pool.query(sql, [ids]).then((r) => r.rows);
    const [members, categories, recurrences, expenses, allocations, payments, settlements] =
      await Promise.all([
        q(`select m.group_id, m.user_id, m.role, m.status, u.name, u.email
           from share_members m join users u on u.id = m.user_id
           where m.group_id = any($1)
           order by (m.role = 'owner') desc, m.created_at, m.user_id`),
        q(`select * from share_categories where group_id = any($1) order by sort, name`),
        q(`select * from share_recurrences where group_id = any($1) and canceled_at is null
           order by created_at`),
        // Excluídas só aparecem se já tiveram pagamentos (o dinheiro saiu).
        q(`select * from share_expenses e where group_id = any($1)
             and (deleted_at is null or exists (
               select 1 from share_payments p
               where p.expense_id = e.id and p.deleted_at is null))
           order by date, created_at`),
        q(`select a.* from share_allocations a join share_expenses e on e.id = a.expense_id
           where e.group_id = any($1)`),
        q(`select p.* from share_payments p join share_expenses e on e.id = p.expense_id
           where e.group_id = any($1) and p.deleted_at is null order by p.date, p.created_at`),
        q(`select * from share_settlements where group_id = any($1) and deleted_at is null
           order by date, created_at`),
      ]);
    const by = (list, key) => {
      const m = new Map();
      for (const r of list) {
        if (!m.has(r[key])) m.set(r[key], []);
        m.get(r[key]).push(r);
      }
      return m;
    };
    const allocBy = by(allocations, 'expense_id');
    const payBy = by(payments, 'expense_id');
    for (const g of active) {
      const gid = g.group_id;
      const isOwner = g.role === 'owner';
      out.groups.push({
        id: gid,
        name: g.name,
        kind: g.kind,
        ownerId: g.owner_id,
        archived: g.archived,
        myRole: g.role,
        categoryMap: g.category_map,
        // Dono do grupo vê todos (com e-mail e situação); os demais veem os
        // participantes ativos e, de ex-participantes, só o nome (histórico).
        members: members
          .filter((m) => m.group_id === gid &&
            (isOwner || m.status !== 'invited' || m.user_id === me))
          .map((m) => ({
            userId: m.user_id,
            name: m.name,
            email: isOwner || m.user_id === me ? m.email : null,
            role: m.role,
            status: isOwner || m.status === 'active' ? m.status : 'former',
          })),
        categories: categories
          .filter((c) => c.group_id === gid)
          .map((c) => ({
            id: c.id,
            name: c.name,
            sort: c.sort,
            percentages: c.percentages,
            archived: c.archived,
          })),
        recurrences: recurrences
          .filter((r) => r.group_id === gid)
          .map((r) => ({
            id: r.id,
            ownerId: r.owner_id,
            // A regra de origem só interessa (e só é exposta) ao dono.
            sourceRuleId: r.owner_id === me ? r.source_rule_id : null,
            categoryId: r.category_id,
            description: r.description,
            override: r.override,
            paused: r.paused,
          })),
        expenses: expenses
          .filter((e) => e.group_id === gid)
          .map((e) => ({
            id: e.id,
            ownerId: e.owner_id,
            categoryId: e.category_id,
            categoryName: e.category_name,
            description: e.description,
            total: Number(e.total),
            date: iso(e.date),
            dueDate: iso(e.due_date),
            source: e.source,
            sourceKey: e.owner_id === me ? e.source_key : null,
            recurrenceId: e.recurrence_id,
            occurrenceDate: iso(e.occurrence_date),
            overridden: e.overridden,
            notes: e.notes,
            deletedAt: e.deleted_at,
            createdAt: e.created_at,
            updatedAt: e.updated_at,
            allocations: (allocBy.get(e.id) ?? []).map((a) => ({
              userId: a.user_id,
              bp: a.bp,
              amount: Number(a.amount),
            })),
            payments: (payBy.get(e.id) ?? []).map((p) => ({
              id: p.id,
              userId: p.user_id,
              amount: Number(p.amount),
              date: iso(p.date),
              note: p.note,
              settlementId: p.settlement_id,
              recordedBy: p.recorded_by,
            })),
          })),
        settlements: settlements
          .filter((s) => s.group_id === gid)
          .map((s) => ({
            id: s.id,
            fromUserId: s.from_user,
            toUserId: s.to_user,
            amount: Number(s.amount),
            date: iso(s.date),
            note: s.note,
            recordedBy: s.recorded_by,
          })),
      });
    }
    res.json(out);
  }));

  // Grupos -------------------------------------------------------------------

  app.post('/shared/groups', authed, wrap(async (req, res) => {
    const name = text(req.body?.name, 'o nome do grupo', 80);
    const kind = KINDS.includes(req.body?.kind) ? req.body.kind : 'household';
    const names = Array.isArray(req.body?.categories) && req.body.categories.length
      ? req.body.categories.map((n) => text(n, 'o nome da categoria', 80))
      : DEFAULT_CATEGORIES;
    const id = await inGroupTx(null, async (c) => {
      const { rows } = await c.query(
        'insert into share_groups (owner_id, name, kind) values ($1, $2, $3) returning id',
        [req.user.id, name, kind],
      );
      const gid = rows[0].id;
      await c.query(
        `insert into share_members (group_id, user_id, role, status, invited_by)
         values ($1, $2, 'owner', 'active', $2)`,
        [gid, req.user.id],
      );
      const pct = JSON.stringify({ [req.user.id]: 10000 });
      for (const [i, n] of [...new Set(names)].entries()) {
        await c.query(
          'insert into share_categories (group_id, name, sort, percentages) values ($1, $2, $3, $4)',
          [gid, n, i, pct],
        );
      }
      await audit(c, gid, req.user.id, 'group.created', { name, kind });
      return gid;
    });
    res.status(201).json({ id });
  }));

  app.patch('/shared/groups/:id', authed, wrap(async (req, res) => {
    await inGroupTx(req.params.id, async (c) => {
      const m = await membership(c, req.params.id, req.user.id);
      requireOwner(m);
      const name = req.body?.name != null ? text(req.body.name, 'o nome do grupo', 80) : m.group_name;
      const kind = KINDS.includes(req.body?.kind) ? req.body.kind : undefined;
      const archived = typeof req.body?.archived === 'boolean' ? req.body.archived : m.archived;
      await c.query(
        `update share_groups set name = $2, kind = coalesce($3, kind), archived = $4,
           updated_at = now() where id = $1`,
        [m.group_id, name, kind ?? null, archived],
      );
      await audit(c, m.group_id, req.user.id, 'group.updated', { name, kind, archived });
    });
    res.status(204).end();
  }));

  // Participantes -------------------------------------------------------------

  app.post('/shared/groups/:id/members', authed, wrap(async (req, res) => {
    const email = String(req.body?.email ?? '').trim().toLowerCase();
    const role = ROLES.includes(req.body?.role) ? req.body.role : 'member';
    const out = await inGroupTx(req.params.id, async (c) => {
      const m = await membership(c, req.params.id, req.user.id);
      requireOwner(m);
      const { rows: users } = await c.query('select id, name from users where email = $1', [email]);
      if (!users.length) {
        throw new HttpError(404, 'Não há usuário do app com este e-mail. Peça ao administrador para criar a conta.');
      }
      const u = users[0];
      if (u.id === req.user.id) throw bad('Você já participa do grupo');
      const { rows: cur } = await c.query(
        'select status from share_members where group_id = $1 and user_id = $2',
        [m.group_id, u.id],
      );
      if (cur[0] && (cur[0].status === 'active' || cur[0].status === 'invited')) {
        throw new HttpError(409, cur[0].status === 'active'
          ? 'Esta pessoa já participa do grupo'
          : 'Esta pessoa já foi convidada');
      }
      await c.query(
        `insert into share_members (group_id, user_id, role, status, invited_by)
         values ($1, $2, $3, 'invited', $4)
         on conflict (group_id, user_id) do update
           set role = excluded.role, status = 'invited', invited_by = excluded.invited_by,
               updated_at = now()`,
        [m.group_id, u.id, role, req.user.id],
      );
      await audit(c, m.group_id, req.user.id, 'member.invited', { userId: u.id, name: u.name, role });
      return { userId: u.id, name: u.name };
    });
    res.status(201).json(out);
  }));

  async function respondInvite(req, accept) {
    await inGroupTx(req.params.id, async (c) => {
      const { rows } = await c.query(
        `update share_members set status = $3, updated_at = now()
         where group_id = $1 and user_id = $2 and status = 'invited' returning role`,
        [uuid(req.params.id), req.user.id, accept ? 'active' : 'rejected'],
      );
      if (!rows.length) throw notFound();
      await audit(c, req.params.id, req.user.id, accept ? 'member.accepted' : 'member.rejected', {
        userId: req.user.id,
        name: req.user.name,
      });
    });
  }
  app.post('/shared/groups/:id/accept', authed, wrap(async (req, res) => {
    await respondInvite(req, true);
    res.status(204).end();
  }));
  app.post('/shared/groups/:id/reject', authed, wrap(async (req, res) => {
    await respondInvite(req, false);
    res.status(204).end();
  }));

  app.patch('/shared/groups/:id/members/:userId', authed, wrap(async (req, res) => {
    const role = req.body?.role;
    if (!ROLES.includes(role)) throw bad('Papel inválido');
    await inGroupTx(req.params.id, async (c) => {
      const m = await membership(c, req.params.id, req.user.id);
      requireOwner(m);
      const { rows } = await c.query(
        `update share_members set role = $3, updated_at = now()
         where group_id = $1 and user_id = $2 and role <> 'owner'
           and status in ('active', 'invited') returning user_id`,
        [m.group_id, uuid(req.params.userId), role],
      );
      if (!rows.length) throw notFound();
      await audit(c, m.group_id, req.user.id, 'member.role', { userId: req.params.userId, role });
    });
    res.status(204).end();
  }));

  /// Dono revoga um participante, ou o próprio participante sai do grupo.
  /// O percentual de quem sai passa para o dono do grupo; as divisões já
  /// lançadas continuam como estavam.
  app.delete('/shared/groups/:id/members/:userId', authed, wrap(async (req, res) => {
    await inGroupTx(req.params.id, async (c) => {
      const target = uuid(req.params.userId);
      const self = target === req.user.id;
      const m = await membership(c, req.params.id, req.user.id);
      if (self && m.role === 'owner') throw bad('O dono não pode sair do próprio grupo');
      if (!self) requireOwner(m);
      const { rows } = await c.query(
        `update share_members set status = $3, updated_at = now()
         where group_id = $1 and user_id = $2 and status in ('active', 'invited')
         returning user_id`,
        [m.group_id, target, self ? 'left' : 'revoked'],
      );
      if (!rows.length) throw notFound();
      const moved = [];
      const { rows: cats } = await c.query(
        'select id, name, percentages from share_categories where group_id = $1',
        [m.group_id],
      );
      for (const cat of cats) {
        const p = { ...cat.percentages };
        const bp = Number(p[target] ?? 0);
        if (!bp) continue;
        delete p[target];
        p[m.owner_id] = Number(p[m.owner_id] ?? 0) + bp;
        await c.query(
          'update share_categories set percentages = $2, updated_at = now() where id = $1',
          [cat.id, JSON.stringify(p)],
        );
        moved.push(cat.name);
      }
      const { rows: recs } = await c.query(
        `select id, override from share_recurrences
         where group_id = $1 and override ? $2 and canceled_at is null`,
        [m.group_id, target],
      );
      for (const r of recs) {
        const p = { ...r.override };
        const bp = Number(p[target] ?? 0);
        delete p[target];
        p[m.owner_id] = Number(p[m.owner_id] ?? 0) + bp;
        await c.query('update share_recurrences set override = $2 where id = $1', [
          r.id,
          JSON.stringify(p),
        ]);
      }
      await audit(c, m.group_id, req.user.id, self ? 'member.left' : 'member.revoked', {
        userId: target,
        movedCategories: moved,
      });
    });
    res.status(204).end();
  }));

  // Categorias e percentuais ----------------------------------------------------

  app.post('/shared/groups/:id/categories', authed, wrap(async (req, res) => {
    const name = text(req.body?.name, 'o nome da categoria', 80);
    const id = await inGroupTx(req.params.id, async (c) => {
      const m = await membership(c, req.params.id, req.user.id);
      requireManager(m);
      const r = checkPercentages(req.body?.percentages, await activeIds(c, m.group_id));
      if (r.error) throw bad(r.error);
      const { rows } = await c.query(
        `insert into share_categories (group_id, name, sort, percentages)
         values ($1, $2, (select coalesce(max(sort), 0) + 1 from share_categories where group_id = $1), $3)
         returning id`,
        [m.group_id, name, JSON.stringify(toObject(r.list))],
      );
      await audit(c, m.group_id, req.user.id, 'category.created', {
        categoryId: rows[0].id,
        name,
        percentages: toObject(r.list),
      });
      return rows[0].id;
    });
    res.status(201).json({ id });
  }));

  /// Altera nome/percentuais (valem para as próximas despesas) ou arquiva.
  app.patch('/shared/categories/:id', authed, wrap(async (req, res) => {
    const { rows } = await pool.query('select group_id from share_categories where id = $1', [
      uuid(req.params.id),
    ]);
    if (!rows.length) throw notFound();
    const gid = rows[0].group_id;
    await inGroupTx(gid, async (c) => {
      const m = await membership(c, gid, req.user.id);
      requireManager(m);
      const cat = await categoryOf(c, gid, req.params.id);
      const name = req.body?.name != null ? text(req.body.name, 'o nome da categoria', 80) : cat.name;
      let percentages = cat.percentages;
      if (req.body?.percentages !== undefined) {
        const r = checkPercentages(req.body.percentages, await activeIds(c, gid));
        if (r.error) throw bad(r.error);
        percentages = toObject(r.list);
      }
      const archived = typeof req.body?.archived === 'boolean' ? req.body.archived : cat.archived;
      await c.query(
        `update share_categories set name = $2, percentages = $3, archived = $4, updated_at = now()
         where id = $1`,
        [cat.id, name, JSON.stringify(percentages), archived],
      );
      await audit(c, gid, req.user.id, 'category.updated', {
        categoryId: cat.id,
        name,
        before: cat.percentages,
        after: percentages,
        archived,
      });
    });
    res.status(204).end();
  }));

  /// Aplica os percentuais atuais às despesas ainda sem pagamento (e sem
  /// exceção manual). As já pagas mantêm a divisão original.
  app.post('/shared/groups/:id/recalculate', authed, wrap(async (req, res) => {
    const updated = await inGroupTx(req.params.id, async (c) => {
      const m = await membership(c, req.params.id, req.user.id);
      requireManager(m);
      const onlyCat = req.body?.categoryId ? uuid(req.body.categoryId) : null;
      const { rows } = await c.query(
        `select e.* from share_expenses e
         where e.group_id = $1 and e.deleted_at is null and not e.overridden
           and e.category_id is not null and ($2::uuid is null or e.category_id = $2)
           and not exists (select 1 from share_payments p
                           where p.expense_id = e.id and p.deleted_at is null)`,
        [m.group_id, onlyCat],
      );
      let n = 0;
      for (const e of rows) {
        const cat = await categoryOf(c, m.group_id, e.category_id);
        const rec = e.recurrence_id
          ? (await c.query('select * from share_recurrences where id = $1', [e.recurrence_id])).rows[0]
          : null;
        const shares = await defaultShares(c, m.group_id, cat, rec);
        const before = await currentShares(c, e.id);
        const same = before.length === shares.length &&
          shares.every((s) => before.some((b) => b.userId === s.userId && b.bp === s.bp));
        if (same) continue;
        await writeAllocations(c, e.id, e.total, shares);
        await c.query('update share_expenses set updated_at = now() where id = $1', [e.id]);
        n++;
      }
      await audit(c, m.group_id, req.user.id, 'allocations.recalculated', {
        categoryId: onlyCat,
        updated: n,
      });
      return n;
    });
    res.json({ updated });
  }));

  // Despesas -------------------------------------------------------------------

  /// Compartilha uma despesa (idempotente por origem: a mesma transação ou
  /// ocorrência devolve a despesa já existente, atualizando valor e datas).
  app.post('/shared/expenses', authed, wrap(async (req, res) => {
    const b = req.body ?? {};
    const groupId = uuid(b.groupId);
    const out = await inGroupTx(groupId, async (c) => {
      const m = await membership(c, groupId, req.user.id);
      requireManager(m);
      if (m.archived) throw bad('Grupo arquivado');
      const description = text(b.description, 'a descrição');
      const total = cents(b.total);
      const d = date(b.date);
      const due = optDate(b.dueDate);
      const source = SOURCES.includes(b.source) ? b.source : 'manual';
      const sourceKey = b.sourceKey == null ? null : String(b.sourceKey).slice(0, 200);
      const notes = String(b.notes ?? '').slice(0, 1000);
      let rec = null;
      if (b.recurrenceId) {
        const { rows } = await c.query(
          `select * from share_recurrences where id = $1 and group_id = $2
             and owner_id = $3 and canceled_at is null`,
          [uuid(b.recurrenceId), groupId, req.user.id],
        );
        if (!rows.length) throw bad('Recorrência compartilhada não encontrada');
        rec = rows[0];
      }
      if (sourceKey) {
        const { rows } = await c.query(
          `select * from share_expenses where group_id = $1 and owner_id = $2
             and source_key = $3 and deleted_at is null`,
          [groupId, req.user.id, sourceKey],
        );
        if (rows.length) {
          const e = rows[0];
          // Já compartilhada: só acompanha a origem (valor, datas, descrição);
          // a divisão gravada é mantida.
          const changed = Number(e.total) !== total || iso(e.date) !== d ||
            iso(e.due_date) !== due || e.description !== description;
          if (changed) {
            await c.query(
              `update share_expenses set total = $2, date = $3, due_date = $4, description = $5,
                 updated_at = now() where id = $1`,
              [e.id, total, d, due, description],
            );
            if (Number(e.total) !== total) {
              await writeAllocations(c, e.id, total, await currentShares(c, e.id));
            }
            await audit(c, groupId, req.user.id, 'expense.updated', {
              expenseId: e.id,
              description,
              before: { total: Number(e.total), date: iso(e.date) },
              after: { total, date: d },
            });
          }
          return { id: e.id, created: false };
        }
      }
      const cat = await categoryOf(c, groupId, b.categoryId ?? rec?.category_id);
      if (cat.archived) throw bad('Categoria arquivada');
      const ids = await activeIds(c, groupId);
      let shares;
      const override = b.override ?? null;
      if (override) {
        const r = checkPercentages(override, ids);
        if (r.error) throw bad(r.error);
        shares = r.list;
        if (b.updateDefault === true) {
          await c.query(
            'update share_categories set percentages = $2, updated_at = now() where id = $1',
            [cat.id, JSON.stringify(toObject(shares))],
          );
          await audit(c, groupId, req.user.id, 'category.updated', {
            categoryId: cat.id,
            name: cat.name,
            before: cat.percentages,
            after: toObject(shares),
          });
        }
      } else {
        shares = await defaultShares(c, groupId, cat, rec);
      }
      const overridden = !!override && b.updateDefault !== true;
      const { rows } = await c.query(
        `insert into share_expenses (group_id, owner_id, category_id, category_name, description,
           total, date, due_date, source, source_key, recurrence_id, occurrence_date,
           overridden, notes)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) returning id`,
        [groupId, req.user.id, cat.id, cat.name, description, total, d, due, source, sourceKey,
          rec?.id ?? null, optDate(b.occurrenceDate), overridden, notes],
      );
      const id = rows[0].id;
      const alloc = await writeAllocations(c, id, total, shares);
      if (b.budgetCategoryId) {
        await c.query(
          `update share_members set category_map = category_map || $3::jsonb
           where group_id = $1 and user_id = $2`,
          [groupId, req.user.id, JSON.stringify({ [String(b.budgetCategoryId).slice(0, 200)]: cat.id })],
        );
      }
      await audit(c, groupId, req.user.id, 'expense.created', {
        expenseId: id,
        description,
        total,
        category: cat.name,
        allocations: alloc,
        overridden,
      });
      return { id, created: true };
    });
    res.status(out.created ? 201 : 200).json(out);
  }));

  /// Edita uma despesa. `override`: objeto = divisão manual só desta
  /// despesa; `null` = volta ao padrão da categoria.
  app.patch('/shared/expenses/:id', authed, wrap(async (req, res) => {
    const { rows } = await pool.query('select group_id from share_expenses where id = $1', [
      uuid(req.params.id),
    ]);
    if (!rows.length) throw notFound();
    await inGroupTx(rows[0].group_id, async (c) => {
      const { e, m } = await expenseFor(c, req.params.id, req.user.id);
      if (e.owner_id !== req.user.id) requireManager(m);
      const b = req.body ?? {};
      const description = b.description != null ? text(b.description, 'a descrição') : e.description;
      const total = b.total != null ? cents(b.total) : Number(e.total);
      const d = b.date != null ? date(b.date) : iso(e.date);
      const due = b.dueDate !== undefined ? optDate(b.dueDate) : iso(e.due_date);
      const notes = b.notes != null ? String(b.notes).slice(0, 1000) : e.notes;
      let cat = e.category_id ? await categoryOf(c, e.group_id, e.category_id) : null;
      const catChanged = b.categoryId != null && b.categoryId !== e.category_id;
      if (catChanged) cat = await categoryOf(c, e.group_id, b.categoryId);
      let shares = await currentShares(c, e.id);
      let overridden = e.overridden;
      let reason = null;
      if (b.override !== undefined) {
        requireManager(m);
        if (b.override === null) {
          if (!cat) throw bad('Escolha uma categoria');
          const rec = e.recurrence_id
            ? (await c.query('select * from share_recurrences where id = $1', [e.recurrence_id])).rows[0]
            : null;
          shares = await defaultShares(c, e.group_id, cat, rec);
          overridden = false;
          reason = 'reset';
        } else {
          const r = checkPercentages(b.override, await activeIds(c, e.group_id));
          if (r.error) throw bad(r.error);
          shares = r.list;
          overridden = true;
          reason = 'override';
          if (b.updateDefault === true && cat) {
            await c.query(
              'update share_categories set percentages = $2, updated_at = now() where id = $1',
              [cat.id, JSON.stringify(toObject(shares))],
            );
            overridden = false;
            await audit(c, e.group_id, req.user.id, 'category.updated', {
              categoryId: cat.id,
              name: cat.name,
              before: cat.percentages,
              after: toObject(shares),
            });
          }
        }
      } else if (catChanged && !e.overridden) {
        shares = await defaultShares(c, e.group_id, cat, null);
        reason = 'category';
      }
      await c.query(
        `update share_expenses set description = $2, total = $3, date = $4, due_date = $5,
           notes = $6, category_id = $7, category_name = $8, overridden = $9, updated_at = now()
         where id = $1`,
        [e.id, description, total, d, due, notes, cat?.id ?? null, cat?.name ?? e.category_name,
          overridden],
      );
      const alloc = await writeAllocations(c, e.id, total, shares);
      await audit(c, e.group_id, req.user.id, reason === 'override' ? 'allocation.override' : 'expense.updated', {
        expenseId: e.id,
        description,
        before: { total: Number(e.total), date: iso(e.date), category: e.category_name },
        after: { total, date: d, category: cat?.name ?? e.category_name },
        allocations: alloc,
        reason,
      });
    });
    res.status(204).end();
  }));

  app.delete('/shared/expenses/:id', authed, wrap(async (req, res) => {
    const { rows } = await pool.query('select group_id from share_expenses where id = $1', [
      uuid(req.params.id),
    ]);
    if (!rows.length) throw notFound();
    await inGroupTx(rows[0].group_id, async (c) => {
      const { e, m } = await expenseFor(c, req.params.id, req.user.id);
      if (e.owner_id !== req.user.id) requireManager(m);
      await c.query('update share_expenses set deleted_at = now(), updated_at = now() where id = $1', [e.id]);
      await audit(c, e.group_id, req.user.id, 'expense.deleted', {
        expenseId: e.id,
        description: e.description,
        total: Number(e.total),
      });
    });
    res.status(204).end();
  }));

  // Pagamentos e acertos --------------------------------------------------------

  /// Quem pode registrar pagamento da parte de `payer`: o próprio, o dono
  /// da despesa (quem recebe) ou o dono/gestor do grupo.
  function canRecordFor(m, e, me, payer) {
    return me === payer || e.owner_id === me || canManage(m);
  }

  app.post('/shared/expenses/:id/payments', authed, wrap(async (req, res) => {
    const { rows } = await pool.query('select group_id from share_expenses where id = $1', [
      uuid(req.params.id),
    ]);
    if (!rows.length) throw notFound();
    const id = await inGroupTx(rows[0].group_id, async (c) => {
      const { e, m } = await expenseFor(c, req.params.id, req.user.id);
      const payer = String(req.body?.userId ?? req.user.id);
      if (!canRecordFor(m, e, req.user.id, payer)) {
        throw new HttpError(403, 'Você só pode registrar o pagamento da sua parte');
      }
      if (payer === e.owner_id) throw bad('A parte de quem pagou a conta já está quitada');
      const { rows: al } = await c.query(
        'select amount from share_allocations where expense_id = $1 and user_id = $2',
        [e.id, payer],
      );
      if (!al.length) throw bad('Esta pessoa não tem parte nesta despesa');
      const amount = cents(req.body?.amount);
      const paid = (await paidByUser(c, e.id))[payer] ?? 0;
      const open = Number(al[0].amount) - paid;
      if (amount > open) {
        throw bad(`O valor passa do saldo em aberto (R$ ${(open / 100).toFixed(2).replace('.', ',')})`);
      }
      const d = date(req.body?.date, 'a data do pagamento');
      const note = String(req.body?.note ?? '').slice(0, 500);
      const { rows: p } = await c.query(
        `insert into share_payments (expense_id, user_id, amount, date, note, recorded_by)
         values ($1, $2, $3, $4, $5, $6) returning id`,
        [e.id, payer, amount, d, note, req.user.id],
      );
      await audit(c, e.group_id, req.user.id, 'payment.recorded', {
        expenseId: e.id,
        description: e.description,
        userId: payer,
        amount,
        date: d,
      });
      return p[0].id;
    });
    res.status(201).json({ id });
  }));

  app.delete('/shared/payments/:id', authed, wrap(async (req, res) => {
    const { rows } = await pool.query(
      `select p.*, e.group_id from share_payments p join share_expenses e on e.id = p.expense_id
       where p.id = $1 and p.deleted_at is null`,
      [uuid(req.params.id)],
    );
    if (!rows.length) throw notFound();
    const p = rows[0];
    await inGroupTx(p.group_id, async (c) => {
      const m = await membership(c, p.group_id, req.user.id);
      const { rows: es } = await c.query('select * from share_expenses where id = $1', [p.expense_id]);
      if (!canRecordFor(m, es[0], req.user.id, p.user_id)) throw new HttpError(403, 'Sem permissão');
      if (p.settlement_id) throw bad('Este pagamento veio de um acerto: desfaça o acerto');
      await c.query('update share_payments set deleted_at = now() where id = $1', [p.id]);
      await audit(c, p.group_id, req.user.id, 'payment.deleted', {
        expenseId: p.expense_id,
        userId: p.user_id,
        amount: Number(p.amount),
      });
    });
    res.status(204).end();
  }));

  /// Acerto: `from` transfere a `to`. Quita, da mais antiga para a mais
  /// nova, as partes em aberto de `from` nas despesas pagas por `to`.
  app.post('/shared/groups/:id/settlements', authed, wrap(async (req, res) => {
    const out = await inGroupTx(req.params.id, async (c) => {
      const m = await membership(c, req.params.id, req.user.id);
      const from = uuid(req.body?.fromUserId);
      const to = uuid(req.body?.toUserId);
      if (from === to) throw bad('Escolha duas pessoas diferentes');
      if (req.user.id !== from && req.user.id !== to && !canManage(m)) {
        throw new HttpError(403, 'Você só pode registrar acertos em que participa');
      }
      const amount = cents(req.body?.amount);
      const d = date(req.body?.date, 'a data do acerto');
      const note = String(req.body?.note ?? '').slice(0, 500);
      const { rows: open } = await c.query(
        `select e.id, e.description, a.amount - coalesce((
             select sum(p.amount) from share_payments p
             where p.expense_id = e.id and p.user_id = $2 and p.deleted_at is null), 0) as open
         from share_expenses e join share_allocations a on a.expense_id = e.id and a.user_id = $2
         where e.group_id = $1 and e.owner_id = $3 and e.deleted_at is null
         order by coalesce(e.due_date, e.date), e.date, e.created_at`,
        [m.group_id, from, to],
      );
      const totalOpen = open.reduce((a, r) => a + Math.max(0, Number(r.open)), 0);
      if (amount > totalOpen) {
        throw bad(`O valor passa do que está em aberto (R$ ${(totalOpen / 100).toFixed(2).replace('.', ',')})`);
      }
      const { rows: s } = await c.query(
        `insert into share_settlements (group_id, from_user, to_user, amount, date, note, recorded_by)
         values ($1, $2, $3, $4, $5, $6, $7) returning id`,
        [m.group_id, from, to, amount, d, note, req.user.id],
      );
      let left = amount;
      const applied = [];
      for (const r of open) {
        if (left <= 0) break;
        const take = Math.min(left, Number(r.open));
        if (take <= 0) continue;
        await c.query(
          `insert into share_payments (expense_id, user_id, amount, date, note, settlement_id, recorded_by)
           values ($1, $2, $3, $4, $5, $6, $7)`,
          [r.id, from, take, d, note, s[0].id, req.user.id],
        );
        applied.push({ expenseId: r.id, description: r.description, amount: take });
        left -= take;
      }
      await audit(c, m.group_id, req.user.id, 'settlement.recorded', {
        settlementId: s[0].id,
        fromUserId: from,
        toUserId: to,
        amount,
        date: d,
        applied,
      });
      return { id: s[0].id, applied };
    });
    res.status(201).json(out);
  }));

  app.delete('/shared/settlements/:id', authed, wrap(async (req, res) => {
    const { rows } = await pool.query(
      'select * from share_settlements where id = $1 and deleted_at is null',
      [uuid(req.params.id)],
    );
    if (!rows.length) throw notFound();
    const s = rows[0];
    await inGroupTx(s.group_id, async (c) => {
      const m = await membership(c, s.group_id, req.user.id);
      if (req.user.id !== s.from_user && req.user.id !== s.to_user && !canManage(m)) {
        throw new HttpError(403, 'Sem permissão');
      }
      await c.query('update share_settlements set deleted_at = now() where id = $1', [s.id]);
      await c.query('update share_payments set deleted_at = now() where settlement_id = $1', [s.id]);
      await audit(c, s.group_id, req.user.id, 'settlement.deleted', {
        settlementId: s.id,
        fromUserId: s.from_user,
        toUserId: s.to_user,
        amount: Number(s.amount),
      });
    });
    res.status(204).end();
  }));

  // Recorrências -----------------------------------------------------------------

  app.post('/shared/recurrences', authed, wrap(async (req, res) => {
    const b = req.body ?? {};
    const groupId = uuid(b.groupId);
    const id = await inGroupTx(groupId, async (c) => {
      const m = await membership(c, groupId, req.user.id);
      requireManager(m);
      const cat = await categoryOf(c, groupId, b.categoryId);
      const ruleId = text(b.sourceRuleId, 'a regra recorrente');
      let override = null;
      if (b.override) {
        const r = checkPercentages(b.override, await activeIds(c, groupId));
        if (r.error) throw bad(r.error);
        override = toObject(r.list);
      }
      const description = text(b.description, 'a descrição');
      try {
        const { rows } = await c.query(
          `insert into share_recurrences (group_id, owner_id, source_rule_id, category_id,
             description, override) values ($1, $2, $3, $4, $5, $6) returning id`,
          [groupId, req.user.id, ruleId, cat.id, description, override && JSON.stringify(override)],
        );
        await audit(c, groupId, req.user.id, 'recurrence.created', {
          recurrenceId: rows[0].id,
          description,
          category: cat.name,
          override,
        });
        return rows[0].id;
      } catch (err) {
        if (err.code === '23505') throw new HttpError(409, 'Esta recorrência já está compartilhada no grupo');
        throw err;
      }
    });
    res.status(201).json({ id });
  }));

  async function recurrenceFor(c, id, userId) {
    const { rows } = await c.query(
      'select * from share_recurrences where id = $1 and canceled_at is null',
      [uuid(id)],
    );
    if (!rows.length) throw notFound();
    const r = rows[0];
    const m = await membership(c, r.group_id, userId);
    if (r.owner_id !== userId) requireOwner(m);
    return { r, m };
  }

  app.patch('/shared/recurrences/:id', authed, wrap(async (req, res) => {
    const { rows } = await pool.query('select group_id from share_recurrences where id = $1', [
      uuid(req.params.id),
    ]);
    if (!rows.length) throw notFound();
    await inGroupTx(rows[0].group_id, async (c) => {
      const { r } = await recurrenceFor(c, req.params.id, req.user.id);
      const b = req.body ?? {};
      const cat = b.categoryId != null ? await categoryOf(c, r.group_id, b.categoryId) : null;
      let override = r.override;
      if (b.override !== undefined) {
        if (b.override === null) override = null;
        else {
          const x = checkPercentages(b.override, await activeIds(c, r.group_id));
          if (x.error) throw bad(x.error);
          override = toObject(x.list);
        }
      }
      const paused = typeof b.paused === 'boolean' ? b.paused : r.paused;
      const description = b.description != null ? text(b.description, 'a descrição') : r.description;
      await c.query(
        `update share_recurrences set category_id = $2, override = $3, paused = $4,
           description = $5, updated_at = now() where id = $1`,
        [r.id, cat?.id ?? r.category_id, override && JSON.stringify(override), paused, description],
      );
      await audit(c, r.group_id, req.user.id, paused !== r.paused
        ? (paused ? 'recurrence.paused' : 'recurrence.resumed')
        : 'recurrence.updated', { recurrenceId: r.id, description, override });
    });
    res.status(204).end();
  }));

  /// Encerra o compartilhamento da recorrência. Ocorrências passadas e as
  /// que já têm pagamento ficam; as futuras sem pagamento saem.
  app.delete('/shared/recurrences/:id', authed, wrap(async (req, res) => {
    const { rows } = await pool.query('select group_id from share_recurrences where id = $1', [
      uuid(req.params.id),
    ]);
    if (!rows.length) throw notFound();
    const today = date(req.query.today ?? new Date().toISOString().slice(0, 10));
    const removed = await inGroupTx(rows[0].group_id, async (c) => {
      const { r } = await recurrenceFor(c, req.params.id, req.user.id);
      await c.query('update share_recurrences set canceled_at = now() where id = $1', [r.id]);
      const { rowCount } = await c.query(
        `update share_expenses e set deleted_at = now(), updated_at = now()
         where e.recurrence_id = $1 and e.deleted_at is null and e.date > $2
           and not exists (select 1 from share_payments p
                           where p.expense_id = e.id and p.deleted_at is null)`,
        [r.id, today],
      );
      await audit(c, r.group_id, req.user.id, 'recurrence.canceled', {
        recurrenceId: r.id,
        description: r.description,
        removedFuture: rowCount,
      });
      return rowCount;
    });
    res.json({ removed });
  }));

  // Histórico -------------------------------------------------------------------

  app.get('/shared/groups/:id/history', authed, wrap(async (req, res) => {
    const m = await membership(pool, req.params.id, req.user.id);
    const { rows } = await pool.query(
      `select a.id, a.action, a.details, a.at, a.actor_id, u.name as actor_name
       from share_audit a left join users u on u.id = a.actor_id
       where a.group_id = $1 order by a.at desc, a.id desc limit 500`,
      [m.group_id],
    );
    res.json({
      history: rows.map((r) => ({
        id: Number(r.id),
        action: r.action,
        details: r.details,
        at: r.at,
        actorId: r.actor_id,
        actorName: r.actor_name,
      })),
    });
  }));
}

module.exports = { mountShared, DEFAULT_CATEGORIES };
