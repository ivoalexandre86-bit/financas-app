// Funil, indicação e painel do negócio. O fluxo com banco exige
// TEST_DATABASE_URL.

const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');
const { createApp, migrate } = require('../app');
const { cleanChannel, canonicalEmail, storeEventName, amountOf } = require('../growth');
const { accessOf } = require('../billing');

test('canal, e-mail canônico e eventos da loja', () => {
  assert.equal(cleanChannel(' Instagram Ads '), 'instagram-ads');
  assert.equal(cleanChannel('Indicação'), 'indicacao');
  assert.equal(cleanChannel(''), null);
  assert.equal(canonicalEmail('I.vo+teste@GMAIL.com'), 'ivo@gmail.com');
  assert.equal(canonicalEmail('i.vo+x@empresa.com'), 'i.vo@empresa.com');
  assert.equal(storeEventName({ type: 'INITIAL_PURCHASE' }, false), 'first_charge');
  assert.equal(storeEventName({ type: 'INITIAL_PURCHASE', period_type: 'TRIAL' }, false), null);
  assert.equal(storeEventName({ type: 'INITIAL_PURCHASE' }, true), 'renewal');
  assert.equal(storeEventName({ type: 'RENEWAL' }, true), 'renewal');
  assert.equal(storeEventName({ type: 'CANCELLATION' }, true), 'cancellation');
  assert.equal(storeEventName({ type: 'TEST' }, true), null);
  assert.equal(amountOf({ price_in_purchased_currency: 9.99, price: 1.8 }), 999);
  assert.equal(amountOf({}), null);
});

test('Premium ganho por indicação', () => {
  const now = new Date('2026-11-02T12:00:00Z');
  const base = { is_admin: false, free_access: false, trial_ends_at: '2026-10-01T00:00:00Z', paid_until: null, plan: null };
  const a = accessOf({ ...base, bonus_until: '2026-12-01T00:00:00Z' }, now);
  assert.equal(a.status, 'bonus');
  assert.equal(a.plan, 'premium');
  assert.equal(a.bonusUntil, '2026-12-01T00:00:00.000Z');
  assert.equal(accessOf({ ...base, bonus_until: '2026-10-02T00:00:00Z' }, now).plan, 'gratis');
  // Assinante do Básico com dias ganhos: Premium enquanto durarem.
  const paid = { ...base, paid_until: '2026-12-01T00:00:00Z', plan: 'basico' };
  assert.equal(accessOf(paid, now).plan, 'basico');
  assert.equal(accessOf({ ...paid, bonus_until: '2026-11-20T00:00:00Z' }, now).plan, 'premium');
  assert.equal(accessOf({ ...paid, bonus_until: '2026-11-20T00:00:00Z' }, now).status, 'active');
});

const url = process.env.TEST_DATABASE_URL;

