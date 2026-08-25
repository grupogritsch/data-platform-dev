-- ============================================================================
-- GOLD — 2. DOMÍNIO PEDÁGIO & CONCESSIONÁRIAS
--
-- Views analíticas e agregadas prontas para consumo no Looker Studio / BI
-- Integração: TruckPag (TAGs Sem Parar / ConectCar / Veloe) + Rateio de Filiais
--
-- Data: 2026-08-25
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS torre;

-- ----------------------------------------------------------------------------
-- 2.1 VIEW ANALÍTICA DETALHADA: Passagem a Passagem de Pedágio
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_pedagio_analitico AS
SELECT
  p.transacao,
  p.data_transacao,
  p.data,
  TO_CHAR(p.data, 'YYYY-MM')                                            AS ano_mes,
  EXTRACT(YEAR FROM p.data)::int                                        AS ano,
  EXTRACT(MONTH FROM p.data)::int                                       AS mes,
  p.placa,
  COALESCE(p.filial_nome, 'OUTROS')                                     AS filial_nome,
  p.filial_estado,
  p.filial_regiao,
  p.filial_tipo,
  COALESCE(p.grupo_veiculo, 'Outros')                                   AS grupo_veiculo,
  p.valor                                                               AS valor_pedagio,
  COALESCE(NULLIF(p.operadora, ''), 'CONCESSIONÁRIA NÃO IDENTIFICADA') AS operadora_concessionaria,
  p.nome_fantasia_posto                                                 AS praca_pedagio,
  p.cidade_posto                                                        AS cidade_praca,
  p.uf_posto                                                            AS uf_praca,
  p.centro_custo
FROM torre.gold_truckpag_pedagio p
WHERE p.placa_tipo IS NULL OR p.placa_tipo != 'TERCEIRO';

COMMENT ON VIEW torre.vw_bi_pedagio_analitico IS 
  'Passagens detalhadas de pedágio com dados de praças, operadoras e rateio filial.';

-- ----------------------------------------------------------------------------
-- 2.2 VIEW AGREGADA: Indicadores Mensais de Pedágio por Filial
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_pedagio_filial_mensal AS
WITH km_filial AS (
  SELECT
    ano_mes,
    filial_nome,
    SUM(total_km) AS total_km_rodado
  FROM torre.gold_mv_eficiencia_placa_mensal
  GROUP BY 1, 2
)
SELECT
  p.ano_mes,
  p.ano,
  p.mes,
  p.filial_nome,
  p.filial_estado,
  p.filial_regiao,
  p.grupo_veiculo,
  COUNT(DISTINCT p.transacao)                                           AS qtd_passagens,
  COUNT(DISTINCT p.placa)                                               AS qtd_veiculos_utilizados,
  ROUND(SUM(p.valor_pedagio)::numeric, 2)                              AS total_valor_pedagio,
  ROUND(AVG(p.valor_pedagio)::numeric, 2)                              AS valor_medio_por_passagem,
  COALESCE(k.total_km_rodado, 0)                                        AS total_km_rodado,
  ROUND(
    SUM(p.valor_pedagio) / NULLIF(k.total_km_rodado, 0)::numeric, 4
  )                                                                     AS custo_pedagio_por_km
FROM torre.vw_bi_pedagio_analitico p
LEFT JOIN km_filial k ON k.ano_mes = p.ano_mes AND k.filial_nome = p.filial_nome
GROUP BY 1, 2, 3, 4, 5, 6, 7, k.total_km_rodado;

COMMENT ON VIEW torre.vw_bi_pedagio_filial_mensal IS 
  'Resumo mensal de pedágios com volume financeiro e custo de pedágio por km rodado.';

-- ----------------------------------------------------------------------------
-- 2.3 VIEW DE RANKING DE CONCESSIONÁRIAS E PRAÇAS DE MAIOR IMPACTO
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_pedagio_concessionarias_ranking AS
SELECT
  p.operadora_concessionaria,
  p.praca_pedagio,
  p.uf_praca,
  p.ano_mes,
  COUNT(DISTINCT p.transacao)                                           AS qtd_passagens,
  COUNT(DISTINCT p.placa)                                               AS qtd_veiculos_distintos,
  ROUND(SUM(p.valor_pedagio)::numeric, 2)                              AS total_valor_pedagio,
  ROUND(AVG(p.valor_pedagio)::numeric, 2)                              AS tarifa_media_praca
FROM torre.vw_bi_pedagio_analitico p
GROUP BY 1, 2, 3, 4;

COMMENT ON VIEW torre.vw_bi_pedagio_concessionarias_ranking IS 
  'Ranking de concessionárias de rodovias e praças de pedágio mais transitadas pela frota.';
