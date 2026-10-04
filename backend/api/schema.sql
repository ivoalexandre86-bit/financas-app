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
