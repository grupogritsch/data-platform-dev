-- ============================================================================
-- GOLD — VIEWS EXECUTIVAS PARA LOOKER STUDIO (DATA STUDIO) — DIRETORIA & FILIAIS
--
-- Padronização para conexão direta no BI (PostgreSQL Connector)
-- 4 Pilares Integrados:
-- 1. Abastecimento (Consumo, Km/L, Custo/KM, Suspeitos, Postos)
-- 2. Pedágio (Gastos por Concessionária, Filial, Praça)
-- 3. Telemetria & Rastreador (Excessos saneados, Ranking, Comunicação)
-- 4. Manutenção & Frota (Status preventiva, Idade média, Odômetros)
--
-- Versão Corrigida: 2026-08-24
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS torre;

-- ============================================================================
-- 1. VIEW CONSOLIDADA: PAINEL DIRETORIA (GRAIN: FILIAL / MÊS)
--    Alimenta os Cards de KPIs de Topo e os Gráficos Comparativos de Filiais
-- ============================================================================
CREATE OR REPLACE VIEW torre.vw_bi_diretoria_kpis_mensal AS
WITH 
comb AS (
  SELECT
    TO_CHAR(c.data, 'YYYY-MM') AS ano_mes,
    DATE_TRUNC('month', c.data)::date AS data_mes_inicio,
    COALESCE(c.filial_nome, 'OUTROS') AS filial_nome,
    c.filial_estado,
    c.filial_regiao,
    COUNT(DISTINCT c.transacao) AS qtd_abastecimentos,
    COUNT(DISTINCT c.placa) AS qtd_veiculos_abastecidos,
    ROUND(SUM(c.litragem)::numeric, 2) AS total_litros,
    ROUND(SUM(c.valor_liquido)::numeric, 2) AS total_valor_combustivel,
    ROUND(SUM(c.valor_liquido) / NULLIF(SUM(c.litragem), 0)::numeric, 4) AS preco_medio_litro
  FROM torre.gold_truckpag_combustivel c
  WHERE c.placa_tipo IS NULL OR c.placa_tipo != 'TERCEIRO'
  GROUP BY 1, 2, 3, 4, 5
),
ped AS (
  SELECT
    TO_CHAR(p.data, 'YYYY-MM') AS ano_mes,
    COALESCE(p.filial_nome, 'OUTROS') AS filial_nome,
    COUNT(DISTINCT p.transacao) AS qtd_passagens_pedagio,
    ROUND(SUM(p.valor)::numeric, 2) AS total_valor_pedagio
  FROM torre.gold_truckpag_pedagio p
  WHERE p.placa_tipo IS NULL OR p.placa_tipo != 'TERCEIRO'
  GROUP BY 1, 2
),
telemetria AS (
  SELECT
    TO_CHAR(t.data_ref, 'YYYY-MM') AS ano_mes,
    COALESCE(t.filial_operacional, 'OUTROS') AS filial_nome,
    COUNT(*) AS qtd_excessos_velocidade,
    COUNT(DISTINCT t.placa) AS qtd_veiculos_infratores,
    ROUND(AVG(t.velocidade_registrada)::numeric, 1) AS velocidade_media_infracao,
    MAX(t.velocidade_registrada) AS velocidade_maxima_registrada
  FROM torre.vw_alertas_telemetria_saneados t
  GROUP BY 1, 2
),
eficiencia AS (
  SELECT
    e.ano_mes,
    COALESCE(e.filial_nome, 'OUTROS') AS filial_nome,
    ROUND(SUM(e.total_km)::numeric, 2) AS total_km_rodado,
    ROUND(SUM(e.total_km) FILTER (WHERE NOT e.cobertura_parcial) / NULLIF(SUM(e.total_litros) FILTER (WHERE NOT e.cobertura_parcial), 0)::numeric, 4) AS km_litro_medio,
    ROUND(SUM(e.total_valor_liquido) FILTER (WHERE NOT e.cobertura_parcial) / NULLIF(SUM(e.total_km) FILTER (WHERE NOT e.cobertura_parcial), 0)::numeric, 4) AS custo_combustivel_km
  FROM torre.gold_mv_eficiencia_placa_mensal e
  GROUP BY 1, 2
),
suspeitos AS (
  SELECT
    s.ano_mes,
    COALESCE(s.filial_nome, 'OUTROS') AS filial_nome,
    COUNT(*) AS qtd_transacoes_suspeitas,
    ROUND(SUM(s.valor)::numeric, 2) AS total_valor_suspeito
  FROM torre.gold_mv_abastecimentos_suspeitos s
  GROUP BY 1, 2
),
frota AS (
  SELECT
    COALESCE(v.filial_operacional, 'OUTROS') AS filial_nome,
    COUNT(*) AS total_veiculos_cadastrados,
    COUNT(*) FILTER (WHERE v.situacao_veiculo = 'ATIVO') AS total_veiculos_ativos,
    COUNT(*) FILTER (WHERE v.ultima_manutencao_preventiva IS NOT NULL 
                       AND v.ultima_manutencao_preventiva < (CURRENT_DATE - INTERVAL '180 days')) AS preventivas_atrasadas
  FROM torre.gold_dim_veiculo v
  GROUP BY 1
)
SELECT
  c.ano_mes,
  c.data_mes_inicio,
  c.filial_nome,
  c.filial_estado,
  c.filial_regiao,
  -- Combustível
  c.qtd_abastecimentos,
  c.qtd_veiculos_abastecidos,
  c.total_litros,
  c.total_valor_combustivel,
  c.preco_medio_litro,
  -- Pedágio
  COALESCE(p.qtd_passagens_pedagio, 0) AS qtd_passagens_pedagio,
  COALESCE(p.total_valor_pedagio, 0.00) AS total_valor_pedagio,
  -- Total Rodagem (Combustível + Pedágio)
  ROUND((c.total_valor_combustivel + COALESCE(p.total_valor_pedagio, 0.00))::numeric, 2) AS custo_total_rodagem,
  -- Eficiência e KM
  COALESCE(e.total_km_rodado, 0.00) AS total_km_rodado,
  COALESCE(e.km_litro_medio, 0.00) AS km_litro_medio,
  COALESCE(e.custo_combustivel_km, 0.00) AS custo_combustivel_km,
  ROUND(
    (c.total_valor_combustivel + COALESCE(p.total_valor_pedagio, 0.00)) / NULLIF(e.total_km_rodado, 0)::numeric, 4
  ) AS custo_total_por_km,
  -- Telemetria
  COALESCE(t.qtd_excessos_velocidade, 0) AS qtd_excessos_velocidade,
  COALESCE(t.qtd_veiculos_infratores, 0) AS qtd_veiculos_infratores,
  COALESCE(t.velocidade_media_infracao, 0.0) AS velocidade_media_infracao,
  COALESCE(t.velocidade_maxima_registrada, 0.0) AS velocidade_maxima_registrada,
  -- Auditoria / Suspeitos
  COALESCE(s.qtd_transacoes_suspeitas, 0) AS qtd_transacoes_suspeitas,
  COALESCE(s.total_valor_suspeito, 0.00) AS total_valor_suspeito,
  -- Frota e Manutenção
  COALESCE(f.total_veiculos_cadastrados, 0) AS total_veiculos_cadastrados,
  COALESCE(f.total_veiculos_ativos, 0) AS total_veiculos_ativos,
  COALESCE(f.preventivas_atrasadas, 0) AS preventivas_atrasadas
