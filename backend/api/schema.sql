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

-- Mensagens já processadas (a Meta pode reenviar o mesmo webhook).
create table if not exists whatsapp_seen (
  message_id text primary key,
  seen_at    timestamptz not null default now()
);
