// Acesso limitado na conta compartilhada: quem entrou só enxerga e grava
// nos cartões e contas liberados. Exige PostgreSQL em TEST_DATABASE_URL.

const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');
const { createApp, migrate } = require('../app');
const { normScope } = require('../account');

test('normScope', () => {
  assert.equal(normScope(null), null);
  assert.equal(normScope('all'), null);
  assert.deepEqual(normScope({ cards: ['c1', 'c1'], accounts: [] }), { cards: ['c1'], accounts: [] });
  assert.throws(() => normScope({ cards: [], accounts: [] }), /ao menos um/);
  assert.throws(() => normScope({ cards: 'c1' }), /inválido/);
});

const url = process.env.TEST_DATABASE_URL;

test('acesso limitado a cartões e contas', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const pool = new Pool({ connectionString: url });
  await pool.query(
    'drop table if exists user_invites, account_members, funnel_events, referrals, marketing_spend, openfinance_interest, share_audit, share_payments, share_settlements, share_allocations, share_expenses, share_recurrences, share_categories, share_members, share_groups, of_items, whatsapp_config, whatsapp_links, whatsapp_link_codes, whatsapp_drafts, whatsapp_seen, whatsapp_usage, whatsapp_reminders_sent, app_docs, users cascade',
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
  const push = (token, docs) => call('POST', '/docs/batch', { token, body: { docs } });
  const ids = async (token) =>
    (await call('GET', '/docs', { token })).body.docs.map((d) => `${d.coll}/${d.id}`).sort();

  const ivo = await signup('Ivo', 'ivo@x.com');
  const ana = await signup('Ana', 'ana@x.com');
  await push(ivo.token, [
    { coll: 'accounts', id: 'itau', data: { id: 'itau', name: 'Itaú' } },
    { coll: 'accounts', id: 'caixa', data: { id: 'caixa', name: 'Caixa' } },
    { coll: 'cards', id: 'nubank', data: { id: 'nubank', name: 'Nubank' } },
    { coll: 'cards', id: 'xp', data: { id: 'xp', name: 'XP' } },
    { coll: 'categories', id: 'food', data: { id: 'food', name: 'Mercado' } },
    { coll: 'transactions', id: 't1', data: { id: 't1', cardId: 'nubank', amount: 10 } },
    { coll: 'transactions', id: 't2', data: { id: 't2', cardId: 'xp', amount: 20 } },
    { coll: 'transactions', id: 't3', data: { id: 't3', accountId: 'itau', amount: 30 } },
    { coll: 'transactions', id: 't4', data: { id: 't4', accountId: 'caixa', destinationAccountId: 'itau' } },
    { coll: 'invoicePayments', id: 'p1', data: { id: 'p1', cardId: 'xp', accountId: 'itau' } },
    { coll: 'budgets', id: 'b1', data: { id: 'b1' } },
    { coll: 'settings', id: 'app', data: { whatsappReminders: true } },
  ]);

  let memberId;
  await t.test('convite com acesso só ao Nubank e ao Itaú', async () => {
    assert.equal(
      (await call('POST', '/account/members', {
        token: ivo.token,
        body: { email: 'ana@x.com', scope: { cards: [], accounts: [] } },
      })).status,
      400,
    );
    const r = await call('POST', '/account/members', {
      token: ivo.token,
      body: { email: 'ana@x.com', scope: { cards: ['nubank'], accounts: ['itau'] } },
    });
    assert.equal(r.status, 201);
    const inv = (await call('GET', '/account', { token: ana.token })).body.invites[0];
    await call('POST', `/account/invites/${inv.id}/accept`, { token: ana.token });
    const me = (await call('GET', '/me', { token: ana.token })).body.user;
    assert.deepEqual(me.account.scope, { cards: ['nubank'], accounts: ['itau'] });
    memberId = (await call('GET', '/account', { token: ivo.token })).body.members.find((m) => m.name === 'Ana').id;
  });

  await t.test('só enxerga os cartões/contas liberados e seus lançamentos', async () => {
    assert.deepEqual(await ids(ana.token), [
      'accounts/itau',
      'cards/nubank',
      'categories/food',
      'transactions/t1',
      'transactions/t3',
      'transactions/t4',
    ]);
  });

  await t.test('grava só lançamentos dentro do acesso', async () => {
    const r = await push(ana.token, [
      { coll: 'transactions', id: 't5', data: { id: 't5', cardId: 'nubank', amount: 5 } },
      { coll: 'transactions', id: 't6', data: { id: 't6', cardId: 'xp', amount: 6 } }, // fora
      { coll: 'transactions', id: 't2', data: { id: 't2', cardId: 'nubank', amount: 0 } }, // roubar t2
      { coll: 'transactions', id: 't1', data: { id: 't1', cardId: 'xp', amount: 10 } }, // mover p/ fora
      { coll: 'transactions', id: 't3', deleted: true },
      { coll: 'budgets', id: 'b1', deleted: true },
      { coll: 'settings', id: 'app', data: {} },
      { coll: 'cards', id: 'nubank', data: { id: 'nubank', name: 'Meu' } },
    ]);
    assert.equal(r.status, 200);
    assert.equal(r.body.saved, 2);
    assert.equal(r.body.skipped, 6);
    const own = (await call('GET', '/docs', { token: ivo.token })).body.docs;
    const get = (c, i) => own.find((d) => d.coll === c && d.id === i)?.data;
    assert.equal(get('transactions', 't5').amount, 5);
    assert.equal(get('transactions', 't6'), undefined);
    assert.equal(get('transactions', 't2').cardId, 'xp');
    assert.equal(get('transactions', 't1').cardId, 'nubank');
    assert.equal(get('transactions', 't3'), undefined); // excluída pela Ana
    assert.ok(get('budgets', 'b1'));
    assert.deepEqual(get('settings', 'app'), { whatsappReminders: true });
    assert.equal(get('cards', 'nubank').name, 'Nubank');
  });

  await t.test('dono muda para acesso total e depois limita de novo', async () => {
    assert.equal(
      (await call('PATCH', `/account/members/${memberId}`, { token: ana.token, body: { scope: null } })).status,
      404,
    );
    const r = await call('PATCH', `/account/members/${memberId}`, { token: ivo.token, body: { scope: null } });
    assert.equal(r.status, 200);
    assert.equal(r.body.members.find((m) => m.id === memberId).scope, null);
    assert.ok((await ids(ana.token)).includes('budgets/b1'));
    await call('PATCH', `/account/members/${memberId}`, {
      token: ivo.token,
      body: { scope: { cards: ['xp'] } },
    });
    assert.deepEqual(await ids(ana.token), ['cards/xp', 'categories/food', 'invoicePayments/p1', 'transactions/t2']);
  });
});
