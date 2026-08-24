#!/usr/bin/env python3
"""
Nova Definição de View Saneada de Telemetria — Unificando Posições e Eventos
"""
import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

conn = psycopg2.connect(
    host='192.168.0.37',
    port=5433,
    database='dw',
    user='gabriel_brittes',
    password=os.getenv('DW_PASSWORD')
)
cur = conn.cursor()

sql_nova_view = """
CREATE SCHEMA IF NOT EXISTS torre;

DROP VIEW IF EXISTS torre.vw_alertas_telemetria_saneados CASCADE;
DROP VIEW IF EXISTS torre.vw_telemetria_anomalias_descartadas CASCADE;
DROP VIEW IF EXISTS torre.vw_email_destinatarios_filiais CASCADE;

-- ============================================================================
-- 1. VIEW UNIFICADA E SANEADA DE ALERTAS DE TELEMETRIA
-- ============================================================================
CREATE OR REPLACE VIEW torre.vw_alertas_telemetria_saneados AS
WITH 
-- 1.1 Eventos explícitos NUXEO (array eventos_json)
eventos_nuxeo AS (
  SELECT DISTINCT ON (UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')), COALESCE(evt->>'dateEvent', evt->>'date'), (evt->>'speed'))
    UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) AS placa,
    'NUXEO' AS provedor_rastreador,
    NULLIF(REPLACE(evt->>'speed', ',', '.'), '')::numeric AS velocidade_registrada,
    COALESCE(evt->>'dateEvent', evt->>'date') AS data_hora_alerta,
    to_timestamp(COALESCE(evt->>'dateEvent', evt->>'date'), 'DD/MM/YYYY HH24:MI:SS') AS data_hora_timestamp,
    COALESCE(NULLIF(evt->>'latitude', '')::numeric, t.latitude) AS latitude,
    COALESCE(NULLIF(evt->>'longitude', '')::numeric, t.longitude) AS longitude,
    COALESCE(NULLIF(evt->>'address', ''), t.endereco) AS endereco,
    COALESCE(NULLIF(evt->>'city', ''), t.cidade) AS cidade,
    COALESCE(NULLIF(evt->>'state', ''), t.estado) AS estado,
    COALESCE(evt->>'nameEvent', evt->>'event', 'Excesso de Velocidade') AS nome_evento
  FROM bronze.nuxeo_posicao_eventos t,
  LATERAL jsonb_array_elements(t.eventos_json) AS evt
  WHERE t.eventos_json IS NOT NULL
    AND jsonb_array_length(t.eventos_json) > 0
    AND (lower(COALESCE(evt->>'nameEvent', evt->>'event', '')) LIKE '%excesso%' 
         OR lower(COALESCE(evt->>'nameEvent', evt->>'event', '')) LIKE '%velocidade%')
  ORDER BY UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')), COALESCE(evt->>'dateEvent', evt->>'date'), (evt->>'speed'), t.ingested_at DESC
),

-- 1.2 Posições NUXEO com excesso de velocidade por categoria (>90 caminhão, >110 leve)
posicoes_nuxeo_excesso AS (
  SELECT DISTINCT ON (UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')), t.data_gps, t.velocidade)
    UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) AS placa,
    'NUXEO' AS provedor_rastreador,
    t.velocidade AS velocidade_registrada,
    t.data_gps AS data_hora_alerta,
    to_timestamp(t.data_gps, 'DD/MM/YYYY HH24:MI:SS') AS data_hora_timestamp,
    t.latitude,
    t.longitude,
    t.endereco,
    t.cidade,
    t.estado,
    'Excesso de Velocidade (Telemetria)' AS nome_evento
  FROM bronze.nuxeo_posicao_eventos t
  LEFT JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) = v.placa
  WHERE t.velocidade IS NOT NULL
    AND t.data_gps IS NOT NULL
    AND (
      (COALESCE(v.grupo_veiculo, '') IN ('Bitruck', 'Truck', 'Toco', '3/4') AND t.velocidade > 90)
      OR (COALESCE(v.grupo_veiculo, 'Leve') NOT IN ('Bitruck', 'Truck', 'Toco', '3/4') AND t.velocidade > 110)
    )
  ORDER BY UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')), t.data_gps, t.velocidade, t.ingested_at DESC
),

-- 1.3 Eventos 3STEC
eventos_3s AS (
  SELECT DISTINCT ON (UPPER(REPLACE(REPLACE(COALESCE(v.placa, ''), '-', ''), ' ', '')), e.data_evento, e.velocidade)
    UPPER(REPLACE(REPLACE(COALESCE(v.placa, ''), '-', ''), ' ', '')) AS placa,
    '3STEC' AS provedor_rastreador,
    NULLIF(REPLACE(e.velocidade, ',', '.'), '')::numeric AS velocidade_registrada,
    e.data_evento AS data_hora_alerta,
    to_timestamp(e.data_evento, 'DD/MM/YYYY HH24:MI:SS') AS data_hora_timestamp,
    NULLIF(REPLACE(e.latitude, ',', '.'), '')::numeric AS latitude,
    NULLIF(REPLACE(e.longitude, ',', '.'), '')::numeric AS longitude,
    e.endereco,
    e.cidade,
    e.uf AS estado,
    '3S Excesso Velocidade' AS nome_evento
  FROM bronze.tres_s_eventos e
  JOIN bronze.tres_s_veiculos v ON v.id_equipamento = e.id_equipamento
  WHERE e.tipo_evento = 'ALERTA_VELOCIDADE'
    AND e.velocidade IS NOT NULL
  ORDER BY UPPER(REPLACE(REPLACE(COALESCE(v.placa, ''), '-', ''), ' ', '')), e.data_evento, e.velocidade, e.ingested_at DESC
),

-- 1.4 União de todos os eventos com deduplicação
todos_eventos AS (
  SELECT DISTINCT ON (placa, data_hora_alerta, velocidade_registrada)
    *
  FROM (
    SELECT * FROM eventos_nuxeo
    UNION ALL
    SELECT * FROM posicoes_nuxeo_excesso
    UNION ALL
    SELECT * FROM eventos_3s
  ) unificados
  ORDER BY placa, data_hora_alerta, velocidade_registrada, provedor_rastreador
),

eventos_enriquecidos AS (
  SELECT
    ev.placa,
    ev.provedor_rastreador,
    ev.velocidade_registrada,
    ev.data_hora_alerta,
    ev.data_hora_timestamp,
    ev.data_hora_timestamp::date AS data_ref,
    ev.latitude,
    ev.longitude,
    ev.endereco,
    ev.cidade,
    ev.estado,
    ev.nome_evento,
    COALESCE(v.filial_operacional, 'DESCONHECIDA') AS filial_operacional,
    COALESCE(v.modelo_raw, '')                     AS modelo,
    COALESCE(v.grupo_veiculo, 'Leve')              AS grupo_veiculo,
    COALESCE(v.situacao_veiculo, 'ATIVO')          AS situacao_veiculo,
    -- Classificação de anomalia / motivo de descarte
    CASE
      WHEN ev.velocidade_registrada IS NULL OR ev.velocidade_registrada <= 0 THEN 'VELOCIDADE_INVALIDA'
      WHEN ev.velocidade_registrada > 160 THEN 'PONTO_SOMBRA_MAX_160'
      WHEN COALESCE(v.grupo_veiculo, '') IN ('Bitruck', 'Truck', 'Toco', '3/4') 
           AND ev.velocidade_registrada > 120 THEN 'PONTO_SOMBRA_CAMINHAO_120'
      WHEN COALESCE(v.situacao_veiculo, '') IN ('VENDIDO', 'BAIXADO', 'VEÍCULOS VENDIDOS', 'VEÍCULOS ROUBADOS') THEN 'VEICULO_INATIVO'
      ELSE 'VALIDO'
    END AS status_validacao
  FROM todos_eventos ev
  LEFT JOIN torre.gold_dim_veiculo v ON v.placa = ev.placa
)
SELECT 
  placa,
  provedor_rastreador,
  velocidade_registrada,
  data_hora_alerta,
  data_hora_timestamp,
  data_ref,
  latitude,
  longitude,
  endereco,
  cidade,
  estado,
  nome_evento,
  filial_operacional,
  modelo,
  grupo_veiculo,
  situacao_veiculo
FROM eventos_enriquecidos
WHERE status_validacao = 'VALIDO';

COMMENT ON VIEW torre.vw_alertas_telemetria_saneados IS 
  'View consolidada de alertas de telemetria unificada (Nuxeo + 3STEC), '
  'deduplicada, enriquecida com cadastro Master Gold e com filtro de anomalias (pontos sombra > 160 km/h e caminhões > 120 km/h).';

-- ============================================================================
-- 2. VIEW DE AUDITORIA DE ANOMALIAS DESCARTADAS
-- ============================================================================
CREATE OR REPLACE VIEW torre.vw_telemetria_anomalias_descartadas AS
WITH 
todos_eventos AS (
  SELECT DISTINCT ON (placa, data_hora_alerta, velocidade_registrada)
    *
  FROM (
    SELECT 
      UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) AS placa,
      'NUXEO' AS provedor_rastreador,
      NULLIF(REPLACE(evt->>'speed', ',', '.'), '')::numeric AS velocidade_registrada,
      COALESCE(evt->>'dateEvent', evt->>'date') AS data_hora_alerta,
      to_timestamp(COALESCE(evt->>'dateEvent', evt->>'date'), 'DD/MM/YYYY HH24:MI:SS') AS data_hora_timestamp,
      COALESCE(NULLIF(evt->>'address', ''), t.endereco) AS endereco,
      COALESCE(NULLIF(evt->>'city', ''), t.cidade) AS cidade,
      COALESCE(NULLIF(evt->>'state', ''), t.estado) AS estado,
      COALESCE(evt->>'nameEvent', evt->>'event', 'Excesso de Velocidade') AS nome_evento
    FROM bronze.nuxeo_posicao_eventos t,
    LATERAL jsonb_array_elements(t.eventos_json) AS evt
    WHERE t.eventos_json IS NOT NULL
    
    UNION ALL
    
    SELECT 
      UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) AS placa,
      'NUXEO' AS provedor_rastreador,
      t.velocidade AS velocidade_registrada,
      t.data_gps AS data_hora_alerta,
      to_timestamp(t.data_gps, 'DD/MM/YYYY HH24:MI:SS') AS data_hora_timestamp,
      t.endereco,
      t.cidade,
      t.estado,
      'Excesso de Velocidade (Telemetria)' AS nome_evento
    FROM bronze.nuxeo_posicao_eventos t
    WHERE t.velocidade > 90
    
    UNION ALL
    
    SELECT 
      UPPER(REPLACE(REPLACE(COALESCE(v.placa, ''), '-', ''), ' ', '')) AS placa,
      '3STEC' AS provedor_rastreador,
      NULLIF(REPLACE(e.velocidade, ',', '.'), '')::numeric AS velocidade_registrada,
      e.data_evento AS data_hora_alerta,
      to_timestamp(e.data_evento, 'DD/MM/YYYY HH24:MI:SS') AS data_hora_timestamp,
      e.endereco,
      e.cidade,
      e.uf AS estado,
      '3S Excesso Velocidade' AS nome_evento
    FROM bronze.tres_s_eventos e
    JOIN bronze.tres_s_veiculos v ON v.id_equipamento = e.id_equipamento
    WHERE e.tipo_evento = 'ALERTA_VELOCIDADE'
  ) unificados
  ORDER BY placa, data_hora_alerta, velocidade_registrada, provedor_rastreador
)
SELECT
  ev.placa,
  ev.provedor_rastreador,
  ev.velocidade_registrada,
  ev.data_hora_alerta,
  ev.data_hora_timestamp,
  ev.cidade,
  ev.estado,
  ev.nome_evento,
  COALESCE(v.filial_operacional, 'DESCONHECIDA') AS filial_operacional,
  COALESCE(v.modelo_raw, '')                     AS modelo,
  COALESCE(v.grupo_veiculo, 'Leve')              AS grupo_veiculo,
  COALESCE(v.situacao_veiculo, 'ATIVO')          AS situacao_veiculo,
  CASE
    WHEN ev.velocidade_registrada IS NULL OR ev.velocidade_registrada <= 0 THEN 'VELOCIDADE_INVALIDA'
    WHEN ev.velocidade_registrada > 160 THEN 'PONTO_SOMBRA_MAX_160'
    WHEN COALESCE(v.grupo_veiculo, '') IN ('Bitruck', 'Truck', 'Toco', '3/4') 
         AND ev.velocidade_registrada > 120 THEN 'PONTO_SOMBRA_CAMINHAO_120'
    WHEN COALESCE(v.situacao_veiculo, '') IN ('VENDIDO', 'BAIXADO', 'VEÍCULOS VENDIDOS', 'VEÍCULOS ROUBADOS') THEN 'VEICULO_INATIVO'
    ELSE 'OUTRO_DESCARTE'
  END AS motivo_descarte
FROM todos_eventos ev
LEFT JOIN torre.gold_dim_veiculo v ON v.placa = ev.placa
WHERE (ev.velocidade_registrada IS NULL OR ev.velocidade_registrada <= 0)
   OR (ev.velocidade_registrada > 160)
   OR (COALESCE(v.grupo_veiculo, '') IN ('Bitruck', 'Truck', 'Toco', '3/4') AND ev.velocidade_registrada > 120)
   OR (COALESCE(v.situacao_veiculo, '') IN ('VENDIDO', 'BAIXADO', 'VEÍCULOS VENDIDOS', 'VEÍCULOS ROUBADOS'));

-- ============================================================================
-- 3. VIEW DE DESTINATÁRIOS
-- ============================================================================
CREATE OR REPLACE VIEW torre.vw_email_destinatarios_filiais AS
SELECT 
  f.filial_operacional,
  f.email_destino,
  f.email_cc,
  f.cc_regional,
  COALESCE(c.valor, 'torredecontrole@gritsch.com.br,flavio@gritsch.com.br,fabio.pepplow@gritsch.com.br') AS cc_global,
  f.ativo
FROM torre.email_gritsch_filiais f
CROSS JOIN (
  SELECT valor FROM torre.email_gritsch_config WHERE chave = 'cc_global' LIMIT 1
) c
WHERE f.ativo = true;
"""

cur.execute(sql_nova_view)
conn.commit()
print("✅ Novas views aplicadas com sucesso no DW!")

cur.execute("""
    SELECT 
        COUNT(*) AS total_alertas_validos,
        COUNT(DISTINCT filial_operacional) AS filiais_com_alerta,
        COUNT(DISTINCT placa) AS veiculos_com_alerta,
        MAX(velocidade_registrada) AS vel_maxima,
        ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media
    FROM torre.vw_alertas_telemetria_saneados
    WHERE data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days';
""")
r = cur.fetchone()
print(f"📊 Panorama Geral Saneado (Últimas 2 Semanas):")
print(f"   - Total Alertas: {r[0]}")
print(f"   - Filiais Ativas com Alerta: {r[1]}")
print(f"   - Veículos Ofensores: {r[2]}")
print(f"   - Velocidade Máxima: {r[3]} km/h")
print(f"   - Velocidade Média: {r[4]} km/h")

cur.close()
conn.close()
