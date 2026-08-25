-- ============================================================================
-- GOLD — 3. DOMÍNIO TELEMETRIA, RASTREADORES & SEGURANÇA OPERACIONAL
--
-- Views analíticas e agregadas prontas para consumo no Looker Studio / BI
-- Integração: 3STEC + NUXEO + OMNILINK + Regras de Saneamento Torre de Controle
--
-- Data: 2026-08-25
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS torre;

-- ----------------------------------------------------------------------------
-- 3.1 VIEW ANALÍTICA DETALHADA: Eventos de Telemetria Saneados
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_telemetria_analitico AS
SELECT
  t.placa,
  t.provedor_rastreador,
  t.velocidade_registrada,
  t.data_hora_alerta,
  t.data_hora_timestamp,
  t.data_ref                                                            AS data,
  TO_CHAR(t.data_ref, 'YYYY-MM')                                        AS ano_mes,
  EXTRACT(YEAR FROM t.data_ref)::int                                    AS ano,
  EXTRACT(MONTH FROM t.data_ref)::int                                   AS mes,
  t.latitude,
  t.longitude,
  t.endereco,
  t.cidade,
  t.estado,
  t.nome_evento,
  COALESCE(t.filial_operacional, 'OUTROS')                              AS filial_nome,
  COALESCE(t.modelo, '')                                                AS modelo,
  COALESCE(t.grupo_veiculo, 'Leve')                                     AS grupo_veiculo,
  t.situacao_veiculo,
  -- Limites Regulamentares por Categoria (Pesados 90 km/h | Leves 110 km/h)
  CASE 
    WHEN t.grupo_veiculo IN ('Bitruck', 'Truck', 'Toco', '3/4') THEN 90
    ELSE 110
  END                                                                   AS velocidade_limite,
  -- Gravidade da Infração
  CASE
    WHEN t.grupo_veiculo IN ('Bitruck', 'Truck', 'Toco', '3/4') AND t.velocidade_registrada > 105 THEN 'GRAVE'
    WHEN t.grupo_veiculo IN ('Bitruck', 'Truck', 'Toco', '3/4') AND t.velocidade_registrada > 90 THEN 'MODERADA'
    WHEN t.velocidade_registrada > 130 THEN 'GRAVE'
    ELSE 'MODERADA'
  END                                                                   AS gravidade_excesso,
  -- Desvio de Velocidade Acima do Limite
  ROUND(
    (t.velocidade_registrada - 
     CASE WHEN t.grupo_veiculo IN ('Bitruck', 'Truck', 'Toco', '3/4') THEN 90 ELSE 110 END)::numeric, 1
  )                                                                     AS excesso_kmh
FROM torre.vw_alertas_telemetria_saneados t;

COMMENT ON VIEW torre.vw_bi_telemetria_analitico IS 
  'Eventos individuais de telemetria saneados sem ruídos e pontos sombra.';

-- ----------------------------------------------------------------------------
-- 3.2 VIEW AGREGADA: Indicadores Mensais de Telemetria por Filial
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_telemetria_filial_mensal AS
SELECT
  t.ano_mes,
  t.ano,
  t.mes,
  t.filial_nome,
  t.grupo_veiculo,
  t.provedor_rastreador,
  COUNT(*)                                                              AS qtd_excessos_velocidade,
  COUNT(DISTINCT t.placa)                                               AS qtd_veiculos_infratores,
  COUNT(*) FILTER (WHERE t.gravidade_excesso = 'GRAVE')                 AS qtd_excessos_graves,
  COUNT(*) FILTER (WHERE t.gravidade_excesso = 'MODERADA')              AS qtd_excessos_moderados,
  ROUND(AVG(t.velocidade_registrada)::numeric, 1)                      AS velocidade_media_infracao,
  MAX(t.velocidade_registrada)                                          AS velocidade_maxima_registrada,
  ROUND(AVG(t.excesso_kmh)::numeric, 1)                                AS excesso_medio_kmh,
  ROUND(
    (COUNT(*) FILTER (WHERE t.gravidade_excesso = 'GRAVE')::numeric / NULLIF(COUNT(*), 0) * 100)::numeric, 2
  )                                                                     AS pct_infracoes_graves
FROM torre.vw_bi_telemetria_analitico t
GROUP BY 1, 2, 3, 4, 5, 6;

