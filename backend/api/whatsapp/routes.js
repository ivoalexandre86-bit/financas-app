// Lançamentos pelo WhatsApp: vínculo do número com a conta do app e o
// webhook que recebe as mensagens da Meta.
//
// Fluxo: mensagem (texto, foto, PDF ou áudio) → IA monta um rascunho →
// bot responde com o resumo e os botões Confirmar / Corrigir / Cancelar →
// "Confirmar" grava o lançamento em app_docs, como se fosse o app.

const crypto = require('crypto');
const { validSignature } = require('./meta');
const {
  buildContext,
  normalizeDraft,
  buildDocs,
  formatSummary,
  todayIso,
} = require('./ledger');
const {
  computeSummary,
  formatMonthSummary,
  parseSummaryRequest,
  invoiceDue,
  invoiceForTx,
} = require('./summary');
const { brl } = require('./ledger');
const { allocate: allocateLine } = require('../shared/allocation');
const { accessOf } = require('../billing');
const { createReminderJob } = require('./reminders');

const CODE_MINUTES = 10;
/** Leituras da IA por mês por usuário (administradores não têm limite). */
const MONTHLY_LIMIT = 300;
/** No plano Grátis: poucas leituras e só por texto. */
const FREE_MONTHLY_LIMIT = 5;
const EDIT_WINDOW = "interval '1 hour'";

const HELP =
  'Mande um gasto ou recebimento e eu lanço no app. Pode ser texto, foto do cupom/comprovante ou áudio.\n\n' +
  'Exemplos:\n• gastei 45,90 no mercado\n• uber 23 ontem no cartão Nubank\n• tênis 600 em 3x no cartão\n• recebi 3500 de salário\n\n' +
  'Se você participa de despesas compartilhadas, eu pergunto se o gasto é só seu ou dividido no grupo.\n\n' +
  'Para ver como está o mês, mande *resumo* (ou "resumo mês passado", "resumo novembro").';

/**
 * @param {import('express').Express} app
 * @param {object} deps
 */
