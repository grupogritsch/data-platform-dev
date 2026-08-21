-- ============================================================================
-- Schemas da plataforma. Idempotente — pode rodar quantas vezes quiser.
--
-- Aplicar:  docker exec -i postgres psql -U admin -d dw < postgres/sql/00_schemas.sql
--
-- ATENCAO: postgres/scripts/ e montado em /docker-entrypoint-initdb.d e SO roda
-- na primeira inicializacao de um volume vazio. Para evolucao de schema use
-- ESTA pasta (postgres/sql/), aplicada manualmente ou por workflow.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS bronze;   -- dados crus, fieis a origem
CREATE SCHEMA IF NOT EXISTS silver;   -- tipado, deduplicado, unificado entre fontes
CREATE SCHEMA IF NOT EXISTS torre;    -- gold (convencao ja usada pelos 28 workflows GOLD)

-- Os tres schemas podem ja existir de antes, com DONO DIFERENTE do role usado
-- para aplicar este script (confirmado real em 04/08/2026: "must be owner of
-- schema bronze" — nao e so o torre, como se pensava antes). COMMENT ON SCHEMA
-- exige ser dono; sem esse privilegio o comando falha. Cada um envolvido em
-- DO/EXCEPTION para o script continuar idempotente em qualquer ambiente, com
-- ou sem esse privilegio — e so documentacao, nao afeta nada funcional.
DO $$ BEGIN
  EXECUTE 'COMMENT ON SCHEMA bronze IS ''Camada raw. Tipos permissivos (TEXT/JSONB), nenhuma regra de negocio. Ingestao nunca deve falhar por dado inesperado.''';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'Sem permissao para comentar o schema bronze (dono e outro role) — ignorando, nao afeta nada.';
END $$;

DO $$ BEGIN
  EXECUTE 'COMMENT ON SCHEMA silver IS ''Camada tipada e unificada entre fontes (3S, Nuxeo). Uma linha = um fato limpo.''';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'Sem permissao para comentar o schema silver (dono e outro role) — ignorando, nao afeta nada.';
END $$;

DO $$ BEGIN
  EXECUTE 'COMMENT ON SCHEMA torre IS ''Camada gold. Objetos prefixados com gold_ e consumidos por relatorios e dashboards.''';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'Sem permissao para comentar o schema torre (dono e outro role) — ignorando, nao afeta nada.';
END $$;
