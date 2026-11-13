// Boletos: leitura do código, lembrete com botões e pagamento pelo WhatsApp.
// O fluxo completo exige TEST_DATABASE_URL.

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { Pool } = require('pg');
const { createApp, migrate } = require('../app');
const { parseBoleto, parsePix, formatBoleto, mod10, crc16, dueFromFactor } = require('../whatsapp/boleto');
const { normalizeDraft, buildDocs, formatSummary } = require('../whatsapp/ledger');
const { buildBoletoReminders, buildReminders } = require('../whatsapp/reminders');

// Monta uma linha digitável válida (boleto bancário) a partir das partes.
function bankLine({ bank = '341', factor, cents, free = '1091234567812345678900000' }) {
  const noDv = bank + '9' + String(factor).padStart(4, '0') + String(cents).padStart(10, '0') + free;
  let sum = 0;
  let w = 2;
  for (let i = noDv.length - 1; i >= 0; i--) {
    sum += Number(noDv[i]) * w;
    w = w === 9 ? 2 : w + 1;
  }
  let dv = 11 - (sum % 11);
  if (dv === 0 || dv >= 10) dv = 1;
  const f1 = bank + '9' + free.slice(0, 5);
  const f2 = free.slice(5, 15);
  const f3 = free.slice(15, 25);
  return (
    f1 + mod10(f1) + f2 + mod10(f2) + f3 + mod10(f3) + dv +
    String(factor).padStart(4, '0') + String(cents).padStart(10, '0')
  );
}

// Fator 1000 = 22/02/2025 (novo ciclo).
const factorFor = (iso) => 1000 + Math.round((Date.parse(`${iso}T00:00:00Z`) - Date.UTC(2025, 1, 22)) / 864e5);

function pixCode(amount = '180.00') {
  const tlv = (id, v) => id + String(v.length).padStart(2, '0') + v;
  const body =
    tlv('00', '01') +
    tlv('26', tlv('00', 'br.gov.bcb.pix') + tlv('01', '123e4567-e12b-12d1-a456-426655440000')) +
    tlv('52', '0000') + tlv('53', '986') + tlv('54', amount) + tlv('58', 'BR') +
    tlv('59', 'CELESC') + tlv('60', 'FLORIANOPOLIS') + tlv('62', tlv('05', '***')) + '6304';
  return body + crc16(body);
}

test('linha digitável: confere dígitos, lê valor e vencimento', () => {
  const line = bankLine({ factor: factorFor('2026-11-03'), cents: 18000 });
  assert.equal(line.length, 47);
  const b = parseBoleto(formatBoleto(line), '2026-11-02');
  assert.deepEqual(b, { kind: 'bank', code: line, amount: 18000, dueDate: '2026-11-03' });
  // Um dígito errado invalida.
  const wrong = line.slice(0, 40) + ((Number(line[40]) + 1) % 10) + line.slice(41);
  assert.equal(parseBoleto(wrong, '2026-11-02'), null);
  assert.equal(parseBoleto('123', '2026-11-02'), null);
  assert.equal(dueFromFactor(0, '2026-11-02'), null);
});

test('arrecadação (48 dígitos) e Pix copia e cola', () => {
  // 8 + segmento 3 + identificador 6 (módulo 10) + DV + valor (11) + 29.
  const noDv = '836' + '00000050001' + '23456789012345678901234567890';
  assert.equal(noDv.length, 43);
  const full = noDv.slice(0, 3) + mod10(noDv) + noDv.slice(3);
  const line = [0, 11, 22, 33].map((i) => full.slice(i, i + 11)).map((x) => x + mod10(x)).join('');
  const a = parseBoleto(line, '2026-11-02');
  assert.equal(a.kind, 'collection');
  assert.equal(a.amount, 50001);
  assert.equal(parseBoleto(line.slice(0, 47) + ((Number(line[47]) + 1) % 10), '2026-11-02'), null);

  const pix = pixCode();
  assert.deepEqual(parsePix(` ${pix} `), { code: pix, amount: 18000 });
  assert.equal(parsePix(pix.slice(0, -1) + (pix.at(-1) === 'A' ? 'B' : 'A')), null);
});

