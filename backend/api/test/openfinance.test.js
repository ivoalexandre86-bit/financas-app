// Sincronização automática do Open Finance: webhook, varredura, cursor,
// idempotência e permissões. Dados fictícios. A parte de integração exige
// PostgreSQL em TEST_DATABASE_URL.

const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');
const { createApp, migrate } = require('../app');
const { itemHealth } = require('../openfinance');
const { PluggyError } = require('../pluggy');

test('itemHealth: situação da conexão para o app', () => {
  const now = new Date('2026-11-27T12:00:00Z');
  assert.equal(itemHealth({ status: 'UPDATED' }, now).state, 'ok');
  assert.equal(itemHealth({ status: 'UPDATING' }, now).state, 'updating');
  assert.equal(itemHealth({ status: 'LOGIN_ERROR' }, now).state, 'renew');
  assert.equal(itemHealth({ status: 'OUTDATED', execution_status: 'USER_AUTHORIZATION_REVOKED' }, now).state, 'renew');
  assert.equal(itemHealth({ status: 'WAITING_USER_INPUT' }, now).state, 'action');
  const err = itemHealth({ status: 'OUTDATED', error_message: 'Banco fora do ar' }, now);
  assert.deepEqual(err, { state: 'error', message: 'Banco fora do ar' });
  assert.equal(itemHealth({ status: 'UPDATED', fetch_error: 'timeout' }, now).state, 'error');
  const expired = itemHealth({ status: 'UPDATED', consent_expires_at: '2026-11-20T00:00:00Z' }, now);
  assert.equal(expired.state, 'renew');
  assert.match(expired.message, /venceu em 20\/11\/2026/);
  const soon = itemHealth({ status: 'UPDATED', consent_expires_at: '2026-12-01T00:00:00Z' }, now);
  assert.equal(soon.state, 'expiring');
  assert.match(soon.message, /vence em 01\/12\/2026/);
  assert.equal(itemHealth({ status: 'DELETED' }, now).state, 'renew');
});

const url = process.env.TEST_DATABASE_URL;

