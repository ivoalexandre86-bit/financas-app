// Pagamento de boletos lembrados pelo WhatsApp.
//
// Dois caminhos:
// 1. Open Finance (Pluggy, iniciação de pagamento): quando o boleto tem Pix
//    copia e cola e a Pluggy liberou pagamentos para o cliente
//    (PLUGGY_PAYMENTS=true), o bot manda um link onde o usuário escolhe o
//    banco e autoriza o Pix no app do banco. A confirmação chega pelo
//    webhook da Pluggy (ou pela verificação periódica) e o lançamento vira
//    pago no app.
// 2. Sempre disponível: o bot manda o código (linha digitável ou Pix) numa
//    mensagem só, fácil de copiar, e uma página com o botão Copiar e um
//    atalho para abrir o app do banco. O usuário avisa com "Já paguei".
//
// O Open Finance no Brasil só inicia pagamentos por Pix; boleto sem Pix
// segue pelo caminho 2.

const jwt = require('jsonwebtoken');
const { brl, brDate } = require('./ledger');
const { formatBoleto } = require('./boleto');

const PAGE_DAYS = 7;

/// App do banco no Android (código COMPE → pacote na Play Store).
const ANDROID_APPS = {
  '001': ['Banco do Brasil', 'br.com.bb.android'],
  '033': ['Santander', 'com.santander.app'],
  '077': ['Inter', 'br.com.intermedium'],
  '104': ['Caixa', 'br.com.gabba.Caixa'],
  '237': ['Bradesco', 'com.bradesco'],
  '260': ['Nubank', 'com.nu.production'],
  '290': ['PagBank', 'br.com.uol.ps.myaccount'],
  '323': ['Mercado Pago', 'com.mercadopago.wallet'],
  '336': ['C6 Bank', 'com.c6bank.app'],
  '341': ['Itaú', 'com.itau'],
  '380': ['PicPay', 'com.picpay'],
};

const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const dueOf = (tx) => tx.dueDate ?? tx.date;

/**
 * @param {import('express').Express} app
 * @param {{pool: import('pg').Pool, wrap: Function, jwtSecret: string,
 *   pluggy?: object|null, payments?: {enabled?: boolean, sandbox?: boolean},
 *   publicUrl?: string, getMeta: () => any}} deps
 */
