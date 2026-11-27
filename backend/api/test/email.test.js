// Lembretes de fatura por e-mail. Regras puras sempre; o fluxo completo
// (confirmação do e-mail, acesso limitado, envio sem repetição) exige
// PostgreSQL em TEST_DATABASE_URL. Envio por transporte de teste (memória):
// nenhum e-mail sai do computador. Dados fictícios.

const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');
const {
  buildInvoiceReminders,
  renderInvoiceEmail,
  localNow,
  cardLabel,
} = require('../email/invoice_reminders');
const { createMemoryTransport, parseFrom, transportFromEnv } = require('../email/transport');

// Fecha dia 1 e vence dia 10: compras de 02/11 a 01/12 caem na fatura
// 2026-12, que vence em 10/12/2026.
const nubank = { id: 'nubank', name: 'Nubank', lastFour: '1234', closingDay: 1, dueDay: 10 };
const xp = { id: 'xp', name: 'XP Visa', closingDay: 1, dueDay: 10 };
const quitado = { id: 'quitado', name: 'Inter', lastFour: '9876', closingDay: 1, dueDay: 10 };
const buy = (id, cardId, amount) => ({
  id, type: 'expense', amount, description: `Compra ${id}`, date: '2026-11-15', cardId, status: 'pending',
});
const docs = {
  cards: [nubank, xp, quitado],
  transactions: [buy('n1', 'nubank', 100000), buy('n2', 'nubank', 23456), buy('x1', 'xp', 50000), buy('q1', 'quitado', 30000)],
  invoicePayments: [
    { id: 'p1', cardId: 'nubank', invoiceKey: '2026-12', amount: 40000, date: '2026-12-02' },
    { id: 'p2', cardId: 'quitado', invoiceKey: '2026-12', amount: 30000, date: '2026-12-03' },
  ],
};

test('aviso antes do vencimento: em aberto, parcial e quitada', () => {
  const items = buildInvoiceReminders(docs, '2026-12-07', { daysBefore: 3, overdue: true });
  assert.deepEqual(items.map((i) => i.key), [
    'fatura:nubank:2026-12:2026-12-10:antes',
    'fatura:xp:2026-12:2026-12-10:antes',
  ]);
  const nu = items[0];
  assert.equal(nu.total, 123456);
  assert.equal(nu.paid, 40000);
  assert.equal(nu.remaining, 83456); // pagamento parcial: só o restante
  assert.equal(nu.daysLeft, 3);
  assert.equal(items[1].remaining, 50000);
  // Antes da janela escolhida: nada.
  assert.deepEqual(buildInvoiceReminders(docs, '2026-12-06', { daysBefore: 3 }), []);
  assert.equal(buildInvoiceReminders(docs, '2026-12-01', { daysBefore: 10 }).length, 2);
});

test('aviso de atraso só quando ligado e até 5 dias depois', () => {
  const on = buildInvoiceReminders(docs, '2026-12-12', { daysBefore: 3, overdue: true });
  assert.deepEqual(on.map((i) => i.phase), ['atraso', 'atraso']);
  assert.deepEqual(buildInvoiceReminders(docs, '2026-12-12', { daysBefore: 3, overdue: false }), []);
  assert.deepEqual(buildInvoiceReminders(docs, '2026-12-16', { overdue: true }), []);
});

test('cartão inativo e fatura sem saldo ficam de fora', () => {
  const d = { ...docs, cards: [{ ...nubank, active: false }, xp, quitado] };
  assert.deepEqual(buildInvoiceReminders(d, '2026-12-08').map((i) => i.cardId), ['xp']);
});

test('e-mail em pt-BR com R$, data dd/mm/aaaa, cartão mascarado e link da fatura', () => {
  const [nu] = buildInvoiceReminders(docs, '2026-12-07');
  const m = renderInvoiceEmail(nu, { name: 'Ivo Teste', appUrl: 'https://app.exemplo/financas/' });
  assert.equal(m.subject, 'Fatura Nubank •••• 1234 vence em 3 dias: R$ 834,56');
  assert.match(m.text, /Olá, Ivo!/);
  assert.match(m.text, /vence em 3 dias \(10\/12\/2026\)/);
  assert.match(m.text, /Já foram pagos R\$\s400,00 de R\$\s1\.234,56\. Falta pagar R\$\s834,56\./);
  assert.equal(m.link, 'https://app.exemplo/financas/?fatura=nubank&mes=2026-12');
  assert.match(m.html, /href="https:\/\/app\.exemplo\/financas\/\?fatura=nubank&amp;mes=2026-12"/);
  const late = renderInvoiceEmail({ ...nu, phase: 'atraso', daysLeft: -2 }, {});
  assert.equal(late.subject, 'Fatura Nubank •••• 1234 em atraso: R$ 834,56');
  assert.match(late.text, /venceu em 10\/12\/2026 e ainda está em aberto/);
  assert.equal(cardLabel({ name: '<b>', lastFour: '' }), '<b>');
  assert.doesNotMatch(renderInvoiceEmail({ ...nu, label: '<b>' }).html, /<b><\/b>|<b> /);
});