test('Open Finance automático', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const pool = new Pool({ connectionString: url });
  await pool.query(
    'drop table if exists of_webhook_events, of_transactions, user_invites, account_members, funnel_events, referrals, marketing_spend, openfinance_interest, share_audit, share_payments, share_settlements, share_allocations, share_expenses, share_recurrences, share_categories, share_members, share_groups, of_items, whatsapp_config, whatsapp_links, whatsapp_link_codes, whatsapp_drafts, whatsapp_seen, whatsapp_usage, whatsapp_reminders_sent, app_docs, users cascade',
  );
  await migrate(pool);

  const ITEM = 'aaaaaaaa-1111-2222-3333-444444444444';
  // Pluggy falsa com estado: o teste muda as transações do "banco".
  const bank = {
    item: { id: ITEM, connector: { name: 'Banco Fictício' }, status: 'UPDATED', executionStatus: 'SUCCESS',
      lastUpdatedAt: '2026-11-27T09:00:00.000Z', nextAutoSyncAt: '2026-11-28T09:00:00.000Z' },
    txs: new Map(),
    calls: [],
  };
  const put = (id, fields) => bank.txs.set(id, {
    id, type: 'DEBIT', status: 'POSTED', description: 'COMPRA', ...fields,
  });
  const pluggy = {
    createConnectToken: async (clientUserId, opts) => {
      bank.calls.push(['token', clientUserId, opts]);
      return 'tok';
    },
    getItem: async (id) => {
      if (id !== ITEM) throw new PluggyError(404, 'not found');
      return bank.item;
    },
    updateItem: async (id, opts) => {
      bank.calls.push(['patch', id, opts]);
      return bank.item;
    },
    listAccounts: async () => [{ id: 'acc-1', itemId: ITEM, type: 'BANK', name: 'Conta' }],
    getAccount: async (id) => {
      if (id === 'acc-1') return { id, itemId: ITEM };
      throw new PluggyError(404, 'not found');
    },
    listTransactions: async (accountId, from, to) => {
      bank.calls.push(['list', accountId, from, to]);
      return [...bank.txs.values()];
    },
    listTransactionsByIds: async (accountId, ids) =>
      ids.map((id) => bank.txs.get(id)).filter(Boolean),
  };
  const app = createApp({
    pool, jwtSecret: 'x'.repeat(40), openSignup: true, pluggy, publicUrl: 'https://api.test/',
  });
  const of = app.locals.openFinance;
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
  const owner = await signup('Dono', 'dono@exemplo.test');
  const guest = await signup('Convidada', 'convidada@exemplo.test');
  const stranger = await signup('Outra', 'outra@exemplo.test');
  const read = (token, q = '') => call('GET', `/openfinance/accounts/acc-1/transactions${q}`, { token });

  put('p1', { date: '2026-12-05T00:00:00.000Z', amount: 120, status: 'PENDING', description: 'PIX AGENDADO ALUGUEL' });
  put('t1', { date: '2026-11-20T00:00:00.000Z', amount: 45.9, description: 'MERCADO' });

  await t.test('vincular grava o webhook na conexão e o token já leva o endereço', async () => {
    assert.ok(of.webhookUrl.startsWith('https://api.test/openfinance/webhook/'));
    assert.equal((await call('GET', '/openfinance/status', { token: owner.token })).body.autoSync, true);
    const r = await call('POST', '/openfinance/items', { token: owner.token, body: { itemId: ITEM } });
    assert.equal(r.status, 201);
    assert.deepEqual(bank.calls.find((c) => c[0] === 'patch'), ['patch', ITEM, { webhookUrl: of.webhookUrl }]);
    await call('POST', '/openfinance/connect-token', { token: owner.token, body: { itemId: ITEM } });
    assert.deepEqual(bank.calls.at(-1), ['token', owner.user.id, { itemId: ITEM, webhookUrl: of.webhookUrl }]);
  });

  let cursor;
  await t.test('primeira leitura busca na Pluggy, inclui o agendado (futuro) e devolve cursor', async () => {
    const r = await read(owner.token);
    assert.equal(r.status, 200);
    assert.deepEqual(r.body.transactions.map((x) => [x.id, x.amountCents, x.pending, x.deleted]), [
      ['t1', -4590, false, false],
      ['p1', -12000, true, false],
    ]);
    const list = bank.calls.find((c) => c[0] === 'list');
    assert.ok(list[3] > '2027-01-01', 'busca também datas futuras');
    cursor = r.body.cursor;
    assert.ok(cursor);
  });

  await t.test('sincronizar de novo (e o mesmo webhook repetido) não duplica nada', async () => {
    await of.refreshItem(ITEM);
    await of.refreshItem(ITEM);
    const { rows } = await pool.query('select count(*)::int as n from of_transactions');
    assert.equal(rows[0].n, 2);
    // Nada mudou: o cursor não traz nada... exceto a margem de segurança,
    // que só repete linhas já vistas (o app ignora repetidas).
    await pool.query("update of_transactions set updated_at = now() - interval '1 hour'");
    assert.deepEqual((await read(owner.token, `?since=${encodeURIComponent(new Date().toISOString())}`)).body.transactions, []);
    await of.refreshItem(ITEM);
    const after = await read(owner.token, `?since=${encodeURIComponent(new Date(Date.now() - 5000).toISOString())}`);
    assert.deepEqual(after.body.transactions, [], 'repetir a busca sem mudanças não mexe nas linhas');
  });

  await t.test('webhook: segredo no endereço, eventId repetido é descartado', async () => {
    assert.equal((await call('POST', '/openfinance/webhook/errado', { body: { event: 'item/updated', itemId: ITEM } })).status, 401);
    const path = `/openfinance/webhook/${of.webhookToken}`;
    // O agendado foi confirmado: mesmo ID, agora POSTED.
    put('p1', { date: '2026-12-05T00:00:00.000Z', amount: 120, description: 'PIX AGENDADO ALUGUEL' });
    const ev = { event: 'transactions/updated', eventId: 'ev-1', itemId: ITEM, accountId: 'acc-1', transactionIds: ['p1'] };
    const first = await call('POST', path, { body: ev });
    assert.deepEqual([first.status, first.body.result], [200, 'transactions']);
    const again = await call('POST', path, { body: ev });
    assert.deepEqual([again.status, again.body.result], [200, 'duplicate']);
    const r = await read(owner.token, `?since=${encodeURIComponent(cursor)}`);
    assert.deepEqual(r.body.transactions.map((x) => [x.id, x.pending]), [['p1', false]]);
    // Conexão de outro cliente da Pluggy: ignorada.
    const other = await call('POST', path, { body: { event: 'item/updated', eventId: 'ev-x', itemId: 'zzz' } });
    assert.equal(other.body.result, 'ignored');
  });

  await t.test('removida no banco: o app recebe a remoção pelo cursor', async () => {
    const c = (await read(owner.token)).body.cursor;
    await pool.query("update of_transactions set updated_at = now() - interval '2 hours'");
    const path = `/openfinance/webhook/${of.webhookToken}`;
    await call('POST', path, { body: { event: 'transactions/deleted', eventId: 'ev-2', itemId: ITEM, accountId: 'acc-1', transactionIds: ['t1'] } });
    const r = await read(owner.token, `?since=${encodeURIComponent(c)}`);
    assert.deepEqual(r.body.transactions.map((x) => [x.id, x.deleted]), [['t1', true]]);
  });

  await t.test('estado da conexão: falha e consentimento a renovar', async () => {
    let items = (await call('GET', '/openfinance/items', { token: owner.token })).body.items;
    assert.equal(items[0].health, 'ok');
    assert.equal(items[0].providerUpdatedAt, '2026-11-27T09:00:00.000Z');
    assert.equal(items[0].nextAutoSyncAt, '2026-11-28T09:00:00.000Z');
    bank.item = { ...bank.item, status: 'LOGIN_ERROR', executionStatus: 'USER_AUTHORIZATION_REVOKED' };
    await call('POST', `/openfinance/webhook/${of.webhookToken}`, { body: { event: 'item/error', eventId: 'ev-3', itemId: ITEM } });
    items = (await call('GET', '/openfinance/items', { token: owner.token })).body.items;
    assert.equal(items[0].needsRenewal, true);
    assert.match(items[0].message, /Renove o consentimento/);
    bank.item = { ...bank.item, status: 'UPDATED', executionStatus: 'SUCCESS' };
    const s = await call('POST', `/openfinance/items/${ITEM}/sync`, { token: owner.token });
    assert.equal(s.status, 200);
    assert.equal(s.body.requested, true);
    assert.equal(s.body.item.health, 'ok');
  });

  await t.test('varredura atualiza conexões paradas', async () => {
    await pool.query("update of_items set fetched_at = now() - interval '1 day'");
    put('t9', { date: '2026-11-26T00:00:00.000Z', amount: 9.99, description: 'APP' });
    assert.equal(await of.sweep(), 1);
    assert.equal(await of.sweep(), 0, 'recém-atualizada fica de fora');
    const { rows } = await pool.query("select 1 from of_transactions where tx_id = 't9'");
    assert.equal(rows.length, 1);
  });

  await t.test('permissões: outro usuário e convidado com acesso limitado não acessam', async () => {
    assert.equal((await read(stranger.token)).status, 404);
    assert.equal((await call('POST', `/openfinance/items/${ITEM}/sync`, { token: stranger.token })).status, 404);
    assert.deepEqual((await call('GET', '/openfinance/items', { token: stranger.token })).body.items, []);
    // Convidada com acesso limitado a um cartão.
    await call('POST', '/account/members', {
      token: owner.token, body: { email: 'convidada@exemplo.test', scope: { cards: ['c1'] } },
    });
    const inv = (await call('GET', '/account', { token: guest.token })).body.invites[0];
    await call('POST', `/account/invites/${inv.id}/accept`, { token: guest.token });
    assert.equal((await read(guest.token)).status, 404);
    assert.deepEqual((await call('GET', '/openfinance/items', { token: guest.token })).body.items, []);
    assert.equal((await call('POST', '/openfinance/connect-token', { token: guest.token, body: {} })).status, 403);
    // Com acesso total, a mesma pessoa passa a ver a conexão do dono.
    const memberId = (await call('GET', '/account', { token: owner.token })).body.members
      .find((m) => m.name === 'Convidada').id;
    await call('PATCH', `/account/members/${memberId}`, { token: owner.token, body: { scope: null } });
    assert.equal((await read(guest.token)).status, 200);
    assert.equal((await call('GET', '/openfinance/items', { token: guest.token })).body.items.length, 1);
  });
});
