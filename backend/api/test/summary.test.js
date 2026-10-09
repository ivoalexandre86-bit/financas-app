// Resumo do mês pelo WhatsApp: regras puras (sem banco).

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  computeSummary,
  formatMonthSummary,
  parseSummaryRequest,
  occurrences,
  invoiceDue,
  invoiceForTx,
} = require('../whatsapp/summary');

const today = '2026-10-09';

test('pedido de resumo e mês pedido', () => {
  assert.equal(parseSummaryRequest('Resumo', today), '2026-10');
  assert.equal(parseSummaryRequest('resumo do mês passado', today), '2026-09');
  assert.equal(parseSummaryRequest('Resumo de novembro', today), '2026-11');
  assert.equal(parseSummaryRequest('resumo março 2027', today), '2027-03');
  assert.equal(parseSummaryRequest('resumo 01/2027', today), '2027-01');
  assert.equal(parseSummaryRequest('Resumo.', today), '2026-10');
  assert.equal(parseSummaryRequest('gastei 50 no mercado', today), null);
});

test('recorrências e faturas seguem as regras do app', () => {
  const rule = { id: 'r', frequency: 'monthly', startDate: '2026-01-31', pauses: [{ from: '2026-03-01', to: '2026-04-01' }] };
  assert.deepEqual(occurrences(rule, '2026-05-31'), ['2026-01-31', '2026-02-28', '2026-04-30', '2026-05-31']);
  const card = { closingDay: 10, dueDay: 17 };
  assert.equal(invoiceForTx(card, { date: '2026-10-09' }), '2026-10');
  assert.equal(invoiceForTx(card, { date: '2026-10-10' }), '2026-11');
  assert.equal(invoiceForTx(card, { date: '2026-10-09', installmentGroupId: 'g', installmentNumber: 3 }), '2026-12');
  assert.equal(invoiceDue(card, '2026-10'), '2026-10-17');
  assert.equal(invoiceDue({ closingDay: 28, dueDay: 5 }, '2026-10'), '2026-11-05');
});

test('resumo do mês na visão de caixa', () => {
  const docs = {
    categories: [{ id: 'food', name: 'Alimentação' }, { id: 'home', name: 'Casa' }],
    cards: [{ id: 'nu', name: 'Nubank', closingDay: 3, dueDay: 10 }],
    transactions: [
      { id: 't1', type: 'income', amount: 500000, date: '2026-10-05', status: 'completed', accountId: 'a' },
      { id: 't2', type: 'expense', amount: 10000, date: '2026-10-02', status: 'completed', accountId: 'a', categoryId: 'food' },
      { id: 't3', type: 'expense', amount: 30000, date: '2026-10-08', dueDate: '2026-10-12', status: 'planned', accountId: 'a', categoryId: 'home' },
      { id: 't4', type: 'expense', amount: 5000, date: '2026-10-01', status: 'pending', accountId: 'a' },
      { id: 't5', type: 'transfer', amount: 99900, date: '2026-10-03', status: 'completed', accountId: 'a' },
      // compra em 20/09 entra na fatura que fecha em 03/10 e vence em 10/10
      { id: 't6', type: 'expense', amount: 20000, date: '2026-09-20', status: 'pending', cardId: 'nu', categoryId: 'food' },
      { id: 't7', type: 'expense', amount: 1000, date: '2026-10-05', status: 'cancelled', accountId: 'a' },
      // ocorrência já gravada da recorrência (não duplica)
      { id: 't8', type: 'expense', amount: 15000, date: '2026-10-15', status: 'completed', accountId: 'a', recurringId: 'r1', occurrenceDate: '2026-10-15', categoryId: 'home' },
    ],
    recurringTransactions: [
      { id: 'r1', type: 'expense', amount: 15000, frequency: 'monthly', startDate: '2026-08-15', accountId: 'a', categoryId: 'home' },
      { id: 'r2', type: 'income', amount: 100000, frequency: 'monthly', startDate: '2026-09-25', accountId: 'a' },
    ],
    invoicePayments: [{ cardId: 'nu', invoiceKey: '2026-10', amount: 5000 }],
  };
  const s = computeSummary(docs, '2026-10', today);
  assert.deepEqual(s.income, { done: 500000, open: 100000 });
  assert.deepEqual(s.expense, { done: 25000, open: 35000 });
  assert.deepEqual(s.invoices, [{ card: 'Nubank', due: '2026-10-10', total: 20000, remaining: 15000 }]);
  assert.deepEqual(s.topCategories[0], { name: 'Casa', amount: 45000 });
  assert.deepEqual(s.upcoming.map((u) => u.label), ['Fatura Nubank', undefined]);
  assert.deepEqual(s.overdue, { count: 1, total: 5000 });

  const text = formatMonthSummary(s, today);
  assert.match(text, /Resumo de outubro\/2026/);
  assert.match(text, /Nubank: R\$\s200,00, vence 10\/10 \(falta R\$\s150,00\)/);
  assert.match(text, /Em atraso neste mês: 1/);
});
