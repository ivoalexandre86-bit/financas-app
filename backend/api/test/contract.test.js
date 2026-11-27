// Leitura de contrato pela IA: normalização dos campos (dados fictícios).

const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeContract } = require('../ai');

test('converte reais em centavos, taxa em fração e lista os campos', () => {
  const c = normalizeContract({
    name: 'CCB veículo',
    lender: 'Banco Exemplo',
    kind: 'vehicle',
    system: 'price',
    monthlyRatePercent: 1.89,
    annualRatePercent: null,
    originalPrincipal: 60000,
    contractDate: '2025-03-10',
    termMonths: 48,
    outstanding: 42000.5,
    balanceDate: 'ontem',
    remainingMonths: 30,
    nextDueDate: '2026-12-10',
    currentPayment: 1789.9,
    monthlyFees: [{ name: 'Seguro prestamista', amount: 35.2 }, { name: 'x', amount: -1 }],
    index: 'none',
    notes: 'CET não informado.',
  });
  assert.equal(c.outstanding, 4200050);
  assert.equal(c.currentPayment, 178990);
  assert.equal(c.monthlyRate, 0.0189);
  assert.equal(c.balanceDate, null);
  assert.deepEqual(c.fees, [{ name: 'Seguro prestamista', monthly: 3520 }]);
  assert.ok(c.fields.includes('outstanding'));
  assert.ok(!c.fields.includes('balanceDate'));
});

test('taxa anual vira mensal equivalente; sem dados devolve null', () => {
  const c = normalizeContract({ annualRatePercent: 12.6825, monthlyFees: [] });
  assert.ok(Math.abs(c.monthlyRate - 0.01) < 1e-6);
  assert.equal(normalizeContract({ monthlyFees: [] }), null);
  assert.equal(normalizeContract(null), null);
});
