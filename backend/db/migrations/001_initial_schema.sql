-- =============================================================================
-- Finanças — esquema inicial (PostgreSQL 14+)
--
-- Convenções
--   * Valores monetários: NUMERIC(15,2) (nunca float). Valores de lançamento
--     são sempre positivos; o sentido vem de `type`.
--   * Isolamento por usuário: toda tabela de domínio tem `user_id`, chaves
--     estrangeiras compostas (id, user_id) impedem referências cruzadas entre
--     usuários, e Row Level Security filtra por `app.current_user_id`.
--   * Datas de negócio: DATE (sem fuso). Auditoria: TIMESTAMPTZ.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()

-- Tipos -----------------------------------------------------------------------
CREATE TYPE transaction_type      AS ENUM ('income', 'expense', 'transfer');
CREATE TYPE transaction_status    AS ENUM ('planned', 'pending', 'completed', 'cancelled');
CREATE TYPE account_type          AS ENUM ('checking', 'savings', 'digital', 'cash', 'investment');
CREATE TYPE category_kind         AS ENUM ('income', 'expense');
CREATE TYPE recurrence_frequency  AS ENUM ('weekly', 'monthly', 'quarterly', 'yearly', 'custom');
CREATE TYPE recurrence_unit       AS ENUM ('days', 'weeks', 'months');
CREATE TYPE invoice_status        AS ENUM ('future', 'open', 'closed', 'partial', 'paid', 'overdue');
CREATE TYPE consent_status        AS ENUM ('pending', 'active', 'expired', 'revoked');
CREATE TYPE external_tx_status    AS ENUM ('pending', 'imported', 'matched', 'ignored');

-- updated_at automático ----------------------------------------------------------
CREATE FUNCTION set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- Usuários e sessões ----------------------------------------------------------------
CREATE TABLE users (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT        NOT NULL CHECK (length(trim(name)) > 0),
  email          TEXT        NOT NULL,
  password_hash  TEXT        NOT NULL,             -- argon2id/bcrypt (formato PHC)
  privacy_accepted_at TIMESTAMPTZ NOT NULL,        -- LGPD: aceite da política
  deleted_at     TIMESTAMPTZ,                      -- exclusão solicitada
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_uq ON users (lower(email)) WHERE deleted_at IS NULL;

CREATE TABLE auth_sessions (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_token_hash TEXT NOT NULL UNIQUE,         -- só o hash do token
  user_agent         TEXT,
  expires_at         TIMESTAMPTZ NOT NULL,
  revoked_at         TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX auth_sessions_user_idx ON auth_sessions (user_id);

-- Contas --------------------------------------------------------------------------
CREATE TABLE accounts (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name             TEXT NOT NULL CHECK (length(trim(name)) > 0),
  institution      TEXT NOT NULL DEFAULT '',
  type             account_type NOT NULL DEFAULT 'checking',
  initial_balance  NUMERIC(15,2) NOT NULL DEFAULT 0,
  active           BOOLEAN NOT NULL DEFAULT true,
  color            INTEGER,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id)
);
CREATE INDEX accounts_user_idx ON accounts (user_id);

-- Cartões ---------------------------------------------------------------------------
CREATE TABLE cards (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name                TEXT NOT NULL CHECK (length(trim(name)) > 0),
  bank                TEXT NOT NULL DEFAULT '',
  brand               TEXT NOT NULL DEFAULT '',
  last_four           CHAR(4) CHECK (last_four ~ '^[0-9]{4}$'),
  credit_limit        NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (credit_limit >= 0),
  closing_day         SMALLINT NOT NULL CHECK (closing_day BETWEEN 1 AND 31),
  due_day             SMALLINT NOT NULL CHECK (due_day BETWEEN 1 AND 31),
  payment_account_id  UUID,
  active              BOOLEAN NOT NULL DEFAULT true,
  color               INTEGER,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  FOREIGN KEY (payment_account_id, user_id) REFERENCES accounts (id, user_id)
);
CREATE INDEX cards_user_idx ON cards (user_id);

-- Categorias (com subcategorias) -----------------------------------------------------
CREATE TABLE categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL CHECK (length(trim(name)) > 0),
  kind        category_kind NOT NULL,
  parent_id   UUID,
  icon        TEXT NOT NULL DEFAULT 'other',
  color       INTEGER,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  CHECK (parent_id IS NULL OR parent_id <> id),
  FOREIGN KEY (parent_id, user_id) REFERENCES categories (id, user_id) ON DELETE SET NULL (parent_id)
);
CREATE INDEX categories_user_idx ON categories (user_id, kind);
CREATE UNIQUE INDEX categories_name_uq
  ON categories (user_id, kind, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name));