test('data e hora locais no fuso da pessoa', () => {
  const at = new Date('2026-12-07T02:30:00Z');
  assert.deepEqual(localNow(at, 'America/Sao_Paulo'), { date: '2026-12-06', hour: 23 });
  assert.deepEqual(localNow(at, 'Asia/Tokyo'), { date: '2026-12-07', hour: 11 });
  assert.deepEqual(localNow(at, 'fuso/invalido'), { date: '2026-12-06', hour: 23 });
});

test('transporte vindo do ambiente', () => {
  assert.equal(transportFromEnv({}), null);
  assert.equal(transportFromEnv({ EMAIL_TRANSPORT: 'log' }).sandbox, true);
  assert.equal(transportFromEnv({ EMAIL_TRANSPORT: 'brevo', BREVO_API_KEY: 'k', EMAIL_FROM: 'a@b.c' }).name, 'brevo');
  assert.deepEqual(parseFrom('Finanças <avisos@exemplo.com>'), { name: 'Finanças', email: 'avisos@exemplo.com' });
});

const url = process.env.TEST_DATABASE_URL;

test('lembretes por e-mail de ponta a ponta', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const { createApp, migrate } = require('../app');
  const pool = new Pool({ connectionString: url });
  await pool.query(
    'drop table if exists email_reminders_sent, email_reminder_prefs, user_invites, account_members, funnel_events, referrals, marketing_spend, openfinance_interest, share_audit, share_payments, share_settlements, share_allocations, share_expenses, share_recurrences, share_categories, share_members, share_groups, of_items, whatsapp_config, whatsapp_links, whatsapp_link_codes, whatsapp_drafts, whatsapp_seen, whatsapp_usage, whatsapp_reminders_sent, app_docs, users cascade',
  );
  await migrate(pool);
  let clock = new Date('2026-12-07T10:00:00Z'); // 07:00 em Brasília
  let hook = null;
  let failNext = 0;
  const transport = createMemoryTransport({ fail: () => failNext > 0 && failNext-- > 0 });
  const app = createApp({
    pool,
    jwtSecret: 'x'.repeat(40),
    openSignup: true,
    email: {
      transport,
      appUrl: 'https://app.exemplo/financas/',
      publicUrl: 'http://api.exemplo',
      now: () => clock,
      onClaimed: (userId, key) => hook?.(userId, key),
    },
  });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    server.close();
    await pool.end();
  });
  async function call(method, path, { token, body } = {}) {
    const res = await fetch(base + path, {
      method,
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = text;
    }
    return { status: res.status, body: json };
  }
  const signup = async (name, email) =>
    (await call('POST', '/auth/register', { body: { name, email, password: 'Senha1234' } })).body;
  const push = (token, list) => call('POST', '/docs/batch', { token, body: { docs: list } });
  const job = app.locals.invoiceEmails;
  const run = () => job.runOnce();
  const sentTo = (email) => transport.sent.filter((m) => m.to === email);

  const ivo = await signup('Ivo Teste', 'ivo@exemplo.test');
  const ana = await signup('Ana Teste', 'ana@exemplo.test');
  const caio = await signup('Caio Teste', 'caio@exemplo.test');
  await push(ivo.token, [
    ...docs.cards.map((c) => ({ coll: 'cards', id: c.id, data: c })),
    ...docs.transactions.map((x) => ({ coll: 'transactions', id: x.id, data: x })),
    ...docs.invoicePayments.map((p) => ({ coll: 'invoicePayments', id: p.id, data: p })),
  ]);
  // Ana entra na conta do Ivo vendo só o Nubank.
  await call('POST', '/account/members', {
    token: ivo.token,
    body: { email: 'ana@exemplo.test', scope: { cards: ['nubank'], accounts: [] } },
  });
  const inv = (await call('GET', '/account', { token: ana.token })).body.invites[0];
  await call('POST', `/account/invites/${inv.id}/accept`, { token: ana.token });

  async function verify(user) {
    const before = transport.sent.length;
    const r = await call('POST', '/email/verify/send', { token: user.token });
    assert.equal(r.status, 200);
    const msg = transport.sent[before];
    assert.equal(msg.to, user.user.email);
    const link = /http:\/\/api\.exemplo(\/email\/verify\?token=\S+)/.exec(msg.text)[1];
    const page = await call('GET', link);
    assert.equal(page.status, 200);
    assert.match(page.body, /E-mail confirmado/);
  }

  await t.test('só liga com e-mail confirmado', async () => {
    const r = await call('PATCH', '/email/reminders', { token: ivo.token, body: { enabled: true } });
    assert.equal(r.status, 400);
    assert.match(r.body.error, /Confirme seu e-mail/);
    assert.equal((await call('GET', '/email/verify?token=lixo')).status, 400);
    await verify(ivo);
    assert.equal((await call('GET', '/me', { token: ivo.token })).body.user.emailVerified, true);
    assert.equal((await call('POST', '/email/verify/send', { token: ivo.token })).body.verified, true);
    const bad = await call('PATCH', '/email/reminders', { token: ivo.token, body: { daysBefore: 30 } });
    assert.equal(bad.status, 400);
    const ok = await call('PATCH', '/email/reminders', {
      token: ivo.token,
      body: { enabled: true, daysBefore: 3, overdue: true, timeZone: 'America/Sao_Paulo', sendHour: 8 },
    });
    assert.equal(ok.status, 200);
    assert.deepEqual(ok.body.prefs, { enabled: true, daysBefore: 3, overdue: true, timeZone: 'America/Sao_Paulo', sendHour: 8 });
    await verify(ana);
    await call('PATCH', '/email/reminders', { token: ana.token, body: { enabled: true } });
    // Caio não tem acesso à conta do Ivo.
    await verify(caio);
    await call('PATCH', '/email/reminders', { token: caio.token, body: { enabled: true } });
    transport.sent.length = 0;
  });

  await t.test('antes da hora escolhida (no fuso da pessoa) não envia', async () => {
    assert.deepEqual(await run(), { sent: 0, suppressed: 0, failed: 0 });
  });

  await t.test('envia saldo em aberto e restante do parcial; quitada antes do envio é descartada', async () => {
    clock = new Date('2026-12-07T11:05:00Z'); // 08:05 em Brasília
    // A fatura do XP é paga entre a reserva e o envio.
    hook = async (userId, key) => {
      if (key.startsWith('fatura:xp:')) {
        await push(ivo.token, [{
          coll: 'invoicePayments', id: 'p3',
          data: { id: 'p3', cardId: 'xp', invoiceKey: '2026-12', amount: 50000, date: '2026-12-07' },
        }]);
      }
    };
    const stats = await run();
    hook = null;
    assert.deepEqual(stats, { sent: 2, suppressed: 1, failed: 0 });
    const toIvo = sentTo('ivo@exemplo.test');
    assert.equal(toIvo.length, 1);
    assert.equal(toIvo[0].subject, 'Fatura Nubank •••• 1234 vence em 3 dias: R$ 834,56');
    assert.match(toIvo[0].text, /\?fatura=nubank&mes=2026-12/);
    // Ana (acesso limitado ao Nubank) recebe só a do Nubank.
    assert.deepEqual(sentTo('ana@exemplo.test').map((m) => m.subject), [toIvo[0].subject]);
    // Caio não enxerga nenhuma fatura do Ivo.
    assert.deepEqual(sentTo('caio@exemplo.test'), []);
    const st = await call('GET', '/email/reminders', { token: ivo.token });
    assert.equal(st.body.recent[0].cardId, 'nubank');
    assert.equal(st.body.recent[0].amount, 83456);
  });

  await t.test('rodadas repetidas e simultâneas não duplicam', async () => {
    clock = new Date('2026-12-07T15:00:00Z');
    const results = await Promise.all([run(), run(), run()]);
    assert.equal(results.reduce((a, r) => a + r.sent, 0), 0);
    clock = new Date('2026-12-09T11:00:00Z');
    assert.equal((await run()).sent, 0);
    assert.equal(transport.sent.length, 2);
  });

  await t.test('aviso de atraso; perda de acesso antes do envio; falha tenta de novo', async () => {
    clock = new Date('2026-12-12T12:00:00Z');
    const memberId = (await call('GET', '/account', { token: ivo.token })).body.members.find((m) => m.name === 'Ana Teste').id;
    // O dono tira o Nubank da Ana entre a reserva e o envio.
    hook = async (userId, key) => {
      if (userId === ana.user.id) {
        await call('PATCH', `/account/members/${memberId}`, { token: ivo.token, body: { scope: { cards: ['xp'] } } });
      }
    };
    failNext = 1; // 1ª tentativa ao Ivo falha no provedor
    const first = await run();
    hook = null;
    assert.equal(first.suppressed, 1); // Ana
    assert.equal(first.failed, 1); // Ivo: falhou, chave liberada
    assert.equal(first.sent, 0);
    // Três rodadas ao mesmo tempo (várias instâncias): um único envio.
    const again = await Promise.all([run(), run(), run()]);
    assert.equal(again.reduce((a, r) => a + r.sent, 0), 1);
    assert.equal(again.reduce((a, r) => a + r.failed, 0), 0);
    const late = sentTo('ivo@exemplo.test').at(-1);
    assert.equal(late.subject, 'Fatura Nubank •••• 1234 em atraso: R$ 834,56');
    assert.equal(sentTo('ana@exemplo.test').length, 1); // só o aviso de antes
    assert.equal((await run()).sent, 0);
  });

  await t.test('e-mail trocado precisa ser confirmado de novo', async () => {
    await pool.query(`update users set email = 'ivo.novo@exemplo.test' where id = $1`, [ivo.user.id]);
    await pool.query(`delete from email_reminders_sent where user_id = $1`, [ivo.user.id]);
    assert.equal((await run()).sent, 0);
    assert.equal((await call('GET', '/email/reminders', { token: ivo.token })).body.verified, false);
  });
});
