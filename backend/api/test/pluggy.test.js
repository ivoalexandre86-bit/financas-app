const test = require('node:test');
const assert = require('node:assert/strict');
const { createPluggy } = require('../pluggy');

test('Pluggy: autentica uma vez e percorre as páginas de transações', async () => {
  const calls = [];
  const fake = async (url, init) => {
    calls.push([init.method, url.pathname + url.search, init.headers['X-API-KEY'] ?? null]);
    const json = (body) => ({ ok: true, status: 200, text: async () => JSON.stringify(body) });
    if (url.pathname === '/auth') {
      assert.deepEqual(JSON.parse(init.body), { clientId: 'id', clientSecret: 'sec', nonExpiring: false });
      return json({ apiKey: 'KEY' });
    }
    if (url.pathname === '/v2/transactions') {
      return url.searchParams.get('after')
        ? json({ results: [{ id: 'b' }], next: null })
        : json({ results: [{ id: 'a' }], next: '/v2/transactions?accountId=x&after=CUR' });
    }
    return { ok: false, status: 404, text: async () => '{"message":"nope"}' };
  };
  const p = createPluggy({ clientId: 'id', clientSecret: 'sec', baseUrl: 'https://p.test', fetch: fake });
  const txs = await p.listTransactions('x', '2026-09-01');
  assert.deepEqual(txs.map((t) => t.id), ['a', 'b']);
  assert.deepEqual(calls, [
    ['POST', '/auth', null],
    ['GET', '/v2/transactions?accountId=x&dateFrom=2026-09-01', 'KEY'],
    ['GET', '/v2/transactions?accountId=x&dateFrom=2026-09-01&after=CUR', 'KEY'],
  ]);
  await assert.rejects(p.getItem('zz'), (e) => e.status === 404 && e.message === 'nope');
});
