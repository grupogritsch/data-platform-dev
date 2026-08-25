-- ============================================================================
-- GOLD — 1. DOMÍNIO ABASTECIMENTO & EFICIÊNCIA DE COMBUSTÍVEL
--
-- Views analíticas e agregadas prontas para consumo no Looker Studio / BI
-- Integração: TruckPag (Transações + Faturas + Títulos) + ANP + Bluefleet
--
-- Data: 2026-08-25
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS torre;

-- ----------------------------------------------------------------------------
-- 1.1 VIEW ANALÍTICA DETALHADA: Transação a Transação com Auditoria
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_abastecimento_analitico AS
SELECT
  c.transacao,
  c.data_transacao,
  c.data,
  TO_CHAR(c.data, 'YYYY-MM')                                            AS ano_mes,
  EXTRACT(YEAR FROM c.data)::int                                        AS ano,
  EXTRACT(MONTH FROM c.data)::int                                       AS mes,
  c.placa,
  COALESCE(c.filial_nome, 'OUTROS')                                     AS filial_nome,
  c.filial_estado,
  c.filial_regiao,
  c.filial_tipo,
  COALESCE(c.grupo_veiculo, 'Outros')                                   AS grupo_veiculo,
  c.hodometro,
  c.litragem,
  c.valor_liquido                                                       AS valor_total,
  c.preco_unitario,
  c.cod_combustivel,
  c.nome_combustivel,
  c.grupo_combustivel,
  c.tipo_abastecimento,
  c.razao_social_posto,
  c.nome_fantasia_posto,
  c.cnpj_posto,
  c.cidade_posto,
  c.uf_posto,
  c.centro_custo,
  c.transacao_estornada,
  -- Flags de Suspeição
  CASE WHEN s.transacao IS NOT NULL THEN TRUE ELSE FALSE END            AS is_suspeito,
  COALESCE(s.score_risco, 0)                                            AS score_risco_suspeita,
  COALESCE(ARRAY_TO_STRING(s.motivos, ', '), 'REGULAR')                 AS motivos_suspeita,
  COALESCE(s.nivel_litragem_alta, 'NORMAL')                             AS nivel_litragem_alta,
  COALESCE(s.flag_intervalo_curto, FALSE)                               AS flag_intervalo_curto,
  COALESCE(s.flag_preco_alto, FALSE)                                    AS flag_preco_alto,
  COALESCE(s.flag_retorno_mesmo_posto, FALSE)                           AS flag_retorno_mesmo_posto,
  COALESCE(s.flag_combustivel_errado, FALSE)                            AS flag_combustivel_errado,
  s.preco_mediano                                                       AS preco_mediano_uf_referencia,
  s.preco_desvio_pct                                                    AS preco_desvio_pct_referencia
FROM torre.gold_truckpag_combustivel c
LEFT JOIN torre.gold_mv_abastecimentos_suspeitos s ON s.transacao = c.transacao
WHERE c.placa_tipo IS NULL OR c.placa_tipo != 'TERCEIRO';

COMMENT ON VIEW torre.vw_bi_abastecimento_analitico IS 
  'Transações detalhadas de combustível com enriquecimento de postos e auditoria de suspeição.';

-- ----------------------------------------------------------------------------
-- 1.2 VIEW AGREGADA: Indicadores Mensais por Filial e Categoria de Veículo
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_abastecimento_filial_mensal AS
SELECT
  c.ano_mes,
  c.ano,
  c.mes,
  c.filial_nome,
  c.filial_estado,
  c.filial_regiao,
  c.grupo_veiculo,
  COUNT(DISTINCT c.transacao)                                           AS qtd_abastecimentos,
  COUNT(DISTINCT c.placa)                                               AS qtd_veiculos_abastecidos,
  ROUND(SUM(c.litragem)::numeric, 2)                                    AS total_litros,
  ROUND(SUM(c.valor_total)::numeric, 2)                                 AS total_valor_combustivel,
  ROUND(SUM(c.valor_total) / NULLIF(SUM(c.litragem), 0)::numeric, 4)   AS preco_medio_pago,
  -- Suspeitos
  COUNT(*) FILTER (WHERE c.is_suspeito)                                 AS qtd_transacoes_suspeitas,
  ROUND(SUM(CASE WHEN c.is_suspeito THEN c.valor_total ELSE 0 END)::numeric, 2) AS total_valor_suspeito,
  ROUND(
    (SUM(CASE WHEN c.is_suspeito THEN c.valor_total ELSE 0 END) / NULLIF(SUM(c.valor_total), 0) * 100)::numeric, 2
  )                                                                     AS pct_valor_suspeito
