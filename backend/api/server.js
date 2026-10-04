const { Pool } = require('pg');
const { createApp, migrate } = require('./app');

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

migrate(pool)
  .then(() => {
    const app = createApp({
      pool,
      jwtSecret: process.env.JWT_SECRET,
      allowedOrigins,
    });
    app.set('trust proxy', 1);
    const port = Number(process.env.PORT ?? 3000);
    app.listen(port, () => console.log(`API ouvindo na porta ${port}`));
  })
  .catch((e) => {
    console.error('Falha ao iniciar:', e);
    process.exit(1);
  });
