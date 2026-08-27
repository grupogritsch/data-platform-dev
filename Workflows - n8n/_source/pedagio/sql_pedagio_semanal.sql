WITH pedagio_raw AS (
  SELECT
    p.transacao,
    p.placa,
    p.data,
    p.data_transacao,
    p.valor,
    COALESCE(p.operadora, p.nome_fantasia_posto, 'Praça de Pedágio') AS praca_nome,
    p.cidade_posto,
    p.uf_posto,
    CASE
      WHEN UPPER(REPLACE(p.placa, '-', '')) IN ('UBH2J71', 'UBR9B22', 'UBR9B09', 'SEP6E34', 'UBR9B08', 'UBR9A97', 'UBR9B27', 'UBR9A92', 'UBR9B16', 'UCB4H75', 'SFK1E50', 'TAI9A24') THEN 'Gritsch Santa Maria'
      WHEN p.garagem IN ('GRITSCH - CWB (BASE)', 'GRITSCH - CWB (ECT)') THEN 'Gritsch Curitiba (Base)'
      ELSE p.filial_nome
    END AS filial_relatorio,
    CASE
      WHEN p.garagem IN ('GRITSCH - CWB (BASE)', 'GRITSCH - CWB (ECT)') THEN 'GRITSCH - CWB (BASE)'
      ELSE p.garagem
    END AS garagem_relatorio
  FROM torre.gold_truckpag_pedagio p
  WHERE p.filial_nome IS NOT NULL
    AND p.garagem NOT IN ('GRITSCH - CWB (DIR)', 'GRITSCH - MATRIZ', 'REFERENCIA CURITIBA', 'REFERÊNCIA CURITIBA')
    AND p.garagem NOT LIKE '%DIR%'
    AND p.garagem NOT LIKE '%MATRIZ%'
    AND p.garagem NOT ILIKE '%REFERENCIA%'
    AND p.garagem NOT ILIKE '%REFERÊNCIA%'
    AND p.filial_nome NOT ILIKE '%REFERENCIA%'
    AND p.filial_nome NOT ILIKE '%REFERÊNCIA%'
),
-- Mesma estrategia de filiais_ativas da combustivel, so que o segundo lado
-- do UNION agora observa quem de fato passou em pedagio, nao em combustivel.
filiais_ativas AS (
  SELECT filial_relatorio, MAX(garagem_referencia) AS garagem_referencia
  FROM (
    SELECT DISTINCT
      CASE
        WHEN garagem IN ('GRITSCH - CWB (BASE)', 'GRITSCH - CWB (ECT)') THEN 'Gritsch Curitiba (Base)'
        ELSE filial_nome
      END AS filial_relatorio,
      CASE
        WHEN garagem IN ('GRITSCH - CWB (BASE)', 'GRITSCH - CWB (ECT)') THEN 'GRITSCH - CWB (BASE)'
        ELSE garagem
      END AS garagem_referencia
    FROM torre.gold_dim_filial
    WHERE tipo = 'GRITSCH'
      AND garagem NOT IN ('GRITSCH - CWB (DIR)', 'GRITSCH - MATRIZ', 'REFERENCIA CURITIBA', 'REFERÊNCIA CURITIBA')
      AND garagem NOT LIKE '%DIR%'
      AND filial_nome NOT ILIKE '%MATRIZ%'
      AND filial_nome NOT ILIKE '%REFERENCIA%'
      AND filial_nome NOT ILIKE '%REFERÊNCIA%'
    UNION
    SELECT DISTINCT
      filial_relatorio,
      garagem_relatorio AS garagem_referencia
    FROM pedagio_raw
    WHERE filial_relatorio IS NOT NULL
  ) sub
  GROUP BY filial_relatorio
),
pedagio_semana AS (
  SELECT
    filial_relatorio,
    ROUND(SUM(valor)::numeric, 2) AS total_pedagio,
    COUNT(*)                      AS total_passagens,
    COUNT(DISTINCT placa)         AS qtd_veiculos_ativos,
    ROUND((SUM(valor) / NULLIF(COUNT(*), 0))::numeric, 2) AS ticket_medio
  FROM pedagio_raw
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
  GROUP BY 1
),
pedagio_ant AS (
  SELECT
    filial_relatorio,
    ROUND(SUM(valor)::numeric, 2) AS total_pedagio_ant,
    COUNT(*)                      AS total_passagens_ant,
    COUNT(DISTINCT placa)         AS qtd_veiculos_ativos_ant,
    ROUND((SUM(valor) / NULLIF(COUNT(*), 0))::numeric, 2) AS ticket_medio_ant
  FROM pedagio_raw
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date_ant }}' AND '{{ $('Calcular Período').first().json.end_date_ant }}'
  GROUP BY 1
),
pedagio_pracas_filial AS (
  SELECT
    filial_relatorio,
    praca_nome AS praca,
    cidade_posto,
    uf_posto,
    COUNT(*) AS passagens,
    ROUND(SUM(valor)::numeric, 2) AS gasto,
    ROUND((SUM(valor) / NULLIF(COUNT(*), 0))::numeric, 2) AS ticket_medio,
    ROW_NUMBER() OVER (PARTITION BY filial_relatorio ORDER BY SUM(valor) DESC) AS rn
  FROM pedagio_raw
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
  GROUP BY filial_relatorio, praca_nome, cidade_posto, uf_posto
),
pedagio_pracas_agg AS (
  SELECT
    filial_relatorio,
    json_agg(
      json_build_object(
        'praca', praca,
        'cidade', cidade_posto,
        'uf', uf_posto,
        'passagens', passagens,
        'gasto', gasto,
        'ticket_medio', ticket_medio
      ) ORDER BY gasto DESC
    ) AS pedagio_pracas_json
  FROM pedagio_pracas_filial
  WHERE rn <= {{ $('Calcular Período').first().json.top_pracas || 8 }}
  GROUP BY filial_relatorio
),
-- Frota por pedagio: nao existia antes -- espelha frota_ativa da combustivel
-- (uma linha por placa, com o gasto e as passagens dela na semana).
frota_pedagio AS (
  SELECT
    filial_relatorio,
    placa,
    COUNT(*)                      AS passagens,
    ROUND(SUM(valor)::numeric, 2) AS valor_total
  FROM pedagio_raw
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
  GROUP BY filial_relatorio, placa
),
frota_pedagio_agg AS (
  SELECT
    filial_relatorio,
    json_agg(
      json_build_object(
        'placa', placa,
        'passagens', passagens,
        'valor_total', valor_total
      ) ORDER BY valor_total DESC
    ) AS frota_json
  FROM frota_pedagio
  GROUP BY filial_relatorio
),
pedagio_detalhe AS (
  SELECT
    filial_relatorio,
    json_agg(
      json_build_object(
        'transacao', transacao,
        'data_hora', TO_CHAR(data_transacao, 'DD/MM/YYYY HH24:MI'),
        'placa', placa,
        'praca', praca_nome,
        'cidade', COALESCE(cidade_posto, 'N/D'),
        'uf', COALESCE(uf_posto, 'N/D'),
        'valor', ROUND(valor::numeric, 2)
      ) ORDER BY data_transacao, transacao
    ) AS pedagios_json
  FROM pedagio_raw
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
    AND filial_relatorio IS NOT NULL
  GROUP BY filial_relatorio
)
SELECT
  fa.filial_relatorio                        AS filial_nome,
  fa.garagem_referencia                      AS garagem,
  -- Destinatarios: MESMO padrao do telemetria e do combustivel -- email do
  -- gestor da filial + CC (proprio + regional + global). Sem isso o pedagio
  -- divergiria do resto da familia Torre de Controle.
  COALESCE(ef.email_destino, '')             AS email_gestor,
  COALESCE(ef.email_cc, '')                  AS email_cc,
  COALESCE(ef.cc_regional, '')               AS cc_regional,
  COALESCE(cfg_cc.valor, '')                 AS cc_global,
  ccfg.consolidado_destinatarios             AS consolidado_destinatarios_db,
  ccfg.consolidado_cc                        AS consolidado_cc_db,
  -- Semana atual
  COALESCE(pd.total_pedagio, 0)              AS total_gasto_pedagio,
  COALESCE(pd.total_passagens, 0)            AS total_passagens,
  COALESCE(pd.qtd_veiculos_ativos, 0)        AS qtd_veiculos_ativos,
  COALESCE(pd.ticket_medio, 0)               AS ticket_medio,
  -- Semana anterior (delta)
  COALESCE(pda.total_pedagio_ant, 0)         AS total_gasto_pedagio_ant,
  COALESCE(pda.total_passagens_ant, 0)       AS total_passagens_ant,
  COALESCE(pda.qtd_veiculos_ativos_ant, 0)   AS qtd_veiculos_ativos_ant,
  COALESCE(pda.ticket_medio_ant, 0)          AS ticket_medio_ant,
  -- Detalhes agregados
  COALESCE(pp.pedagio_pracas_json, '[]'::json) AS pedagio_pracas_utilizadas,
  COALESCE(fp.frota_json, '[]'::json)          AS frota_pedagio,
  COALESCE(pdd.pedagios_json, '[]'::json)      AS pedagios_detalhe
