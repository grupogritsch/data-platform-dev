-- ============================================================================
-- GOLD — 4. DOMÍNIO MANUTENÇÃO & GESTÃO DE FROTAS
--
-- Views analíticas e agregadas prontas para consumo no Looker Studio / BI
-- Integração: Bluefleet (SQL Server Master) + Insumos de Manutenção TruckPag
--
-- Data: 2026-08-25
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS torre;

-- ----------------------------------------------------------------------------
-- 4.1 VIEW DIMENSÃO MESTRE DE FROTA: Cadastro e Especificações Técnicas
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_manutencao_frota_master AS
SELECT
  v.placa,
  COALESCE(v.modelo_raw, 'NÃO INFORMADO')                               AS modelo,
  COALESCE(v.grupo_veiculo, 'Leve')                                     AS grupo_veiculo,
  COALESCE(v.filial_operacional, 'OUTROS')                              AS filial_nome,
  COALESCE(v.situacao_veiculo, 'ATIVO')                                 AS situacao_veiculo,
  v.montadora,
  v.ano_modelo,
  v.ano_fabricacao,
  (EXTRACT(YEAR FROM CURRENT_DATE) - COALESCE(v.ano_fabricacao, EXTRACT(YEAR FROM CURRENT_DATE)::smallint)) AS idade_veiculo_anos,
  v.tanque_litros,
  v.odometro_confirmado,
  v.ultima_manutencao,
  v.ultima_manutencao_preventiva,
  v.km_ultima_manutencao_preventiva,
  -- Diferencial de KM rodados desde a última preventiva
  CASE 
    WHEN v.odometro_confirmado IS NOT NULL AND v.km_ultima_manutencao_preventiva IS NOT NULL
    THEN GREATEST(0, (v.odometro_confirmado - v.km_ultima_manutencao_preventiva))
    ELSE NULL
  END                                                                   AS km_rodados_desde_preventiva,
  -- Classificação de Status da Preventiva (Tempo)
  CASE
    WHEN v.ultima_manutencao_preventiva IS NULL THEN 'SEM REGISTRO'
    WHEN v.ultima_manutencao_preventiva < (CURRENT_DATE - INTERVAL '180 days') THEN 'VENCIDA (>180 dias)'
    WHEN v.ultima_manutencao_preventiva < (CURRENT_DATE - INTERVAL '150 days') THEN 'ATENÇÃO (VENCE EM 30d)'
    ELSE 'EM DIA'
  END                                                                   AS status_preventiva_tempo,
  -- Classificação de Status da Preventiva (KM)
  CASE
    WHEN v.km_ultima_manutencao_preventiva IS NULL THEN 'SEM REGISTRO KM'
    WHEN (v.odometro_confirmado - v.km_ultima_manutencao_preventiva) > 20000 THEN 'CRÍTICO (>20.000 km)'
    WHEN (v.odometro_confirmado - v.km_ultima_manutencao_preventiva) > 10000 THEN 'ATENÇÃO (>10.000 km)'
    ELSE 'EM DIA KM'
  END                                                                   AS status_preventiva_km
FROM torre.gold_dim_veiculo v;

COMMENT ON VIEW torre.vw_bi_manutencao_frota_master IS 
  'Dimensão enriquecida de veículos com odômetros, preventivas e idade da frota.';

-- ----------------------------------------------------------------------------
-- 4.2 VIEW ANALÍTICA DE INSUMOS & ITENS DE MANUTENÇÃO TRUCKPAG (ARLA / OFICINA)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_manutencao_insumos_truckpag AS
SELECT
  t.transacao,
  t.data_transacao,
  DATE(t.data_transacao AT TIME ZONE 'America/Sao_Paulo')               AS data,
  TO_CHAR(t.data_transacao AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM') AS ano_mes,
  UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', ''))                   AS placa,
  COALESCE(f.filial_nome, t.garagem)                                   AS filial_nome,
  f.filial_estado,
  f.filial_regiao,
  COALESCE(v.grupo_veiculo, 'Outros')                                   AS grupo_veiculo,
  t.nome_combustivel                                                    AS item_manutencao,
  CASE 
    WHEN LOWER(t.nome_combustivel) LIKE '%arla%' THEN 'ARLA 32'
    WHEN LOWER(t.nome_combustivel) LIKE '%oleo%' OR LOWER(t.nome_combustivel) LIKE '%lubrificante%' THEN 'LUBRIFICANTES'
    WHEN LOWER(t.nome_combustivel) LIKE '%lavagem%' OR LOWER(t.nome_combustivel) LIKE '%ducha%' THEN 'LAVAGEM'
    ELSE 'OUTROS INSUMOS'
  END                                                                   AS categoria_insumo,
  t.litragem                                                            AS quantidade_unidades,
  t.valor                                                               AS valor_total,
  t.nome_fantasia_posto                                                 AS estabelecimento,
  t.cidade_posto,
  t.uf_posto
FROM torre.integration_truckpag_transacoes t
LEFT JOIN torre.gold_dim_filial f ON f.garagem = t.garagem
LEFT JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(REPLACE(v.placa, '-', ''), ' ', '')) = UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', ''))
WHERE t.servico NOT IN ('ABASTECIMENTO', 'PEDAGIO', 'Estorno')
   OR (t.servico = 'ABASTECIMENTO' AND LOWER(t.nome_combustivel) LIKE '%arla%');

