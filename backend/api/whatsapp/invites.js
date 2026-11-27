// Convite pelo WhatsApp: o administrador informa o nome e o número de uma
// pessoa; o bot manda uma mensagem dizendo que ela foi selecionada para
// participar do sistema, com o botão "Fazer cadastro" (link do app com o
// código do convite).
//
// Mensagem que a empresa inicia fora da janela de 24 h só sai por um modelo
// aprovado na Meta. O servidor cria o modelo sozinho (uma vez) e, enquanto a
// Meta não aprova, o app oferece enviar o mesmo texto pelo WhatsApp do
// próprio administrador (link wa.me).
//
// Ao criar a conta pelo link: o número já fica ligado ao bot, a conta não
// paga (como as criadas pelo administrador) e, se o convite pedir, a pessoa
// entra na conta (orçamento) de quem convidou.

const crypto = require('crypto');
const { phoneKey } = require('./ledger');
const { MAX_MEMBERS, normScope } = require('../account');

const INVITE_DAYS = 7;
const DAILY_LIMIT = 30;
const DEFAULT_TEMPLATE = 'convite_financas';
const DEFAULT_APP_URL = 'https://ivoalexandre86-bit.github.io/financas-app/';
const STATUS_TTL_MS = 10 * 60 * 1000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const firstName = (n) => String(n ?? '').trim().split(/\s+/)[0] || '';

/// Número com DDI (só dígitos). Sem "+" e com 10 ou 11 dígitos (DDD +
/// número), vale o Brasil.
function normalizePhone(raw) {
  const s = String(raw ?? '').trim();
  let d = s.replace(/\D/g, '');
  const intl = s.startsWith('+') || d.startsWith('00');
  if (d.startsWith('00')) d = d.slice(2);
  if (!intl && (d.length === 10 || d.length === 11)) d = `55${d}`;
  if (d.startsWith('55') && d.length !== 12 && d.length !== 13) return null;
  return d.length >= 11 && d.length <= 15 ? d : null;
}

/// +55 (47) 99189-2931
function formatPhone(d) {
  const m = /^55(\d{2})(\d{4,5})(\d{4})$/.exec(d ?? '');
  return m ? `+55 (${m[1]}) ${m[2]}-${m[3]}` : `+${d}`;
}

/// Link do app que abre o cadastro com o convite.
const signupLink = (appUrl, token) => `${appUrl}?cadastro=${encodeURIComponent(token)}`;

/// Texto do convite (o mesmo do modelo da Meta), para envio manual.
function inviteText({ name, inviter, link }) {
  return (
    `Olá, ${firstName(name)}! Você foi selecionado(a) por ${firstName(inviter)} para participar ` +
    `do Finanças, o sistema de gestão financeira. Para criar a sua conta, acesse: ${link}\n\n` +
    `O convite vale por ${INVITE_DAYS} dias.`
  );
}

/// Modelo enviado para a análise da Meta (botão com link dinâmico).
function templateDefinition(name, appUrl) {
  return {
    name,
    language: 'pt_BR',
    category: 'MARKETING',
    components: [
      {
        type: 'BODY',
        text:
          'Olá, {{1}}! Você foi selecionado(a) por {{2}} para participar do Finanças, ' +
          'o sistema de gestão financeira. Toque em Fazer cadastro para criar a sua conta. ' +
          `O convite vale por ${INVITE_DAYS} dias.`,
        example: { body_text: [['Ana', 'Ivo']] },
      },
      { type: 'FOOTER', text: 'Se não conhece quem enviou, ignore esta mensagem.' },
      {
        type: 'BUTTONS',
        buttons: [
          {
            type: 'URL',
            text: 'Fazer cadastro',
            url: `${appUrl}?cadastro={{1}}`,
            example: [`${appUrl}?cadastro=Xy12AbCd34`],
          },
        ],
      },
    ],
  };
}

/**
 * @param {import('express').Express} app
 * @param {{pool: import('pg').Pool, authed: Function, wrap: Function,
 *   HttpError: any, getMeta: () => any, template?: string, appUrl?: string}} deps
 */