-- Projetos e metas ---------------------------------------------------------------------
CREATE TABLE projects (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL CHECK (length(trim(name)) > 0),
  description  TEXT NOT NULL DEFAULT '',
  budget       NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (budget >= 0),
  start_date   DATE,
  end_date     DATE,
  archived     BOOLEAN NOT NULL DEFAULT false,
  color        INTEGER,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);
CREATE INDEX projects_user_idx ON projects (user_id);

CREATE TABLE financial_goals (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  project_id     UUID,
  name           TEXT NOT NULL CHECK (length(trim(name)) > 0),
  target_amount  NUMERIC(15,2) NOT NULL CHECK (target_amount > 0),
  target_date    DATE,
  account_id     UUID,                              -- conta onde a reserva fica
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  FOREIGN KEY (project_id, user_id) REFERENCES projects (id, user_id) ON DELETE SET NULL (project_id),
  FOREIGN KEY (account_id, user_id) REFERENCES accounts (id, user_id) ON DELETE SET NULL (account_id)
);
CREATE INDEX financial_goals_user_idx ON financial_goals (user_id);

-- Regras recorrentes ---------------------------------------------------------------------
CREATE TABLE recurring_transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type              transaction_type NOT NULL CHECK (type IN ('income', 'expense')),
  amount            NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  description       TEXT NOT NULL CHECK (length(trim(description)) > 0),
  category_id       UUID,
  account_id        UUID,
  card_id           UUID,
  project_id        UUID,
  frequency         recurrence_frequency NOT NULL DEFAULT 'monthly',
  interval_count    SMALLINT NOT NULL DEFAULT 1 CHECK (interval_count BETWEEN 1 AND 365),
  interval_unit     recurrence_unit NOT NULL DEFAULT 'months',
  day_of_month      SMALLINT CHECK (day_of_month BETWEEN 1 AND 31),
  start_date        DATE NOT NULL,
  end_date          DATE,
  previous_rule_id  UUID,                           -- versão anterior (edição "somente futuras")
  notes             TEXT NOT NULL DEFAULT '',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  CHECK ((account_id IS NULL) <> (card_id IS NULL)),
  CHECK (end_date IS NULL OR end_date >= start_date),
  FOREIGN KEY (category_id, user_id) REFERENCES categories (id, user_id) ON DELETE SET NULL (category_id),
  FOREIGN KEY (account_id, user_id)  REFERENCES accounts (id, user_id),
  FOREIGN KEY (card_id, user_id)     REFERENCES cards (id, user_id),
  FOREIGN KEY (project_id, user_id)  REFERENCES projects (id, user_id) ON DELETE SET NULL (project_id),
  FOREIGN KEY (previous_rule_id, user_id) REFERENCES recurring_transactions (id, user_id) ON DELETE SET NULL (previous_rule_id)
);
CREATE INDEX recurring_user_idx ON recurring_transactions (user_id);

-- Períodos de pausa (pausar/retomar sem perder histórico)
CREATE TABLE recurring_pauses (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recurring_id      UUID NOT NULL,
  paused_from       DATE NOT NULL,
  paused_until      DATE,                           -- NULL = ainda pausada
  FOREIGN KEY (recurring_id, user_id) REFERENCES recurring_transactions (id, user_id) ON DELETE CASCADE,
  CHECK (paused_until IS NULL OR paused_until >= paused_from)
);
CREATE INDEX recurring_pauses_rule_idx ON recurring_pauses (recurring_id);

