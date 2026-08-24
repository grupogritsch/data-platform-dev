-- ============================================================
-- DDL: torre.gold_fato_fechamento_semanal_combustivel
-- Armazena o fechamento histórico semanal de combustível por filial
-- Base para dashboards de tendência de Custo/KM no Metabase/BI
-- ============================================================
CREATE SCHEMA IF NOT EXISTS torre;

CREATE TABLE IF NOT EXISTS torre.gold_fato_fechamento_semanal_combustivel (
  id                      SERIAL PRIMARY KEY,
  semana_inicio           DATE NOT NULL,
  semana_fim              DATE NOT NULL,
  data_referencia         TEXT NOT NULL,
  filial_nome             TEXT NOT NULL,
  garagem                 TEXT NOT NULL,
  total_litros            NUMERIC(12,2) DEFAULT 0,
  total_gasto             NUMERIC(12,2) DEFAULT 0,
  preco_medio_litro       NUMERIC(10,2) DEFAULT 0,
  qtd_veiculos_ativos     INT DEFAULT 0,
  total_km_rodado         NUMERIC(12,2) DEFAULT 0,
  custo_por_km            NUMERIC(10,2),
  custo_extra_anp_total   NUMERIC(12,2) DEFAULT 0,
  resumo_combustivel_json JSONB,
  frota_ativa_json        JSONB,
  postos_utilizados_json  JSONB,
  criado_em               TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT uq_fechamento_semanal_filial UNIQUE (semana_inicio, filial_nome)
);

CREATE INDEX IF NOT EXISTS idx_fechamento_semanal_filial 
  ON torre.gold_fato_fechamento_semanal_combustivel (filial_nome, semana_inicio DESC);

CREATE INDEX IF NOT EXISTS idx_fechamento_semanal_custo_km 
  ON torre.gold_fato_fechamento_semanal_combustivel (custo_por_km);