test('funil, indicação e painel pela API', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const pool = new Pool({ connectionString: url });
  await pool.query(
    'drop table if exists funnel_events, referrals, marketing_spend, openfinance_interest, share_audit, share_payments, share_settlements, share_allocations, share_expenses, share_recurrences, share_categories, share_members, share_groups, of_items, whatsapp_config, whatsapp_links, whatsapp_link_codes, whatsapp_drafts, whatsapp_seen, whatsapp_usage, app_docs, users cascade',
  );
  await migrate(pool);
  const app = createApp({
    pool,
    jwtSecret: 'x'.repeat(40),
    openSignup: true,
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
  const signup = (name, email, extra = {}) =>
    call('POST', '/auth/register', { body: { name, email, password: 'Senha1234', ...extra } });
  const hook = (event) =>
    call('POST', '/billing/revenuecat', { body: { event }, headers: { authorization: 'Bearer segredo' } });

  // Instalação anônima pelo link de um anúncio; o cadastro herda o canal.
  assert.equal((await call('POST', '/events', { body: { name: 'first_budget' } })).status, 401);
  assert.equal((await call('POST', '/events', { body: { name: 'install' } })).status, 400);
  assert.equal((await call('POST', '/events', { body: { name: 'hack', deviceId: 'dev-aaaaaaaa' } })).status, 400);
  const inst = await call('POST', '/events', { body: { name: 'install', deviceId: 'dev-aaaaaaaa', channel: 'Instagram' } });
  assert.equal(inst.body.saved, true);
  // Mesma instalação de novo não conta duas vezes.
  assert.equal((await call('POST', '/events', { body: { name: 'install', deviceId: 'dev-aaaaaaaa' } })).body.saved, false);

  const owner = (await signup('Ivo Alexandre', 'ivo@gmail.com', { deviceId: 'dev-owner000' })).body;
  const ana = (await signup('Ana', 'ana@x.com', { deviceId: 'dev-aaaaaaaa' })).body;
  const anaRow = (await pool.query('select * from users where id = $1', [ana.user.id])).rows[0];
  assert.equal(anaRow.channel, 'instagram');

  // Eventos do app com login, únicos por usuário.
  for (const name of ['first_budget', 'first_budget', 'first_simulation', 'active', 'active']) {
    assert.equal((await call('POST', '/events', { token: ana.token, body: { name, props: { a: 1, 'x y': 2, o: {} } } })).status, 200);
  }
  const anaEvents = (await pool.query(
    'select name, props from funnel_events where user_id = $1 order by id', [ana.user.id])).rows;
  assert.deepEqual(anaEvents.map((e) => e.name), ['signup', 'trial_start', 'first_budget', 'first_simulation', 'active']);
  assert.deepEqual(anaEvents[2].props, { a: 1 });

  // Convite do Ivo.
  const ref = (await call('GET', '/referral', { token: owner.token })).body;
  assert.match(ref.code, /^[A-Z2-9]{6}$/);
  assert.equal((await call('GET', '/referral', { token: owner.token })).body.code, ref.code);
  assert.equal((await call('GET', `/referral/${ref.code}`)).body.name, 'Ivo');
  assert.equal((await call('GET', '/referral/ZZZZZZ')).status, 404);

  // Indicado válido ganha 15 dias a mais de teste.
  const bia = (await signup('Bia', 'bia@x.com', { ref: ref.code.toLowerCase(), deviceId: 'dev-bia00000' })).body;
  const biaRow = (await pool.query('select * from users where id = $1', [bia.user.id])).rows[0];
  assert.equal(biaRow.channel, 'indicacao');
  const trialDays = (new Date(biaRow.trial_ends_at) - new Date(biaRow.created_at)) / 864e5;
  assert.ok(Math.abs(trialDays - 45) < 0.01, `teste de ${trialDays} dias`);
  // Antifraude: o próprio Ivo com apelido de e-mail e alguém no aparelho dele.
  await signup('Ivo 2', 'i.vo+2@gmail.com', { ref: ref.code });
  await signup('Ivo 3', 'outro@x.com', { ref: ref.code, deviceId: 'dev-owner000' });
  const refs = (await pool.query('select status, reason from referrals order by created_at')).rows;
  assert.deepEqual(refs.map((r) => r.status), ['pending', 'rejected', 'rejected']);
  assert.deepEqual(refs.slice(1).map((r) => r.reason), ['mesmo e-mail', 'mesmo aparelho']);

  // Bia assina: 1ª cobrança → Ivo ganha 30 dias de Premium.
  await hook({ id: 'ev1', type: 'INITIAL_PURCHASE', app_user_id: bia.user.id, price_in_purchased_currency: 9.99, currency: 'BRL', store: 'PLAY_STORE', entitlement_ids: ['basico'] });
  await hook({ id: 'ev1', type: 'INITIAL_PURCHASE', app_user_id: bia.user.id, price_in_purchased_currency: 9.99 });
  await hook({ id: 'ev2', type: 'RENEWAL', app_user_id: bia.user.id, price_in_purchased_currency: 9.99 });
  await hook({ id: 'ev3', type: 'CANCELLATION', app_user_id: bia.user.id, cancel_reason: 'UNSUBSCRIBE' });
  const biaEvents = (await pool.query(
    `select name from funnel_events where user_id = $1 and name not in ('signup', 'trial_start') order by id`, [bia.user.id])).rows;
  assert.deepEqual(biaEvents.map((e) => e.name), ['first_charge', 'renewal', 'cancellation']);
  const after = (await call('GET', '/referral', { token: owner.token })).body;
  assert.equal(after.rewarded, 1);
  assert.equal(after.invited, 3);
  assert.ok(new Date(after.bonusUntil) > new Date(Date.now() + 29 * 864e5));

  // Ana (sem convite) com assinatura e Premium ganho por indicação.
  await pool.query("update users set paid_until = now() + interval '20 days', plan = 'premium' where id = $1", [ana.user.id]);
  await pool.query("update users set paid_until = now() + interval '20 days', plan = 'basico' where id = $1", [bia.user.id]);

  // Painel: só administradores.
  assert.equal((await call('GET', '/admin/metrics', { token: ana.token })).status, 403);
  assert.equal((await call('POST', '/admin/spend', { token: owner.token, body: { month: '2026-13', channel: 'x', amountCents: 1 } })).status, 400);
  const month = new Date().toISOString().slice(0, 7);
  assert.equal((await call('POST', '/admin/spend', { token: owner.token, body: { month, channel: 'Indicação', amountCents: 5000 } })).status, 204);
  assert.equal((await call('POST', '/admin/spend', { token: owner.token, body: { month, channel: 'tiktok', amountCents: 300 } })).status, 204);
  assert.equal((await call('POST', '/admin/spend', { token: owner.token, body: { month, channel: 'tiktok', amountCents: 0 } })).status, 204);
  assert.deepEqual((await call('GET', '/admin/spend', { token: owner.token })).body.spend, [
    { month, channel: 'indicacao', amountCents: 5000 },
  ]);
  const m = (await call('GET', '/admin/metrics', { token: owner.token })).body;
  assert.equal(m.kpis.mrrCents, 999 + 1999);
  assert.equal(m.kpis.paying, 2);
  assert.equal(m.kpis.cacCents, 5000);
  const f = Object.fromEntries(m.funnel.map((x) => [x.name, x.count]));
  assert.equal(f.install, 1);
  assert.equal(f.signup, 5);
  assert.equal(f.first_budget, 1);
  assert.equal(f.first_charge, 1);
  assert.equal(f.cancellation, 1);
  const ch = Object.fromEntries(m.channels.map((c) => [c.channel, c]));
  assert.equal(ch.indicacao.paying, 1);
  assert.equal(ch.indicacao.revenueCents, 1998);
  assert.equal(ch.indicacao.cacCents, 5000);
  assert.equal(ch.instagram.signups, 1);
  const cur = m.months.at(-1);
  assert.equal(cur.month, month);
  assert.equal(cur.revenueCents, 1998);
  assert.equal(m.cohorts.at(-1).month, month);
  assert.equal(m.cohorts.at(-1).retention[0], 25); // Ana ativa entre 4 não-admins.
  assert.equal(m.cohorts.at(-1).retention[1], null); // mês que ainda não chegou.
  assert.deepEqual(m.referrals, { pending: 0, rewarded: 1, rejected: 2 });

  // Conta excluída: o evento fica para os números, sem o vínculo.
  assert.equal((await call('DELETE', '/me', { token: bia.token })).status, 204);
  const orphan = await pool.query(`select count(*)::int n from funnel_events where name = 'first_charge' and user_id is null`);
  assert.equal(orphan.rows[0].n, 1);
});