-- Compras parceladas --------------------------------------------------------------------
CREATE TABLE installment_groups (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  description        TEXT NOT NULL CHECK (length(trim(description)) > 0),
  total_amount       NUMERIC(15,2) NOT NULL CHECK (total_amount > 0),
  installment_count  SMALLINT NOT NULL CHECK (installment_count BETWEEN 2 AND 120),
  purchase_date      DATE NOT NULL,
  account_id         UUID,
  card_id            UUID,
  category_id        UUID,
  project_id         UUID,
  notes              TEXT NOT NULL DEFAULT '',
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  CHECK ((account_id IS NULL) <> (card_id IS NULL)),
  FOREIGN KEY (account_id, user_id)  REFERENCES accounts (id, user_id),
  FOREIGN KEY (card_id, user_id)     REFERENCES cards (id, user_id),
  FOREIGN KEY (category_id, user_id) REFERENCES categories (id, user_id) ON DELETE SET NULL (category_id),
  FOREIGN KEY (project_id, user_id)  REFERENCES projects (id, user_id) ON DELETE SET NULL (project_id)
);
CREATE INDEX installment_groups_user_idx ON installment_groups (user_id);

-- Faturas ---------------------------------------------------------------------------
-- Uma linha por cartão e mês de fechamento. Totais são derivados dos
-- lançamentos; a linha guarda datas efetivas e o estado de pagamento.
CREATE TABLE invoices (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  card_id          UUID NOT NULL,
  reference_month  DATE NOT NULL CHECK (extract(day FROM reference_month) = 1),
  closing_date     DATE NOT NULL,
  due_date         DATE NOT NULL,
  status           invoice_status NOT NULL DEFAULT 'open',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  UNIQUE (card_id, reference_month),
  CHECK (due_date >= closing_date),
  FOREIGN KEY (card_id, user_id) REFERENCES cards (id, user_id) ON DELETE CASCADE
);
CREATE INDEX invoices_user_due_idx ON invoices (user_id, due_date);