function mountWhatsApp(app, { pool, authed, wrap, HttpError, whatsapp, shared }) {
  const cfg = whatsapp?.config ?? {};
  const { extract, transcribe } = whatsapp ?? {};
  const digits = (n) => String(n ?? '').replace(/\D/g, '') || null;

  // Número do bot: o conectado pelo Cadastro incorporado (gravado no banco)
  // vale mais que o das variáveis de ambiente.
  let meta = whatsapp?.meta;
  let botNumber = digits(cfg.botNumber);
  const isEnabled = () => !!meta && !!extract;

  function useStored(row) {
    if (!row?.access_token || !row?.phone_number_id || !whatsapp?.createMeta) return;
    meta = whatsapp.createMeta({ token: row.access_token, phoneNumberId: row.phone_number_id });
    botNumber = digits(row.bot_number) ?? botNumber;
  }
  const loaded = pool
    .query('select * from whatsapp_config where id = 1')
    .then(({ rows }) => {
      useStored(rows[0]);
      if (rows[0] && isEnabled()) console.log(`WhatsApp ativo no número ${botNumber}`);
    })
    .catch((e) => console.error('WhatsApp: falha ao ler a configuração salva', e));

  // Lembretes diários (só no servidor; os testes chamam runOnce direto).
  const reminders = createReminderJob({
    pool,
    getMeta: () => (isEnabled() ? meta : null),
    template: whatsapp?.reminderTemplate,
  });
  app.locals.reminders = reminders;
  if (whatsapp?.startReminders) loaded.then(() => reminders.start());

  // App ----------------------------------------------------------------------

  app.get('/whatsapp/status', authed, wrap(async (req, res) => {
    await loaded;
    const { rows } = await pool.query(
      'select wa_id from whatsapp_links where user_id = $1',
      [req.user.id],
    );
    res.json({
      enabled: isEnabled(),
      botNumber,
      audio: !!whatsapp?.transcribe,
      linkedNumber: rows[0]?.wa_id ?? null,
    });
  }));

  app.post('/whatsapp/link-code', authed, wrap(async (req, res) => {
    await loaded;
    if (!isEnabled()) throw new HttpError(409, 'WhatsApp ainda não está configurado no servidor');
    const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
    const { rows } = await pool.query(
      `insert into whatsapp_link_codes (user_id, code, expires_at)
       values ($1, $2, now() + interval '${CODE_MINUTES} minutes')
       on conflict (user_id) do update
         set code = excluded.code, expires_at = excluded.expires_at
       returning expires_at`,
      [req.user.id, code],
    );
    const text = `VINCULAR ${code}`;
    res.json({
      code,
      text,
      expiresAt: rows[0].expires_at,
      botNumber,
      url: botNumber
        ? `https://wa.me/${botNumber}?text=${encodeURIComponent(text)}`
        : null,
    });
  }));

  app.delete('/whatsapp/link', authed, wrap(async (req, res) => {
    await pool.query('delete from whatsapp_links where user_id = $1', [req.user.id]);
    res.status(204).end();
  }));

  // Cadastro incorporado (Embedded Signup) da Meta: conecta um número que já
  // usa o app WhatsApp Business (coexistência). A página de cadastro manda o
  // código do login da Meta e os ids do número; o servidor troca o código por
  // um token comercial que não expira e passa a usar esse número.
  app.post('/whatsapp/embedded-signup', authed, wrap(async (req, res) => {
    if (!req.user.is_admin) throw new HttpError(403, 'Somente administradores conectam o número do bot');
    if (!whatsapp?.signup) throw new HttpError(409, 'Cadastro pela Meta não está configurado no servidor');
    const code = String(req.body?.code ?? '');
    const phoneNumberId = digits(req.body?.phoneNumberId);
    const wabaId = digits(req.body?.wabaId);
    if (!code || !wabaId) {
      throw new HttpError(400, 'Faltam o código da Meta ou a conta do WhatsApp Business');
    }
    let out;
    try {
      out = await whatsapp.signup({ code, phoneNumberId, wabaId });
    } catch (e) {
      console.error('WhatsApp: cadastro incorporado falhou', e);
      throw new HttpError(502, 'A Meta recusou o cadastro. Tente de novo.');
    }
    const row = {
      access_token: out.token,
      phone_number_id: digits(out.phoneNumberId) ?? phoneNumberId,
      waba_id: wabaId,
      bot_number: digits(out.botNumber),
    };
    await pool.query(
      `insert into whatsapp_config (id, access_token, phone_number_id, waba_id, bot_number)
       values (1, $1, $2, $3, $4)
       on conflict (id) do update set access_token = excluded.access_token,
         phone_number_id = excluded.phone_number_id, waba_id = excluded.waba_id,
         bot_number = excluded.bot_number, updated_at = now()`,
      [row.access_token, row.phone_number_id, row.waba_id, row.bot_number],
    );
    await loaded;
    useStored(row);
    console.log(`WhatsApp: número ${botNumber} conectado pelo cadastro incorporado`);
    res.json({ botNumber, phoneNumberId: row.phone_number_id, wabaId, enabled: isEnabled() });
  }));

  // Webhook da Meta ------------------------------------------------------------

  app.get('/whatsapp/webhook', (req, res) => {
    if (
      cfg.verifyToken &&
      req.query['hub.mode'] === 'subscribe' &&
      req.query['hub.verify_token'] === cfg.verifyToken
    ) {
      return res.type('text/plain').send(String(req.query['hub.challenge'] ?? ''));
    }
    res.sendStatus(403);
  });

  app.post('/whatsapp/webhook', wrap(async (req, res) => {
    await loaded;
    if (!isEnabled()) {
      console.warn('WhatsApp: webhook recebido, mas o bot está desligado');
      return res.sendStatus(401);
    }
    if (!validSignature(req.rawBody, req.get('x-hub-signature-256'), cfg.appSecret)) {
      console.warn('WhatsApp: assinatura inválida no webhook (confira WHATSAPP_APP_SECRET)');
      return res.sendStatus(401);
    }
    // A Meta reenvia se não receber 200 rápido: responde já e processa depois.
    res.sendStatus(200);
    const messages = [];
    for (const entry of req.body?.entry ?? []) {
      for (const change of entry.changes ?? []) {
        for (const m of change.value?.messages ?? []) messages.push(m);
        // Entregas que a Meta não conseguiu fazer (ex.: número fora da lista
        // de teste, janela de 24 h): só aparecem aqui, não na hora do envio.
        for (const st of change.value?.statuses ?? []) {
          if (st.status === 'failed') {
            console.warn(
              `WhatsApp: entrega falhou para ${st.recipient_id}: ${JSON.stringify(st.errors ?? [])}`,
            );
          }
        }
      }
    }
    if (messages.length) console.log(`WhatsApp: ${messages.length} mensagem(ns) recebida(s)`);
    const done = Promise.all(messages.map((m) => handle(m).catch((e) => fail(m, e))));
    whatsapp.onProcessed?.(done);
  }));

  // Processamento ----------------------------------------------------------------

  async function fail(m, err) {
    console.error('WhatsApp: erro ao processar mensagem', err);
    await meta
      .sendText(m.from, 'Não consegui processar essa mensagem agora. Tente de novo em instantes.')
      .catch(() => {});
  }

  async function handle(m) {
    const fresh = await pool.query(
      `insert into whatsapp_seen (message_id) values ($1)
       on conflict do nothing returning message_id`,
      [m.id],
    );
    if (!fresh.rowCount) return; // reentrega da Meta
    const from = String(m.from);

    const text = m.type === 'text' ? String(m.text?.body ?? '').trim() : '';
    const link = /^vincular\s+(\d{6})$/i.exec(text);
    if (link) {
      meta.markRead(m.id);
      return linkNumber(from, link[1]);
    }

    const { rows } = await pool.query(
      `select u.* from whatsapp_links l join users u on u.id = l.user_id
       where l.wa_id = $1`,
      [from],
    );
    const user = rows[0];
    // O número do bot pode ser o mesmo do WhatsApp Business do dono
    // (coexistência): conversas de quem não vinculou ficam intocadas, sem
    // resposta e sem marcar como lidas.
    if (!user) return;
    meta.markRead(m.id);

    if (m.type === 'interactive' && m.interactive?.type === 'button_reply') {
      return onButton(from, user, String(m.interactive.button_reply?.id ?? ''));
    }
    if (m.type === 'interactive' && m.interactive?.type === 'list_reply') {
      return onButton(from, user, String(m.interactive.list_reply?.id ?? ''));
    }
    if (/^cancelar$/i.test(text)) return cancelLatest(from, user);
    if (/^(ajuda|menu|help|oi|olá|ola)$/i.test(text)) {
      return meta.sendText(from, `Olá, ${firstName(user.name)}! ${HELP}`);
    }
    if (text && parseSummaryRequest(text, todayIso())) {
      return sendSummary(from, user, text);
    }

    // Grátis: só texto. Recusa antes de baixar ou transcrever (sem custo) e
    // sem contar no limite do mês.
    if (['image', 'document', 'audio'].includes(m.type) && accessOf(user).plan === 'gratis') {
      return meta.sendText(
        from,
        'No plano Grátis eu leio só mensagens de texto. Fotos, PDFs e áudios fazem parte do ' +
          'plano Básico; assine pelo app. Por enquanto, me mande o gasto por escrito.',
      );
    }

    let input;
    switch (m.type) {
      case 'text':
        input = { text };
        break;
      case 'image':
        input = { text: m.image?.caption, media: await meta.downloadMedia(m.image.id) };
        break;
      case 'document': {
        const media = await meta.downloadMedia(m.document.id);
        if (media.mimeType !== 'application/pdf' && !media.mimeType.startsWith('image/')) {
          return meta.sendText(from, 'Consigo ler fotos e PDFs. Esse tipo de arquivo eu não leio.');
        }
        input = { text: m.document?.caption, media };
        break;
      }
      case 'audio': {
        if (!transcribe) {
          return meta.sendText(from, 'Áudio ainda não está ativado. Mande por texto ou foto, por favor.');
        }
        const said = await transcribe(await meta.downloadMedia(m.audio.id));
        if (!said) return meta.sendText(from, 'Não entendi o áudio. Pode repetir ou escrever?');
        if (parseSummaryRequest(said, todayIso())) return sendSummary(from, user, said);
        input = { text: `(áudio transcrito) ${said}` };
        break;
      }
      default:
        return meta.sendText(from, `Ainda não leio esse tipo de mensagem.\n\n${HELP}`);
    }
    return newOrCorrection(from, user, input);
  }

  async function linkNumber(from, code) {
    const { rows } = await pool.query(
      `delete from whatsapp_link_codes
       where code = $1 and expires_at > now()
       returning user_id`,
      [code],
    );
    if (!rows.length) {
      return meta.sendText(from, 'Código inválido ou vencido. Gere um novo no app em Configurações › WhatsApp.');
    }
    const userId = rows[0].user_id;
    // Um número por conta e uma conta por número: o vínculo novo substitui.
    await pool.query(
      'delete from whatsapp_links where wa_id = $1 or user_id = $2',
      [from, userId],
    );
    await pool.query(
      `insert into whatsapp_links (wa_id, user_id) values ($1, $2)
       on conflict (wa_id) do update set user_id = excluded.user_id`,
      [from, userId],
    );
    const u = await pool.query('select name from users where id = $1', [userId]);
    return meta.sendText(
      from,
      `Pronto, ${firstName(u.rows[0]?.name)}! Este WhatsApp está ligado à sua conta.\n\n${HELP}`,
    );
  }

  async function sendSummary(from, user, text) {
    const today = todayIso();
    const month = parseSummaryRequest(text, today);
    const { rows } = await pool.query(
      `select coll, data from app_docs
       where user_id = $1 and not deleted
         and coll in ('transactions', 'recurringTransactions', 'cards',
                      'categories', 'invoicePayments')`,
      [user.id],
    );
    const docs = {};
    for (const r of rows) (docs[r.coll] ??= []).push(r.data);
    return meta.sendText(from, formatMonthSummary(computeSummary(docs, month, today), today));
  }

  async function loadContext(userId) {
    const { rows } = await pool.query(
      `select coll, data from app_docs
       where user_id = $1 and not deleted
         and coll in ('accounts', 'cards', 'categories')`,
      [userId],
    );
    return buildContext(rows);
  }

  const limitOf = (user) =>
    accessOf(user).plan === 'gratis'
      ? whatsapp?.freeMonthlyLimit ?? FREE_MONTHLY_LIMIT
      : whatsapp?.monthlyLimit ?? MONTHLY_LIMIT;

  /// Conta a leitura do mês; false quando o usuário passou do limite.
  async function withinLimit(user) {
    if (user.is_admin) return true;
    const limit = limitOf(user);
    const { rows } = await pool.query(
      `insert into whatsapp_usage (user_id, month, reads) values ($1, $2, 1)
       on conflict (user_id, month) do update set reads = whatsapp_usage.reads + 1
       returning reads`,
      [user.id, todayIso().slice(0, 7)],
    );
    return rows[0].reads <= limit;
  }

  async function newOrCorrection(from, user, input) {
    if (!(await withinLimit(user))) {
      const limit = limitOf(user);
      if (accessOf(user).plan === 'gratis') {
        return meta.sendText(
          from,
          `Você usou seus ${limit} lançamentos do mês pelo WhatsApp. ` +
            'Assine o Básico pelo app para lançar à vontade; o limite volta no dia 1º.',
        );
      }
      return meta.sendText(
        from,
        `Você chegou ao limite de ${limit} lançamentos pelo WhatsApp neste mês. ` +
          'Pelo app você continua lançando normalmente, e o limite volta no dia 1º.',
      );
    }
    const ctx = await loadContext(user.id);
    const { rows } = await pool.query(
      `select id, draft from whatsapp_drafts
       where user_id = $1 and state = 'editing'
         and updated_at > now() - ${EDIT_WINDOW}
       order by updated_at desc limit 1`,
      [user.id],
    );
    const editing = rows[0];
    const raw = await extract({
      ...input,
      previous: editing ? toPrompt(editing.draft) : undefined,
      ctx,
    });
    const { draft, error } = normalizeDraft(raw, ctx);
    if (!draft) return meta.sendText(from, error || HELP);

    let id;
    if (editing) {
      id = editing.id;
      await pool.query(
        `update whatsapp_drafts set draft = $2, state = 'pending', updated_at = now()
         where id = $1`,
        [id, draft],
      );
    } else {
      id = crypto.randomUUID();
      await pool.query(
        `insert into whatsapp_drafts (id, user_id, wa_id, draft) values ($1, $2, $3, $4)`,
        [id, user.id, from, draft],
      );
    }
    // Despesa à vista de quem administra um grupo: pode ir só para o
    // orçamento dele ou ser dividida no grupo.
    if ((await shareChoices(user.id, draft)).length) {
      return meta.sendButtons(
        from,
        `${formatSummary(draft, ctx)}\n\nLançar como despesa sua ou compartilhada? ` +
          'Para desistir, responda *cancelar*.',
        [
          { id: `ok:${id}`, title: 'Despesa' },
          { id: `sh:${id}`, title: 'Compartilhada' },
          { id: `edit:${id}`, title: 'Corrigir' },
        ],
      );
    }
    return meta.sendButtons(from, formatSummary(draft, ctx), [
      { id: `ok:${id}`, title: 'Confirmar' },
      { id: `edit:${id}`, title: 'Corrigir' },
      { id: `no:${id}`, title: 'Cancelar' },
    ]);
  }

  /// Grupos/categorias onde o rascunho pode ser compartilhado.
  async function shareChoices(userId, draft) {
    if (!shared || draft.type !== 'expense' || draft.installments > 1) return [];
    return shared.shareOptions(userId, draft.categoryId);
  }

  async function cancelLatest(from, user) {
    const { rows } = await pool.query(
      `update whatsapp_drafts set state = 'cancelled', updated_at = now()
       where id = (select id from whatsapp_drafts
                   where user_id = $1 and state in ('pending', 'editing')
                     and updated_at > now() - ${EDIT_WINDOW}
                   order by updated_at desc limit 1)
       returning id`,
      [user.id],
    );
    return meta.sendText(
      from,
      rows.length ? 'Cancelado. Nada foi lançado.' : 'Não há lançamento esperando confirmação.',
    );
  }

  /// Despesa já gravada no orçamento: divide no grupo escolhido.
  async function shareSaved(from, user, tx, option) {
    try {
      await shared.upsertExpense(user.id, {
        groupId: option.groupId,
        categoryId: option.categoryId,
        sourceKey: tx.id,
        source: tx.cardId ? 'card' : 'account',
        description: tx.description,
        total: tx.amount,
        date: tx.date,
        dueDate: await dueDateOf(user.id, tx),
        budgetCategoryId: tx.categoryId ?? undefined,
        notes: 'Lançado pelo WhatsApp',
      });
    } catch (e) {
      console.error('WhatsApp: falha ao compartilhar despesa', e);
      return meta.sendText(
        from,
        'Lancei a despesa só para você, mas não consegui dividir no grupo' +
          `${e?.message ? ` (${e.message})` : ''}. Você pode compartilhar pelo app em Despesas compartilhadas.`,
      );
    }
    const names = await shared.memberNames(option.groupId);
    const parts = allocateLine(tx.amount, option.shares)
      .map((p) => `• ${p.userId === user.id ? 'Você' : firstName(names[p.userId])}: ${brl(p.amount)}`)
      .join('\n');
    return meta.sendText(
      from,
      `Lançado e compartilhado ✅ em ${option.groupName} › ${option.categoryName}\n${parts}\n\n` +
        'Cada um já vê a sua parte no app.',
    );
  }

  /// Vencimento usado na despesa compartilhada: no cartão, o da fatura.
  async function dueDateOf(userId, tx) {
    if (!tx.cardId) return tx.date;
    const { rows } = await pool.query(
      `select data from app_docs where user_id = $1 and coll = 'cards' and id = $2`,
      [userId, tx.cardId],
    );
    const card = rows[0]?.data;
    if (!card?.closingDay || !card?.dueDay) return tx.date;
    return invoiceDue(card, invoiceForTx(card, tx));
  }

  async function onButton(from, user, payload) {
    const [action, id] = payload.split(':');
    const client = await pool.connect();
    try {
      await client.query('begin');
      const { rows } = await client.query(
        `select draft, state from whatsapp_drafts
         where id = $1 and user_id = $2 for update`,
        [id, user.id],
      );
      const d = rows[0];
      if (!d || d.state === 'saved' || d.state === 'cancelled') {
        await client.query('rollback');
        const msg = d?.state === 'saved' ? 'Esse lançamento já foi gravado ✅'
          : d?.state === 'cancelled' ? 'Esse lançamento foi cancelado.'
          : 'Não encontrei esse lançamento. Mande de novo, por favor.';
        return meta.sendText(from, msg);
      }
      if (action === 'sh') {
        await client.query('rollback');
        const opts = await shareChoices(user.id, d.draft);
        if (!opts.length) {
          return meta.sendText(from, 'Você não administra nenhum grupo com categorias prontas para dividir.');
        }
        if (opts.length === 1) return onButton(from, user, `sc:${id}:${opts[0].categoryId}`);
        return meta.sendList(
          from,
          'Em qual grupo e categoria devo dividir esta despesa?',
          'Escolher',
          opts.map((o) => ({
            id: `sc:${id}:${o.categoryId}`,
            title: o.categoryName,
            description: `${o.groupName}${o.suggested ? ' · sugerida' : ''}`,
          })),
        );
      }
      let option = null;
      if (action === 'sc') {
        const catId = payload.split(':')[2];
        option = (await shareChoices(user.id, d.draft)).find((o) => o.categoryId === catId);
        if (!option) {
          await client.query('rollback');
          return meta.sendText(from, 'Essa categoria não está mais disponível para dividir. Escolha de novo.');
        }
      }
      if (action === 'ok' || option) {
        const ctx = await loadContext(user.id);
        const docs = buildDocs(d.draft, ctx.today);
        for (const doc of docs) {
          await client.query(
            `insert into app_docs (user_id, coll, id, data) values ($1, $2, $3, $4)`,
            [user.id, doc.coll, doc.id, JSON.stringify(doc.data)],
          );
        }
        await client.query(
          `update whatsapp_drafts set state = 'saved', updated_at = now() where id = $1`,
          [id],
        );
        await client.query('commit');
        if (option) return shareSaved(from, user, docs[0].data, option);
        return meta.sendText(from, 'Lançado ✅ Já aparece no app (atualize a tela se ele estiver aberto).');
      }
      const state = action === 'edit' ? 'editing' : 'cancelled';
      if (state === 'editing') {
        // Só um rascunho em edição por vez.
        await client.query(
          `update whatsapp_drafts set state = 'pending'
           where user_id = $1 and state = 'editing' and id <> $2`,
          [user.id, id],
        );
      }
      await client.query(
        `update whatsapp_drafts set state = $2, updated_at = now() where id = $1`,
        [id, state],
      );
      await client.query('commit');
      return meta.sendText(
        from,
        state === 'editing'
          ? 'O que devo corrigir? Ex.: "valor 50", "categoria Transporte", "no cartão Nubank", "data 03/10", "em 2x".'
          : 'Cancelado. Nada foi lançado.',
      );
    } catch (e) {
      await client.query('rollback').catch(() => {});
      throw e;
    } finally {
      client.release();
    }
  }
}

/// Rascunho no vocabulário do esquema da IA (valor em reais).
const toPrompt = (d) => ({
  type: d.type,
  amount: d.amount / 100,
  description: d.description,
  date: d.date,
  category_id: d.categoryId,
  account_id: d.accountId,
  card_id: d.cardId,
  installments: d.installments,
  notes: d.notes,
});

const firstName = (name) => String(name ?? '').trim().split(/\s+/)[0] || '';

module.exports = { mountWhatsApp };
