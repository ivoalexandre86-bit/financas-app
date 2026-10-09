// Lançamentos pelo WhatsApp. As regras puras rodam sempre; o fluxo completo
// (webhook → rascunho → Confirmar → app_docs) exige TEST_DATABASE_URL.

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { Pool } = require('pg');
const { createApp, migrate } = require('../app');
const { validSignature } = require('../whatsapp/meta');
const {
  addMonths,
  splitCents,
  buildContext,
  normalizeDraft,
  buildDocs,
  formatSummary,
  todayIso,
} = require('../whatsapp/ledger');

const ctx = {
  today: '2026-10-05',
  accounts: [{ id: 'acc_1', name: 'Itaú', institution: '' }],
  cards: [{ id: 'card_1', name: 'Nubank', bank: '' }],
  categories: [
    { id: 'cat_food', name: 'Alimentação', kind: 'expense' },
    { id: 'cat_sal', name: 'Salário', kind: 'income' },
  ],
};

const raw = (over = {}) => ({
  is_transaction: true,
  reply: '',
  type: 'expense',
  amount: 45.9,
  description: 'Mercado',
  date: '2026-10-05',
  category_id: 'cat_food',
  account_id: null,
  card_id: null,
  installments: 1,
  notes: '',
  ...over,
});

test('datas e divisão em parcelas seguem o app', () => {
  assert.equal(addMonths('2026-01-31', 1), '2026-02-28');
  assert.equal(addMonths('2026-11-15', 2), '2027-01-15');
  assert.deepEqual(splitCents(1000, 3), [334, 333, 333]);
  assert.match(todayIso(new Date('2026-10-06T02:00:00Z')), /^2026-10-05$/);
});

test('normalizeDraft valida ids, valor e conta padrão', () => {
  const { draft } = normalizeDraft(raw(), ctx);
  assert.equal(draft.amount, 4590);
  assert.equal(draft.accountId, 'acc_1'); // sem conta citada: 1ª conta
  assert.equal(draft.cardId, null);

  const card = normalizeDraft(raw({ card_id: 'card_1', account_id: 'acc_1' }), ctx).draft;
  assert.equal(card.cardId, 'card_1');
  assert.equal(card.accountId, null);

  const bad = normalizeDraft(raw({ category_id: 'inventada', date: '2026-02-30' }), ctx).draft;
  assert.equal(bad.categoryId, null);
  assert.equal(bad.date, ctx.today);

  // Receita não usa cartão nem categoria de despesa nem parcelas.
  const inc = normalizeDraft(
    raw({ type: 'income', card_id: 'card_1', category_id: 'cat_food', installments: 3 }),
    ctx,
  ).draft;
  assert.equal(inc.cardId, null);
  assert.equal(inc.accountId, 'acc_1');
  assert.equal(inc.categoryId, null);
  assert.equal(inc.installments, 1);

  assert.ok(normalizeDraft(raw({ amount: 0 }), ctx).error);
  assert.equal(
    normalizeDraft({ is_transaction: false, reply: 'Só registro gastos.' }, ctx).error,
    'Só registro gastos.',
  );
  assert.ok(normalizeDraft(raw(), { ...ctx, accounts: [], cards: [] }).error);
});

test('buildDocs gera lançamento e parcelas como o app', () => {
  const [one] = buildDocs(normalizeDraft(raw(), ctx).draft, ctx.today);
  assert.equal(one.coll, 'transactions');
  assert.equal(one.data.status, 'completed');
  assert.equal(one.data.amount, 4590);
  assert.match(one.id, /^tx_/);
  assert.equal(one.data.id, one.id);

  const future = buildDocs(normalizeDraft(raw({ date: '2026-10-20' }), ctx).draft, ctx.today);
  assert.equal(future[0].data.status, 'planned');

  const cardDocs = buildDocs(
    normalizeDraft(raw({ card_id: 'card_1', amount: 100, installments: 3 }), ctx).draft,
    ctx.today,
  );
  assert.equal(cardDocs.length, 4);
  const [group, ...parts] = cardDocs;
  assert.equal(group.coll, 'installmentGroups');
  assert.equal(group.data.totalAmount, 10000);
  assert.deepEqual(parts.map((p) => p.data.amount), [3334, 3333, 3333]);
  assert.deepEqual(parts.map((p) => p.data.date), ['2026-10-05', '2026-10-05', '2026-10-05']);
  assert.deepEqual(parts.map((p) => p.data.status), ['pending', 'planned', 'planned']);
  assert.ok(parts.every((p) => p.data.installmentGroupId === group.id));

  const accParts = buildDocs(
    normalizeDraft(raw({ amount: 30, installments: 2, date: '2026-09-30' }), ctx).draft,
    ctx.today,
  ).slice(1);
  assert.deepEqual(accParts.map((p) => p.data.date), ['2026-09-30', '2026-10-30']);
  assert.deepEqual(accParts.map((p) => p.data.status), ['completed', 'planned']);
});