function mountBoletoPayments(app, { pool, wrap, jwtSecret, pluggy, payments = {}, publicUrl, getMeta }) {
  const base = String(publicUrl ?? '').replace(/\/$/, '');
  const openFinance = () => !!(pluggy && payments.enabled && base);

  async function loadTx(userId, txId) {
    const { rows } = await pool.query(
      `select data from app_docs
        where user_id = $1 and coll = 'transactions' and id = $2 and not deleted`,
      [userId, txId],
    );
    return rows[0]?.data ?? null;
  }

  /// Marca o lançamento como pago (concluído), como o app faria.
  async function markPaid(userId, txId) {
    const { rows } = await pool.query(
      `update app_docs
          set data = data || jsonb_build_object('status', 'completed', 'updatedAt', $3::text),
              updated_at = now()
        where user_id = $1 and coll = 'transactions' and id = $2 and not deleted
          and data->>'status' <> 'completed'
        returning data`,
      [userId, txId, new Date().toISOString()],
    );
    return rows[0]?.data ?? null;
  }

  const pageUrl = (userId, txId) =>
    base
      ? `${base}/pagar/${jwt.sign({ u: userId, t: txId, k: 'pay' }, jwtSecret, { expiresIn: `${PAGE_DAYS}d` })}`
      : null;

  const head = (tx) => `🧾 *${tx.description}* · *${brl(tx.amount)}* · vence ${brDate(dueOf(tx))}`;

  /// Link do Open Finance (Pluggy) para pagar o Pix do boleto.
  async function openFinanceLink(user, tx, waId) {
    const recipient = await pluggy.createPixQrRecipient(tx.pixCode);
    const callback = `${base}/pagar/retorno`;
    const req = await pluggy.createPaymentRequest({
      amount: tx.amount / 100,
      description: String(tx.description).slice(0, 60),
      recipientId: recipient.id,
      callbackUrls: { success: callback, error: callback, pending: callback },
      isSandbox: payments.sandbox,
    });
    if (!req?.id || !req?.paymentUrl) throw new Error('Pluggy não devolveu o link de pagamento');
    await pool.query(
      `insert into boleto_payments (request_id, user_id, tx_id, wa_id, status, payment_url)
       values ($1, $2, $3, $4, $5, $6)`,
      [req.id, user.id, tx.id, waId, req.status ?? 'CREATED', req.paymentUrl],
    );
    return req.paymentUrl;
  }

  /** "Pagar agora": manda o caminho de pagamento do boleto. */
  async function pay(from, user, txId) {
    const meta = getMeta();
    const tx = await loadTx(user.id, txId);
    if (!tx) return meta.sendText(from, 'Não encontrei esse boleto no app. Ele pode ter sido apagado.');
    if (tx.status === 'completed') return meta.sendText(from, 'Esse boleto já está marcado como pago ✅');
    if (!tx.boletoCode && !tx.pixCode) {
      return meta.sendText(from, `${head(tx)}\n\nEsse lançamento não tem código de pagamento salvo. Adicione a linha digitável no app (editar lançamento) ou me mande a foto do boleto.`);
    }

    if (openFinance() && tx.pixCode) {
      try {
        const url = await openFinanceLink(user, tx, from);
        return meta.sendCta(
          from,
          `${head(tx)}\n\nToque em *Pagar pelo banco*, escolha o seu banco e confirme o Pix no app dele ` +
            '(Open Finance, sem copiar código). Quando o banco confirmar, eu marco como pago no app.',
          'Pagar pelo banco',
          url,
        );
      } catch (e) {
        console.error('Boleto: Open Finance indisponível, mando o código', e.message);
      }
    }

    const page = pageUrl(user.id, tx.id);
    const how = tx.boletoCode
      ? 'Copie a linha digitável da próxima mensagem e cole no app do seu banco, em *Pagar boleto*.'
      : 'Copie o código da próxima mensagem e cole no app do seu banco, em *Pix copia e cola*.';
    await meta.sendText(
      from,
      `${head(tx)}\n\n${how}` +
        (tx.boletoCode && tx.pixCode ? ' Se preferir Pix, o código Pix vem logo depois.' : ''),
    );
    if (tx.boletoCode) await meta.sendText(from, tx.boletoCode);
    if (tx.pixCode) await meta.sendText(from, tx.pixCode);
    return meta.sendButtons(
      from,
      (page ? `Para copiar com um toque e abrir o app do banco: ${page}\n\n` : '') +
        'Depois de pagar, toque em *Já paguei* que eu dou baixa no app.',
      [{ id: `bpaid:${tx.id}`, title: 'Já paguei' }],
    );
  }

  /** "Já paguei". */
  async function paid(from, user, txId) {
    const meta = getMeta();
    const tx = await markPaid(user.id, txId);
    if (tx) {
      return meta.sendText(from, `Baixa feita ✅ ${tx.description} (${brl(tx.amount)}) está como pago no app.`);
    }
    const cur = await loadTx(user.id, txId);
    return meta.sendText(
      from,
      cur ? 'Esse boleto já estava marcado como pago ✅' : 'Não encontrei esse boleto no app.',
    );
  }

  /** Boletos em aberto (para o comando "boletos"). */
  async function openBoletos(userId, today) {
    const { rows } = await pool.query(
      `select data from app_docs
        where user_id = $1 and coll = 'transactions' and not deleted
          and (data->>'boletoCode' is not null or data->>'pixCode' is not null)
          and data->>'status' not in ('completed', 'cancelled')`,
      [userId],
    );
    return rows
      .map((r) => r.data)
      .filter((t) => dueOf(t) >= addDaysIso(today, -60))
      .sort((a, b) => dueOf(a).localeCompare(dueOf(b)));
  }

  async function list(from, user, today) {
    const meta = getMeta();
    const items = await openBoletos(user.id, today);
    if (!items.length) {
      return meta.sendText(
        from,
        'Nenhum boleto em aberto 🙌\n\nMande a foto ou o PDF de um boleto (ou a linha digitável) que eu lanço e te lembro no vencimento.',
      );
    }
    return meta.sendList(
      from,
      `Você tem ${items.length} boleto(s) em aberto. Escolha um para pagar:`,
      'Ver boletos',
      items.slice(0, 10).map((t) => ({
        id: `bpay:${t.id}`,
        title: t.description,
        description: `${brl(t.amount)} · ${dueOf(t) < today ? 'venceu' : 'vence'} ${brDate(dueOf(t))}`,
      })),
    );
  }

  /// Confere um pedido na Pluggy; quando concluído, dá baixa e avisa.
  async function settle(requestId) {
    const { rows } = await pool.query(
      'select * from boleto_payments where request_id = $1',
      [requestId],
    );
    const p = rows[0];
    if (!p || p.status === 'COMPLETED') return false;
    const req = await pluggy.getPaymentRequest(requestId);
    const status = String(req?.status ?? p.status);
    if (status === p.status) return false;
    await pool.query(
      'update boleto_payments set status = $2, updated_at = now() where request_id = $1',
      [requestId, status],
    );
    if (status !== 'COMPLETED') return false;
    const tx = await markPaid(p.user_id, p.tx_id);
    const meta = getMeta();
    if (tx && meta && p.wa_id) {
      await meta
        .sendText(p.wa_id, `Pagamento confirmado pelo banco ✅ ${tx.description} (${brl(tx.amount)}) está como pago no app.`)
        .catch((e) => console.error('Boleto: aviso de pagamento falhou', e.message));
    }
    return true;
  }

  /// Pedidos em andamento das últimas 48 h (caso o webhook não chegue).
  async function checkPending() {
    if (!pluggy) return 0;
    const { rows } = await pool.query(
      `select request_id from boleto_payments
        where status not in ('COMPLETED', 'ERROR', 'CANCELED', 'CANCELLED', 'EXPIRED')
          and created_at > now() - interval '48 hours'`,
    );
    let n = 0;
    for (const r of rows) {
      try {
        if (await settle(r.request_id)) n++;
      } catch (e) {
        console.error('Boleto: falha ao conferir pagamento', e.message);
      }
    }
    return n;
  }

  // Webhook da Pluggy: o corpo só serve de aviso; o status vem da própria
  // API (ninguém consegue dar baixa forjando o webhook).
  app.post('/pluggy/webhook', wrap(async (req, res) => {
    res.sendStatus(200);
    const b = req.body ?? {};
    const id = b.paymentRequestId ?? b.data?.paymentRequestId ?? b.paymentRequest?.id ??
      (String(b.event ?? '').startsWith('payment_request') ? b.id : null);
    if (!id || !pluggy) return;
    settle(String(id)).catch((e) => console.error('Boleto: webhook da Pluggy', e.message));
  }));

  app.get('/pagar/retorno', (req, res) => {
    res.type('html').send(page('Pagamento', '<p>Pronto! Volte para o WhatsApp: assim que o banco confirmar, eu aviso por lá e dou baixa no app.</p>'));
  });

  app.get('/pagar/:token', wrap(async (req, res) => {
    let claims;
    try {
      claims = jwt.verify(req.params.token, jwtSecret, { algorithms: ['HS256'] });
    } catch {
      claims = null;
    }
    if (claims?.k !== 'pay') {
      return res.status(404).type('html').send(page('Link vencido', '<p>Este link venceu. Mande <b>boletos</b> no WhatsApp para receber um novo.</p>'));
    }
    const tx = await loadTx(claims.u, claims.t);
    if (!tx) return res.status(404).type('html').send(page('Boleto', '<p>Esse boleto não está mais no app.</p>'));
    const { rows } = await pool.query(
      `select data from app_docs where user_id = $1 and coll = 'accounts' and id = $2`,
      [claims.u, tx.accountId ?? ''],
    );
    const bank = ANDROID_APPS[rows[0]?.data?.institutionCode];
    res.set('cache-control', 'no-store').type('html').send(payPage(tx, bank));
  }));

  return { pay, paid, list, markPaid, checkPending, settle, openFinance };
}

