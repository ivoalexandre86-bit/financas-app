// Crescimento: eventos do funil (instalação → cadastro → 1º orçamento → 1ª
// simulação → teste → 1ª cobrança → renovação/cancelamento), programa de
// indicação e o painel do negócio (CAC, MRR, conversão, retenção e receita
// por canal) para administradores.

const crypto = require('crypto');

/// Eventos que o app pode enviar. `install` é o único sem login.
const CLIENT_EVENTS = new Set([
  'install',
  'first_budget',
  'first_simulation',
  'paywall_view',
  'purchase_start',
  'referral_share',
  'active',
]);

/// Eventos gravados pelo servidor (cadastro e lojas).
const SERVER_EVENTS = [
  'signup',
  'trial_start',
  'first_charge',
  'renewal',
  'cancellation',
  'uncancellation',
  'expiration',
  'billing_issue',
  'product_change',
  'referral_rewarded',
];

/// Ordem e nomes do funil no painel.
const FUNNEL = [
  ['install', 'Instalações'],
  ['signup', 'Cadastros'],
  ['first_budget', '1º orçamento'],
  ['first_simulation', '1ª simulação'],
  ['trial_start', 'Início do teste'],
  ['first_charge', '1ª cobrança'],
  ['renewal', 'Renovações'],
  ['cancellation', 'Cancelamentos'],
];

/// Eventos que acontecem uma vez por usuário (ou aparelho).
const ONCE = new Set(['install', 'first_budget', 'first_simulation', 'signup', 'trial_start', 'first_charge']);

/// Indicação: dias de Premium para quem indica (após a 1ª cobrança do
/// indicado), dias extras de teste para quem chega pelo convite, limites.
const REFERRAL = {
  rewardDays: 30,
  friendDays: 15,
  maxRewardsPerYear: 12,
  maxSignupsPerDay: 10,
};

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_RE = /^[A-Z2-9]{4,12}$/;
const DEVICE_RE = /^[A-Za-z0-9_-]{8,64}$/;

/// Canal de aquisição: minúsculas, sem espaços (ex.: instagram, google-ads).
function cleanChannel(c) {
  const s = String(c ?? '')
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);
  return s || null;
}

const cleanCode = (c) => {
  const s = String(c ?? '').trim().toUpperCase();
  return CODE_RE.test(s) ? s : null;
};

const cleanDevice = (d) => {
  const s = String(d ?? '').trim();
  return DEVICE_RE.test(s) ? s : null;
};

/// E-mail "canônico" para detectar a mesma pessoa com apelidos
/// (pontos e +sufixo do Gmail).
function canonicalEmail(email) {
  const [user, domain] = String(email ?? '').toLowerCase().split('@');
  if (!domain) return String(email ?? '').toLowerCase();
  let u = user.split('+')[0];
  const d = domain === 'googlemail.com' ? 'gmail.com' : domain;
  if (d === 'gmail.com') u = u.replace(/\./g, '');
  return `${u}@${d}`;
}

function newCode(len = 6) {
  const bytes = crypto.randomBytes(len);
  let s = '';
  for (const b of bytes) s += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return s;
}

const monthKey = (d) => d.toISOString().slice(0, 7);

function lastMonths(n, now = new Date()) {
  const out = [];
  for (let i = n - 1; i >= 0; i--) {
    out.push(monthKey(new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1))));
  }
  return out;
}

const pct = (a, b) => (b > 0 ? Math.round((a / b) * 1000) / 10 : null);

/// Tipo de evento do RevenueCat → evento do funil.
function storeEventName(ev, alreadyCharged) {
  switch (ev?.type) {
    case 'INITIAL_PURCHASE':
    case 'NON_RENEWING_PURCHASE':
      if (ev.period_type === 'TRIAL') return null;
      return alreadyCharged ? 'renewal' : 'first_charge';
    case 'RENEWAL':
      return alreadyCharged ? 'renewal' : 'first_charge';
    case 'CANCELLATION':
      return 'cancellation';
    case 'UNCANCELLATION':
      return 'uncancellation';
    case 'EXPIRATION':
      return 'expiration';
    case 'BILLING_ISSUE':
      return 'billing_issue';
    case 'PRODUCT_CHANGE':
      return 'product_change';
    default:
      return null;
  }
}

