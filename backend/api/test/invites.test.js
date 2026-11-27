// Convite pelo WhatsApp: administrador convida um número, o bot manda o
// modelo com o link, a pessoa se cadastra pelo link (número ligado ao bot e,
// se pedido, conta compartilhada). Exige PostgreSQL em TEST_DATABASE_URL.

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { Pool } = require('pg');
const { createApp, migrate } = require('../app');
const { normalizePhone, formatPhone, templateDefinition } = require('../whatsapp/invites');

test('normalizePhone', () => {
  assert.equal(normalizePhone('(47) 99189-2931'), '5547991892931');
  assert.equal(normalizePhone('+55 47 99189-2931'), '5547991892931');
  assert.equal(normalizePhone('4732418582'), '554732418582');
  assert.equal(normalizePhone('+1 415 555 0100'), '14155550100');
  assert.equal(normalizePhone('123'), null);
  assert.equal(normalizePhone('55 47 9'), null);
  assert.equal(formatPhone('5547991892931'), '+55 (47) 99189-2931');
  const def = templateDefinition('convite_financas', 'https://app.example/');
  assert.equal(def.components[2].buttons[0].url, 'https://app.example/?cadastro={{1}}');
});

const url = process.env.TEST_DATABASE_URL;

test('convite pelo WhatsApp', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const pool = new Pool({ connectionString: url });
  await pool.query(
    'drop table if exists user_invites, account_members, funnel_events, referrals, marketing_spend, openfinance_interest, share_audit, share_payments, share_settlements, share_allocations, share_expenses, share_recurrences, share_categories, share_members, share_groups, of_items, whatsapp_config, whatsapp_links, whatsapp_link_codes, whatsapp_drafts, whatsapp_seen, whatsapp_usage, whatsapp_reminders_sent, app_docs, users cascade',
  );
  await migrate(pool);

  const sent = [];
  const created = [];
  let tplStatus = null;
  let failSend = false;
  let processed = Promise.resolve();
  const meta = {
    templateStatus: async () => (tplStatus ? { status: tplStatus } : null),
    createTemplate: async (def) => {
      created.push(def);
      tplStatus = 'PENDING';
    },
    sendTemplateComponents: async (to, name, components) => {
      if (failSend) throw new Error('WhatsApp API 400: boom');
      sent.push({ to, name, components });
      return { contacts: [{ wa_id: '554791892931' }], messages: [{ id: `wamid.inv${sent.length}` }] };
    },
    sendCta: async (to, text, label, link) => sent.push({ to, text, label, link }),
    sendText: async (to, text) => sent.push({ to, text }),
    markRead: () => {},
  };
  const whatsapp = {
    config: { verifyToken: 'vt', appSecret: 'app-secret', botNumber: '5547991892931' },
    meta,
    extract: async () => ({}),
    appUrl: 'https://app.example/',
    onProcessed: (p) => (processed = p),
  };
  // Cadastro fechado: só o 1º (admin) ou quem tem convite.
  const app = createApp({ pool, jwtSecret: 'x'.repeat(40), whatsapp, openSignup: false });
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
  async function webhook(value) {
    const body = JSON.stringify({ object: 'whatsapp_business_account', entry: [{ changes: [{ value }] }] });
    const sig = 'sha256=' + crypto.createHmac('sha256', 'app-secret').update(body).digest('hex');
    sent.length = 0;
    await fetch(`${base}/whatsapp/webhook`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-hub-signature-256': sig },
      body,
    });
    await processed;
    await new Promise((r) => setTimeout(r, 50));
  }
  const tokenOf = (link) => new URL(link).searchParams.get('cadastro');

  const ivo = (await call('POST', '/auth/register', {
    body: { name: 'Ivo Alexandre', email: 'ivo@x.com', password: 'Senha1234' },
  })).body;

  let first;
  await t.test('sem modelo aprovado: cria o modelo e oferece o envio manual', async () => {
    const r = await call('POST', '/invites', {
      token: ivo.token,
      body: {
        name: 'Ana Souza',
        phone: '(47) 99189-2931',
        joinAccount: true,
        scope: { cards: ['nubank'], accounts: [] },
      },
    });
    assert.equal(r.status, 201);
    assert.equal(created.length, 1);
    assert.equal(created[0].name, 'convite_financas');
    assert.equal(r.body.template.status, 'PENDING');
    const inv = r.body.invite;
    assert.equal(inv.phone, '5547991892931');
    assert.equal(inv.sendStatus, 'not_sent');
    assert.equal(inv.status, 'pending');
    assert.match(inv.link, /^https:\/\/app\.example\/\?cadastro=/);
    assert.match(inv.shareUrl, /^https:\/\/wa\.me\/5547991892931\?text=Ol%C3%A1%2C%20Ana!/);
    assert.equal(sent.length, 0);
    first = inv;
  });

  await t.test('modelo aprovado: reenviar manda pelo bot', async () => {
    tplStatus = 'APPROVED';
    const r = await call('POST', `/invites/${first.id}/resend`, { token: ivo.token });
    assert.equal(r.status, 200);
    assert.equal(r.body.invite.sendStatus, 'sent');
    assert.equal(sent.length, 1);
    assert.equal(sent[0].to, '5547991892931');
    assert.deepEqual(sent[0].components[0].parameters.map((p) => p.text), ['Ana', 'Ivo']);
    assert.equal(sent[0].components[1].parameters[0].text, tokenOf(first.link));
  });

  await t.test('status da entrega chega pelo webhook', async () => {
    await webhook({ statuses: [{ id: 'wamid.inv1', status: 'read', recipient_id: '554791892931' }] });
    const list = await call('GET', '/invites', { token: ivo.token });
    assert.equal(list.body.invites[0].sendStatus, 'read');
    await webhook({ statuses: [{ id: 'wamid.inv1', status: 'delivered' }] });
    assert.equal((await call('GET', '/invites', { token: ivo.token })).body.invites[0].sendStatus, 'read');
  });

  await t.test('convidado que escreve para o bot recebe o link', async () => {
    await webhook({ messages: [{ id: 'wamid.in1', from: '554791892931', type: 'text', text: { body: 'oi' } }] });
    assert.equal(sent.length, 1);
    assert.equal(sent[0].label, 'Fazer cadastro');
    assert.equal(sent[0].link, first.link);
    assert.match(sent[0].text, /Ivo convidou você/);
  });

  await t.test('só administradores convidam; validações', async () => {
    assert.equal((await call('POST', '/invites', { token: ivo.token, body: { name: '', phone: '47991892931' } })).status, 400);
    assert.equal((await call('POST', '/invites', { token: ivo.token, body: { name: 'X', phone: '12' } })).status, 400);
    assert.equal((await call('GET', '/invites')).status, 401);
  });

  let ana;
  await t.test('cadastro pelo link: conta, número no bot e conta compartilhada', async () => {
    const token = tokenOf(first.link);
    const info = await call('GET', `/auth/invites/${token}`);
    assert.equal(info.status, 200);
    assert.deepEqual(
      [info.body.name, info.body.inviterName, info.body.joinAccount],
      ['Ana Souza', 'Ivo Alexandre', true],
    );
    // Sem convite o cadastro está fechado.
    assert.equal(
      (await call('POST', '/auth/register', { body: { name: 'Zé', email: 'ze@x.com', password: 'Senha1234' } })).status,
      403,
    );
    const r = await call('POST', '/auth/register', {
      body: { name: 'Ana Souza', email: 'ana@x.com', password: 'Senha1234', inviteToken: token },
    });
    assert.equal(r.status, 201);
    ana = r.body;
    assert.equal(ana.user.account.ownerName, 'Ivo Alexandre');
    assert.deepEqual(ana.user.account.scope, { cards: ['nubank'], accounts: [] });
    assert.equal(ana.user.access.status, 'free');
    const link = await pool.query('select wa_id from whatsapp_links where user_id = $1', [ana.user.id]);
    assert.equal(link.rows[0].wa_id, '554791892931');
    // O convite não vale de novo.
    assert.equal((await call('GET', `/auth/invites/${token}`)).status, 404);
    const again = await call('POST', '/auth/register', {
      body: { name: 'Outro', email: 'outro@x.com', password: 'Senha1234', inviteToken: token },
    });
    assert.equal(again.status, 403);
    const list = (await call('GET', '/invites', { token: ivo.token })).body.invites;
    assert.equal(list[0].status, 'accepted');
    assert.equal(list[0].userName, 'Ana Souza');
    assert.ok(list[0].memberId);
    assert.deepEqual(list[0].scope, { cards: ['nubank'], accounts: [] });
    // Número já ligado: não convida de novo.
    assert.equal(
      (await call('POST', '/invites', { token: ivo.token, body: { name: 'Ana', phone: '47 99189-2931' } })).status,
      409,
    );
    assert.equal((await call('GET', '/invites', { token: ana.token })).status, 403);
  });

  await t.test('falha no envio fica registrada; cancelar apaga', async () => {
    failSend = true;
    const r = await call('POST', '/invites', { token: ivo.token, body: { name: 'Bia', phone: '11 98888-7777' } });
    assert.equal(r.status, 201);
    assert.equal(r.body.invite.sendStatus, 'failed');
    assert.match(r.body.invite.sendError, /boom/);
    assert.equal((await call('DELETE', `/invites/${r.body.invite.id}`, { token: ivo.token })).status, 204);
    assert.equal((await call('DELETE', `/invites/${r.body.invite.id}`, { token: ivo.token })).status, 404);
  });
});
