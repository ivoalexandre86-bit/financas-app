// Testes de integração: exigem um PostgreSQL em TEST_DATABASE_URL.
// Ex.: TEST_DATABASE_URL=postgres://postgres@localhost:5432/financas_test npm test

const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');
const { createApp, migrate } = require('../app');

const url = process.env.TEST_DATABASE_URL;

test('API', { skip: !url && 'TEST_DATABASE_URL não definido' }, async (t) => {
  const pool = new Pool({ connectionString: url });
  await pool.query('drop table if exists app_docs, users cascade');
  await migrate(pool);
  const app = createApp({
    pool,
    jwtSecret: 'x'.repeat(40),
    allowedOrigins: ['https://ok.example'],
  });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    server.close();
    await pool.end();
  });

  async function call(method, path, { token, body, origin } = {}) {
    const res = await fetch(base + path, {
      method,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(origin ? { origin } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null, res };
  }

  let adminToken, bob, bobToken;

  await t.test('1º cadastro vira administrador; depois o cadastro fecha', async () => {
    assert.equal((await call('GET', '/auth/has-users')).body.hasUsers, false);
    const weak = await call('POST', '/auth/register', {
      body: { name: 'Ivo', email: 'ivo@x.com', password: 'curta' },
    });
    assert.equal(weak.status, 400);
    const r = await call('POST', '/auth/register', {
      body: { name: 'Ivo', email: ' Ivo@X.com ', password: 'Senha1234' },
    });
    assert.equal(r.status, 201);
    assert.equal(r.body.user.isAdmin, true);
    assert.equal(r.body.user.email, 'ivo@x.com');
    adminToken = r.body.token;
    const again = await call('POST', '/auth/register', {
      body: { name: 'Eva', email: 'eva@x.com', password: 'Senha1234' },
    });
    assert.equal(again.status, 403);
  });

  await t.test('login', async () => {
    const bad = await call('POST', '/auth/login', {
      body: { email: 'ivo@x.com', password: 'errada123' },
    });
    assert.equal(bad.status, 401);
    const ok = await call('POST', '/auth/login', {
      body: { email: 'IVO@x.com', password: 'Senha1234' },
    });
    assert.equal(ok.status, 200);
    const me = await call('GET', '/me', { token: ok.body.token });
    assert.equal(me.body.user.name, 'Ivo');
    assert.equal((await call('GET', '/me', { token: 'lixo' })).status, 401);
  });

  await t.test('admin cria usuário; não-admin não gerencia', async () => {
    const r = await call('POST', '/users', {
      token: adminToken,
      body: { name: 'Bob', email: 'bob@x.com', password: 'Senha1234' },
    });
    assert.equal(r.status, 201);
    bob = r.body.user;
    const dup = await call('POST', '/users', {
      token: adminToken,
      body: { name: 'B2', email: 'bob@x.com', password: 'Senha1234' },
    });
    assert.equal(dup.status, 409);
    bobToken = (await call('POST', '/auth/login', {
      body: { email: 'bob@x.com', password: 'Senha1234' },
    })).body.token;
    assert.equal((await call('GET', '/users', { token: bobToken })).status, 403);
    const list = await call('GET', '/users', { token: adminToken });
    assert.deepEqual(list.body.users.map((u) => u.name), ['Bob', 'Ivo']);
  });

  await t.test('dados isolados por usuário, upsert e exclusão', async () => {
    const put = await call('POST', '/docs/batch', {
      token: adminToken,
      body: {
        docs: [
          { coll: 'transactions', id: 't1', data: { amount: 1000 } },
          { coll: 'transactions', id: 't2', data: { amount: 2000 } },
          { coll: 'settings', id: 'app', data: { theme: 'dark' } },
        ],
      },
    });
    assert.equal(put.body.saved, 3);
    await call('POST', '/docs/batch', {
      token: adminToken,
      body: {
        docs: [
          { coll: 'transactions', id: 't1', data: { amount: 1500 } },
          { coll: 'transactions', id: 't2', data: null },
        ],
      },
    });
    const mine = await call('GET', '/docs', { token: adminToken });
    assert.deepEqual(mine.body.docs, [
      { coll: 'settings', id: 'app', data: { theme: 'dark' } },
      { coll: 'transactions', id: 't1', data: { amount: 1500 } },
    ]);
    const bobs = await call('GET', '/docs', { token: bobToken });
    assert.deepEqual(bobs.body.docs, []);
    const bad = await call('POST', '/docs/batch', {
      token: adminToken,
      body: { docs: [{ coll: '', id: 'x' }] },
    });
    assert.equal(bad.status, 400);
  });

  await t.test('senha: troca própria e redefinição pelo admin', async () => {
    const wrong = await call('POST', '/me/password', {
      token: bobToken,
      body: { current: 'errada123', password: 'Nova12345' },
    });
    assert.equal(wrong.status, 400);
    assert.equal((await call('POST', '/me/password', {
      token: bobToken,
      body: { current: 'Senha1234', password: 'Nova12345' },
    })).status, 204);
    assert.equal((await call('POST', `/users/${bob.id}/password`, {
      token: adminToken,
      body: { password: 'Admin1234' },
    })).status, 204);
    const login = await call('POST', '/auth/login', {
      body: { email: 'bob@x.com', password: 'Admin1234' },
    });
    assert.equal(login.status, 200);
  });

  await t.test('último administrador é protegido', async () => {
    const demote = await call('PATCH', '/users/' + (await call('GET', '/me', { token: adminToken })).body.user.id, {
      token: adminToken,
      body: { name: 'Ivo', email: 'ivo@x.com', isAdmin: false },
    });
    assert.equal(demote.status, 409);
    assert.equal((await call('DELETE', '/me', { token: adminToken })).status, 409);
    const promote = await call('PATCH', `/users/${bob.id}`, {
      token: adminToken,
      body: { name: 'Bob', email: 'bob@x.com', isAdmin: true },
    });
    assert.equal(promote.body.user.isAdmin, true);
    assert.equal((await call('PATCH', '/users/nao-e-uuid', {
      token: adminToken,
      body: { name: 'X', email: 'x@x.com', isAdmin: true },
    })).status, 404);
  });

  await t.test('excluir usuário apaga os dados e invalida o token', async () => {
    await call('POST', '/docs/batch', {
      token: bobToken,
      body: { docs: [{ coll: 'transactions', id: 'b1', data: {} }] },
    });
    assert.equal((await call('DELETE', `/users/${bob.id}`, { token: adminToken })).status, 204);
    assert.equal((await call('GET', '/docs', { token: bobToken })).status, 401);
    const { rows } = await pool.query(
      'select count(*)::int n from app_docs where user_id = $1', [bob.id]);
    assert.equal(rows[0].n, 0);
  });

  await t.test('CORS só para a origem do app', async () => {
    const ok = await call('GET', '/health', { origin: 'https://ok.example' });
    assert.equal(ok.res.headers.get('access-control-allow-origin'), 'https://ok.example');
    const no = await call('GET', '/health', { origin: 'https://evil.example' });
    assert.equal(no.res.headers.get('access-control-allow-origin'), null);
  });

  await t.test('limite de tentativas de login', async () => {
    let last;
    for (let i = 0; i < 12; i++) {
      last = await call('POST', '/auth/login', {
        body: { email: 'ivo@x.com', password: 'errada' + i },
      });
    }
    assert.equal(last.status, 429);
  });
});
