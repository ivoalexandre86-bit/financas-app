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

test('pedido de resumo em linguagem natural', () => {
  const t = '2026-11-26';
  assert.equal(parseSummaryRequest('Mande um resumo do mês atual', t), '2026-11');
  assert.equal(parseSummaryRequest('me manda o resumo do mês passado por favor', t), '2026-10');
  assert.equal(parseSummaryRequest('Pode me mandar o extrato de outubro?', t), '2026-10');
  assert.equal(parseSummaryRequest('como está meu mês?', t), '2026-11');
  assert.equal(parseSummaryRequest('Como estão as finanças?', t), '2026-11');
  assert.equal(parseSummaryRequest('quanto gastei esse mês', t), '2026-11');
  assert.equal(parseSummaryRequest('quanto vai sobrar no próximo mês?', t), '2026-12');
  assert.equal(parseSummaryRequest('qual o saldo de dezembro', t), '2026-12');
  assert.equal(parseSummaryRequest('resumo 01/2027', t), '2027-01');
  assert.equal(parseSummaryRequest('uber 23 ontem no cartão Nubank', t), null);
  assert.equal(parseSummaryRequest('paguei 120,50 de luz', t), null);
  assert.equal(parseSummaryRequest('quando é o fechamento do nubank?', t), null);
  assert.equal(parseSummaryRequest('cabe uma TV de 3.000 em 12x?', t), null);
});

test('resumo igual à Projeção: fechamento, inativos e fatura paga antes', () => {
  const docs = {
    accounts: [
      { id: 'a', initialBalance: 100000 },
      { id: 'old', initialBalance: 0, active: false },
    ],
    cards: [
      { id: 'nu', name: 'Nubank', closingDay: 3, dueDay: 10 },
      { id: 'velho', name: 'Velho', closingDay: 3, dueDay: 10, active: false },
    ],
    transactions: [
      { id: 'i1', type: 'income', amount: 500000, date: '2026-11-05', status: 'completed', accountId: 'a' },
      // conta inativa: o que está em aberto não conta, o concluído conta
      { id: 'x1', type: 'expense', amount: 1760000, date: '2026-11-10', status: 'planned', accountId: 'old' },
      { id: 'x2', type: 'expense', amount: 1000, date: '2026-11-10', status: 'completed', accountId: 'old' },
      // fatura de dezembro (fecha 03/12, vence 10/12) paga em 28/11: conta em novembro
      { id: 'c1', type: 'expense', amount: 40000, date: '2026-11-20', status: 'pending', cardId: 'nu' },
      // cartão inativo sem pagamento: fora
      { id: 'c2', type: 'expense', amount: 9900, date: '2026-10-20', status: 'pending', cardId: 'velho' },
    ],
    invoicePayments: [{ cardId: 'nu', invoiceKey: '2026-12', amount: 40000, date: '2026-11-28', accountId: 'a' }],
  };
  const s = computeSummary(docs, '2026-11', '2026-11-26');
  assert.deepEqual(s.income, { done: 500000, open: 0 });
  assert.deepEqual(s.expense, { done: 41000, open: 0 });
  assert.equal(s.accumulated, 100000 + 500000 - 41000);
  assert.equal(s.closing, null);

  // Mês fechado: valem os valores do fechamento, também no acumulado.
  docs.monthClosings = [{ id: '2026-11', month: '2026-11', income: 300000, expenses: 300000, computedIncome: 200000, computedExpenses: 300000 }];
  const c = computeSummary(docs, '2026-11', '2026-11-26');
  assert.equal(c.closing.income, 300000);
  assert.equal(c.accumulated, 100000);
  const text = formatMonthSummary(c, '2026-11-26');
  assert.match(text, /Mês fechado/);
  // Receitas/despesas calculadas ao fechar; o ajuste fica numa linha própria.
  assert.match(text, /Receitas: \*R\$\s2\.000,00\*/);
  assert.match(text, /Ajuste manual: \*\+R\$\s1\.000,00\*/);
  assert.doesNotMatch(text, /Receitas: \*R\$\s3\.000,00\*/);
  assert.match(text, /Resultado: \*R\$\s0,00\*/);
  assert.match(text, /Pelos lançamentos de hoje seria/);
});

test('fatura paga em duas vezes divide as compras como o app', () => {
  const docs = {
    cards: [{ id: 'nu', name: 'Nubank', closingDay: 3, dueDay: 10 }],
    transactions: [
      { id: 'a', type: 'expense', amount: 10001, date: '2026-09-20', status: 'pending', cardId: 'nu' },
      { id: 'b', type: 'expense', amount: 19999, date: '2026-09-21', status: 'pending', cardId: 'nu' },
    ],
    // fatura de outubro (vence 10/10): 10.000 pagos em setembro, resto em outubro
    invoicePayments: [
      { cardId: 'nu', invoiceKey: '2026-10', amount: 10000, date: '2026-09-30' },
      { cardId: 'nu', invoiceKey: '2026-10', amount: 20000, date: '2026-10-10' },
    ],
  };
  const sep = computeSummary(docs, '2026-09', '2026-10-15');
  const oct = computeSummary(docs, '2026-10', '2026-10-15');
  assert.equal(sep.expense.done, 10000);
  assert.equal(oct.expense.done, 20000);
  assert.equal(sep.expense.done + oct.expense.done, 30000);
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
  // pagamento sem data conta no vencimento; o saldo da fatura fica a pagar
  assert.deepEqual(s.expense, { done: 30000, open: 50000 });
  assert.equal(s.cardExpenses, 20000);
  assert.deepEqual(s.invoices, [{ card: 'Nubank', due: '2026-10-10', inMonth: 20000, total: 20000, remaining: 15000 }]);
  assert.deepEqual(s.topCategories[0], { name: 'Casa', amount: 45000 });
  assert.deepEqual(s.upcoming.map((u) => u.label), ['Fatura Nubank', undefined]);
  assert.deepEqual(s.overdue, { count: 1, total: 5000 });

  const text = formatMonthSummary(s, today);
  assert.match(text, /Resumo de outubro\/2026/);
  assert.match(text, /Nubank: R\$\s200,00, vence 10\/10 \(falta R\$\s150,00\)/);
  assert.match(text, /Em atraso neste mês: 1/);
});
