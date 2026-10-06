// Cliente mínimo da WhatsApp Cloud API (Meta Graph API).

const crypto = require('crypto');

const GRAPH = 'https://graph.facebook.com';
const MAX_MEDIA_BYTES = 20 * 1024 * 1024;

/// Confere a assinatura X-Hub-Signature-256 enviada pela Meta.
function validSignature(rawBody, header, appSecret) {
  if (!rawBody || !header || !appSecret) return false;
  const expected =
    'sha256=' +
    crypto.createHmac('sha256', appSecret).update(rawBody).digest('hex');
  const a = Buffer.from(expected);
  const b = Buffer.from(String(header));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/**
 * @param {{token: string, phoneNumberId: string, apiVersion?: string}} opts
 */
function createMetaClient({ token, phoneNumberId, apiVersion = 'v23.0' }) {
  const auth = { authorization: `Bearer ${token}` };

  async function graph(path, init = {}) {
    const res = await fetch(`${GRAPH}/${apiVersion}/${path}`, {
      ...init,
      headers: { ...auth, ...(init.headers ?? {}) },
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`WhatsApp API ${res.status}: ${body.slice(0, 500)}`);
    }
    return res.json();
  }

  async function send(to, payload) {
    const res = await graph(`${phoneNumberId}/messages`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ messaging_product: 'whatsapp', to, ...payload }),
    });
    if (to) console.log(`WhatsApp: enviado para ${to} (${res?.messages?.[0]?.id ?? 'sem id'})`);
    return res;
  }

  return {
    sendText: (to, text) =>
      send(to, { type: 'text', text: { body: text.slice(0, 4096) } }),

    /// Mensagem com até 3 botões de resposta ({id, title ≤ 20 caracteres}).
    sendButtons: (to, text, buttons) =>
      send(to, {
        type: 'interactive',
        interactive: {
          type: 'button',
          body: { text: text.slice(0, 1024) },
          action: {
            buttons: buttons.map((b) => ({
              type: 'reply',
              reply: { id: b.id, title: b.title.slice(0, 20) },
            })),
          },
        },
      }),

    markRead: (messageId) =>
      send(undefined, { status: 'read', message_id: messageId }).catch(() => {}),

    /// Baixa uma mídia recebida (foto, áudio, documento).
    async downloadMedia(mediaId) {
      const info = await graph(mediaId);
      if (info.file_size && info.file_size > MAX_MEDIA_BYTES) {
        throw new Error('Arquivo grande demais');
      }
      const res = await fetch(info.url, { headers: auth });
      if (!res.ok) throw new Error(`Download da mídia falhou: ${res.status}`);
      const data = Buffer.from(await res.arrayBuffer());
      return { data, mimeType: String(info.mime_type ?? '').split(';')[0] };
    },
  };
}

/**
 * Conclui o Cadastro incorporado: troca o código do login da Meta por um
 * token comercial (não expira), inscreve a conta do WhatsApp Business no app
 * para receber o webhook e lê o número de telefone.
 * @param {{appId: string, appSecret: string, apiVersion?: string}} opts
 */
function createSignup({ appId, appSecret, apiVersion = 'v23.0' }) {
  async function call(path, init = {}) {
    const res = await fetch(`${GRAPH}/${apiVersion}/${path}`, init);
    const body = await res.text();
    if (!res.ok) throw new Error(`Graph ${res.status}: ${body.slice(0, 500)}`);
    return JSON.parse(body);
  }
  return async ({ code, phoneNumberId, wabaId }) => {
    const q = new URLSearchParams({ client_id: appId, client_secret: appSecret, code });
    const { access_token: token } = await call(`oauth/access_token?${q}`);
    const auth = { authorization: `Bearer ${token}` };
    await call(`${wabaId}/subscribed_apps`, { method: 'POST', headers: auth });
    // Na coexistência a Meta pode mandar só a conta; o número vem da lista.
    const phone = phoneNumberId
      ? await call(`${phoneNumberId}?fields=id,display_phone_number`, { headers: auth })
      : (await call(`${wabaId}/phone_numbers?fields=id,display_phone_number`, { headers: auth })).data?.[0];
    if (!phone?.id) throw new Error('Nenhum número na conta do WhatsApp Business');
    return { token, phoneNumberId: phone.id, botNumber: phone.display_phone_number };
  };
}

module.exports = { createMetaClient, createSignup, validSignature };
