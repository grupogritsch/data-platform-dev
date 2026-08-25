-- ============================================================================
-- GOLD — 5. DOMÍNIO DIRETORIA & MATRIZ EXECUTIVA DE REUNIÕES COM FILIAIS
--
-- View 360° unificada e Scorecard de Filiais para consumo no Looker Studio
-- Consolidação dos 4 Pilares: Abastecimento + Pedágio + Telemetria + Manutenção
--
-- Data: 2026-08-25
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS torre;

-- ----------------------------------------------------------------------------
-- 5.1 VIEW MATRIZ 360°: Painel Completo de Fechamento por Filial e Mês
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_diretoria_reuniao_filial_360 AS
WITH 
comb AS (
  SELECT
    ano_mes,
    ano,
    mes,
    filial_nome,
    filial_estado,
    filial_regiao,
    SUM(qtd_abastecimentos)                                             AS qtd_abastecimentos,
    SUM(qtd_veiculos_abastecidos)                                       AS qtd_veiculos_abastecidos,
    ROUND(SUM(total_litros)::numeric, 2)                                AS total_litros,
    ROUND(SUM(total_valor_combustivel)::numeric, 2)                     AS total_valor_combustivel,
    ROUND(SUM(total_valor_combustivel) / NULLIF(SUM(total_litros), 0)::numeric, 4) AS preco_medio_litro,
    SUM(qtd_transacoes_suspeitas)                                       AS qtd_transacoes_suspeitas,
    ROUND(SUM(total_valor_suspeito)::numeric, 2)                        AS total_valor_suspeito
  FROM torre.vw_bi_abastecimento_filial_mensal
  GROUP BY 1, 2, 3, 4, 5, 6
),
ped AS (
  SELECT
    ano_mes,
    filial_nome,
    SUM(qtd_passagens)                                                  AS qtd_passagens_pedagio,
    ROUND(SUM(total_valor_pedagio)::numeric, 2)                         AS total_valor_pedagio
  FROM torre.vw_bi_pedagio_filial_mensal
  GROUP BY 1, 2
),
efi AS (
  SELECT
    ano_mes,
    COALESCE(filial_nome, 'OUTROS')                                     AS filial_nome,
    ROUND(SUM(total_km)::numeric, 2)                                    AS total_km_rodado,
    ROUND(SUM(total_km) FILTER (WHERE NOT cobertura_parcial) / NULLIF(SUM(total_litros) FILTER (WHERE NOT cobertura_parcial), 0)::numeric, 4) AS km_litro_medio,
    ROUND(SUM(total_valor_liquido) FILTER (WHERE NOT cobertura_parcial) / NULLIF(SUM(total_km) FILTER (WHERE NOT cobertura_parcial), 0)::numeric, 4) AS custo_combustivel_km
  FROM torre.gold_mv_eficiencia_placa_mensal
  GROUP BY 1, 2
),
telemetria AS (
  SELECT
    ano_mes,
    filial_nome,
    SUM(qtd_excessos_velocidade)                                        AS qtd_excessos_velocidade,
    SUM(qtd_veiculos_infratores)                                        AS qtd_veiculos_infratores,
    SUM(qtd_excessos_graves)                                            AS qtd_excessos_graves,
    MAX(velocidade_maxima_registrada)                                   AS velocidade_pico_filial
  FROM torre.vw_bi_telemetria_filial_mensal
  GROUP BY 1, 2
),
manut AS (
  SELECT
    ano_mes,
    filial_nome,
    total_veiculos,
    veiculos_ativos,
    preventivas_em_dia,
    preventivas_vencidas,
    taxa_conformidade_preventiva_pct,
    total_gasto_insumos,
    gasto_arla_32
  FROM torre.vw_bi_manutencao_filial_resumo
)
SELECT
  c.ano_mes,
  c.ano,
  c.mes,
  c.filial_nome,
  c.filial_estado,
  c.filial_regiao,
  -- 1. Combustível
  c.qtd_abastecimentos,
  c.qtd_veiculos_abastecidos,
  c.total_litros,
  c.total_valor_combustivel,
  c.preco_medio_litro,
  -- 2. Pedágio
  COALESCE(p.qtd_passagens_pedagio, 0)                                 AS qtd_passagens_pedagio,
  COALESCE(p.total_valor_pedagio, 0.00)                                AS total_valor_pedagio,
  -- 3. Insumos Manutenção
  COALESCE(m.total_gasto_insumos, 0.00)                                AS total_gasto_insumos,
  COALESCE(m.gasto_arla_32, 0.00)                                      AS gasto_arla_32,
  -- 4. Custos Totais de Rodagem
  ROUND(
    (c.total_valor_combustivel + COALESCE(p.total_valor_pedagio, 0.00) + COALESCE(m.total_gasto_insumos, 0.00))::numeric, 2
  )                                                                     AS custo_total_operacao,
  -- 5. Eficiência e KM
  COALESCE(e.total_km_rodado, 0.00)                                     AS total_km_rodado,
  COALESCE(e.km_litro_medio, 0.00)                                      AS km_litro_medio,
  COALESCE(e.custo_combustivel_km, 0.00)                                AS custo_combustivel_km,
  ROUND(
    (c.total_valor_combustivel + COALESCE(p.total_valor_pedagio, 0.00) + COALESCE(m.total_gasto_insumos, 0.00))
    / NULLIF(e.total_km_rodado, 0)::numeric, 4
  )                                                                     AS custo_total_por_km,
  -- 6. Telemetria & Segurança
  COALESCE(t.qtd_excessos_velocidade, 0)                                AS qtd_excessos_velocidade,
  COALESCE(t.qtd_excessos_graves, 0)                                    AS qtd_excessos_graves,
  COALESCE(t.qtd_veiculos_infratores, 0)                                AS qtd_veiculos_infratores,
  COALESCE(t.velocidade_pico_filial, 0)                                 AS velocidade_pico_filial,
  ROUND(
    (COALESCE(t.qtd_excessos_velocidade, 0)::numeric / NULLIF(e.total_km_rodado, 0) * 10000)::numeric, 2
  )                                                                     AS taxa_excessos_por_10mil_km,
  -- 7. Auditoria de Suspeição
  COALESCE(c.qtd_transacoes_suspeitas, 0)                               AS qtd_transacoes_suspeitas,
  COALESCE(c.total_valor_suspeito, 0.00)                                AS total_valor_suspeito,
  ROUND(
    (COALESCE(c.total_valor_suspeito, 0.00) / NULLIF(c.total_valor_combustivel, 0) * 100)::numeric, 2
  )                                                                     AS pct_valor_suspeito,
  -- 8. Conformidade de Manutenção
  COALESCE(m.total_veiculos, 0)                                         AS total_veiculos_filial,
  COALESCE(m.veiculos_ativos, 0)                                        AS veiculos_ativos_filial,
  COALESCE(m.preventivas_em_dia, 0)                                     AS preventivas_em_dia,
  COALESCE(m.preventivas_vencidas, 0)                                   AS preventivas_vencidas,
  COALESCE(m.taxa_conformidade_preventiva_pct, 0.0)                     AS taxa_conformidade_preventiva_pct