const ctx = {
  today: '2026-11-02',
  accounts: [{ id: 'acc_1', name: 'Nubank', institution: '' }],
  cards: [{ id: 'card_1', name: 'Nubank', bank: '' }],
  categories: [{ id: 'cat_casa', name: 'Moradia', kind: 'expense' }],
};
const item = (over = {}) => ({
  is_transaction: true,
  reply: '',
  items: [{
    type: 'expense', amount: 170, description: 'Luz CELESC', date: '2026-11-01',
    category_id: 'cat_casa', account_id: null, card_id: null, installments: 1, notes: '',
    boleto_code: null, pix_code: null, ...over,
  }],
});

test('boleto lido vira despesa pendente com vencimento do código', () => {
  const line = bankLine({ factor: factorFor('2026-11-03'), cents: 18000 });
  const { draft } = normalizeDraft(item({ boleto_code: line, pix_code: pixCode() }), ctx);
  assert.equal(draft.amount, 18000); // o código vale mais que a leitura
  assert.equal(draft.date, '2026-11-03');
  assert.equal(draft.boletoCode, line);
  assert.match(formatSummary(draft, ctx), /Boleto 34191\.09123/);
  assert.match(formatSummary(draft, ctx), /Vence 03\/11/);
  const [doc] = buildDocs(draft, ctx.today);
  assert.equal(doc.data.status, 'planned');
  assert.equal(doc.data.dueDate, '2026-11-03');
  assert.ok(doc.data.pixCode);

  // Vencido hoje: pendente, nunca concluído.
  const today = normalizeDraft(item({ pix_code: pixCode() }), { ...ctx, today: '2026-11-05' }).draft;
  assert.equal(buildDocs(today, '2026-11-05')[0].data.status, 'pending');

  // Código errado: lança sem código e avisa.
  const bad = normalizeDraft(item({ boleto_code: '1234' }), ctx).draft;
  assert.equal(bad.boletoCode, undefined);
  assert.match(formatSummary(bad, ctx), /Não consegui ler o código/);
  assert.equal(buildDocs(bad, ctx.today)[0].data.status, 'completed');
});

test('lembretes de boleto: véspera, dia e atraso; fora da lista geral', () => {
  const tx = (id, due, over = {}) => ({
    id, type: 'expense', amount: 10000, description: id, date: due, dueDate: due,
    accountId: 'a', status: 'pending', boletoCode: '1', ...over,
  });
  const docs = {
    transactions: [
      tx('amanha', '2026-11-03'),
      tx('hoje', '2026-11-02'),
      tx('atraso', '2026-10-30'),
      tx('antigo', '2026-10-01'),
      tx('pago', '2026-11-02', { status: 'completed' }),
      tx('depois', '2026-11-10'),
      { id: 'luz', type: 'expense', amount: 5000, description: 'Água', date: '2026-11-02', accountId: 'a', status: 'pending' },
    ],
  };
  const items = buildBoletoReminders(docs, '2026-11-02');
  assert.deepEqual(items.map((i) => i.key), [
    'boleto:atraso:2026-10-30:atraso',
    'boleto:hoje:2026-11-02:hoje',
    'boleto:amanha:2026-11-03:antes',
  ]);
  assert.match(items[2].text, /vence \*amanhã\* \(03\/11\)/);
  const general = buildReminders(docs, '2026-11-02', { budgets: false });
  assert.match(general[0].text, /hoje Água/);
  assert.doesNotMatch(general[0].text, /amanha|hoje hoje/);
});

const url = process.env.TEST_DATABASE_URL;

