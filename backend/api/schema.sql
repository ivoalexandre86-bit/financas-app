-- Finanças · API na nuvem. Aplicado automaticamente ao iniciar o servidor
-- (todos os comandos são idempotentes).

create extension if not exists pgcrypto;

create table if not exists users (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  email         text not null unique,
  password_hash text not null,
  is_admin      boolean not null default false,
  created_at    timestamptz not null default now()
);

-- Assinatura: teste grátis contado do cadastro, validade do plano pago
-- (RevenueCat) e cortesia para contas criadas pelo administrador. Quem já
-- existia antes do cadastro aberto foi criado pelo administrador.
alter table users add column if not exists trial_ends_at timestamptz not null
  default (now() + interval '30 days');
alter table users add column if not exists paid_until timestamptz;
alter table users add column if not exists plan text;
alter table users add column if not exists free_access boolean;
update users set free_access = true where free_access is null;
alter table users alter column free_access set default false;
alter table users alter column free_access set not null;

-- Dados do app: um documento JSON por registro (coleção + id), isolado por
-- usuário. Exclusões ficam marcadas (deleted) para propagar aos aparelhos.
create table if not exists app_docs (
  user_id    uuid not null references users (id) on delete cascade,
  coll       text not null,
  id         text not null,
  data       jsonb,
  deleted    boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, coll, id)
);

