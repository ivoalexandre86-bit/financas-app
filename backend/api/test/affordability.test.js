// Assistente de compras pelo WhatsApp: regras puras (sem banco).

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  parsePurchaseQuestion,
  analyzePurchase,
  formatAnalysis,
  projectMargins,
} = require('../whatsapp/affordability');

const today = '2026-11-02';

test('lê a pergunta de compra parcelada', () => {
  const q = parsePurchaseQuestion('Cabe uma TV de R$ 2.400,00 em 12x?', today);
  assert.equal(q.total, 240000);
  assert.equal(q.installments, 12);
  assert.equal(q.startMonth, null);

  const c = parsePurchaseQuestion('posso comprar um celular de 3 mil em 10 parcelas no cartão Nubank a partir de janeiro?', today);
  assert.equal(c.total, 300000);
  assert.equal(c.installments, 10);
  assert.equal(c.startMonth, '2027-01');
  assert.equal(c.card, true);

  const p = parsePurchaseQuestion('consigo pagar 12x de 199,90?', today);
  assert.equal(p.total, 239880);
  assert.equal(p.parcel, 19990);

  const j = parsePurchaseQuestion('vale a pena comprar uma geladeira de 3000 em 12x de 290?', today);
  assert.equal(j.total, 348000);
  assert.equal(j.listPrice, 300000);

  const w = parsePurchaseQuestion('da pra parcelar 1500 em doze vezes?', today);
  assert.equal(w.installments, 12);
  assert.equal(w.total, 150000);

  const d = parsePurchaseQuestion('cabe 1.200 em dez vezes?', today);
  assert.equal(d.installments, 10);
  assert.equal(d.startMonth, null);

  const r = parsePurchaseQuestion('cabe uma parcela de 300 por 12 meses?', today);
  assert.equal(r.installments, 12);
  assert.equal(r.total, 360000);

  const m = parsePurchaseQuestion('cabe 2,5 mil em 5x com a primeira parcela em março de 2027?', today);
  assert.equal(m.total, 250000);
  assert.equal(m.startMonth, '2027-03');

  assert.deepEqual(parsePurchaseQuestion('posso comprar um sofá em 10x?', today), { missing: 'amount' });
  // Lançamentos continuam indo para a IA.
  assert.equal(parsePurchaseQuestion('tênis 600 em 3x no cartão', today), null);
  assert.equal(parsePurchaseQuestion('comprei uma tv de 2000 em 10x, cabe?', today), null);
  assert.equal(parsePurchaseQuestion('gastei 45,90 no mercado', today), null);
  assert.equal(parsePurchaseQuestion('resumo', today), null);
});

const salary = { id: 'sal', type: 'income', amount: 500000, frequency: 'monthly', startDate: '2026-01-05', dayOfMonth: 5, accountId: 'a' };
const rent = { id: 'rent', type: 'expense', amount: 200000, frequency: 'monthly', startDate: '2026-01-10', dayOfMonth: 10, accountId: 'a', categoryId: 'home' };

function docs(extra = {}) {
  return {
    categories: [
      { id: 'home', name: 'Casa' },
      { id: 'food', name: 'Alimentação' },
      { id: 'market', name: 'Mercado', parentId: 'food' },
    ],
    cards: [{ id: 'nu', name: 'Nubank', bank: 'Nubank', closingDay: 3, dueDay: 10 }],
    recurringTransactions: [salary, rent],
    transactions: [],
    budgets: [{ id: 'b', categoryId: 'food', amount: 100000 }],
    ...extra,
  };
}

test('projeção desconta contas fixas, orçamento e média dos gastos avulsos', () => {
  const d = docs({
    transactions: [
      // gastos avulsos de lazer em ago/set/out: média de 30.000
      { id: 'l1', type: 'expense', amount: 30000, date: '2026-08-15', status: 'completed', accountId: 'a', categoryId: 'fun' },
      { id: 'l2', type: 'expense', amount: 60000, date: '2026-09-15', status: 'completed', accountId: 'a', categoryId: 'fun' },
      { id: 'l3', type: 'expense', amount: 0, date: '2026-10-15', status: 'completed', accountId: 'a', categoryId: 'fun' },
      // mercado já gasto em dezembro: abate do orçamento de Alimentação
      { id: 'm1', type: 'expense', amount: 40000, date: '2026-12-03', status: 'planned', accountId: 'a', categoryId: 'market' },
    ],
  });
  const [nov, dec] = projectMargins(d, today, '2026-11', '2026-12');
  // 5.000 − 2.000 aluguel − 1.000 orçamento − 300 lazer
  assert.equal(nov.margin, 170000);
  // dez: 5.000 − 2.000 − 400 mercado − 600 resto do orçamento − 300 lazer
  assert.equal(dec.margin, 170000);
  assert.equal(dec.cushion, 50000);
});

test('compra que cabe com folga', () => {
  const q = parsePurchaseQuestion('cabe 2.400 em 12x no nubank?', today);
  const a = analyzePurchase(docs(), q, today);
  // compra hoje (02/11) entra na fatura que fecha 03/11 e vence 10/11
  assert.equal(a.first, '2026-11');
  assert.equal(a.card, 'Nubank');
  assert.equal(a.result.level, 'ok');
  const text = formatAnalysis(a);
  assert.match(text, /Cabe no orçamento/);
  assert.match(text, /12x de R\$\s?200,00/);
});

test('compra que não cabe traz alternativas', () => {
  const q = parsePurchaseQuestion('posso comprar um notebook de 12.000 em 6x?', today);
  const a = analyzePurchase(docs(), q, today);
  // sobra 2.000/mês, folga 500: parcela de 2.000 zera a sobra -> apertado
  assert.equal(a.first, '2026-12');
  assert.equal(a.result.level, 'tight');
  const kinds = a.alternatives.map((x) => x.kind);
  assert.ok(kinds.includes('count'));
  assert.ok(kinds.includes('value'));
  const more = a.alternatives.find((x) => x.kind === 'count');
  assert.equal(more.installments, 8); // 1.500/mês deixa 500 de folga
  assert.equal(a.alternatives.find((x) => x.kind === 'value').total, 900000);

  const big = analyzePurchase(docs(), parsePurchaseQuestion('cabe 30 mil em 10x?', today), today);
  assert.equal(big.result.level, 'no');
  assert.match(formatAnalysis(big), /não é viável/);
  assert.match(formatAnalysis(big), /Opções que cabem com folga/);
});

test('começar depois resolve quando há um gasto grande previsto', () => {
  const d = docs({
    transactions: [
      { id: 'ipva', type: 'expense', amount: 150000, date: '2027-01-20', status: 'planned', accountId: 'a', categoryId: 'home' },
      { id: 'iptu', type: 'expense', amount: 150000, date: '2027-02-20', status: 'planned', accountId: 'a', categoryId: 'home' },
    ],
  });
  const a = analyzePurchase(d, parsePurchaseQuestion('cabe 3.000 em 2x?', today), today);
  assert.notEqual(a.result.level, 'ok');
  const later = a.alternatives.find((x) => x.kind === 'later');
  assert.equal(later.first, '2027-03');
});

test('sem receitas previstas pede para cadastrar o salário', () => {
  const d = docs({ recurringTransactions: [rent] });
  const a = analyzePurchase(d, parsePurchaseQuestion('cabe 1000 em 5x?', today), today);
  assert.equal(a.noIncome, true);
  assert.match(formatAnalysis(a), /Cadastre o salário/);
});