/// Valor cobrado (centavos) informado pela loja.
function amountOf(ev) {
  const v = Number(ev?.price_in_purchased_currency ?? ev?.price);
  if (!Number.isFinite(v) || v <= 0) return null;
  return Math.round(v * 100);
}

/**
 * @param {import('express').Express} app
 * @param {{pool: import('pg').Pool, authed: Function, admin: Function,
 *   optionalAuthed: Function, wrap: Function, HttpError: Function,
 *   prices?: {basico: number, premium: number}}} deps
 */
function mountGrowth(app, { pool, authed, admin, optionalAuthed, wrap, HttpError, prices }) {
  const price = {
    basico: prices?.basico ?? 999,
    premium: prices?.premium ?? 1999,
  };

  /// Grava um evento. Eventos únicos (por usuário/aparelho), o "ativo" de
  /// cada dia e os das lojas não se repetem.
  async function track(name, { userId = null, deviceId = null, channel = null, props = {}, dedupe } = {}, db = pool) {
    let key = dedupe;
    if (key === undefined) {
      if (name === 'install') key = `install:${deviceId}`;
      else if (ONCE.has(name)) key = `${name}:${userId ?? deviceId}`;
      else if (name === 'active') key = `active:${userId}:${new Date().toISOString().slice(0, 10)}`;
      else key = null;
    }
    if (!channel && userId) {
      const { rows } = await db.query('select channel from users where id = $1', [userId]);
      channel = rows[0]?.channel ?? null;
    }
    const { rowCount } = await db.query(
      `insert into funnel_events (name, user_id, device_id, channel, props, dedupe)
       values ($1, $2, $3, $4, $5, $6) on conflict (dedupe) do nothing`,
      [name, userId, deviceId, channel, JSON.stringify(props ?? {}), key],
    );
    return rowCount > 0;
  }

  /// Cadastro: canal de aquisição, convite e eventos do funil. Chamado na
  /// mesma transação que cria o usuário.
  async function onSignup(client, user, { channel, ref, deviceId, ip } = {}) {
    const device = cleanDevice(deviceId);
    let ch = cleanChannel(channel);
    if (!ch && device) {
      const { rows } = await client.query(
        `select channel from funnel_events where name = 'install' and device_id = $1
         order by created_at limit 1`,
        [device],
      );
      ch = rows[0]?.channel ?? null;
    }
    const code = cleanCode(ref);
    let referral = null;
    if (code) {
      const { rows } = await client.query('select * from users where referral_code = $1', [code]);
      const referrer = rows[0];
      if (referrer && referrer.id !== user.id) {
        referral = { referrer, status: 'pending', reason: null };
        ch = ch ?? 'indicacao';
        // Antifraude: mesma pessoa (e-mail com apelido) ou mesmo aparelho.
        if (canonicalEmail(referrer.email) === canonicalEmail(user.email)) {
          referral.status = 'rejected';
          referral.reason = 'mesmo e-mail';
        } else if (device) {
          const same = await client.query(
            `select 1 from funnel_events where user_id = $1 and device_id = $2 limit 1`,
            [referrer.id, device],
          );
          if (same.rows.length || referrer.device_id === device) {
            referral.status = 'rejected';
            referral.reason = 'mesmo aparelho';
          }
        }
        if (referral.status === 'pending') {
          const today = await client.query(
            `select count(*)::int n from referrals
             where referrer_id = $1 and created_at > now() - interval '1 day'`,
            [referrer.id],
          );
          if (today.rows[0].n >= REFERRAL.maxSignupsPerDay) {
            referral.status = 'rejected';
            referral.reason = 'limite diário de convites';
          }
        }
      }
    }
    const { rows } = await client.query(
      `update users set channel = $2, device_id = $3, signup_ip = $4,
         referred_by = $5,
         trial_ends_at = case when $6 then trial_ends_at + make_interval(days => $7)
                              else trial_ends_at end
       where id = $1 returning *`,
      [
        user.id,
        ch ?? 'organico',
        device,
        ip ?? null,
        referral?.referrer.id ?? null,
        referral?.status === 'pending',
        REFERRAL.friendDays,
      ],
    );
    if (referral) {
      await client.query(
        `insert into referrals (referred_id, referrer_id, status, reason)
         values ($1, $2, $3, $4) on conflict do nothing`,
        [user.id, referral.referrer.id, referral.status, referral.reason],
      );
    }
    const u = rows[0];
    const props = referral ? { referral: referral.status } : {};
    await track('signup', { userId: u.id, deviceId: device, channel: u.channel, props }, client);
    if (!u.is_admin && !u.free_access) {
      await track('trial_start', {
        userId: u.id,
        deviceId: device,
        channel: u.channel,
        props: { endsAt: u.trial_ends_at },
      }, client);
    }
    return u;
  }

  /// Indicado pagou pela 1ª vez: quem indicou ganha dias de Premium.
  async function rewardReferral(referredId) {
    const client = await pool.connect();
    try {
      await client.query('begin');
      const { rows } = await client.query(
        `select * from referrals where referred_id = $1 and status = 'pending' for update`,
        [referredId],
      );
      const r = rows[0];
      if (!r) {
        await client.query('commit');
        return false;
      }
      const year = await client.query(
        `select count(*)::int n from referrals
         where referrer_id = $1 and status = 'rewarded'
           and rewarded_at > now() - interval '1 year'`,
        [r.referrer_id],
      );
      if (year.rows[0].n >= REFERRAL.maxRewardsPerYear) {
        await client.query(
          `update referrals set status = 'rejected', reason = 'limite anual de recompensas'
           where referred_id = $1`,
          [referredId],
        );
        await client.query('commit');
        return false;
      }
      await client.query(
        `update referrals set status = 'rewarded', rewarded_at = now() where referred_id = $1`,
        [referredId],
      );
      await client.query(
        `update users set bonus_until = greatest(coalesce(bonus_until, now()), now())
           + make_interval(days => $2) where id = $1`,
        [r.referrer_id, REFERRAL.rewardDays],
      );
      await track('referral_rewarded', {
        userId: r.referrer_id,
        props: { referred: referredId, days: REFERRAL.rewardDays },
        dedupe: `referral_rewarded:${referredId}`,
      }, client);
      await client.query('commit');
      return true;
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }
  }

  /// Evento do webhook do RevenueCat (compra, renovação, cancelamento…).
  async function storeEvent(userId, ev) {
    const { rows } = await pool.query(
      `select exists (select 1 from funnel_events where user_id = $1 and name = 'first_charge') c`,
      [userId],
    );
    const name = storeEventName(ev, rows[0].c);
    if (!name) return null;
    const props = {
      store: ev.store ?? null,
      product: ev.product_id ?? null,
      currency: ev.currency ?? null,
      amountCents: amountOf(ev),
      periodType: ev.period_type ?? null,
      reason: ev.cancel_reason ?? ev.expiration_reason ?? null,
      plan: (ev.entitlement_ids ?? []).includes('premium') ? 'premium' : 'basico',
    };
    const key = ev.id ? `rc:${ev.id}` : name === 'first_charge' ? undefined : null;
    await track(name, { userId, props, dedupe: key });
    if (name === 'first_charge') await rewardReferral(userId);
    return name;
  }

  // Rotas do app -----------------------------------------------------------

  app.post('/events', optionalAuthed, wrap(async (req, res) => {
    const name = String(req.body?.name ?? '');
    if (!CLIENT_EVENTS.has(name)) throw new HttpError(400, 'Evento desconhecido');
    const deviceId = cleanDevice(req.body?.deviceId);
    if (!req.user && name !== 'install') throw new HttpError(401, 'Entre para registrar este evento');
    if (name === 'install' && !deviceId) throw new HttpError(400, 'Aparelho inválido');
    const raw = req.body?.props;
    const props = {};
    if (raw && typeof raw === 'object') {
      for (const [k, v] of Object.entries(raw).slice(0, 10)) {
        if (/^[a-zA-Z0-9_]{1,30}$/.test(k) && ['string', 'number', 'boolean'].includes(typeof v)) {
          props[k] = typeof v === 'string' ? v.slice(0, 100) : v;
        }
      }
    }
    const saved = await track(name, {
      userId: req.user?.id ?? null,
      deviceId,
      // Instalação: canal do link de entrada; os demais herdam o da conta.
      channel: name === 'install' ? cleanChannel(req.body?.channel) : null,
      props,
    });
    res.json({ saved });
  }));

  async function ensureCode(userId) {
    for (let i = 0; i < 5; i++) {
      try {
        const { rows } = await pool.query(
          `update users set referral_code = coalesce(referral_code, $2) where id = $1
           returning referral_code`,
          [userId, newCode()],
        );
        return rows[0].referral_code;
      } catch (e) {
        if (e.code !== '23505') throw e;
      }
    }
    throw new HttpError(500, 'Não foi possível gerar o código de convite');
  }

  app.get('/referral', authed, wrap(async (req, res) => {
    const code = await ensureCode(req.user.id);
    const { rows } = await pool.query(
      `select status, count(*)::int n from referrals where referrer_id = $1 group by status`,
      [req.user.id],
    );
    const by = Object.fromEntries(rows.map((r) => [r.status, r.n]));
    const { rows: u } = await pool.query('select bonus_until from users where id = $1', [req.user.id]);
    res.json({
      code,
      invited: (by.pending ?? 0) + (by.rewarded ?? 0) + (by.rejected ?? 0),
      pending: by.pending ?? 0,
      rewarded: by.rewarded ?? 0,
      bonusUntil: u[0].bonus_until ? new Date(u[0].bonus_until).toISOString() : null,
      rewardDays: REFERRAL.rewardDays,
      friendDays: REFERRAL.friendDays,
      maxRewardsPerYear: REFERRAL.maxRewardsPerYear,
    });
  }));

  /// Convite válido? (tela de cadastro mostra "convite de Fulano").
  app.get('/referral/:code', wrap(async (req, res) => {
    const code = cleanCode(req.params.code);
    const { rows } = code
      ? await pool.query('select name from users where referral_code = $1', [code])
      : { rows: [] };
    if (!rows.length) throw new HttpError(404, 'Convite não encontrado');
    res.json({ valid: true, name: String(rows[0].name).split(/\s+/)[0], friendDays: REFERRAL.friendDays });
  }));

  // Painel do negócio (administradores) --------------------------------------

  app.get('/admin/spend', admin, wrap(async (req, res) => {
    const { rows } = await pool.query(
      'select month, channel, amount_cents from marketing_spend order by month desc, channel',
    );
    res.json({
      spend: rows.map((r) => ({ month: r.month, channel: r.channel, amountCents: Number(r.amount_cents) })),
    });
  }));

  /// Investimento em divulgação de um canal no mês (0 apaga).
  app.post('/admin/spend', admin, wrap(async (req, res) => {
    const month = String(req.body?.month ?? '');
    const channel = cleanChannel(req.body?.channel);
    const amount = Math.round(Number(req.body?.amountCents));
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw new HttpError(400, 'Mês inválido (AAAA-MM)');
    if (!channel) throw new HttpError(400, 'Informe o canal');
    if (!Number.isFinite(amount) || amount < 0) throw new HttpError(400, 'Valor inválido');
    if (amount === 0) {
      await pool.query('delete from marketing_spend where month = $1 and channel = $2', [month, channel]);
    } else {
      await pool.query(
        `insert into marketing_spend (month, channel, amount_cents) values ($1, $2, $3)
         on conflict (month, channel) do update set amount_cents = excluded.amount_cents`,
        [month, channel, amount],
      );
    }
    res.status(204).end();
  }));

  app.get('/admin/metrics', admin, wrap(async (req, res) => {
    res.json(await metrics({
      days: Math.min(Math.max(Number(req.query.days) || 30, 1), 366),
      months: Math.min(Math.max(Number(req.query.months) || 6, 1), 24),
    }));
  }));

  async function metrics({ days = 30, months = 6, now = new Date() } = {}) {
    const since = new Date(now.getTime() - days * 864e5);
    const monthList = lastMonths(months, now);
    const firstMonth = `${monthList[0]}-01`;

    // Assinantes agora e MRR (preço do plano; cortesias e admins fora).
    const { rows: base } = await pool.query(
      `select
         count(*) filter (where not is_admin and not free_access)::int as customers,
         count(*) filter (where not is_admin and not free_access and paid_until > $1 and plan = 'premium')::int as premium,
         count(*) filter (where not is_admin and not free_access and paid_until > $1 and coalesce(plan, '') <> 'premium')::int as basico,
         count(*) filter (where not is_admin and not free_access and (paid_until is null or paid_until <= $1) and trial_ends_at > $1)::int as trial,
         count(*) filter (where not is_admin and not free_access and (paid_until is null or paid_until <= $1) and trial_ends_at <= $1 and bonus_until > $1)::int as bonus,
         count(*) filter (where is_admin or free_access)::int as courtesy
       from users`,
      [now],
    );
    const b = base[0];
    const paying = b.premium + b.basico;
    const mrrCents = b.premium * price.premium + b.basico * price.basico;
    const gratis = b.customers - paying - b.trial - b.bonus;

    // Funil do período (pessoas/aparelhos distintos).
    const { rows: funnelRows } = await pool.query(
      `select name, count(distinct coalesce(user_id::text, device_id, id::text))::int n
       from funnel_events where created_at >= $1 group by name`,
      [since],
    );
    const fc = Object.fromEntries(funnelRows.map((r) => [r.name, r.n]));
    const funnel = FUNNEL.map(([name, label], i) => {
      const count = fc[name] ?? 0;
      const prev = i > 0 && i <= 5 ? fc[FUNNEL[i - 1][0]] ?? 0 : null;
      return { name, label, count, fromPrevious: prev == null ? null : pct(count, prev) };
    });

    // Conversão do teste: quem terminou o teste no período e pagou.
    const { rows: conv } = await pool.query(
      `select count(*)::int ended,
         count(*) filter (where exists (
           select 1 from funnel_events e where e.user_id = u.id and e.name = 'first_charge'))::int converted
       from users u
       where not is_admin and not free_access and trial_ends_at between $1 and $2`,
      [since, now],
    );

    // Cancelamentos no período sobre os assinantes do início do período.
    const { rows: churnRows } = await pool.query(
      `select
         count(distinct user_id) filter (where name = 'cancellation')::int canceled,
         count(distinct user_id) filter (where name = 'expiration')::int expired
       from funnel_events where created_at >= $1`,
      [since],
    );
    const { rows: startRows } = await pool.query(
      `select count(distinct user_id)::int n from funnel_events
       where name in ('first_charge', 'renewal') and created_at < $1
         and created_at >= $1::timestamptz - interval '35 days'`,
      [since],
    );

    // Mês a mês: cadastros, 1ªs cobranças, receita e investimento.
    const { rows: monthly } = await pool.query(
      `select to_char(created_at at time zone 'UTC', 'YYYY-MM') m,
         count(*) filter (where name = 'signup')::int signups,
         count(*) filter (where name = 'first_charge')::int first_charges,
         count(*) filter (where name = 'cancellation')::int cancellations,
         coalesce(sum((props->>'amountCents')::bigint) filter (where name in ('first_charge', 'renewal')), 0)::bigint revenue
       from funnel_events where created_at >= $1 group by 1`,
      [firstMonth],
    );
    const { rows: spendRows } = await pool.query(
      'select month, channel, amount_cents from marketing_spend where month >= $1',
      [monthList[0]],
    );
    const spendByMonth = {};
    for (const s of spendRows) spendByMonth[s.month] = (spendByMonth[s.month] ?? 0) + Number(s.amount_cents);
    const byMonth = Object.fromEntries(monthly.map((r) => [r.m, r]));
    const monthsOut = monthList.map((m) => {
      const r = byMonth[m] ?? {};
      const spend = spendByMonth[m] ?? 0;
      const fcN = r.first_charges ?? 0;
      return {
        month: m,
        signups: r.signups ?? 0,
        firstCharges: fcN,
        cancellations: r.cancellations ?? 0,
        revenueCents: Number(r.revenue ?? 0),
        spendCents: spend,
        cacCents: fcN > 0 && spend > 0 ? Math.round(spend / fcN) : null,
      };
    });

    // Por canal, nos meses do painel.
    const { rows: chRows } = await pool.query(
      `select coalesce(channel, 'organico') ch,
         count(distinct coalesce(user_id::text, device_id)) filter (where name = 'install')::int installs,
         count(*) filter (where name = 'signup')::int signups,
         count(*) filter (where name = 'first_charge')::int paying,
         coalesce(sum((props->>'amountCents')::bigint) filter (where name in ('first_charge', 'renewal')), 0)::bigint revenue
       from funnel_events where created_at >= $1 group by 1`,
      [firstMonth],
    );
    const spendByChannel = {};
    for (const s of spendRows) spendByChannel[s.channel] = (spendByChannel[s.channel] ?? 0) + Number(s.amount_cents);
    const channelNames = new Set([...chRows.map((r) => r.ch), ...Object.keys(spendByChannel)]);
    const chBy = Object.fromEntries(chRows.map((r) => [r.ch, r]));
    const channels = [...channelNames].map((ch) => {
      const r = chBy[ch] ?? {};
      const spend = spendByChannel[ch] ?? 0;
      const payingN = r.paying ?? 0;
      return {
        channel: ch,
        installs: r.installs ?? 0,
        signups: r.signups ?? 0,
        paying: payingN,
        conversion: pct(payingN, r.signups ?? 0),
        revenueCents: Number(r.revenue ?? 0),
        spendCents: spend,
        cacCents: payingN > 0 && spend > 0 ? Math.round(spend / payingN) : null,
      };
    }).sort((a, b2) => b2.revenueCents - a.revenueCents || b2.signups - a.signups);

    // Retenção por safra de cadastro: % com uso no mês 0..5 depois.
    const { rows: cohortRows } = await pool.query(
      `with c as (
         select id, date_trunc('month', created_at at time zone 'UTC') m from users
         where not is_admin and created_at >= $1
       ), a as (
         select distinct user_id, date_trunc('month', created_at at time zone 'UTC') m
         from funnel_events where name = 'active' and user_id is not null
       )
       select to_char(c.m, 'YYYY-MM') cohort, k,
         count(distinct c.id)::int size,
         count(distinct a.user_id)::int active
       from c cross join generate_series(0, 5) k
       left join a on a.user_id = c.id and a.m = c.m + make_interval(months => k)
       group by c.m, k order by c.m, k`,
      [firstMonth],
    );
    const cohorts = [];
    for (const r of cohortRows) {
      let c = cohorts.find((x) => x.month === r.cohort);
      if (!c) cohorts.push((c = { month: r.cohort, size: r.size, retention: [] }));
      const end = new Date(`${r.cohort}-01T00:00:00Z`);
      end.setUTCMonth(end.getUTCMonth() + r.k);
      c.retention.push(end > now ? null : pct(r.active, r.size));
    }

    const { rows: refRows } = await pool.query(
      'select status, count(*)::int n from referrals group by status',
    );
    const refs = Object.fromEntries(refRows.map((r) => [r.status, r.n]));

    const totalSpend = Object.values(spendByChannel).reduce((a, x) => a + x, 0);
    const totalFirst = monthsOut.reduce((a, x) => a + x.firstCharges, 0);
    return {
      generatedAt: now.toISOString(),
      periodDays: days,
      prices: price,
      kpis: {
        mrrCents,
        arpuCents: paying ? Math.round(mrrCents / paying) : null,
        paying,
        premium: b.premium,
        basico: b.basico,
        trial: b.trial,
        bonus: b.bonus,
        gratis,
        courtesy: b.courtesy,
        trialConversion: pct(conv[0].converted, conv[0].ended),
        trialsEnded: conv[0].ended,
        churn: pct(churnRows[0].canceled, startRows[0].n),
        cancellations: churnRows[0].canceled,
        expirations: churnRows[0].expired,
        cacCents: totalFirst > 0 && totalSpend > 0 ? Math.round(totalSpend / totalFirst) : null,
        spendCents: totalSpend,
      },
      funnel,
      months: monthsOut,
      channels,
      cohorts,
      referrals: {
        pending: refs.pending ?? 0,
        rewarded: refs.rewarded ?? 0,
        rejected: refs.rejected ?? 0,
      },
    };
  }

  return { track, onSignup, storeEvent, rewardReferral, metrics };
}

module.exports = {
  mountGrowth,
  cleanChannel,
  canonicalEmail,
  storeEventName,
  amountOf,
  REFERRAL,
  FUNNEL,
  SERVER_EVENTS,
};
