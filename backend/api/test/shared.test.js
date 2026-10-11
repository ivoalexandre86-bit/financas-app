// Despesas compartilhadas. Integração exige PostgreSQL em TEST_DATABASE_URL.

const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');
const { createApp, migrate } = require('../app');
const { allocate, checkPercentages } = require('../shared/allocation');

test('allocate: soma exata e centavos para as maiores frações', () => {
  assert.deepEqual(
    allocate(30000, [{ userId: 'a', bp: 6000 }, { userId: 'b', bp: 4000 }]),
    [{ userId: 'a', bp: 6000, amount: 18000 }, { userId: 'b', bp: 4000, amount: 12000 }],
  );
  const three = allocate(10000, [
    { userId: 'a', bp: 3334 },
    { userId: 'b', bp: 3333 },
    { userId: 'c', bp: 3333 },
  ]);
  assert.equal(three.reduce((s, r) => s + r.amount, 0), 10000);
  assert.deepEqual(three.map((r) => r.amount), [3334, 3333, 3333]);
  const odd = allocate(101, [{ userId: 'a', bp: 5000 }, { userId: 'b', bp: 5000 }]);
  assert.deepEqual(odd.map((r) => r.amount), [51, 50]);
});

test('checkPercentages', () => {
  const ids = ['a', 'b'];
  assert.match(checkPercentages({ a: 6000, b: 3000 }, ids).error, /100%/);
  assert.match(checkPercentages({ a: 6000, c: 4000 }, ids).error, /ativos/);
  assert.match(checkPercentages({ a: 60.5, b: 3950 }, ids).error, /inválido/);
  assert.deepEqual(checkPercentages({ b: 4000, a: 6000 }, ids).list, [
    { userId: 'a', bp: 6000 },
    { userId: 'b', bp: 4000 },
  ]);
});

const url = process.env.TEST_DATABASE_URL;

