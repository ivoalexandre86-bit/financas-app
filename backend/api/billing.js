// Assinatura: teste grátis de 30 dias contado no servidor e plano pago
// comprado nas lojas (App Store / Google Play) pelo RevenueCat.
//
// O app identifica o comprador no RevenueCat pelo id do usuário; o servidor
// lê as permissões ("entitlements") pela API do RevenueCat ou pelo webhook.

const crypto = require('crypto');

const PREMIUM = 'premium';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const iso = (d) => (d ? new Date(d).toISOString() : null);

/**
 * Situação de acesso de um usuário (linha de `users`).
 * admin: dono do servidor · free: cortesia (conta criada pelo administrador)
 * · active: assinatura paga em dia · trial: teste grátis · expired: vencido.
 */
function accessOf(u, now = new Date()) {
  const paid = !!u.paid_until && new Date(u.paid_until) > now;
  const trial = !!u.trial_ends_at && new Date(u.trial_ends_at) > now;
  const status = u.is_admin
    ? 'admin'
    : u.free_access
      ? 'free'
      : paid
        ? 'active'
        : trial
          ? 'trial'
          : 'expired';
  return {
    status,
    trialEndsAt: iso(u.trial_ends_at),
    paidUntil: iso(u.paid_until),
    premium: status === 'admin' || status === 'free' || (paid && u.plan === PREMIUM),
  };
}

/// Permissões do RevenueCat → validade da assinatura e plano.
function fromEntitlements(entitlements = {}, now = new Date()) {
  let paidUntil = null;
  let premium = false;
  for (const [id, e] of Object.entries(entitlements)) {
    // Sem data de validade = vitalícia.
    const exp = e?.expires_date ? new Date(e.expires_date) : new Date('9999-12-31T00:00:00Z');
    if (!paidUntil || exp > paidUntil) paidUntil = exp;
    if (id === PREMIUM && exp > now) premium = true;
  }
  return { paidUntil, plan: paidUntil ? (premium ? PREMIUM : 'basico') : null };
}

/** Cliente mínimo da API REST do RevenueCat (chave secreta, só no servidor). */
function createRevenueCat({ secretKey, fetchImpl = fetch }) {
  return {
    async entitlements(appUserId) {
      const res = await fetchImpl(
        `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
        { headers: { authorization: `Bearer ${secretKey}`, accept: 'application/json' } },
      );
      if (!res.ok) throw new Error(`RevenueCat ${res.status}`);
      const body = await res.json();
      return body?.subscriber?.entitlements ?? {};
    },
  };
}

function sameSecret(a, b) {
  const x = Buffer.from(String(a ?? ''));
  const y = Buffer.from(String(b ?? ''));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

/**
 * @param {import('express').Express} app
 * @param {{pool: import('pg').Pool, authed: Function, wrap: Function,
 *   HttpError: Function, revenuecat?: ReturnType<typeof createRevenueCat>|null,
 *   webhookAuth?: string}} deps
 */
function mountBilling(app, { pool, authed, wrap, HttpError, revenuecat, webhookAuth }) {
  async function save(userId, { paidUntil, plan }) {
    const { rows } = await pool.query(
      `update users set paid_until = $2, plan = $3 where id = $1 returning *`,
      [userId, paidUntil, plan],
    );
    return rows[0];
  }

  /// O app chama depois de comprar ou restaurar: confere no RevenueCat.
  app.post('/billing/refresh', authed, wrap(async (req, res) => {
    let user = req.user;
    if (revenuecat) {
      try {
        user = await save(user.id, fromEntitlements(await revenuecat.entitlements(user.id)));
      } catch (e) {
        console.error('Assinatura: falha ao consultar o RevenueCat', e);
        throw new HttpError(502, 'Não foi possível confirmar a assinatura agora.');
      }
    }
    res.json({ access: accessOf(user) });
  }));

  /// Webhook do RevenueCat (compra, renovação, cancelamento, vencimento).
  /// No painel, o cabeçalho Authorization deve ter o valor de
  /// REVENUECAT_WEBHOOK_AUTH.
  app.post('/billing/revenuecat', wrap(async (req, res) => {
    if (!webhookAuth || !sameSecret(req.get('authorization'), webhookAuth)) {
      throw new HttpError(401, 'Não autorizado');
    }
    const ev = req.body?.event ?? {};
    const ids = [ev.app_user_id, ...(ev.aliases ?? [])].filter((id) => UUID.test(String(id)));
    for (const id of new Set(ids)) {
      const { rows } = await pool.query('select id from users where id = $1', [id]);
      if (!rows.length) continue;
      if (revenuecat) {
        await save(id, fromEntitlements(await revenuecat.entitlements(id)));
      } else if (ev.expiration_at_ms) {
        const paidUntil = new Date(Number(ev.expiration_at_ms));
        const premium = (ev.entitlement_ids ?? []).includes(PREMIUM);
        await save(id, { paidUntil, plan: premium ? PREMIUM : 'basico' });
      }
    }
    res.json({ ok: true });
  }));

  /// Bloqueia gravações de quem está com a assinatura vencida.
  const active = (req, res, next) =>
    authed(req, res, (err) => {
      if (err) return next(err);
      if (accessOf(req.user).status === 'expired') {
        return next(new HttpError(402, 'Sua assinatura venceu. Assine para voltar a lançar.'));
      }
      next();
    });

  /// Recursos do plano Premium (Open Finance).
  const premium = (req, res, next) =>
    authed(req, res, (err) => {
      if (err) return next(err);
      if (!accessOf(req.user).premium) {
        return next(new HttpError(402, 'O Open Finance faz parte do plano Premium.'));
      }
      next();
    });

  return { active, premium };
}

module.exports = { accessOf, fromEntitlements, createRevenueCat, mountBilling, PREMIUM };