FROM comb c
LEFT JOIN ped p ON p.filial_nome = c.filial_nome AND p.ano_mes = c.ano_mes
LEFT JOIN efi e ON e.filial_nome = c.filial_nome AND e.ano_mes = c.ano_mes
LEFT JOIN telemetria t ON t.filial_nome = c.filial_nome AND t.ano_mes = c.ano_mes
LEFT JOIN manut m ON m.filial_nome = c.filial_nome AND m.ano_mes = c.ano_mes;

COMMENT ON VIEW torre.vw_bi_diretoria_reuniao_filial_360 IS 
  'View principal 360° para reuniões executivas da diretoria com os gestores das filiais.';

-- ----------------------------------------------------------------------------
-- 5.2 VIEW DE SCORECARD & RANKING DE PERFORMANCE DAS FILIAIS
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW torre.vw_bi_diretoria_ranking_score_filiais AS
WITH base AS (
  SELECT
    ano_mes,
    filial_nome,
    filial_estado,
    filial_regiao,
    total_km_rodado,
    custo_total_operacao,
    custo_total_por_km,
    km_litro_medio,
    taxa_excessos_por_10mil_km,
    pct_valor_suspeito,
    taxa_conformidade_preventiva_pct
  FROM torre.vw_bi_diretoria_reuniao_filial_360
  WHERE total_km_rodado > 1000 -- Exclui filiais sem operação significativa
),
scores AS (
  SELECT
    b.*,
    -- Score de Custo (0 a 30 pts) — Menor custo por KM = mais pontos
    ROUND(
      GREATEST(0, LEAST(30, (1.20 - COALESCE(b.custo_total_por_km, 1.20)) * 50))::numeric, 1
    ) AS score_custo_km,
    -- Score de Eficiência (0 a 25 pts) — Maior km/L = mais pontos
    ROUND(
      GREATEST(0, LEAST(25, (COALESCE(b.km_litro_medio, 2.0) - 2.0) * 15))::numeric, 1
    ) AS score_eficiencia_kml,
    -- Score de Segurança Telemetria (0 a 20 pts) — Menos excessos = mais pontos
    ROUND(
      GREATEST(0, LEAST(20, 20 - (COALESCE(b.taxa_excessos_por_10mil_km, 0) * 2)))::numeric, 1
    ) AS score_seguranca,
    -- Score de Manutenção (0 a 15 pts) — Mais preventivas em dia = mais pontos
    ROUND(
      (COALESCE(b.taxa_conformidade_preventiva_pct, 0) * 0.15)::numeric, 1
    ) AS score_manutencao,
    -- Score de Conformidade / Sem Suspeitas (0 a 10 pts) — Menos suspeitos = mais pontos
    ROUND(
      GREATEST(0, LEAST(10, 10 - (COALESCE(b.pct_valor_suspeito, 0) * 2)))::numeric, 1
    ) AS score_auditoria
  FROM base b
)
SELECT
  s.ano_mes,
  s.filial_nome,
  s.filial_estado,
  s.filial_regiao,
  s.total_km_rodado,
  s.custo_total_operacao,
  s.custo_total_por_km,
  s.km_litro_medio,
  s.taxa_excessos_por_10mil_km,
  s.taxa_conformidade_preventiva_pct,
  s.pct_valor_suspeito,
  -- Score Global de Performance (0 a 100)
  (s.score_custo_km + s.score_eficiencia_kml + s.score_seguranca + s.score_manutencao + s.score_auditoria) AS score_geral_performance,
  -- Classificação
  CASE
    WHEN (s.score_custo_km + s.score_eficiencia_kml + s.score_seguranca + s.score_manutencao + s.score_auditoria) >= 80 THEN 'EXCELENTE (DESTAQUE)'
    WHEN (s.score_custo_km + s.score_eficiencia_kml + s.score_seguranca + s.score_manutencao + s.score_auditoria) >= 65 THEN 'SATISFATÓRIO (REGULAR)'
    ELSE 'CRÍTICO (COBRANÇA PRIORITÁRIA)'
  END AS status_filial_reuniao,
  -- Ranking mensal
  DENSE_RANK() OVER (
    PARTITION BY s.ano_mes 
    ORDER BY (s.score_custo_km + s.score_eficiencia_kml + s.score_seguranca + s.score_manutencao + s.score_auditoria) DESC
  ) AS posicao_ranking_nacional
FROM scores s;

COMMENT ON VIEW torre.vw_bi_diretoria_ranking_score_filiais IS 
  'Scorecard e Ranking nacional de filiais de 0 a 100 para condução de reuniões de diretoria.';