function addDaysIso(s, days) {
  const [y, m, d] = s.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

function page(title, body) {
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>${esc(title)}</title><style>
:root{--bg:#f6f7f9;--fg:#15181d;--muted:#5d6570;--card:#fff;--line:#dfe3e8;--accent:#0b7a53}
@media (prefers-color-scheme:dark){:root{--bg:#111418;--fg:#eef1f4;--muted:#9aa3ad;--card:#1b1f25;--line:#2c323a;--accent:#3cc58f}}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:520px;margin:0 auto;padding:24px 16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px;margin-bottom:14px}
h1{font-size:20px;margin:0 0 4px}.muted{color:var(--muted);font-size:14px}
.amount{font-size:28px;font-weight:700;margin:6px 0}
.code{font:15px/1.4 ui-monospace,Menlo,monospace;word-break:break-all;background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:12px;margin:8px 0}
button,a.btn{display:block;width:100%;box-sizing:border-box;text-align:center;border:0;border-radius:10px;padding:13px;font-size:16px;font-weight:600;cursor:pointer;text-decoration:none;margin-top:8px}
button{background:var(--accent);color:#fff}a.btn{background:transparent;color:var(--accent);border:1px solid var(--accent)}
</style></head><body><main>${body}</main></body></html>`;
}

function payPage(tx, bank) {
  const due = dueOf(tx);
  const codes = [];
  if (tx.boletoCode) codes.push(['Linha digitável', formatBoleto(tx.boletoCode), tx.boletoCode, 'Pagar boleto']);
  if (tx.pixCode) codes.push(['Pix copia e cola', tx.pixCode, tx.pixCode, 'Pix copia e cola']);
  const blocks = codes
    .map(([label, shown, raw], i) => `<div class="card"><div class="muted">${esc(label)}</div>
<div class="code" id="c${i}">${esc(shown)}</div>
<button type="button" data-code="${esc(raw)}" onclick="copy(this)">Copiar ${esc(label.toLowerCase())}</button></div>`)
    .join('');
  const open = bank
    ? `<a class="btn android" style="display:none" href="intent://#Intent;package=${esc(bank[1])};S.browser_fallback_url=${encodeURIComponent(`https://play.google.com/store/apps/details?id=${bank[1]}`)};end">Abrir o app ${esc(bank[0])}</a>`
    : '';
  const where = codes.map((c) => c[3]).join(' ou ');
  return page(
    `Pagar ${tx.description}`,
    `<div class="card"><h1>${esc(tx.description)}</h1>
<div class="amount">${esc(brl(tx.amount))}</div>
<div class="muted">Vencimento ${esc(brDate(due))}${tx.status === 'completed' ? ' · já está pago ✅' : ''}</div></div>
${blocks}
<div class="card"><b>Como pagar</b><p class="muted" style="margin:6px 0 0">Copie o código, abra o app do seu banco e escolha <b>${esc(where)}</b>. Depois volte ao WhatsApp e toque em <b>Já paguei</b>.</p>${open}</div>
<script>
if (/android/i.test(navigator.userAgent)) document.querySelectorAll('.android').forEach(e => e.style.display = 'block');
async function copy(b){const t=b.dataset.code;try{await navigator.clipboard.writeText(t)}catch(e){const a=document.createElement('textarea');a.value=t;document.body.appendChild(a);a.select();document.execCommand('copy');a.remove()}
const o=b.textContent;b.textContent='Copiado ✓';setTimeout(()=>b.textContent=o,2000)}
</script>`,
  );
}

module.exports = { mountBoletoPayments, ANDROID_APPS };