COMMENT ON VIEW torre.vw_bi_manutencao_insumos_truckpag IS 
  'Gastos com insumos operacionais e de manutenção faturados via TruckPag (Arla, óleos, etc).';

-- ----------------------------------------------------------------------------
-- 4.3 VIEW AGREGADA: Indicadores Mensais de Manutenção e Frota por Filial
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_manutencao_filial_resumo AS
WITH 
frota_agregada AS (
  SELECT
    filial_nome,
    COUNT(*)                                                            AS total_veiculos,
    COUNT(*) FILTER (WHERE situacao_veiculo = 'ATIVO')                 AS veiculos_ativos,
    COUNT(*) FILTER (WHERE status_preventiva_tempo = 'EM DIA')          AS preventivas_em_dia,
    COUNT(*) FILTER (WHERE status_preventiva_tempo = 'ATENÇÃO (VENCE EM 30d)') AS preventivas_a_vencer,
    COUNT(*) FILTER (WHERE status_preventiva_tempo = 'VENCIDA (>180 dias)')     AS preventivas_vencidas,
    COUNT(*) FILTER (WHERE status_preventiva_tempo = 'SEM REGISTRO')   AS preventivas_sem_registro,
    ROUND(AVG(idade_veiculo_anos)::numeric, 1)                         AS idade_media_frota_anos,
    ROUND(AVG(odometro_confirmado)::numeric, 0)                         AS odometro_medio
  FROM torre.vw_bi_manutencao_frota_master
  GROUP BY 1
),
insumos_agregados AS (
  SELECT
    ano_mes,
    filial_nome,
    ROUND(SUM(valor_total)::numeric, 2)                                 AS total_gasto_insumos,
    ROUND(SUM(CASE WHEN categoria_insumo = 'ARLA 32' THEN valor_total ELSE 0 END)::numeric, 2) AS gasto_arla_32,
    ROUND(SUM(CASE WHEN categoria_insumo = 'LUBRIFICANTES' THEN valor_total ELSE 0 END)::numeric, 2) AS gasto_lubrificantes
  FROM torre.vw_bi_manutencao_insumos_truckpag
  GROUP BY 1, 2
)
SELECT
  COALESCE(i.ano_mes, TO_CHAR(CURRENT_DATE, 'YYYY-MM'))                 AS ano_mes,
  f.filial_nome,
  f.total_veiculos,
  f.veiculos_ativos,
  f.preventivas_em_dia,
  f.preventivas_a_vencer,
  f.preventivas_vencidas,
  f.preventivas_sem_registro,
  ROUND((f.preventivas_em_dia::numeric / NULLIF(f.veiculos_ativos, 0) * 100)::numeric, 1) AS taxa_conformidade_preventiva_pct,
  f.idade_media_frota_anos,
  f.odometro_medio,
  COALESCE(i.total_gasto_insumos, 0.00)                                 AS total_gasto_insumos,
  COALESCE(i.gasto_arla_32, 0.00)                                       AS gasto_arla_32,
  COALESCE(i.gasto_lubrificantes, 0.00)                                 AS gasto_lubrificantes
FROM frota_agregada f
LEFT JOIN insumos_agregados i ON i.filial_nome = f.filial_nome;

COMMENT ON VIEW torre.vw_bi_manutencao_filial_resumo IS 
  'Resumo mensal de conformidade de manutenção preventiva e gastos de insumos por filial.';