FROM comb c
LEFT JOIN ped p ON p.filial_nome = c.filial_nome AND p.ano_mes = c.ano_mes
LEFT JOIN telemetria t ON t.filial_nome = c.filial_nome AND t.ano_mes = c.ano_mes
LEFT JOIN eficiencia e ON e.filial_nome = c.filial_nome AND e.ano_mes = c.ano_mes
LEFT JOIN suspeitos s ON s.filial_nome = c.filial_nome AND s.ano_mes = c.ano_mes
LEFT JOIN frota f ON f.filial_nome = c.filial_nome;

COMMENT ON VIEW torre.vw_bi_diretoria_kpis_mensal IS 
  'View principal de KPIs agregados por filial e mês para o Looker Studio.';

-- ============================================================================
-- 2. VIEW ANALÍTICA: ABASTECIMENTOS DETALHADOS (FILTROS POR POSTO/PLACA/TIPO)
-- ============================================================================
CREATE OR REPLACE VIEW torre.vw_bi_diretoria_analitico_combustivel AS
SELECT
  c.transacao,
  c.data,
  TO_CHAR(c.data, 'YYYY-MM') AS ano_mes,
  c.placa,
  c.grupo_veiculo,
  c.filial_nome,
  c.filial_estado,
  c.filial_regiao,
  c.hodometro,
  c.litragem,
  c.valor_liquido AS valor_total,
  c.preco_unitario,
  c.nome_combustivel,
  c.grupo_combustivel,
  c.tipo_abastecimento,
  c.nome_fantasia_posto,
  c.razao_social_posto,
  c.cidade_posto,
  c.uf_posto,
  c.transacao_estornada,
  -- Identificação de Suspeito
  CASE 
    WHEN s.transacao IS NOT NULL THEN TRUE 
    ELSE FALSE 
  END AS is_suspeito,
  COALESCE(ARRAY_TO_STRING(s.motivos, ', '), 'REGULAR') AS motivos_suspeita,
  s.score_risco,
  COALESCE(s.nivel_litragem_alta, 'NORMAL') AS gravidade_litragem
FROM torre.gold_truckpag_combustivel c
LEFT JOIN torre.gold_mv_abastecimentos_suspeitos s ON s.transacao = c.transacao;

COMMENT ON VIEW torre.vw_bi_diretoria_analitico_combustivel IS 
  'View analítica de abastecimentos para drill-down e auditoria no Looker Studio.';