test('resumo mostra valor, conta e parcelas', () => {
  const d = normalizeDraft(raw({ card_id: 'card_1', amount: 600, installments: 3 }), ctx).draft;
  const s = formatSummary(d, ctx);
  assert.match(s, /R\$\s?600,00/);
  assert.match(s, /Cartão Nubank/);
  assert.match(s, /3x de R\$\s?200,00/);
  assert.match(s, /Alimentação/);
});

test('buildContext ignora contas e cartões inativos', () => {
  const c = buildContext([
    { coll: 'accounts', data: { id: 'a1', name: 'A' } },
    { coll: 'accounts', data: { id: 'a2', name: 'B', active: false } },
    { coll: 'cards', data: { id: 'c1', name: 'C', active: false } },
    { coll: 'categories', data: { id: 'k', name: 'K', kind: 'income' } },
  ]);
  assert.deepEqual(c.accounts.map((a) => a.id), ['a1']);
  assert.equal(c.cards.length, 0);
  assert.equal(c.categories[0].kind, 'income');
});

test('assinatura do webhook', () => {
  const body = Buffer.from('{"a":1}');
  const sig = 'sha256=' + crypto.createHmac('sha256', 's3cr3t').update(body).digest('hex');
  assert.ok(validSignature(body, sig, 's3cr3t'));
  assert.ok(!validSignature(body, sig, 'outro'));
  assert.ok(!validSignature(body, undefined, 's3cr3t'));
});

const url = process.env.TEST_DATABASE_URL;

