// Lembretes diários pelo WhatsApp (regras puras).

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildReminders, createReminderJob } = require('../whatsapp/reminders');

const today = '2026-10-19';
const docs = {
  categories: [
    { id: 'cat_food', name: 'Alimentação', kind: 'expense' },
    { id: 'cat_groceries', name: 'Mercado', kind: 'expense', parentId: 'cat_food' },
  ],
  cards: [{ id: 'nu', name: 'Nubank', closingDay: 3, dueDay: 10, active: true }],
  transactions: [
    { id: 'luz', type: 'expense', amount: 18000, description: 'Luz', date: '2026-10-20',
      accountId: 'a', status: 'pending' },
    { id: 'net', type: 'expense', amount: 9990, description: 'Internet', date: '2026-10-19',
      accountId: 'a', status: 'planned' },
    { id: 'longe', type: 'expense', amount: 5000, description: 'Depois', date: '2026-10-25',
      accountId: 'a', status: 'pending' },
    { id: 'm1', type: 'expense', amount: 70000, description: 'Mercado', date: '2026-10-05',
      accountId: 'a', categoryId: 'cat_groceries', status: 'completed' },
    // Fatura que fechou em 03/10 e vence 10/10: conta no mês.
    { id: 'c1', type: 'expense', amount: 15000, description: 'Feira', date: '2026-09-20',
      cardId: 'nu', categoryId: 'cat_food', status: 'pending' },
  ],
  budgets: [{ id: 'b', categoryId: 'cat_food', amount: 100000, alertPercent: 80 }],
};

test('lista o que vence hoje e amanhã e o orçamento no limite', () => {
  const items = buildReminders(docs, today);
  const bills = items.find((i) => i.key === `bills:${today}`);
  assert.ok(bills);
  assert.match(bills.text, /hoje Internet/);
  assert.match(bills.text, /amanhã Luz/);
  assert.doesNotMatch(bills.text, /Depois/);
  const budget = items.find((i) => i.key.startsWith('budget:b:2026-10:'));
  assert.equal(budget.key, 'budget:b:2026-10:80');
  assert.match(budget.text, /Alimentação em 85%/);
});

test('orçamento estourado e avisos desligados', () => {
  const more = {
    ...docs,
    transactions: [
      ...docs.transactions,
      { id: 'm2', type: 'expense', amount: 30000, description: 'x', date: '2026-10-06',
        accountId: 'a', categoryId: 'cat_food', status: 'completed' },
    ],
  };
  const items = buildReminders(more, today, { bills: false });
  assert.equal(items.length, 1);
  assert.equal(items[0].key, 'budget:b:2026-10:100');
  assert.match(items[0].text, /estourado/);
  assert.deepEqual(buildReminders(docs, today, { bills: false, budgets: false }), []);
});

test('antes das 8h não envia; depois envia uma vez por chave', async () => {
  const sent = [];
  const keys = new Set();
  const pool = {
    async query(sql, params) {
      if (sql.includes('from whatsapp_links')) {
        return { rows: [{ wa_id: '5547', user_id: 'u', settings: { whatsappReminders: true, whatsappBudgetAlerts: true } }] };
      }
      if (sql.includes('from app_docs')) {
        const rows = [];
        for (const [coll, list] of Object.entries(docs)) for (const data of list) rows.push({ coll, data });
        return { rows };
      }
      if (sql.startsWith('select key')) return { rows: params[1].filter((k) => keys.has(k)).map((key) => ({ key })) };
      if (sql.includes('insert into whatsapp_reminders_sent')) {
        const fresh = params[1].filter((k) => !keys.has(k));
        fresh.forEach((k) => keys.add(k));
        return { rows: fresh.map((key) => ({ key })) };
      }
      throw new Error(`SQL inesperado: ${sql}`);
    },
  };
  const meta = { sendText: async (to, text) => sent.push({ to, text }) };
  let at = new Date('2026-10-19T09:00:00Z'); // 06h em Brasília
  const job = createReminderJob({ pool, getMeta: () => meta, now: () => at });
  assert.equal(await job.runOnce(), 0);
  at = new Date('2026-10-19T12:00:00Z'); // 09h
  assert.equal(await job.runOnce(), 1);
  assert.equal(sent.length, 1);
  assert.match(sent[0].text, /Contas a vencer/);
  assert.match(sent[0].text, /Orçamento de Alimentação/);
  assert.equal(await job.runOnce(), 0); // já enviado hoje
});