-- Pagamentos de fatura: liquidação do passivo do cartão, NUNCA despesa.
CREATE TABLE invoice_payments (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  invoice_id   UUID NOT NULL,
  account_id   UUID NOT NULL,
  amount       NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  paid_on      DATE NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (invoice_id, user_id) REFERENCES invoices (id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (account_id, user_id) REFERENCES accounts (id, user_id)
);
CREATE INDEX invoice_payments_invoice_idx ON invoice_payments (invoice_id);

-- Lançamentos --------------------------------------------------------------------------
CREATE TABLE transactions (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type                    transaction_type NOT NULL,
  status                  transaction_status NOT NULL DEFAULT 'completed',
  amount                  NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  description             TEXT NOT NULL CHECK (length(trim(description)) > 0),
  transaction_date        DATE NOT NULL,           -- data da compra/lançamento
  payment_date            DATE,                    -- quando foi efetivamente pago
  category_id             UUID,
  account_id              UUID,                    -- origem (ou conta do lançamento)
  destination_account_id  UUID,                    -- destino (transferência)
  card_id                 UUID,
  invoice_id              UUID,                    -- fatura alocada (cartão)
  project_id              UUID,
  recurring_id            UUID,
  occurrence_date         DATE,                    -- chave da ocorrência recorrente
  installment_group_id    UUID,
  installment_number      SMALLINT,
  installment_count       SMALLINT,
  external_transaction_id UUID,                    -- origem Open Finance (conciliação)
  notes                   TEXT NOT NULL DEFAULT '',
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  -- Integridade do vínculo conta/cartão por tipo
  CHECK (
    (type = 'transfer' AND account_id IS NOT NULL AND destination_account_id IS NOT NULL
       AND account_id <> destination_account_id AND card_id IS NULL AND category_id IS NULL)
    OR
    (type <> 'transfer' AND destination_account_id IS NULL
       AND (account_id IS NULL) <> (card_id IS NULL))
  ),
  CHECK (invoice_id IS NULL OR card_id IS NOT NULL),
  CHECK ((recurring_id IS NULL) = (occurrence_date IS NULL) OR recurring_id IS NULL),
  CHECK (
    (installment_group_id IS NULL AND installment_number IS NULL AND installment_count IS NULL)
    OR (installment_group_id IS NOT NULL AND installment_number BETWEEN 1 AND installment_count)
  ),
  FOREIGN KEY (category_id, user_id)            REFERENCES categories (id, user_id) ON DELETE SET NULL (category_id),
  FOREIGN KEY (account_id, user_id)             REFERENCES accounts (id, user_id),
  FOREIGN KEY (destination_account_id, user_id) REFERENCES accounts (id, user_id),
  FOREIGN KEY (card_id, user_id)                REFERENCES cards (id, user_id),
  FOREIGN KEY (invoice_id, user_id)             REFERENCES invoices (id, user_id) ON DELETE SET NULL (invoice_id),
  FOREIGN KEY (project_id, user_id)             REFERENCES projects (id, user_id) ON DELETE SET NULL (project_id),
  -- Excluir a regra NÃO apaga o histórico: o vínculo é apenas anulado.
  FOREIGN KEY (recurring_id, user_id)           REFERENCES recurring_transactions (id, user_id) ON DELETE SET NULL (recurring_id),
  FOREIGN KEY (installment_group_id, user_id)   REFERENCES installment_groups (id, user_id) ON DELETE CASCADE
);
CREATE INDEX transactions_user_date_idx    ON transactions (user_id, transaction_date);
CREATE INDEX transactions_user_status_idx  ON transactions (user_id, status);
CREATE INDEX transactions_account_idx      ON transactions (account_id) WHERE account_id IS NOT NULL;
CREATE INDEX transactions_dest_idx         ON transactions (destination_account_id) WHERE destination_account_id IS NOT NULL;
CREATE INDEX transactions_card_idx         ON transactions (card_id, transaction_date) WHERE card_id IS NOT NULL;
CREATE INDEX transactions_invoice_idx      ON transactions (invoice_id) WHERE invoice_id IS NOT NULL;
CREATE INDEX transactions_project_idx      ON transactions (project_id) WHERE project_id IS NOT NULL;
CREATE INDEX transactions_category_idx     ON transactions (category_id);
-- Uma ocorrência materializada por regra + data (evita duplicidade).
CREATE UNIQUE INDEX transactions_occurrence_uq
  ON transactions (recurring_id, occurrence_date) WHERE recurring_id IS NOT NULL;
-- Uma parcela por número dentro do grupo.
CREATE UNIQUE INDEX transactions_installment_uq
  ON transactions (installment_group_id, installment_number) WHERE installment_group_id IS NOT NULL;

-- Parcelas: visão detalhada por parcela (fatura alocada e progresso)
CREATE TABLE installments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  group_id        UUID NOT NULL,
  number          SMALLINT NOT NULL CHECK (number >= 1),
  amount          NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  due_date        DATE NOT NULL,
  transaction_id  UUID NOT NULL,
  invoice_id      UUID,
  UNIQUE (group_id, number),
  UNIQUE (transaction_id),
  FOREIGN KEY (group_id, user_id)       REFERENCES installment_groups (id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (transaction_id, user_id) REFERENCES transactions (id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (invoice_id, user_id)     REFERENCES invoices (id, user_id) ON DELETE SET NULL (invoice_id)
);
CREATE INDEX installments_user_due_idx ON installments (user_id, due_date);

-- Open Finance ----------------------------------------------------------------------
-- Nunca armazenamos senhas bancárias: apenas IDs de consentimento do provedor.
CREATE TABLE open_finance_connections (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider              TEXT NOT NULL,             -- ex.: 'pluggy', 'belvo', 'sandbox'
  provider_item_id      TEXT,                      -- id da conexão no provedor
  institution_name      TEXT NOT NULL,
  consent_id            TEXT,
  consent_status        consent_status NOT NULL DEFAULT 'pending',
  consent_expires_at    TIMESTAMPTZ,
  last_sync_at          TIMESTAMPTZ,
  last_error            TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  UNIQUE (provider, provider_item_id)
);
CREATE INDEX of_connections_user_idx ON open_finance_connections (user_id);

CREATE TABLE external_accounts (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  connection_id        UUID NOT NULL,
  provider_account_id  TEXT NOT NULL,
  kind                 TEXT NOT NULL CHECK (kind IN ('bank', 'credit_card', 'investment')),
  name                 TEXT NOT NULL,
  number_masked        TEXT,
  balance              NUMERIC(15,2),
  linked_account_id    UUID,
  linked_card_id       UUID,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  UNIQUE (connection_id, provider_account_id),
  CHECK (linked_account_id IS NULL OR linked_card_id IS NULL),
  FOREIGN KEY (connection_id, user_id)     REFERENCES open_finance_connections (id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (linked_account_id, user_id) REFERENCES accounts (id, user_id) ON DELETE SET NULL (linked_account_id),
  FOREIGN KEY (linked_card_id, user_id)    REFERENCES cards (id, user_id) ON DELETE SET NULL (linked_card_id)
);

CREATE TABLE external_transactions (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  external_account_id      UUID NOT NULL,
  provider_transaction_id  TEXT NOT NULL,
  transaction_date         DATE NOT NULL,
  amount                   NUMERIC(15,2) NOT NULL,  -- com sinal: + entrada / − saída
  description              TEXT NOT NULL,
  raw                      JSONB,
  status                   external_tx_status NOT NULL DEFAULT 'pending',
  matched_transaction_id   UUID,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  -- Prevenção de duplicidade na importação
  UNIQUE (external_account_id, provider_transaction_id),
  FOREIGN KEY (external_account_id, user_id)    REFERENCES external_accounts (id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (matched_transaction_id, user_id) REFERENCES transactions (id, user_id) ON DELETE SET NULL (matched_transaction_id)
);
CREATE INDEX external_tx_user_status_idx ON external_transactions (user_id, status);
CREATE INDEX external_tx_match_idx ON external_transactions (user_id, transaction_date, amount);

ALTER TABLE transactions
  ADD FOREIGN KEY (external_transaction_id, user_id)
  REFERENCES external_transactions (id, user_id) ON DELETE SET NULL (external_transaction_id);
CREATE UNIQUE INDEX transactions_external_uq
  ON transactions (external_transaction_id) WHERE external_transaction_id IS NOT NULL;

-- Triggers updated_at -------------------------------------------------------------------
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['users','accounts','cards','categories','projects','financial_goals',
                           'recurring_transactions','installment_groups','invoices','transactions',
                           'open_finance_connections','external_accounts','external_transactions']
  LOOP
    EXECUTE format('CREATE TRIGGER %I_updated_at BEFORE UPDATE ON %I
                    FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t, t);
  END LOOP;
END $$;

-- Row Level Security --------------------------------------------------------------------
-- A API executa `SET LOCAL app.current_user_id = '<uuid>'` em cada transação
-- de banco; mesmo um bug de consulta não expõe dados de outro usuário.
CREATE FUNCTION current_app_user() RETURNS UUID LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('app.current_user_id', true), '')::uuid
$$;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['auth_sessions','accounts','cards','categories','projects','financial_goals',
                           'recurring_transactions','recurring_pauses','installment_groups','installments',
                           'invoices','invoice_payments','transactions','open_finance_connections',
                           'external_accounts','external_transactions']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I_isolation ON %I USING (user_id = current_app_user())
                    WITH CHECK (user_id = current_app_user())', t, t);
  END LOOP;
END $$;

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;
CREATE POLICY users_self ON users USING (id = current_app_user()) WITH CHECK (id = current_app_user());

COMMIT;