test('API de despesas compartilhadas', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const pool = new Pool({ connectionString: url });
  await pool.query(
    'drop table if exists share_audit, share_payments, share_settlements, share_allocations, share_expenses, share_recurrences, share_categories, share_members, share_groups, of_items, whatsapp_config, whatsapp_links, whatsapp_link_codes, whatsapp_drafts, whatsapp_seen, app_docs, users cascade',
  );
  await migrate(pool);
  const app = createApp({ pool, jwtSecret: 'x'.repeat(40) });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    server.close();
    await pool.end();
  });

  async function call(method, path, token, body) {
    const res = await fetch(base + path, {
      method,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const txt = await res.text();
    return { status: res.status, body: txt ? JSON.parse(txt) : null };
  }

  const reg = await call('POST', '/auth/register', null, {
    name: 'Ana', email: 'ana@x.com', password: 'Senha1234',
  });
  const ana = { token: reg.body.token, id: reg.body.user.id };
  async function newUser(name) {
    const email = `${name.toLowerCase()}@x.com`;
    const r = await call('POST', '/users', ana.token, { name, email, password: 'Senha1234' });
    const l = await call('POST', '/auth/login', null, { email, password: 'Senha1234' });
    return { token: l.body.token, id: r.body.user.id };
  }
  const bia = await newUser('Bia');
  const caio = await newUser('Caio');
  const state = async (u) => (await call('GET', '/shared/state', u.token)).body;

  let gid, cats, luz;
  await t.test('cria grupo com categorias padrão (dono com 100%)', async () => {
    const r = await call('POST', '/shared/groups', ana.token, { name: 'Casa', kind: 'household' });
    assert.equal(r.status, 201);
    gid = r.body.id;
    const s = await state(ana);
    assert.equal(s.groups.length, 1);
    cats = s.groups[0].categories;
    assert.equal(cats.length, 10);
    luz = cats.find((c) => c.name === 'Luz e água');
    assert.deepEqual(luz.percentages, { [ana.id]: 10000 });
    assert.equal(s.groups[0].myRole, 'owner');
  });

  await t.test('convite: usuário inexistente, aceite e privacidade', async () => {
    assert.equal((await call('POST', `/shared/groups/${gid}/members`, ana.token, { email: 'nao@x.com' })).status, 404);
    const r = await call('POST', `/shared/groups/${gid}/members`, ana.token, { email: 'BIA@x.com' });
    assert.equal(r.status, 201);
    assert.equal((await call('POST', `/shared/groups/${gid}/members`, ana.token, { email: 'bia@x.com' })).status, 409);
    // Convidada ainda não vê o grupo, só o convite.
    let s = await state(bia);
    assert.equal(s.groups.length, 0);
    assert.equal(s.invites[0].groupName, 'Casa');
    // Só o dono convida.
    assert.equal((await call('POST', `/shared/groups/${gid}/members`, bia.token, { email: 'caio@x.com' })).status, 404);
    assert.equal((await call('POST', `/shared/groups/${gid}/accept`, bia.token)).status, 204);
    s = await state(bia);
    assert.equal(s.groups[0].myRole, 'member');
    // Quem não participa não vê nada nem consegue agir no grupo.
    assert.equal((await state(caio)).groups.length, 0);
    assert.equal((await call('GET', `/shared/groups/${gid}/history`, caio.token)).status, 404);
    // E-mails dos outros ficam ocultos para quem não é dono.
    const anaRow = s.groups[0].members.find((m) => m.userId === ana.id);
    assert.equal(anaRow.email, null);
  });

  await t.test('percentuais por categoria: precisam somar 100%', async () => {
    const bad = await call('PATCH', `/shared/categories/${luz.id}`, ana.token, {
      percentages: { [ana.id]: 6000, [bia.id]: 3000 },
    });
    assert.equal(bad.status, 400);
    assert.match(bad.body.error, /100%/);
    const notMember = await call('PATCH', `/shared/categories/${luz.id}`, ana.token, {
      percentages: { [ana.id]: 6000, [caio.id]: 4000 },
    });
    assert.equal(notMember.status, 400);
    // Participante comum não altera a configuração.
    const member = await call('PATCH', `/shared/categories/${luz.id}`, bia.token, {
      percentages: { [ana.id]: 5000, [bia.id]: 5000 },
    });
    assert.equal(member.status, 403);
    const ok = await call('PATCH', `/shared/categories/${luz.id}`, ana.token, {
      percentages: { [ana.id]: 6000, [bia.id]: 4000 },
    });
    assert.equal(ok.status, 204);
    const custom = await call('POST', `/shared/groups/${gid}/categories`, ana.token, {
      name: 'Pets', percentages: { [ana.id]: 3000, [bia.id]: 7000 },
    });
    assert.equal(custom.status, 201);
  });

  let exp;
  await t.test('divisão automática e idempotência pela origem', async () => {
    const r = await call('POST', '/shared/expenses', ana.token, {
      groupId: gid, categoryId: luz.id, description: 'Conta de luz', total: 30000,
      date: '2026-10-10', dueDate: '2026-10-15', source: 'account', sourceKey: 'tx1',
      budgetCategoryId: 'cat_luz',
    });
    assert.equal(r.status, 201);
    exp = r.body.id;
    let e = (await state(bia)).groups[0].expenses.find((x) => x.id === exp);
    assert.deepEqual(
      e.allocations.map((a) => [a.userId, a.bp, a.amount]).sort(),
      [[ana.id, 6000, 18000], [bia.id, 4000, 12000]].sort(),
    );
    assert.equal(e.sourceKey, null, 'origem só aparece para o dono');
    // Mesma origem: não duplica; acompanha o valor mantendo os percentuais.
    const again = await call('POST', '/shared/expenses', ana.token, {
      groupId: gid, categoryId: luz.id, description: 'Conta de luz', total: 31000,
      date: '2026-10-10', dueDate: '2026-10-15', sourceKey: 'tx1',
    });
    assert.equal(again.status, 200);
    assert.equal(again.body.id, exp);
    const s = await state(ana);
    assert.equal(s.groups[0].expenses.length, 1);
    e = s.groups[0].expenses[0];
    assert.equal(e.total, 31000);
    assert.equal(e.allocations.find((a) => a.userId === bia.id).amount, 12400);
    assert.equal(s.groups[0].categoryMap.cat_luz, luz.id);
    // Participante comum não lança despesa no grupo.
    const member = await call('POST', '/shared/expenses', bia.token, {
      groupId: gid, categoryId: luz.id, description: 'x', total: 100, date: '2026-10-10',
    });
    assert.equal(member.status, 403);
  });

  await t.test('mudança de percentual vale para as próximas; histórico preservado', async () => {
    await call('PATCH', `/shared/categories/${luz.id}`, ana.token, {
      percentages: { [ana.id]: 5000, [bia.id]: 5000 },
    });
    const r = await call('POST', '/shared/expenses', ana.token, {
      groupId: gid, categoryId: luz.id, description: 'Água', total: 10000, date: '2026-10-12',
      sourceKey: 'tx2',
    });
    const s = await state(ana);
    const old = s.groups[0].expenses.find((x) => x.id === exp);
    const neu = s.groups[0].expenses.find((x) => x.id === r.body.id);
    assert.equal(old.allocations.find((a) => a.userId === bia.id).bp, 4000);
    assert.equal(neu.allocations.find((a) => a.userId === bia.id).amount, 5000);
  });

  await t.test('exceção manual numa despesa', async () => {
    const r = await call('POST', '/shared/expenses', ana.token, {
      groupId: gid, categoryId: luz.id, description: 'Gás', total: 10000, date: '2026-10-13',
      override: { [ana.id]: 9000, [bia.id]: 1000 },
    });
    assert.equal(r.status, 201);
    let s = await state(ana);
    const e = s.groups[0].expenses.find((x) => x.id === r.body.id);
    assert.equal(e.overridden, true);
    assert.equal(e.allocations.find((a) => a.userId === bia.id).amount, 1000);
    // A categoria continua 50/50.
    assert.deepEqual(s.groups[0].categories.find((c) => c.id === luz.id).percentages,
      { [ana.id]: 5000, [bia.id]: 5000 });
    const bad = await call('PATCH', `/shared/expenses/${r.body.id}`, ana.token, {
      override: { [ana.id]: 9000, [bia.id]: 2000 },
    });
    assert.equal(bad.status, 400);
    // Volta ao padrão.
    await call('PATCH', `/shared/expenses/${r.body.id}`, ana.token, { override: null });
    s = await state(ana);
    assert.equal(s.groups[0].expenses.find((x) => x.id === r.body.id).overridden, false);
  });

  await t.test('pagamentos: parcial, excesso, quem pode registrar', async () => {
    // Bia deve 12400 da luz.
    assert.equal((await call('POST', `/shared/expenses/${exp}/payments`, bia.token, {
      amount: 20000, date: '2026-10-20',
    })).status, 400);
    assert.equal((await call('POST', `/shared/expenses/${exp}/payments`, ana.token, {
      userId: ana.id, amount: 100, date: '2026-10-20',
    })).status, 400, 'parte de quem pagou a conta já está quitada');
    const p = await call('POST', `/shared/expenses/${exp}/payments`, bia.token, {
      amount: 5000, date: '2026-10-20', note: 'Pix',
    });
    assert.equal(p.status, 201);
    const e = (await state(bia)).groups[0].expenses.find((x) => x.id === exp);
    assert.equal(e.payments.length, 1);
    assert.equal(e.payments[0].amount, 5000);
  });

  await t.test('recalcular só despesas sem pagamento', async () => {
    await call('PATCH', `/shared/categories/${luz.id}`, ana.token, {
      percentages: { [ana.id]: 7000, [bia.id]: 3000 },
    });
    const r = await call('POST', `/shared/groups/${gid}/recalculate`, ana.token, { categoryId: luz.id });
    assert.equal(r.body.updated, 2); // Água e Gás; a luz já tem pagamento.
    const s = await state(ana);
    assert.equal(s.groups[0].expenses.find((x) => x.id === exp)
      .allocations.find((a) => a.userId === bia.id).bp, 4000);
  });

  await t.test('acerto quita as partes mais antigas primeiro', async () => {
    // Bia deve (por vencimento): água 3000 (12/10), gás 3000 (13/10), luz 7400 (15/10).
    const tooMuch = await call('POST', `/shared/groups/${gid}/settlements`, bia.token, {
      fromUserId: bia.id, toUserId: ana.id, amount: 999999, date: '2026-10-25',
    });
    assert.equal(tooMuch.status, 400);
    const r = await call('POST', `/shared/groups/${gid}/settlements`, bia.token, {
      fromUserId: bia.id, toUserId: ana.id, amount: 9000, date: '2026-10-25',
    });
    assert.equal(r.status, 201);
    assert.deepEqual(r.body.applied.map((a) => a.amount), [3000, 3000, 3000]);
    let s = await state(ana);
    assert.equal(s.groups[0].settlements.length, 1);
    // Pagamento de acerto só se desfaz pelo acerto.
    const fromSettlement = s.groups[0].expenses.find((x) => x.id === exp)
      .payments.find((p) => p.settlementId);
    assert.equal((await call('DELETE', `/shared/payments/${fromSettlement.id}`, ana.token)).status, 400);
    assert.equal((await call('DELETE', `/shared/settlements/${r.body.id}`, caio.token)).status, 404);
    assert.equal((await call('DELETE', `/shared/settlements/${r.body.id}`, bia.token)).status, 204);
    s = await state(ana);
    assert.equal(s.groups[0].settlements.length, 0);
    assert.equal(s.groups[0].expenses.find((x) => x.id === exp).payments.length, 1);
  });

  await t.test('recorrência: percentuais próprios e cancelamento', async () => {
    const internet = cats.find((c) => c.name === 'Internet e telefonia');
    await call('PATCH', `/shared/categories/${internet.id}`, ana.token, {
      percentages: { [ana.id]: 5000, [bia.id]: 5000 },
    });
    const r = await call('POST', '/shared/recurrences', ana.token, {
      groupId: gid, categoryId: internet.id, sourceRuleId: 'rule1', description: 'Internet',
      override: { [ana.id]: 8000, [bia.id]: 2000 },
    });
    assert.equal(r.status, 201);
    const dup = await call('POST', '/shared/recurrences', ana.token, {
      groupId: gid, categoryId: internet.id, sourceRuleId: 'rule1', description: 'Internet',
    });
    assert.equal(dup.status, 409);
    for (const d of ['2026-10-05', '2026-11-05', '2026-12-05']) {
      const o = await call('POST', '/shared/expenses', ana.token, {
        groupId: gid, recurrenceId: r.body.id, description: 'Internet', total: 12000, date: d,
        source: 'recurring', sourceKey: `r:rule1:${d}`, occurrenceDate: d,
      });
      assert.equal(o.status, 201);
    }
    let s = await state(ana);
    const occ = s.groups[0].expenses.filter((x) => x.recurrenceId === r.body.id);
    assert.equal(occ.length, 3);
    assert.equal(occ[0].allocations.find((a) => a.userId === bia.id).amount, 2400);
    assert.equal(s.groups[0].recurrences[0].sourceRuleId, 'rule1');
    assert.equal((await state(bia)).groups[0].recurrences[0].sourceRuleId, null);
    const c = await call('DELETE', `/shared/recurrences/${r.body.id}?today=2026-10-31`, ana.token);
    assert.equal(c.body.removed, 2);
    s = await state(ana);
    assert.equal(s.groups[0].expenses.filter((x) => x.recurrenceId === r.body.id).length, 1);
    assert.equal(s.groups[0].recurrences.length, 0);
  });

  await t.test('excluir despesa com pagamento mantém o registro', async () => {
    assert.equal((await call('DELETE', `/shared/expenses/${exp}`, bia.token)).status, 403);
    assert.equal((await call('DELETE', `/shared/expenses/${exp}`, ana.token)).status, 204);
    const e = (await state(bia)).groups[0].expenses.find((x) => x.id === exp);
    assert.ok(e.deletedAt);
    assert.equal(e.payments.length, 1);
  });

  await t.test('revogar participante devolve o percentual ao dono', async () => {
    assert.equal((await call('DELETE', `/shared/groups/${gid}/members/${bia.id}`, bia.token)).status, 204);
    const s = await state(ana);
    assert.deepEqual(s.groups[0].categories.find((c) => c.id === luz.id).percentages,
      { [ana.id]: 10000 });
    assert.equal(s.groups[0].members.find((m) => m.userId === bia.id).status, 'left');
    // Divisões já lançadas continuam com a parte dela.
    assert.ok(s.groups[0].expenses.some((e) => e.allocations.some((a) => a.userId === bia.id)));
    assert.equal((await state(bia)).groups.length, 0);
    assert.equal((await call('DELETE', `/shared/groups/${gid}/members/${ana.id}`, ana.token)).status, 400);
  });

  await t.test('histórico registra as ações', async () => {
    const h = (await call('GET', `/shared/groups/${gid}/history`, ana.token)).body.history;
    const actions = new Set(h.map((x) => x.action));
    for (const a of ['group.created', 'member.invited', 'member.accepted', 'category.updated',
      'expense.created', 'payment.recorded', 'settlement.recorded', 'settlement.deleted',
      'allocations.recalculated', 'recurrence.canceled', 'expense.deleted', 'member.left']) {
      assert.ok(actions.has(a), a);
    }
    assert.equal(h[0].actorName, 'Bia');
  });
});
