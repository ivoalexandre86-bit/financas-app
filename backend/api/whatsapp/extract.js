// Leitura de lançamentos (texto, foto de cupom/comprovante ou PDF) com o
// Claude, devolvendo JSON no formato de `SCHEMA`.

const Anthropic = require('@anthropic-ai/sdk');

const nullable = (schema) => ({ anyOf: [schema, { type: 'null' }] });

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: [
    'is_transaction',
    'reply',
    'type',
    'amount',
    'description',
    'date',
    'category_id',
    'account_id',
    'card_id',
    'installments',
    'notes',
  ],
  properties: {
    is_transaction: { type: 'boolean' },
    reply: { type: 'string' },
    type: { type: 'string', enum: ['expense', 'income'] },
    amount: { type: 'number' },
    description: { type: 'string' },
    date: { type: 'string' },
    category_id: nullable({ type: 'string' }),
    account_id: nullable({ type: 'string' }),
    card_id: nullable({ type: 'string' }),
    installments: { type: 'integer' },
    notes: { type: 'string' },
  },
};

const SYSTEM = `Você registra despesas e receitas no app de finanças pessoais do usuário a partir de mensagens de WhatsApp em português do Brasil (texto, áudio transcrito, foto de cupom fiscal, nota, comprovante de Pix ou boleto pago).

Extraia um único lançamento:
- type: "expense" para gastos/pagamentos, "income" para salário, recebimentos, Pix recebido, reembolsos.
- amount: valor total em reais, positivo (ex.: 45.9). Em cupom fiscal, use o TOTAL pago (com descontos), não a soma de itens nem o troco.
- description: curta e útil, como o usuário escreveria (ex.: "Mercado Pão de Açúcar", "Uber", "Salário"). Em cupom, use o nome do estabelecimento.
- date: AAAA-MM-DD. Use a data citada ("ontem", "dia 3", data do cupom/comprovante); sem menção, use a data de hoje informada.
- category_id: o id da categoria mais adequada da lista do usuário, do mesmo tipo (despesa/receita). null se nenhuma servir.
- card_id: id do cartão quando o usuário falar em cartão/crédito/fatura ou citar o nome de um cartão da lista; o comprovante mostrar compra no crédito também conta. Só para despesas.
- account_id: id da conta citada (débito, Pix, dinheiro, nome do banco). null se não der para saber.
- installments: número de parcelas ("em 3x", "parcelado em 10") ou 1.
- notes: detalhes úteis que não couberam na descrição (pode ficar vazio).

Use somente ids que aparecem nas listas. Se a mensagem não for um lançamento (cumprimento, pergunta, assunto sem relação) ou não der para identificar o valor, responda is_transaction=false e escreva em reply uma resposta curta em português explicando que você registra despesas e receitas, com um exemplo ("gastei 45,90 no mercado no cartão Nubank"), e que "resumo" mostra como está o mês. Nesse caso preencha os demais campos com valores neutros (amount 0, textos vazios, ids null, installments 1, type "expense", date de hoje). Não responda a outros assuntos.`;

function contextText(ctx) {
  const list = (items, fmt) =>
    items.length ? items.map(fmt).join('\n') : '(nenhum)';
  return [
    `Hoje é ${ctx.today}.`,
    '',
    'Contas:',
    list(ctx.accounts, (a) => `- ${a.id}: ${a.name}${a.institution ? ` (${a.institution})` : ''}`),
    '',
    'Cartões de crédito:',
    list(ctx.cards, (c) => `- ${c.id}: ${c.name}${c.bank ? ` (${c.bank})` : ''}`),
    '',
    'Categorias de despesa:',
    list(ctx.categories.filter((c) => c.kind === 'expense'), (c) => `- ${c.id}: ${c.name}`),
    '',
    'Categorias de receita:',
    list(ctx.categories.filter((c) => c.kind === 'income'), (c) => `- ${c.id}: ${c.name}`),
  ].join('\n');
}

const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/gif', 'image/webp']);

/**
 * @param {{apiKey: string, model?: string}} opts
 */
function createExtractor({ apiKey, model = 'claude-opus-5-5' }) {
  const client = new Anthropic({ apiKey, timeout: 60_000, maxRetries: 2 });

  /**
   * @param {{text?: string, media?: {data: Buffer, mimeType: string},
   *   previous?: object, ctx: object}} input
   * @returns {Promise<object|null>} JSON no formato de SCHEMA, ou null se recusado
   */
  return async function extract({ text, media, previous, ctx }) {
    const content = [{ type: 'text', text: contextText(ctx) }];
    if (media) {
      const data = media.data.toString('base64');
      if (media.mimeType === 'application/pdf') {
        content.push({
          type: 'document',
          source: { type: 'base64', media_type: 'application/pdf', data },
        });
      } else if (IMAGE_TYPES.has(media.mimeType)) {
        content.push({
          type: 'image',
          source: { type: 'base64', media_type: media.mimeType, data },
        });
      }
    }
    if (previous) {
      content.push({
        type: 'text',
        text:
          'Lançamento em edição (JSON):\n' +
          JSON.stringify(previous) +
          '\n\nAplique a correção do usuário abaixo e devolva o lançamento completo atualizado.',
      });
    }
    content.push({
      type: 'text',
      text: `Mensagem do usuário:\n${text?.trim() || '(sem texto)'}`,
    });

    const res = await client.beta.messages.create({
      model,
      max_tokens: 4000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      output_config: {
        effort: 'low',
        format: { type: 'json_schema', schema: SCHEMA },
      },
      system: SYSTEM,
      messages: [{ role: 'user', content }],
    });
    if (res.stop_reason === 'refusal' || res.stop_reason === 'max_tokens') {
      return null;
    }
    const out = res.content.find((b) => b.type === 'text');
    return out ? JSON.parse(out.text) : null;
  };
}

module.exports = { createExtractor, SCHEMA, contextText };