test('fluxo pelo webhook', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const pool = new Pool({ connectionString: url });
  await pool.query(
    'drop table if exists whatsapp_config, whatsapp_links, whatsapp_link_codes, whatsapp_drafts, whatsapp_seen, app_docs, users cascade',
  );
  await migrate(pool);

  const sent = [];
  const extracted = [];
  let nextRaw = raw();
  let processed = Promise.resolve();
  const fakeMeta = (via) => ({
    sendText: async (to, text) => sent.push({ to, text, via }),
    sendButtons: async (to, text, buttons) => sent.push({ to, text, buttons, via }),
    markRead: () => {},
    downloadMedia: async () => ({ data: Buffer.from('img'), mimeType: 'image/jpeg' }),
  });
  const signups = [];
  const whatsapp = {
    config: { verifyToken: 'vt', appSecret: 'app-secret', botNumber: '+1 555 000 1234' },
    meta: fakeMeta('env'),
    createMeta: ({ token, phoneNumberId }) => fakeMeta(`${token}@${phoneNumberId}`),
    signup: async (input) => {
      signups.push(input);
      if (input.code === 'ruim') throw new Error('Graph 400');
      return { token: 'tok-business', phoneNumberId: input.phoneNumberId ?? '777', botNumber: '+55 47 3241-8582' };
    },
    extract: async (input) => {
      extracted.push(input);
      return nextRaw;
    },
    onProcessed: (p) => (processed = p),
  };
  const app = createApp({ pool, jwtSecret: 'x'.repeat(40), whatsapp });
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
    const json = (res.headers.get('content-type') ?? '').includes('json');
    return { status: res.status, body: json ? JSON.parse(text) : null, text };
  }

  let seq = 0;
  async function deliver(from, message, { secret = 'app-secret' } = {}) {
    const body = JSON.stringify({
      object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: { messages: [{ id: `wamid.${++seq}`, from, ...message }] } }] }],
    });
    const sig = 'sha256=' + crypto.createHmac('sha256', secret).update(body).digest('hex');
    sent.length = 0;
    const res = await fetch(`${base}/whatsapp/webhook`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-hub-signature-256': sig },
      body,
    });
    await processed;
    return res.status;
  }
  const text = (body) => ({ type: 'text', text: { body } });
  const button = (id) => ({ type: 'interactive', interactive: { type: 'button_reply', button_reply: { id } } });

  const reg = await call('POST', '/auth/register', {
    body: { name: 'Ivo Alexandre', email: 'ivo@x.com', password: 'Senha1234' },
  });
  const token = reg.body.token;
  await call('POST', '/docs/batch', {
    token,
    body: {
      docs: [
        { coll: 'accounts', id: 'acc_1', data: { id: 'acc_1', name: 'Itaú' } },
        { coll: 'cards', id: 'card_1', data: { id: 'card_1', name: 'Nubank', closingDay: 1, dueDay: 8 } },
        { coll: 'categories', id: 'cat_food', data: { id: 'cat_food', name: 'Alimentação', kind: 'expense' } },
      ],
    },
  });

  await t.test('verificação do webhook pela Meta', async () => {
    const ok = await call('GET', '/whatsapp/webhook?hub.mode=subscribe&hub.verify_token=vt&hub.challenge=42');
    assert.equal(ok.text, '42');
    const bad = await call('GET', '/whatsapp/webhook?hub.mode=subscribe&hub.verify_token=no&hub.challenge=42');
    assert.equal(bad.status, 403);
  });

  await t.test('assinatura inválida é recusada', async () => {
    assert.equal(await deliver('5511999990000', text('oi'), { secret: 'errado' }), 401);
    assert.equal(sent.length, 0);
  });

  await t.test('número sem vínculo é ignorado (WhatsApp Business do dono)', async () => {
    assert.equal(await deliver('5511999990000', text('mercado 10')), 200);
    assert.equal(sent.length, 0);
    assert.equal(extracted.length, 0);
  });

  await t.test('vínculo pelo código do app', async () => {
    const st = await call('GET', '/whatsapp/status', { token });
    assert.deepEqual(st.body, { enabled: true, botNumber: '15550001234', audio: false, linkedNumber: null });
    const code = await call('POST', '/whatsapp/link-code', { token });
    assert.match(code.body.code, /^\d{6}$/);
    assert.equal(code.body.url, `https://wa.me/15550001234?text=VINCULAR%20${code.body.code}`);

    await deliver('5511999990000', text('vincular 000000'));
    assert.match(sent[0].text, /inválido/);
    await deliver('5511999990000', text(`VINCULAR ${code.body.code}`));
    assert.match(sent[0].text, /Pronto, Ivo!/);
    const after = await call('GET', '/whatsapp/status', { token });
    assert.equal(after.body.linkedNumber, '5511999990000');
    // Código é de uso único.
    await deliver('5511888880000', text(`VINCULAR ${code.body.code}`));
    assert.match(sent[0].text, /inválido/);
  });

  let draftId;
  await t.test('mensagem vira rascunho com botões', async () => {
    nextRaw = raw({ card_id: 'card_1', amount: 90, installments: 3 });
    await deliver('5511999990000', text('tênis 90 em 3x no nubank'));
    assert.equal(extracted.at(-1).text, 'tênis 90 em 3x no nubank');
    assert.deepEqual(extracted.at(-1).ctx.cards.map((c) => c.id), ['card_1']);
    const msg = sent[0];
    assert.match(msg.text, /3x de R\$\s?30,00/);
    assert.deepEqual(msg.buttons.map((b) => b.title), ['Confirmar', 'Corrigir', 'Cancelar']);
    draftId = msg.buttons[0].id.split(':')[1];
  });

  await t.test('Corrigir aplica a próxima mensagem ao rascunho', async () => {
    await deliver('5511999990000', button(`edit:${draftId}`));
    assert.match(sent[0].text, /O que devo corrigir/);
    nextRaw = raw({ card_id: 'card_1', amount: 120, installments: 3 });
    await deliver('5511999990000', text('valor 120'));
    assert.equal(extracted.at(-1).previous.amount, 90);
    assert.equal(sent[0].buttons[0].id, `ok:${draftId}`);
    assert.match(sent[0].text, /R\$\s?120,00/);
  });

  await t.test('Confirmar grava no app e não duplica', async () => {
    await deliver('5511999990000', button(`ok:${draftId}`));
    assert.match(sent[0].text, /Lançado/);
    const docs = (await call('GET', '/docs', { token })).body.docs;
    const txs = docs.filter((d) => d.coll === 'transactions');
    assert.equal(txs.length, 3);
    assert.deepEqual(txs.map((d) => d.data.amount).sort(), [4000, 4000, 4000]);
    assert.equal(docs.filter((d) => d.coll === 'installmentGroups').length, 1);
    await deliver('5511999990000', button(`ok:${draftId}`));
    assert.match(sent[0].text, /já foi gravado/);
    const again = (await call('GET', '/docs', { token })).body.docs;
    assert.equal(again.filter((d) => d.coll === 'transactions').length, 3);
  });

  await t.test('resumo responde sem passar pela IA', async () => {
    const before = extracted.length;
    await deliver('5511999990000', text('Resumo'));
    assert.equal(extracted.length, before);
    assert.match(sent[0].text, /^📊 \*Resumo de /);
    await deliver('5511999990000', text('resumo março 2030'));
    assert.match(sent[0].text, /Resumo de março\/2030/);
  });

  await t.test('Cancelar e mensagens que não são lançamento', async () => {
    nextRaw = raw();
    await deliver('5511999990000', text('mercado 45,90'));
    const id = sent[0].buttons[2].id;
    await deliver('5511999990000', button(id));
    assert.match(sent[0].text, /Cancelado/);

    nextRaw = { ...raw(), is_transaction: false, reply: 'Só registro despesas e receitas.' };
    await deliver('5511999990000', text('qual a capital da França?'));
    assert.equal(sent[0].text, 'Só registro despesas e receitas.');
  });

  await t.test('foto vai para a IA; áudio sem transcrição avisa', async () => {
    nextRaw = raw();
    await deliver('5511999990000', { type: 'image', image: { id: 'm1', caption: 'almoço' } });
    assert.equal(extracted.at(-1).media.mimeType, 'image/jpeg');
    assert.equal(extracted.at(-1).text, 'almoço');
    await deliver('5511999990000', { type: 'audio', audio: { id: 'm2' } });
    assert.match(sent[0].text, /Áudio ainda não está ativado/);
  });

  await t.test('reentrega da mesma mensagem é ignorada', async () => {
    const body = JSON.stringify({
      entry: [{ changes: [{ value: { messages: [{ id: 'wamid.dup', from: '5511999990000', ...text('oi') }] } }] }],
    });
    const sig = 'sha256=' + crypto.createHmac('sha256', 'app-secret').update(body).digest('hex');
    const post = async () => {
      sent.length = 0;
      await fetch(`${base}/whatsapp/webhook`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-hub-signature-256': sig },
        body,
      });
      await processed;
      return sent.length;
    };
    assert.equal(await post(), 1);
    assert.equal(await post(), 0);
  });

  await t.test('desvincular', async () => {
    assert.equal((await call('DELETE', '/whatsapp/link', { token })).status, 204);
    const before = extracted.length;
    await deliver('5511999990000', text('mercado 10'));
    assert.equal(sent.length, 0);
    assert.equal(extracted.length, before);
  });

  await t.test('cadastro incorporado troca o número do bot', async () => {
    const other = await call('POST', '/users', {
      token,
      body: { name: 'Ana', email: 'ana@x.com', password: 'Senha1234' },
    });
    assert.equal(other.status, 201);
    const login = await call('POST', '/auth/login', { body: { email: 'ana@x.com', password: 'Senha1234' } });
    const body = { code: 'abc', phoneNumberId: '777', wabaId: '888' };
    assert.equal((await call('POST', '/whatsapp/embedded-signup', { token: login.body.token, body })).status, 403);
    assert.equal((await call('POST', '/whatsapp/embedded-signup', { token, body: { phoneNumberId: '777', wabaId: '888' } })).status, 400);
    assert.equal(
      (await call('POST', '/whatsapp/embedded-signup', { token, body: { ...body, code: 'ruim' } })).status,
      502,
    );

    const ok = await call('POST', '/whatsapp/embedded-signup', { token, body });
    assert.equal(ok.status, 200);
    assert.deepEqual(ok.body, { botNumber: '554732418582', phoneNumberId: '777', wabaId: '888', enabled: true });
    assert.deepEqual(signups.at(-1), body);
    const st = await call('GET', '/whatsapp/status', { token });
    assert.equal(st.body.botNumber, '554732418582');

    // Respostas saem pelo número novo, com o token comercial.
    const code = await call('POST', '/whatsapp/link-code', { token });
    assert.equal(code.body.url, `https://wa.me/554732418582?text=VINCULAR%20${code.body.code}`);
    await deliver('5511999990000', text(`VINCULAR ${code.body.code}`));
    assert.equal(sent[0].via, 'tok-business@777');

    // Ao reiniciar, o servidor usa o número salvo mesmo sem as variáveis.
    const fresh = createApp({ pool, jwtSecret: 'x'.repeat(40), whatsapp: { ...whatsapp, meta: undefined } });
    const s2 = fresh.listen(0);
    try {
      const r = await fetch(`http://127.0.0.1:${s2.address().port}/whatsapp/status`, {
        headers: { authorization: `Bearer ${token}` },
      });
      const j = await r.json();
      assert.equal(j.enabled, true);
      assert.equal(j.botNumber, '554732418582');
    } finally {
      s2.close();
    }
  });
});