FROM torre.vw_bi_abastecimento_analitico c
GROUP BY 1, 2, 3, 4, 5, 6, 7;

COMMENT ON VIEW torre.vw_bi_abastecimento_filial_mensal IS 
  'Agregação mensal de combustível por filial e grupo de veículo para o BI.';

-- ----------------------------------------------------------------------------
-- 1.3 VIEW DE RANKING & AUDITORIA DE POSTOS (GESTÃO DE FORNECEDORES)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_abastecimento_postos_ranking AS
SELECT
  c.cnpj_posto,
  c.nome_fantasia_posto,
  c.razao_social_posto,
  c.cidade_posto,
  c.uf_posto,
  c.ano_mes,
  COUNT(DISTINCT c.transacao)                                           AS qtd_abastecimentos,
  COUNT(DISTINCT c.placa)                                               AS qtd_veiculos_atendidos,
  ROUND(SUM(c.litragem)::numeric, 2)                                    AS total_litros,
  ROUND(SUM(c.valor_total)::numeric, 2)                                 AS total_valor_faturado,
  ROUND(SUM(c.valor_total) / NULLIF(SUM(c.litragem), 0)::numeric, 4)   AS preco_medio_praticado,
  COUNT(*) FILTER (WHERE c.is_suspeito)                                 AS qtd_ocorrencias_suspeitas,
  ROUND(SUM(CASE WHEN c.is_suspeito THEN c.valor_total ELSE 0 END)::numeric, 2) AS valor_suspeito_posto
FROM torre.vw_bi_abastecimento_analitico c
WHERE c.cnpj_posto IS NOT NULL AND c.cnpj_posto <> ''
GROUP BY 1, 2, 3, 4, 5, 6;

COMMENT ON VIEW torre.vw_bi_abastecimento_postos_ranking IS 
  'Ranking e auditoria de postos de combustível com preços e recorrência de suspeitas.';

-- ----------------------------------------------------------------------------
-- 1.4 VIEW DE EFICIÊNCIA DA FROTA (KM/L vs METAS / BENCHMARKS)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_abastecimento_eficiencia_benchmark AS
SELECT
  e.ano_mes,
  COALESCE(e.filial_nome, 'OUTROS')                                     AS filial_nome,
  e.filial_estado,
  e.filial_regiao,
  e.grupo_veiculo,
  e.placa,
  e.modelo,
  e.total_km,
  e.total_litros,
  e.total_valor_liquido                                                 AS total_valor_combustivel,
  e.km_por_litro,
  e.custo_por_km,
  e.cobertura_parcial,
  -- Benchmark de Meta Estimada por Grupo de Veículo
  CASE 
    WHEN e.grupo_veiculo = 'Bitruck' THEN 2.20
    WHEN e.grupo_veiculo = 'Truck'   THEN 2.80
    WHEN e.grupo_veiculo = 'Toco'    THEN 3.50
    WHEN e.grupo_veiculo = '3/4'     THEN 4.20
    WHEN e.grupo_veiculo = 'Leve'    THEN 9.00
    ELSE 3.00
  END                                                                   AS meta_km_litro,
  -- Desvio % vs Meta
  ROUND(
    ((e.km_por_litro / NULLIF(
      CASE 
        WHEN e.grupo_veiculo = 'Bitruck' THEN 2.20
        WHEN e.grupo_veiculo = 'Truck'   THEN 2.80
        WHEN e.grupo_veiculo = 'Toco'    THEN 3.50
        WHEN e.grupo_veiculo = '3/4'     THEN 4.20
        WHEN e.grupo_veiculo = 'Leve'    THEN 9.00
        ELSE 3.00
      END, 0) - 1) * 100)::numeric, 2
  )                                                                     AS desvio_meta_pct
FROM torre.gold_mv_eficiencia_placa_mensal e;

COMMENT ON VIEW torre.vw_bi_abastecimento_eficiencia_benchmark IS 
  'Eficiência individual por placa e modelo comparada com as metas operacionais.';