-- ============================================================================
-- 3. VIEW ANALÍTICA: PEDÁGIOS DETALHADOS (FILTROS POR PRAÇA/CONCESSIONÁRIA)
-- ============================================================================
CREATE OR REPLACE VIEW torre.vw_bi_diretoria_analitico_pedagio AS
SELECT
  p.transacao,
  p.data,
  TO_CHAR(p.data, 'YYYY-MM') AS ano_mes,
  p.placa,
  p.grupo_veiculo,
  p.filial_nome,
  p.filial_estado,
  p.filial_regiao,
  p.valor AS valor_pedagio,
  p.operadora,
  p.nome_fantasia_posto AS praca_pedagio,
  p.cidade_posto AS cidade_praca,
  p.uf_posto AS uf_praca
FROM torre.gold_truckpag_pedagio p;

COMMENT ON VIEW torre.vw_bi_diretoria_analitico_pedagio IS 
  'View analítica de pedágios para controle de rotas e praças no Looker Studio.';

-- ============================================================================
-- 4. VIEW ANALÍTICA: TELEMETRIA E SEGURANÇA (EXCESSOS SANEADOS)
-- ============================================================================
CREATE OR REPLACE VIEW torre.vw_bi_diretoria_analitico_telemetria AS
SELECT
  t.placa,
  t.provedor_rastreador,
  t.velocidade_registrada,
  t.data_hora_alerta,
  t.data_hora_timestamp,
  t.data_ref AS data,
  TO_CHAR(t.data_ref, 'YYYY-MM') AS ano_mes,
  t.latitude,
  t.longitude,
  t.endereco,
  t.cidade,
  t.estado,
  t.nome_evento,
  t.filial_operacional AS filial_nome,
  t.modelo,
  t.grupo_veiculo,
  t.situacao_veiculo,
  -- Limite regulamentar e gravidade
  CASE 
    WHEN t.grupo_veiculo IN ('Bitruck', 'Truck', 'Toco', '3/4') THEN 90
    ELSE 110
  END AS velocidade_limite,
  CASE
    WHEN t.grupo_veiculo IN ('Bitruck', 'Truck', 'Toco', '3/4') AND t.velocidade_registrada > 105 THEN 'GRAVE'
    WHEN t.grupo_veiculo IN ('Bitruck', 'Truck', 'Toco', '3/4') AND t.velocidade_registrada > 90 THEN 'MODERADA'
    WHEN t.velocidade_registrada > 130 THEN 'GRAVE'
    ELSE 'MODERADA'
  END AS gravidade_excesso
FROM torre.vw_alertas_telemetria_saneados t;

COMMENT ON VIEW torre.vw_bi_diretoria_analitico_telemetria IS 
  'View de eventos de telemetria saneados para rankings e segurança no Looker Studio.';

-- ============================================================================
-- 5. VIEW ANALÍTICA: FROTA E MANUTENÇÃO (CADASTRO, PREVENTIVAS E IDADE)
-- ============================================================================
CREATE OR REPLACE VIEW torre.vw_bi_diretoria_frota_manutencao AS
SELECT
  v.placa,
  v.modelo_raw AS modelo,
  v.grupo_veiculo,
  v.filial_operacional AS filial_nome,
  v.situacao_veiculo,
  v.tanque_litros,
  v.ano_modelo,
  v.ano_fabricacao,
  (EXTRACT(YEAR FROM CURRENT_DATE) - COALESCE(v.ano_fabricacao, EXTRACT(YEAR FROM CURRENT_DATE)::smallint)) AS idade_veiculo_anos,
  v.montadora,
  v.odometro_confirmado,
  v.ultima_manutencao,
  v.ultima_manutencao_preventiva,
  v.km_ultima_manutencao_preventiva,
  -- Status preventiva
  CASE
    WHEN v.ultima_manutencao_preventiva IS NULL THEN 'SEM REGISTRO'
    WHEN v.ultima_manutencao_preventiva < (CURRENT_DATE - INTERVAL '180 days') THEN 'VENCIDA (>180 dias)'
    WHEN v.ultima_manutencao_preventiva < (CURRENT_DATE - INTERVAL '150 days') THEN 'ATENÇÃO (VENCE EM BREVE)'
    ELSE 'EM DIA'
  END AS status_preventiva_tempo,
  -- Diferencial de KM desde a última preventiva
  CASE 
    WHEN v.odometro_confirmado IS NOT NULL AND v.km_ultima_manutencao_preventiva IS NOT NULL
    THEN v.odometro_confirmado - v.km_ultima_manutencao_preventiva
    ELSE NULL
  END AS km_rodados_desde_preventiva
FROM torre.gold_dim_veiculo v;

COMMENT ON VIEW torre.vw_bi_diretoria_frota_manutencao IS 
  'View cadastral e de controle de manutenção da frota para o Looker Studio.';
