// Assinatura: regras puras sempre; o fluxo com banco exige TEST_DATABASE_URL.

const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');
const { createApp, migrate } = require('../app');
const { accessOf, fromEntitlements } = require('../billing');

const now = new Date('2026-10-18T12:00:00Z');
const later = '2026-11-18T12:00:00Z';
const before = '2026-10-01T12:00:00Z';

test('situação de acesso', () => {
  const base = { is_admin: false, free_access: false, trial_ends_at: later, paid_until: null, plan: null };
  assert.equal(accessOf(base, now).status, 'trial');
  assert.equal(accessOf({ ...base, trial_ends_at: before }, now).status, 'expired');
  assert.equal(accessOf({ ...base, trial_ends_at: before, paid_until: later, plan: 'basico' }, now).status, 'active');
  assert.equal(accessOf({ ...base, trial_ends_at: before, paid_until: later, plan: 'basico' }, now).premium, false);
  assert.equal(accessOf({ ...base, trial_ends_at: before, paid_until: later, plan: 'premium' }, now).premium, true);
  assert.equal(accessOf({ ...base, trial_ends_at: before, free_access: true }, now).status, 'free');
  assert.equal(accessOf({ ...base, trial_ends_at: before, is_admin: true }, now).status, 'admin');
  // O teste grátis não dá Open Finance.
  assert.equal(accessOf(base, now).premium, false);
});

test('permissões do RevenueCat', () => {
  assert.deepEqual(fromEntitlements({}, now), { paidUntil: null, plan: null });
  const basic = fromEntitlements({ basico: { expires_date: later } }, now);
  assert.equal(basic.plan, 'basico');
  assert.equal(basic.paidUntil.toISOString(), new Date(later).toISOString());
  assert.equal(fromEntitlements({ basico: { expires_date: later }, premium: { expires_date: later } }, now).plan, 'premium');
  // Premium vencido não conta, mas a validade fica registrada.
  const old = fromEntitlements({ premium: { expires_date: before } }, now);
  assert.equal(old.plan, 'basico');
  assert.equal(old.paidUntil.toISOString(), new Date(before).toISOString());
});

const url = process.env.TEST_DATABASE_URL;

test('assinatura pela API', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const pool = new Pool({ connectionString: url });
  await pool.query(
    'drop table if exists share_audit, share_payments, share_settlements, share_allocations, share_expenses, share_recurrences, share_categories, share_members, share_groups, of_items, whatsapp_config, whatsapp_links, whatsapp_link_codes, whatsapp_drafts, whatsapp_seen, whatsapp_usage, app_docs, users cascade',
  );
  await migrate(pool);
  const entitlements = new Map();
  const app = createApp({
    pool,
    jwtSecret: 'x'.repeat(40),
    openSignup: true,
    revenuecat: { entitlements: async (id) => entitlements.get(id) ?? {} },
    revenuecatWebhookAuth: 'Bearer segredo',
  });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    server.close();
    await pool.end();
  });
  async function call(method, path, { token, body, headers = {} } = {}) {
    const res = await fetch(base + path, {
      method,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...headers,
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  }
  const signup = (name, email) =>
    call('POST', '/auth/register', { body: { name, email, password: 'Senha1234', freeAccess: true } });

  const owner = (await signup('Ivo', 'ivo@x.com')).body;
  assert.equal(owner.user.access.status, 'admin');
  const eva = (await signup('Eva', 'eva@x.com')).body;
  // Quem se cadastra começa no teste grátis, mesmo pedindo cortesia.
  assert.equal(eva.user.access.status, 'trial');
  const doc = { docs: [{ coll: 'accounts', id: 'a1', data: { id: 'a1', name: 'Itaú' } }] };
  assert.equal((await call('POST', '/docs/batch', { token: eva.token, body: doc })).status, 200);

  // Teste vencido: lê, mas não grava.
  await pool.query("update users set trial_ends_at = now() - interval '1 day' where id = $1", [eva.user.id]);
  assert.equal((await call('GET', '/me', { token: eva.token })).body.user.access.status, 'expired');
  const blocked = await call('POST', '/docs/batch', { token: eva.token, body: doc });
  assert.equal(blocked.status, 402);
  assert.match(blocked.body.error, /assinatura venceu/);
  assert.equal((await call('GET', '/docs', { token: eva.token })).status, 200);

  // Compra do plano básico confirmada pelo app.
  entitlements.set(eva.user.id, { basico: { expires_date: '2099-01-01T00:00:00Z' } });
  const paid = await call('POST', '/billing/refresh', { token: eva.token });
  assert.equal(paid.body.access.status, 'active');
  assert.equal(paid.body.access.premium, false);
  assert.equal((await call('POST', '/docs/batch', { token: eva.token, body: doc })).status, 200);
  // Open Finance só no Premium.
  const of = await call('POST', '/openfinance/connect-token', { token: eva.token });
  assert.equal(of.status, 402);

  // Webhook: precisa do segredo; troca para Premium.
  const hook = { event: { type: 'PRODUCT_CHANGE', app_user_id: eva.user.id } };
  assert.equal((await call('POST', '/billing/revenuecat', { body: hook })).status, 401);
  entitlements.set(eva.user.id, { premium: { expires_date: '2099-01-01T00:00:00Z' } });
  const ok = await call('POST', '/billing/revenuecat', { body: hook, headers: { authorization: 'Bearer segredo' } });
  assert.equal(ok.status, 200);
  assert.equal((await call('GET', '/me', { token: eva.token })).body.user.access.premium, true);

  // Conta criada pelo administrador é cortesia.
  const guest = await call('POST', '/users', {
    token: owner.token,
    body: { name: 'Bia', email: 'bia@x.com', password: 'Senha1234' },
  });
  assert.equal(guest.body.user?.access?.status ?? guest.body.access?.status, 'free');
});