function mountInvites(app, { pool, authed, wrap, HttpError, getMeta, template, appUrl }) {
  const templateName = template || DEFAULT_TEMPLATE;
  const baseUrl = (appUrl || DEFAULT_APP_URL).replace(/\/?$/, '/');
  const bad = (msg) => new HttpError(400, msg);

  // Situação do modelo na Meta (em cache) e criação automática, uma vez.
  let cached = null; // {at, value}
  let creating = null;
  async function templateState() {
    const meta = getMeta();
    if (!meta?.templateStatus) return { name: templateName, status: meta ? 'UNKNOWN' : 'OFF' };
    if (cached && Date.now() - cached.at < STATUS_TTL_MS && cached.value.status !== 'PENDING') {
      return cached.value;
    }
    let value;
    try {
      const t = await meta.templateStatus(templateName);
      if (t) {
        value = { name: templateName, status: t.status, rejectedReason: t.rejectedReason };
      } else {
        creating ??= meta
          .createTemplate(templateDefinition(templateName, baseUrl))
          .then(() => console.log(`WhatsApp: modelo ${templateName} enviado para a análise da Meta`))
          .catch((e) => {
            console.error(`WhatsApp: falha ao criar o modelo ${templateName}`, e);
            creating = null;
            throw e;
          });
        await creating.catch(() => {});
        value = { name: templateName, status: creating ? 'PENDING' : 'MISSING' };
      }
    } catch (e) {
      console.error('WhatsApp: falha ao consultar o modelo de convite', e);
      value = { name: templateName, status: 'UNKNOWN' };
    }
    cached = { at: Date.now(), value };
    return value;
  }

  const requireAdmin = (req) => {
    if (!req.user.is_admin) throw new HttpError(403, 'Somente administradores convidam pessoas');
  };

  const toInvite = (r) => {
    const link = signupLink(baseUrl, r.token);
    const expired = r.status === 'pending' && new Date(r.expires_at) <= new Date();
    return {
      id: r.id,
      name: r.name,
      phone: r.phone,
      phoneLabel: formatPhone(r.phone),
      joinAccount: r.join_account,
      // Acesso limitado ao orçamento (null = tudo) e o vínculo atual na
      // conta, para editar depois.
      scope: r.member_id ? r.member_scope ?? null : r.scope ?? null,
      memberId: r.member_id ?? null,
      status: expired ? 'expired' : r.status,
      sendStatus: r.send_status,
      sendError: r.send_error,
      invitedBy: r.inviter_name ?? null,
      userName: r.user_name ?? null,
      createdAt: r.created_at,
      sentAt: r.sent_at,
      expiresAt: r.expires_at,
      acceptedAt: r.accepted_at,
      link,
      // Envio pelo WhatsApp do próprio administrador (sem o bot).
      shareUrl: `https://wa.me/${r.phone}?text=${encodeURIComponent(
        inviteText({ name: r.name, inviter: r.inviter_name, link }),
      )}`,
    };
  };

  async function load(id) {
    const { rows } = await pool.query(
      `select i.*, u.name as inviter_name, n.name as user_name,
              m.id as member_id, m.scope as member_scope
         from user_invites i
         join users u on u.id = i.invited_by
         left join users n on n.id = i.user_id
         left join account_members m
           on m.account_id = i.invited_by and m.user_id = i.user_id and m.status = 'active'
        where i.id = $1`,
      [id],
    );
    return rows[0] ?? null;
  }

  /// Manda o modelo aprovado; sem aprovação, fica "not_sent" (envio manual).
  async function send(inv) {
    const meta = getMeta();
    const tpl = await templateState();
    let out = { send_status: 'not_sent', send_error: null, wa_id: null, wa_message_id: null, sent: false };
    if (meta && tpl.status === 'APPROVED') {
      try {
        const res = await meta.sendTemplateComponents(inv.phone, templateName, [
          {
            type: 'body',
            parameters: [
              { type: 'text', text: firstName(inv.name) },
              { type: 'text', text: firstName(inv.inviter_name) },
            ],
          },
          {
            type: 'button',
            sub_type: 'url',
            index: '0',
            parameters: [{ type: 'text', text: inv.token }],
          },
        ]);
        out = {
          send_status: 'sent',
          send_error: null,
          wa_id: res?.contacts?.[0]?.wa_id ?? null,
          wa_message_id: res?.messages?.[0]?.id ?? null,
          sent: true,
        };
      } catch (e) {
        console.error('WhatsApp: falha ao enviar o convite', e);
        out.send_status = 'failed';
        out.send_error = String(e.message ?? e).slice(0, 300);
      }
    } else if (!meta) {
      out.send_error = 'O bot do WhatsApp está desligado no servidor.';
    } else if (tpl.status === 'REJECTED') {
      out.send_error = 'A Meta recusou o modelo da mensagem de convite.';
    } else {
      out.send_error = 'O modelo da mensagem está em análise na Meta.';
    }
    await pool.query(
      `update user_invites
          set send_status = $2, send_error = $3,
              wa_id = coalesce($4, wa_id), wa_message_id = coalesce($5, wa_message_id),
              sent_at = case when $6 then now() else sent_at end
        where id = $1`,
      [inv.id, out.send_status, out.send_error, out.wa_id, out.wa_message_id, out.sent],
    );
  }

  // Administrador -------------------------------------------------------------

  app.get('/invites', authed, wrap(async (req, res) => {
    requireAdmin(req);
    const { rows } = await pool.query(
      `select i.*, u.name as inviter_name, n.name as user_name,
              m.id as member_id, m.scope as member_scope
         from user_invites i
         join users u on u.id = i.invited_by
         left join users n on n.id = i.user_id
         left join account_members m
           on m.account_id = i.invited_by and m.user_id = i.user_id and m.status = 'active'
        order by i.created_at desc
        limit 200`,
    );
    res.json({ invites: rows.map(toInvite), template: await templateState(), days: INVITE_DAYS });
  }));

  app.post('/invites', authed, wrap(async (req, res) => {
    requireAdmin(req);
    const name = String(req.body?.name ?? '').trim().slice(0, 80);
    if (!name) throw bad('Informe o nome da pessoa');
    const phone = normalizePhone(req.body?.phone);
    if (!phone) throw bad('Número inválido. Use DDD + número, ex.: (47) 99999-1234');
    const joinAccount = req.body?.joinAccount === true;
    let scope = null;
    try {
      if (joinAccount) scope = normScope(req.body?.scope);
    } catch (e) {
      throw bad(e.message);
    }
    const key = phoneKey(phone);

    const linked = await pool.query('select wa_id from whatsapp_links');
    if (linked.rows.some((r) => phoneKey(r.wa_id) === key)) {
      throw new HttpError(409, 'Este número já está ligado a uma conta do app.');
    }
    const today = await pool.query(
      `select count(*)::int as n from user_invites
        where invited_by = $1 and created_at > now() - interval '1 day'`,
      [req.user.id],
    );
    if (today.rows[0].n >= DAILY_LIMIT) {
      throw new HttpError(429, `Limite de ${DAILY_LIMIT} convites por dia.`);
    }
    // Convite em aberto para o mesmo número: troca pelo novo.
    const open = await pool.query(`select id, phone from user_invites where status = 'pending'`);
    const old = open.rows.filter((r) => phoneKey(r.phone) === key).map((r) => r.id);
    if (old.length) await pool.query('delete from user_invites where id = any($1)', [old]);

    const token = crypto.randomBytes(12).toString('base64url');
    const { rows } = await pool.query(
      `insert into user_invites (token, phone, name, invited_by, join_account, scope, expires_at)
       values ($1, $2, $3, $4, $5, $6, now() + interval '${INVITE_DAYS} days') returning id`,
      [token, phone, name, req.user.id, joinAccount, scope ? JSON.stringify(scope) : null],
    );
    const inv = await load(rows[0].id);
    await send(inv);
    res.status(201).json({ invite: toInvite(await load(inv.id)), template: await templateState() });
  }));

  app.post('/invites/:id/resend', authed, wrap(async (req, res) => {
    requireAdmin(req);
    if (!UUID_RE.test(req.params.id)) throw new HttpError(404, 'Convite não encontrado');
    const { rows } = await pool.query(
      `update user_invites set expires_at = now() + interval '${INVITE_DAYS} days'
        where id = $1 and status = 'pending' returning id`,
      [req.params.id],
    );
    if (!rows.length) throw new HttpError(404, 'Convite não encontrado');
    await send(await load(req.params.id));
    res.json({ invite: toInvite(await load(req.params.id)), template: await templateState() });
  }));

  app.delete('/invites/:id', authed, wrap(async (req, res) => {
    requireAdmin(req);
    if (!UUID_RE.test(req.params.id)) throw new HttpError(404, 'Convite não encontrado');
    const { rowCount } = await pool.query(
      `delete from user_invites where id = $1 and status = 'pending'`,
      [req.params.id],
    );
    if (!rowCount) throw new HttpError(404, 'Convite não encontrado');
    res.status(204).end();
  }));

  // Quem recebeu o convite ------------------------------------------------------

  /// Dados do convite para a tela de cadastro (sem login).
  app.get('/auth/invites/:token', wrap(async (req, res) => {
    const { rows } = await pool.query(
      `select i.name, i.join_account, i.scope, i.expires_at, u.name as inviter_name
         from user_invites i join users u on u.id = i.invited_by
        where i.token = $1 and i.status = 'pending' and i.expires_at > now()`,
      [String(req.params.token ?? '')],
    );
    if (!rows.length) throw new HttpError(404, 'Convite inválido ou vencido. Peça um novo a quem convidou.');
    const r = rows[0];
    res.json({
      name: r.name,
      inviterName: r.inviter_name,
      joinAccount: r.join_account,
      limited: !!r.scope,
      expiresAt: r.expires_at,
    });
  }));

  /**
   * Cadastro pelo link do convite (dentro da transação do cadastro).
   * Retorna o convite usado ou null (inválido/vencido).
   */
  async function acceptOnSignup(c, token, user) {
    if (!token) return null;
    const { rows } = await c.query(
      `select * from user_invites
        where token = $1 and status = 'pending' and expires_at > now()
        for update`,
      [String(token)],
    );
    const inv = rows[0];
    if (!inv) return null;
    await c.query(
      `update user_invites set status = 'accepted', user_id = $2, accepted_at = now() where id = $1`,
      [inv.id, user.id],
    );
    // O número convidado já fica ligado ao bot (se ninguém o usa).
    await c.query(
      `insert into whatsapp_links (wa_id, user_id) values ($1, $2) on conflict do nothing`,
      [inv.wa_id ?? inv.phone, user.id],
    );
    if (inv.join_account) {
      const ok = await c.query(
        `select
           (select count(*) from account_members where account_id = $1)::int as members,
           exists (select 1 from account_members where user_id = $1 and status = 'active') as elsewhere`,
        [inv.invited_by],
      );
      const { members, elsewhere } = ok.rows[0];
      if (!elsewhere && members < MAX_MEMBERS) {
        await c.query(
          `insert into account_members (account_id, email, user_id, status, invited_by, accepted_at, scope)
           values ($1, $2, $3, 'active', $1, now(), $4)
           on conflict (account_id, email) do update
             set user_id = excluded.user_id, status = 'active', accepted_at = now(),
                 scope = excluded.scope`,
          [inv.invited_by, user.email, user.id, inv.scope ? JSON.stringify(inv.scope) : null],
        );
      }
    }
    return inv;
  }

  /// Convite em aberto para este número (quem convidou + link), ou null.
  async function pendingFor(from) {
    const key = phoneKey(from);
    if (!key) return null;
    const { rows } = await pool.query(
      `select i.*, u.name as inviter_name from user_invites i join users u on u.id = i.invited_by
        where i.status = 'pending' and i.expires_at > now()
        order by i.created_at desc`,
    );
    const inv = rows.find((r) => (r.wa_id && r.wa_id === String(from)) || phoneKey(r.phone) === key);
    return inv ? { ...inv, link: signupLink(baseUrl, inv.token) } : null;
  }

  /// Entrega/leitura/falha da mensagem do convite (webhook da Meta).
  async function onStatus(st) {
    if (!st?.id || !['delivered', 'read', 'failed'].includes(st.status)) return;
    const err = st.status === 'failed'
      ? String(st.errors?.[0]?.title ?? st.errors?.[0]?.message ?? 'Falha na entrega').slice(0, 300)
      : null;
    // "read" vale mais que "delivered" (podem chegar fora de ordem).
    await pool.query(
      `update user_invites set send_status = $2, send_error = $3
        where wa_message_id = $1 and not (send_status = 'read' and $2 = 'delivered')`,
      [st.id, st.status, err],
    );
  }

  return { acceptOnSignup, pendingFor, onStatus, templateState };
}

module.exports = { mountInvites, normalizePhone, formatPhone, inviteText, templateDefinition };