test('boleto pelo WhatsApp: lembrete, pagar e dar baixa', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const pool = new Pool({ connectionString: url });
  await pool.query(
    'drop table if exists account_members, boleto_payments, openfinance_interest, share_audit, share_payments, share_settlements, share_allocations, share_expenses, share_recurrences, share_categories, share_members, share_groups, whatsapp_config, whatsapp_links, whatsapp_link_codes, whatsapp_drafts, whatsapp_seen, whatsapp_usage, whatsapp_reminders_sent, app_docs, users cascade',
  );
  await migrate(pool);

  const sent = [];
  let processed = Promise.resolve();
  const meta = {
    sendText: async (to, text) => sent.push({ to, text }),
    sendButtons: async (to, text, buttons) => sent.push({ to, text, buttons }),
    sendList: async (to, text, button, rows) => sent.push({ to, text, rows }),
    sendCta: async (to, text, label, link) => sent.push({ to, text, label, link }),
    sendTemplate: async (to, name, params) => sent.push({ to, template: name, params }),
    sendTemplateComponents: async (to, name, components) => sent.push({ to, template: name, components }),
    markRead: () => {},
  };
  const pluggyCalls = [];
  let pluggyStatus = 'CREATED';
  const pluggy = {
    createPixQrRecipient: async (code) => (pluggyCalls.push(['recipient', code]), { id: 'rcp_1' }),
    createPaymentRequest: async (body) => (pluggyCalls.push(['request', body]), { id: 'preq_1', status: 'CREATED', paymentUrl: 'https://pay.pluggy.ai/preq_1' }),
    getPaymentRequest: async (id) => ({ id, status: pluggyStatus }),
  };
  const whatsapp = {
    config: { verifyToken: 'vt', appSecret: 'app-secret', botNumber: '5547' },
    meta,
    extract: async () => item({ boleto_code: bankLine({ factor: factorFor('2026-11-03'), cents: 18000 }) }),
    onProcessed: (p) => (processed = p),
    boletoTemplate: 'lembrete_boleto',
    publicUrl: 'https://api.exemplo',
    payments: { enabled: false },
  };
  const app = createApp({ pool, jwtSecret: 'x'.repeat(40), whatsapp, pluggy });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    server.close();
    await pool.end();
  });

  const reg = await fetch(`${base}/auth/register`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'Ivo', email: 'ivo@x.com', password: 'Senha1234' }),
  }).then((r) => r.json());
  const userId = reg.user.id;
  await pool.query(
    `insert into app_docs (user_id, coll, id, data) values
      ($1, 'accounts', 'acc_1', '{"id":"acc_1","name":"Nubank","institutionCode":"260"}'),
      ($1, 'settings', 'app', '{"whatsappReminders":true}')`,
    [userId],
  );
  await pool.query(`insert into whatsapp_links (wa_id, user_id) values ('5511', $1)`, [userId]);

  let seq = 0;
  async function deliver(message) {
    const body = JSON.stringify({ entry: [{ changes: [{ value: { messages: [{ id: `w${++seq}`, from: '5511', ...message }] } }] }] });
    const sig = 'sha256=' + crypto.createHmac('sha256', 'app-secret').update(body).digest('hex');
    sent.length = 0;
    await fetch(`${base}/whatsapp/webhook`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-hub-signature-256': sig },
      body,
    });
    await processed;
  }
  const button = (id) => ({ type: 'interactive', interactive: { type: 'button_reply', button_reply: { id } } });
  const txOf = async (id) =>
    (await pool.query(`select data from app_docs where user_id = $1 and coll = 'transactions' and id = $2`, [userId, id])).rows[0].data;

  // Foto do boleto → rascunho → Confirmar → "Pagar agora".
  await deliver({ type: 'text', text: { body: 'boleto da luz' } });
  assert.match(sent[0].text, /Boleto 34191/);
  await deliver(button(sent[0].buttons[0].id));
  assert.match(sent[0].text, /Vou te lembrar na véspera/);
  const payId = sent[0].buttons[0].id;
  const txId = payId.split(':')[1];
  const tx = await txOf(txId);
  assert.equal(tx.dueDate, '2026-11-03');
  assert.equal(tx.amount, 18000);

  // Lembrete fora da janela de 24 h: modelo com botões.
  await pool.query('update whatsapp_links set last_inbound_at = null');
  sent.length = 0;
  const reminders = app.locals.reminders;
  // runOnce usa o relógio real; força o dia e a hora pelo now injetado.
  const { createReminderJob } = require('../whatsapp/reminders');
  const job = createReminderJob({
    pool, getMeta: () => meta, template: 'lembrete_financas', boletoTemplate: 'lembrete_boleto',
    now: () => new Date('2026-11-02T12:00:00Z'),
  });
  assert.ok(reminders);
  assert.equal(await job.runOnce(), 1);
  assert.equal(sent[0].template, 'lembrete_boleto');
  assert.deepEqual(sent[0].components[0].parameters.map((p) => p.text), ['Luz CELESC', 'R$ 180,00', '03/11/2026']);
  assert.equal(sent[0].components[1].parameters[0].payload, `bpay:${txId}`);
  assert.equal(await job.runOnce(), 0); // uma vez por fase

  // Resposta pelo botão do modelo: código para copiar + página.
  await deliver({ type: 'button', button: { payload: `bpay:${txId}`, text: 'Pagar agora' } });
  assert.match(sent[0].text, /Pagar boleto/);
  assert.equal(sent[1].text, tx.boletoCode);
  const page = /https:\/\/api\.exemplo(\/pagar\/\S+)/.exec(sent[2].text)[1];
  assert.equal(sent[2].buttons[0].id, `bpaid:${txId}`);
  const html = await fetch(base + page).then((r) => r.text());
  assert.match(html, /Luz CELESC/);
  assert.match(html, /com\.nu\.production/);
  assert.match(html, /Copiar linha digitável/);
  assert.equal((await fetch(`${base}/pagar/abc`)).status, 404);

  // "boletos" lista os em aberto; "paguei" dá baixa no último lembrado.
  await deliver({ type: 'text', text: { body: 'boletos' } });
  assert.equal(sent[0].rows[0].id, `bpay:${txId}`);
  await deliver({ type: 'text', text: { body: 'paguei' } });
  assert.match(sent[0].text, /Baixa feita/);
  assert.equal((await txOf(txId)).status, 'completed');
  await deliver(button(`bpaid:${txId}`));
  assert.match(sent[0].text, /já estava marcado como pago/);

  // Open Finance: boleto com Pix vira link da Pluggy; o webhook dá baixa.
  whatsapp.payments.enabled = true;
  await pool.query(
    `insert into app_docs (user_id, coll, id, data) values ($1, 'transactions', 'tx_pix', $2)`,
    [userId, JSON.stringify({ id: 'tx_pix', type: 'expense', amount: 18000, description: 'Internet', date: '2026-11-02', dueDate: '2026-11-02', accountId: 'acc_1', status: 'pending', pixCode: pixCode() })],
  );
  await deliver(button('bpay:tx_pix'));
  assert.equal(sent[0].link, 'https://pay.pluggy.ai/preq_1');
  assert.equal(pluggyCalls[1][1].amount, 180);
  assert.equal(pluggyCalls[1][1].callbackUrls.success, 'https://api.exemplo/pagar/retorno');
  sent.length = 0;
  pluggyStatus = 'COMPLETED';
  await fetch(`${base}/pluggy/webhook`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ event: 'payment_request/updated', paymentRequestId: 'preq_1' }),
  });
  for (let i = 0; i < 50 && (await txOf('tx_pix')).status !== 'completed'; i++) {
    await new Promise((r) => setTimeout(r, 20));
  }
  assert.equal((await txOf('tx_pix')).status, 'completed');
  assert.match(sent.at(-1).text, /Pagamento confirmado pelo banco/);
});