COMMENT ON VIEW torre.vw_bi_telemetria_filial_mensal IS 
  'Agregação mensal de indicadores de segurança e excessos por filial.';

-- ----------------------------------------------------------------------------
-- 3.3 VIEW DE RANKING DE VEÍCULOS E CONDUTORES CRÍTICOS
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_telemetria_ranking_infratores AS
SELECT
  t.placa,
  t.filial_nome,
  t.modelo,
  t.grupo_veiculo,
  t.provedor_rastreador,
  t.ano_mes,
  COUNT(*)                                                              AS total_excessos,
  COUNT(*) FILTER (WHERE t.gravidade_excesso = 'GRAVE')                 AS excessos_graves,
  MAX(t.velocidade_registrada)                                          AS velocidade_pico,
  ROUND(AVG(t.velocidade_registrada)::numeric, 1)                      AS velocidade_media_infracao,
  MAX(t.data_hora_timestamp)                                            AS ultima_infracao_data
FROM torre.vw_bi_telemetria_analitico t
GROUP BY 1, 2, 3, 4, 5, 6;

COMMENT ON VIEW torre.vw_bi_telemetria_ranking_infratores IS 
  'Ranking mensal de veículos e placas críticas com excessos de velocidade para ação operacional.';

-- ----------------------------------------------------------------------------
-- 3.4 VIEW DE STATUS DE COMUNICAÇÃO & TRANSMISSÃO DOS RASTREADORES
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_telemetria_status_comunicacao AS
WITH 
ultimas_3s AS (
  SELECT 
    UPPER(REPLACE(REPLACE(placa, '-', ''), ' ', '')) AS placa,
    '3STEC' AS provedor,
    MAX(to_timestamp(data_gps, 'DD/MM/YYYY HH24:MI:SS')) AS ultima_comunicacao
  FROM bronze.tres_s_ultima_posicao
  WHERE data_gps IS NOT NULL
  GROUP BY 1
),
ultimas_nuxeo AS (
  SELECT 
    UPPER(REPLACE(REPLACE(placa, '-', ''), ' ', '')) AS placa,
    CASE 
      WHEN UPPER(COALESCE(complemento, payload_json->>'complement', '')) LIKE '%OMNILINK%' THEN 'OMNILINK'
      ELSE 'NUXEO'
    END AS provedor,
    MAX(to_timestamp(data_gps, 'DD/MM/YYYY HH24:MI:SS')) AS ultima_comunicacao
  FROM bronze.nuxeo_veiculos_posicao
  WHERE data_gps IS NOT NULL
  GROUP BY 1, 2
),
comunicacoes_unificadas AS (
  SELECT placa, provedor, ultima_comunicacao FROM ultimas_3s
  UNION ALL
  SELECT placa, provedor, ultima_comunicacao FROM ultimas_nuxeo
)
SELECT
  v.placa,
  COALESCE(v.filial_operacional, 'OUTROS')                              AS filial_nome,
  COALESCE(v.modelo_raw, '')                                            AS modelo,
  COALESCE(v.grupo_veiculo, 'Leve')                                     AS grupo_veiculo,
  v.situacao_veiculo,
  c.provedor                                                            AS provedor_rastreador,
  c.ultima_comunicacao,
  -- Tempo sem transmitir em dias / horas
  ROUND(
    (EXTRACT(EPOCH FROM (NOW() - c.ultima_comunicacao)) / 86400.0)::numeric, 1
  )                                                                     AS dias_sem_comunicar,
  -- Status de Comunicação
  CASE
    WHEN c.ultima_comunicacao IS NULL THEN 'SEM REGISTRO GPS'
    WHEN c.ultima_comunicacao >= (NOW() - INTERVAL '24 hours') THEN 'ONLINE (<24h)'
    WHEN c.ultima_comunicacao >= (NOW() - INTERVAL '72 hours') THEN 'ATENÇÃO (24h a 72h)'
    ELSE 'OFFLINE (>72h)'
  END                                                                   AS status_comunicacao
FROM torre.gold_dim_veiculo v
LEFT JOIN comunicacoes_unificadas c ON c.placa = UPPER(REPLACE(REPLACE(v.placa, '-', ''), ' ', ''))
WHERE v.situacao_veiculo = 'ATIVO';

COMMENT ON VIEW torre.vw_bi_telemetria_status_comunicacao IS 
  'Status em tempo real de comunicação dos rastreadores para identificar antenas desligadas ou veículos inativos.';
