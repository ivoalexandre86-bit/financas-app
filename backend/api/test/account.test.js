// Conta com vários usuários: convite, aceite, dados em comum, plano do dono,
// saída e remoção. Exige PostgreSQL em TEST_DATABASE_URL.

const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');
const { createApp, migrate } = require('../app');

const url = process.env.TEST_DATABASE_URL;

test('conta com vários usuários', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const pool = new Pool({ connectionString: url });
  await pool.query(
    'drop table if exists account_members, funnel_events, referrals, marketing_spend, openfinance_interest, share_audit, share_payments, share_settlements, share_allocations, share_expenses, share_recurrences, share_categories, share_members, share_groups, of_items, whatsapp_config, whatsapp_links, whatsapp_link_codes, whatsapp_drafts, whatsapp_seen, whatsapp_usage, app_docs, users cascade',
  );
  await migrate(pool);
  const app = createApp({ pool, jwtSecret: 'x'.repeat(40), openSignup: true });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    server.close();
    await pool.end();
  });
  async function call(method, path, { token, body } = {}) {
    const res = await fetch(base + path, {
      method,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  }
  const signup = async (name, email) =>
    (await call('POST', '/auth/register', { body: { name, email, password: 'Senha1234' } })).body;
  const save = (token, id, name) =>
    call('POST', '/docs/batch', {
      token,
      body: { docs: [{ coll: 'accounts', id, data: { id, name } }] },
    });
  const names = async (token) =>
    (await call('GET', '/docs', { token })).body.docs.map((d) => d.data.name).sort();

  const ivo = await signup('Ivo', 'ivo@x.com');
  const ana = await signup('Ana', 'ana@x.com');
  const bia = await signup('Bia', 'bia@x.com');
  await save(ivo.token, 'a1', 'Itaú do Ivo');
  await save(ana.token, 'b1', 'Nubank da Ana');

  await t.test('dono convida pelo e-mail; convidado vê o convite', async () => {
    assert.equal((await call('POST', '/account/members', { token: ivo.token, body: { email: 'x' } })).status, 400);
    assert.equal(
      (await call('POST', '/account/members', { token: ivo.token, body: { email: 'ivo@x.com' } })).status,
      400,
    );
    const r = await call('POST', '/account/members', { token: ivo.token, body: { email: ' Ana@X.com ' } });
    assert.equal(r.status, 201);
    assert.deepEqual(r.body.members.map((m) => [m.email, m.status]), [
      ['ivo@x.com', 'owner'],
      ['ana@x.com', 'invited'],
    ]);
    assert.equal(
      (await call('POST', '/account/members', { token: ivo.token, body: { email: 'ana@x.com' } })).status,
      409,
    );
    const me = (await call('GET', '/me', { token: ana.token })).body.user;
    assert.equal(me.pendingInvites, 1);
    assert.equal(me.account, null);
    const st = (await call('GET', '/account', { token: ana.token })).body;
    assert.equal(st.invites.length, 1);
    assert.equal(st.invites[0].ownerName, 'Ivo');
    // Outra pessoa não aceita o convite da Ana.
    assert.equal((await call('POST', `/account/invites/${st.invites[0].id}/accept`, { token: bia.token })).status, 404);
  });

  await t.test('aceitar: os dois usam o mesmo orçamento', async () => {
    const inv = (await call('GET', '/account', { token: ana.token })).body.invites[0];
    const r = await call('POST', `/account/invites/${inv.id}/accept`, { token: ana.token });
    assert.equal(r.status, 200);
    assert.equal(r.body.account.isOwner, false);
    assert.equal(r.body.account.ownerName, 'Ivo');
    assert.deepEqual(await names(ana.token), ['Itaú do Ivo']);
    await save(ana.token, 'a2', 'Caixa da casa');
    assert.deepEqual(await names(ivo.token), ['Caixa da casa', 'Itaú do Ivo']);
    const me = (await call('GET', '/me', { token: ana.token })).body.user;
    assert.equal(me.account.id, ivo.user.id);
    assert.equal(me.account.ownerName, 'Ivo');
    // Login também informa a conta.
    const login = await call('POST', '/auth/login', { body: { email: 'ana@x.com', password: 'Senha1234' } });
    assert.equal(login.body.user.account.ownerName, 'Ivo');
    // Só o dono convida.
    assert.equal(
      (await call('POST', '/account/members', { token: ana.token, body: { email: 'bia@x.com' } })).status,
      409,
    );
    // Lista vista pelos dois.
    const st = (await call('GET', '/account', { token: ana.token })).body;
    assert.deepEqual(st.members.map((m) => [m.name, m.status]), [['Ivo', 'owner'], ['Ana', 'active']]);
  });

  await t.test('quem entrou usa o plano do dono quando é melhor', async () => {
    await pool.query("update users set trial_ends_at = now() - interval '1 day' where id = $1", [ana.user.id]);
    const own = (await call('GET', '/me', { token: ana.token })).body.user.access;
    assert.equal(own.plan, 'premium'); // Ivo é o administrador do servidor.
    assert.equal(own.sharedBy, 'Ivo');
  });

  await t.test('quem divide a própria conta não entra em outra', async () => {
    await call('POST', '/account/members', { token: bia.token, body: { email: 'ivo@x.com' } });
    const inv = (await call('GET', '/account', { token: ivo.token })).body.invites[0];
    const r = await call('POST', `/account/invites/${inv.id}/accept`, { token: ivo.token });
    assert.equal(r.status, 409);
    assert.equal((await call('POST', `/account/invites/${inv.id}/reject`, { token: ivo.token })).status, 200);
    assert.equal((await call('GET', '/account', { token: ivo.token })).body.invites.length, 0);
  });

  await t.test('sair devolve os próprios dados; o dono pode remover', async () => {
    const left = await call('POST', '/account/leave', { token: ana.token });
    assert.equal(left.body.account.isOwner, true);
    assert.deepEqual(await names(ana.token), ['Nubank da Ana']);
    assert.equal((await call('GET', '/me', { token: ana.token })).body.user.access.plan, 'gratis');

    await call('POST', '/account/members', { token: ivo.token, body: { email: 'ana@x.com' } });
    const inv = (await call('GET', '/account', { token: ana.token })).body.invites[0];
    await call('POST', `/account/invites/${inv.id}/accept`, { token: ana.token });
    assert.deepEqual(await names(ana.token), ['Caixa da casa', 'Itaú do Ivo']);
    const member = (await call('GET', '/account', { token: ivo.token })).body.members.find((m) => m.name === 'Ana');
    // Outra pessoa não remove.
    assert.equal((await call('DELETE', `/account/members/${member.id}`, { token: bia.token })).status, 404);
    const r = await call('DELETE', `/account/members/${member.id}`, { token: ivo.token });
    assert.equal(r.status, 200);
    assert.equal(r.body.members.length, 1);
    assert.deepEqual(await names(ana.token), ['Nubank da Ana']);
  });

  await t.test('convite para quem ainda não tem conta vale no cadastro', async () => {
    await call('POST', '/account/members', { token: ivo.token, body: { email: 'novo@x.com' } });
    const novo = await signup('Novo', 'novo@x.com');
    assert.equal(novo.user.pendingInvites, 1);
  });
});