-- Open Finance (Pluggy): conexões (items) que cada usuário registrou. O
-- servidor só devolve dados de items do próprio usuário.
create table if not exists of_items (
  item_id    text primary key,
  user_id    uuid not null references users (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists of_items_user_idx on of_items (user_id);

-- WhatsApp ------------------------------------------------------------------

-- Número do WhatsApp (wa_id, só dígitos) ligado a uma conta do app.
create table if not exists whatsapp_links (
  wa_id      text primary key,
  user_id    uuid not null unique references users (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Código de vínculo gerado no app e enviado pelo WhatsApp ("VINCULAR 123456").
create table if not exists whatsapp_link_codes (
  user_id    uuid primary key references users (id) on delete cascade,
  code       text not null unique,
  expires_at timestamptz not null
);

-- Lançamentos lidos pela IA aguardando Confirmar / Corrigir / Cancelar.
create table if not exists whatsapp_drafts (
  id         text primary key,
  user_id    uuid not null references users (id) on delete cascade,
  wa_id      text not null,
  draft      jsonb not null,
  state      text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists whatsapp_drafts_user_state
  on whatsapp_drafts (user_id, state, updated_at desc);

-- Leituras da IA pelo WhatsApp por usuário e mês (limite mensal).
create table if not exists whatsapp_usage (
  user_id uuid not null references users (id) on delete cascade,
  month   text not null,
  reads   int not null default 0,
  primary key (user_id, month)
);

-- Mensagens já processadas (a Meta pode reenviar o mesmo webhook).
create table if not exists whatsapp_seen (
  message_id text primary key,
  seen_at    timestamptz not null default now()
);

-- Número do bot conectado pelo Cadastro incorporado da Meta (linha única).
-- Vale mais que WHATSAPP_TOKEN / WHATSAPP_PHONE_NUMBER_ID do ambiente.
create table if not exists whatsapp_config (
  id              int primary key default 1 check (id = 1),
  access_token    text not null,
  phone_number_id text not null,
  waba_id         text not null,
  bot_number      text,
  updated_at      timestamptz not null default now()
);

-- Despesas compartilhadas ---------------------------------------------------
-- Grupos (casa, casal, família…) com participantes que são usuários do app.
-- A despesa original fica só no orçamento de quem a lançou; aqui ficam a
-- divisão (percentual e valor de cada participante, gravados no momento do
-- lançamento), os pagamentos de cada parte e os acertos entre participantes.
-- Percentuais em pontos-base: 10000 = 100%.

create table if not exists share_groups (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references users (id) on delete cascade,
  name       text not null,
  kind       text not null default 'household',
  archived   boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- role: owner | manager | member. status: invited | active | rejected |
-- revoked | left. category_map: categoria do orçamento do usuário → categoria
-- do grupo (lembra a última escolha ao compartilhar).
create table if not exists share_members (
  group_id     uuid not null references share_groups (id) on delete cascade,
  user_id      uuid not null references users (id) on delete cascade,
  role         text not null default 'member',
  status       text not null default 'invited',
  invited_by   uuid references users (id) on delete set null,
  category_map jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists share_members_user_idx on share_members (user_id, status);

-- Categorias do grupo e percentual padrão de cada participante.
create table if not exists share_categories (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references share_groups (id) on delete cascade,
  name        text not null,
  sort        int not null default 0,
  percentages jsonb not null default '{}'::jsonb,
  archived    boolean not null default false,
  updated_at  timestamptz not null default now()
);
create index if not exists share_categories_group_idx on share_categories (group_id);

-- Recorrências compartilhadas (regra recorrente do orçamento do dono).
create table if not exists share_recurrences (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references share_groups (id) on delete cascade,
  owner_id       uuid not null references users (id) on delete cascade,
  source_rule_id text not null,
  category_id    uuid references share_categories (id) on delete set null,
  description    text not null,
  override       jsonb,
  paused         boolean not null default false,
  canceled_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index if not exists share_recurrences_rule_idx
  on share_recurrences (group_id, owner_id, source_rule_id) where canceled_at is null;

-- Despesa compartilhada: espelho da transação original (valor total uma
-- única vez). source_key identifica a origem no orçamento do dono
-- (id da transação ou "r:<regra>:<data>" para ocorrências de recorrência).
create table if not exists share_expenses (
  id              uuid primary key default gen_random_uuid(),
  group_id        uuid not null references share_groups (id) on delete cascade,
  owner_id        uuid not null references users (id) on delete cascade,
  category_id     uuid references share_categories (id) on delete set null,
  category_name   text not null,
  description     text not null,
  total           bigint not null check (total > 0),
  date            date not null,
  due_date        date,
  source          text not null default 'manual',
  source_key      text,
  recurrence_id   uuid references share_recurrences (id) on delete set null,
  occurrence_date date,
  overridden      boolean not null default false,
  notes           text not null default '',
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index if not exists share_expenses_source_idx
  on share_expenses (group_id, owner_id, source_key) where deleted_at is null;
create index if not exists share_expenses_group_idx on share_expenses (group_id, date);

-- Parte de cada participante, gravada no lançamento (histórico preservado).
create table if not exists share_allocations (
  expense_id uuid not null references share_expenses (id) on delete cascade,
  user_id    uuid not null references users (id) on delete cascade,
  bp         int not null check (bp between 0 and 10000),
  amount     bigint not null check (amount >= 0),
  primary key (expense_id, user_id)
);

-- Acerto entre participantes (transferência); quita partes em aberto.
create table if not exists share_settlements (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references share_groups (id) on delete cascade,
  from_user   uuid not null references users (id) on delete cascade,
  to_user     uuid not null references users (id) on delete cascade,
  amount      bigint not null check (amount > 0),
  date        date not null,
  note        text not null default '',
  recorded_by uuid references users (id) on delete set null,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now()
);

-- Pagamento de uma parte (avulso ou gerado por um acerto).
create table if not exists share_payments (
  id            uuid primary key default gen_random_uuid(),
  expense_id    uuid not null references share_expenses (id) on delete cascade,
  user_id       uuid not null references users (id) on delete cascade,
  amount        bigint not null check (amount > 0),
  date          date not null,
  note          text not null default '',
  settlement_id uuid references share_settlements (id) on delete cascade,
  recorded_by   uuid references users (id) on delete set null,
  deleted_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists share_payments_expense_idx on share_payments (expense_id);

-- Histórico (auditoria) de ações no grupo.
create table if not exists share_audit (
  id         bigserial primary key,
  group_id   uuid not null references share_groups (id) on delete cascade,
  actor_id   uuid references users (id) on delete set null,
  action     text not null,
  details    jsonb not null default '{}'::jsonb,
  at         timestamptz not null default now()
);
create index if not exists share_audit_group_idx on share_audit (group_id, at desc);
