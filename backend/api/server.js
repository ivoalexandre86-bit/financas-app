const { Pool } = require('pg');
const { createApp, migrate } = require('./app');
const { createPluggy } = require('./pluggy');
const { createMetaClient, createSignup } = require('./whatsapp/meta');
const { createExtractor } = require('./whatsapp/extract');
const { createTranscriber } = require('./whatsapp/transcribe');

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error('DATABASE_URL não definido');
  process.exit(1);
}

const pool = new Pool({
  connectionString: databaseUrl,
  // Conexão interna do Render não usa SSL; a externa exige.
  ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

const allowedOrigins = (process.env.ALLOWED_ORIGINS ??
  'https://ivoalexandre86-bit.github.io')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

/// Lançamentos pelo WhatsApp: precisa do segredo do app da Meta, do token de
/// verificação do webhook e da chave do Claude. O número do bot vem do
/// Cadastro incorporado (salvo no banco) ou de WHATSAPP_TOKEN +
/// WHATSAPP_PHONE_NUMBER_ID. A chave da OpenAI é opcional (habilita áudio).
function whatsAppFromEnv(env) {
  const config = {
    verifyToken: env.WHATSAPP_VERIFY_TOKEN,
    appSecret: env.WHATSAPP_APP_SECRET,
    botNumber: env.WHATSAPP_BOT_NUMBER,
  };
  if (!config.verifyToken || !config.appSecret || !env.ANTHROPIC_API_KEY) {
    return { config };
  }
  const fromEnv = env.WHATSAPP_TOKEN && env.WHATSAPP_PHONE_NUMBER_ID;
  if (fromEnv) console.log('WhatsApp ativo' + (env.OPENAI_API_KEY ? ' (com áudio)' : ''));
  return {
    config,
    createMeta: createMetaClient,
    signup: createSignup({
      appId: env.WHATSAPP_APP_ID || '1624966215848250',
      appSecret: config.appSecret,
    }),
    meta: fromEnv
      ? createMetaClient({
          token: env.WHATSAPP_TOKEN,
          phoneNumberId: env.WHATSAPP_PHONE_NUMBER_ID,
        })
      : undefined,
    extract: createExtractor({
      apiKey: env.ANTHROPIC_API_KEY,
      model: env.ANTHROPIC_MODEL || undefined,
    }),
    transcribe: env.OPENAI_API_KEY
      ? createTranscriber({ apiKey: env.OPENAI_API_KEY })
      : undefined,
  };
}

migrate(pool)
  .then(() => {
    const app = createApp({
      pool,
      jwtSecret: process.env.JWT_SECRET,
      allowedOrigins,
      // Open Finance: ativo quando as credenciais da Pluggy estão definidas.
      pluggy:
        process.env.PLUGGY_CLIENT_ID && process.env.PLUGGY_CLIENT_SECRET
          ? createPluggy({
              clientId: process.env.PLUGGY_CLIENT_ID,
              clientSecret: process.env.PLUGGY_CLIENT_SECRET,
            })
          : null,
      whatsapp: whatsAppFromEnv(process.env),
    });
    app.set('trust proxy', 1);
    const port = Number(process.env.PORT ?? 3000);
    app.listen(port, () => console.log(`API ouvindo na porta ${port}`));
  })
  .catch((e) => {
    console.error('Falha ao iniciar:', e);
    process.exit(1);
  });