FROM filiais_ativas fa
LEFT JOIN torre.email_gritsch_filiais ef ON ef.filial_operacional = fa.garagem_referencia AND ef.ativo = true
-- COALESCE dentro do CROSS JOIN (nao "SELECT valor ... LIMIT 1" solto): se a
-- chave nao existir, a subquery voltaria ZERO linhas e o CROSS JOIN zeraria o
-- relatorio inteiro. Mesmo fix aplicado no combustivel em 24/08/2026.
CROSS JOIN (
  SELECT COALESCE(
    (SELECT valor FROM torre.email_gritsch_config WHERE chave = 'cc_global' LIMIT 1),
    'torredecontrole@gritsch.com.br,flavio@gritsch.com.br,fabio.pepplow@gritsch.com.br'
  ) AS valor
) cfg_cc
CROSS JOIN (
  SELECT
    COALESCE(MAX(CASE WHEN chave = 'consolidado_destinatarios' THEN valor END), 'jefferson@gritsch.com.br') AS consolidado_destinatarios,
    COALESCE(MAX(CASE WHEN chave = 'consolidado_cc' THEN valor END), 'sandro@gritsch.com.br,torredecontrole@gritsch.com.br,flavio@gritsch.com.br,fabio.pepplow@gritsch.com.br') AS consolidado_cc
  FROM torre.email_gritsch_config
) ccfg
LEFT JOIN pedagio_semana     pd  ON pd.filial_relatorio  = fa.filial_relatorio
LEFT JOIN pedagio_ant        pda ON pda.filial_relatorio = fa.filial_relatorio
LEFT JOIN pedagio_pracas_agg pp  ON pp.filial_relatorio  = fa.filial_relatorio
LEFT JOIN frota_pedagio_agg  fp  ON fp.filial_relatorio  = fa.filial_relatorio
LEFT JOIN pedagio_detalhe    pdd ON pdd.filial_relatorio = fa.filial_relatorio
WHERE pd.total_pedagio IS NOT NULL
ORDER BY fa.filial_relatorio;
