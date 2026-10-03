-- Painéis personalizados (dashboards).
--
-- Guardam apenas configuração; os números são sempre calculados a partir
-- das transações. Filtro do painel e gráficos ficam em JSONB porque o
-- formato evolui junto com a interface (ver lib/domain/models/dashboard.dart).
BEGIN;

CREATE TABLE dashboards (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL CHECK (length(trim(name)) > 0),
  is_default  BOOLEAN NOT NULL DEFAULT false,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  filter      JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(filter) = 'object'),
  charts      JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(charts) = 'array'),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, user_id)
);

CREATE INDEX dashboards_user_idx ON dashboards (user_id, sort_order);
-- No máximo um painel padrão por usuário.
CREATE UNIQUE INDEX dashboards_one_default ON dashboards (user_id) WHERE is_default;

CREATE TRIGGER dashboards_updated_at BEFORE UPDATE ON dashboards
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE dashboards ENABLE ROW LEVEL SECURITY;
ALTER TABLE dashboards FORCE ROW LEVEL SECURITY;
CREATE POLICY dashboards_isolation ON dashboards USING (user_id = current_app_user())
  WITH CHECK (user_id = current_app_user());

COMMIT;
