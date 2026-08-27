WITH base_tx_raw AS (
  SELECT
    c.transacao,
    c.placa,
    c.data,
    c.data_transacao,
    c.hodometro,
    c.litragem,
    c.valor_liquido,
    c.preco_unitario,
    c.grupo_combustivel,
    c.grupo_veiculo,
    c.cnpj_posto,
    REGEXP_REPLACE(c.cnpj_posto, '[^0-9]', '', 'g') AS cnpj_normalizado,
    c.garagem,
    c.cidade_posto,
    c.uf_posto,
    COALESCE(NULLIF(c.nome_fantasia_posto, ''), c.razao_social_posto) AS posto_nome_raw,
    CASE
      WHEN UPPER(REPLACE(c.placa, '-', '')) IN ('UBH2J71', 'UBR9B22', 'UBR9B09', 'SEP6E34', 'UBR9B08', 'UBR9A97', 'UBR9B27', 'UBR9A92', 'UBR9B16', 'UCB4H75', 'SFK1E50', 'TAI9A24') THEN 'Gritsch Santa Maria'
      WHEN c.garagem IN ('GRITSCH - CWB (BASE)', 'GRITSCH - CWB (ECT)') THEN 'Gritsch Curitiba (Base)'
      ELSE c.filial_nome
    END AS filial_relatorio,
    ROW_NUMBER() OVER (
      PARTITION BY c.placa, c.data_transacao, c.cnpj_posto, c.litragem
      ORDER BY c.transacao
    ) AS rn_dedup
  FROM torre.gold_truckpag_combustivel c
  WHERE NOT c.transacao_estornada
    AND c.litragem > 0
    AND c.valor_liquido > 0
    AND c.litragem < 1200
    AND c.grupo_combustivel NOT IN ('Arla', 'Outros')
    AND c.garagem NOT IN ('GRITSCH - CWB (DIR)', 'GRITSCH - MATRIZ', 'REFERENCIA CURITIBA', 'REFERÊNCIA CURITIBA')
    AND c.garagem NOT LIKE '%DIR%'
    AND c.garagem NOT LIKE '%MATRIZ%'
    AND c.garagem NOT ILIKE '%REFERENCIA%'
    AND c.garagem NOT ILIKE '%REFERÊNCIA%'
    AND c.filial_nome NOT ILIKE '%REFERENCIA%'
    AND c.filial_nome NOT ILIKE '%REFERÊNCIA%'
),
base_tx AS (
  SELECT * FROM base_tx_raw WHERE rn_dedup = 1
),
-- Coleta ANP de referencia: a pesquisa da MESMA semana do relatorio.
-- FIX 24/08/2026 -- antes nao havia filtro de data nenhum aqui: a media
-- pegava TODA a historia acumulada da tabela (backfill desde 06/2025 + uma
-- coleta nova toda segunda). Como o preco subiu no periodo, essa media
-- historica ficava ABAIXO do preco corrente e o relatorio mostrava as
-- filiais pagando "acima da ANP" mesmo pagando preco de mercado -- e o
-- desvio piorava a cada semana que a tabela crescia. Agora compara a semana
-- do relatorio contra a pesquisa ANP daquela mesma semana.
anp_semana AS (
  SELECT COALESCE(
    -- coleta mais recente ATE o fim do periodo do relatorio
    (SELECT MAX(data_coleta) FROM torre.raw_anp_combustiveis
      WHERE data_coleta <= '{{ $('Calcular Período').first().json.end_date }}'),
    -- fallback: periodo anterior ao inicio da serie ANP (backfill antigo)
    (SELECT MIN(data_coleta) FROM torre.raw_anp_combustiveis)
  ) AS data_coleta_ref
),
anp_ref_estado AS (
  SELECT
    CASE UPPER(TRIM(a.estado_sigla))
      WHEN 'PARANA' THEN 'PR' WHEN 'SANTA CATARINA' THEN 'SC' WHEN 'RIO GRANDE DO SUL' THEN 'RS'
      WHEN 'SAO PAULO' THEN 'SP' WHEN 'MATO GROSSO' THEN 'MT' WHEN 'MATO GROSSO DO SUL' THEN 'MS'
      WHEN 'GOIAS' THEN 'GO' WHEN 'BAHIA' THEN 'BA' WHEN 'TOCANTINS' THEN 'TO' WHEN 'DISTRITO FEDERAL' THEN 'DF'
      ELSE UPPER(TRIM(a.estado_sigla))
    END AS uf,
    CASE
      WHEN a.produto ILIKE '%DIESEL%' THEN 'Diesel'
      WHEN a.produto ILIKE '%GASOLINA%' THEN 'Gasolina'
      WHEN a.produto ILIKE '%ETANOL%' OR a.produto ILIKE '%LCOOL%' THEN 'Álcool'
      ELSE 'Outros'
    END AS grupo_combustivel,
    ROUND(AVG(a.preco_revenda)::numeric, 4) AS preco_anp_uf
  FROM torre.raw_anp_combustiveis a
  CROSS JOIN anp_semana s
  WHERE a.data_coleta = s.data_coleta_ref
    AND a.preco_revenda > 0
    -- SO posto de BANDEIRA (pedido do usuario 24/08/2026): a rede Gritsch
    -- abastece em posto bandeirado, entao a referencia justa e' o preco de
    -- bandeirado -- posto branco puxa a media pra baixo e distorce o desvio.
    -- Casamento por LIKE, nao lista fixa: a ANP escreve "BRANCA",
    -- "BANDEIRA BRANCA", com acento/espaco extra etc., e o NOT IN antigo
    -- (string exata) deixava variacoes passarem.
    AND a.bandeira IS NOT NULL
    AND TRIM(a.bandeira) <> ''
    AND UPPER(TRIM(a.bandeira)) NOT LIKE '%BRANCA%'
    AND UPPER(TRIM(a.bandeira)) NOT LIKE '%SEM BANDEIRA%'
    AND UPPER(TRIM(a.bandeira)) NOT IN ('OUTRAS', 'OUTROS', 'NAO INFORMADA', 'NÃO INFORMADA', 'N/D', 'ND', '-')
  GROUP BY 1, 2
),
tx_com_valid_hod AS (
  SELECT
    transacao,
    LAG(hodometro) OVER (PARTITION BY placa ORDER BY data_transacao, transacao) AS hod_ant
  FROM base_tx
  WHERE hodometro > 0
),
tx_com_km AS (
  SELECT
    b.*,
    CASE
      WHEN b.hodometro > 0 AND h.hod_ant > 0 AND b.hodometro > h.hod_ant AND (b.hodometro - h.hod_ant) < 15000
      THEN (b.hodometro - h.hod_ant)
      ELSE NULL
    END AS km_trecho,
    COALESCE(a.preco_anp_uf, 6.22) AS preco_anp_ref,
    (b.litragem * COALESCE(a.preco_anp_uf, 6.22)) AS valor_anp_esperado
  FROM base_tx b
  LEFT JOIN tx_com_valid_hod h ON h.transacao = b.transacao
  LEFT JOIN anp_ref_estado a ON a.uf = b.uf_posto AND a.grupo_combustivel = b.grupo_combustivel
),
-- Filiais_ativas: UNION do dimensional com o que realmente aparece nas
-- transacoes DE COMBUSTIVEL (era assim no original, so trocando a fonte
-- do segundo lado do UNION quando isso virar a versao pedagio).
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
      garagem AS garagem_referencia
    FROM base_tx
    WHERE filial_relatorio IS NOT NULL
  ) sub
  GROUP BY filial_relatorio
),
kpis_semana AS (
  SELECT
    filial_relatorio,
    ROUND(SUM(litragem)::numeric, 2)      AS total_litros,
    ROUND(SUM(valor_liquido)::numeric, 2) AS total_gasto_comb,
    ROUND((SUM(valor_liquido) / NULLIF(SUM(litragem), 0))::numeric, 2) AS preco_medio_litro,
    ROUND(((SUM(valor_liquido) - SUM(valor_anp_esperado)) / NULLIF(SUM(valor_anp_esperado), 0) * 100)::numeric, 1) AS desvio_anp_ponderado_pct,
    COUNT(DISTINCT placa)                 AS qtd_veiculos_ativos,
    COALESCE(SUM(km_trecho), 0)           AS total_km,
    ROUND((SUM(CASE WHEN km_trecho > 0 THEN valor_liquido ELSE 0 END) / NULLIF(SUM(km_trecho), 0))::numeric, 2) AS custo_km_comb_medido
  FROM tx_com_km
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
    AND filial_relatorio IS NOT NULL
  GROUP BY filial_relatorio
),
kpis_ant AS (
  SELECT
    filial_relatorio,
    ROUND(SUM(litragem)::numeric, 2)      AS total_litros_ant,
    ROUND(SUM(valor_liquido)::numeric, 2) AS total_gasto_comb_ant,
    ROUND((SUM(valor_liquido) / NULLIF(SUM(litragem), 0))::numeric, 2) AS preco_medio_litro_ant,
    COUNT(DISTINCT placa)                 AS qtd_veiculos_ativos_ant,
    COALESCE(SUM(km_trecho), 0)           AS total_km_ant,
    ROUND((SUM(CASE WHEN km_trecho > 0 THEN valor_liquido ELSE 0 END) / NULLIF(SUM(km_trecho), 0))::numeric, 2) AS custo_km_ant_medido
  FROM tx_com_km
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date_ant }}' AND '{{ $('Calcular Período').first().json.end_date_ant }}'
    AND filial_relatorio IS NOT NULL
  GROUP BY filial_relatorio
),
combustivel_agg AS (
  SELECT
    filial_relatorio,
    json_agg(
      json_build_object(
        'grupo_combustivel', grupo_combustivel,
        'total_litros', total_litros,
        'total_gasto', total_gasto,
        'preco_medio', preco_medio,
        'total_km', total_km,
        'custo_km', custo_km
      ) ORDER BY total_gasto DESC
    ) AS combustivel_json
  FROM (
    SELECT
      filial_relatorio,
      grupo_combustivel,
      ROUND(SUM(litragem)::numeric, 2)      AS total_litros,
      ROUND(SUM(valor_liquido)::numeric, 2) AS total_gasto,
      ROUND((SUM(valor_liquido) / NULLIF(SUM(litragem), 0))::numeric, 2) AS preco_medio,
      COALESCE(SUM(km_trecho), 0)           AS total_km,
      ROUND((SUM(CASE WHEN km_trecho > 0 THEN valor_liquido ELSE 0 END) / NULLIF(SUM(km_trecho), 0))::numeric, 2) AS custo_km
    FROM tx_com_km
    WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
      AND filial_relatorio IS NOT NULL
    GROUP BY filial_relatorio, grupo_combustivel
  ) sub
  GROUP BY filial_relatorio
),
frota_ativa AS (
  SELECT
    filial_relatorio,
    placa,
    grupo_combustivel,
    COALESCE(grupo_veiculo, 'Outros') AS grupo_veiculo,
    COALESCE(SUM(litragem), 0)      AS total_litros,
    COALESCE(SUM(valor_liquido), 0) AS valor_total,
    COALESCE(SUM(km_trecho), 0)     AS km_percorrido
  FROM tx_com_km
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
    AND filial_relatorio IS NOT NULL
  GROUP BY filial_relatorio, placa, grupo_combustivel, grupo_veiculo
),
frota_agg AS (
  SELECT
    filial_relatorio,
    json_agg(
      json_build_object(
        'placa', placa,
        'combustivel', grupo_combustivel,
        'grupo_veiculo', grupo_veiculo,
        'total_litros', ROUND(total_litros::numeric, 2),
        'valor_total', ROUND(valor_total::numeric, 2),
        'km_percorrido', km_percorrido,
        'custo_km', CASE WHEN km_percorrido > 0 THEN ROUND((valor_total / km_percorrido)::numeric, 2) ELSE NULL END
      ) ORDER BY valor_total DESC
    ) AS frota_json
  FROM frota_ativa
  GROUP BY filial_relatorio
),
-- Media por grupo de veiculo NESTA filial, na semana -- pra comparar cada
-- veiculo com os pares da mesma categoria aqui dentro.
grupo_veiculo_filial AS (
  SELECT
    filial_relatorio,
    COALESCE(grupo_veiculo, 'Outros') AS grupo_veiculo,
    COUNT(DISTINCT placa) AS qtd_veiculos,
    COALESCE(SUM(km_trecho), 0) AS km_grupo,
    ROUND(SUM(valor_liquido)::numeric, 2) AS gasto_grupo,
    ROUND((SUM(CASE WHEN km_trecho > 0 THEN valor_liquido ELSE 0 END) / NULLIF(SUM(km_trecho), 0))::numeric, 2) AS custo_km_filial
  FROM tx_com_km
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
    AND filial_relatorio IS NOT NULL
  GROUP BY filial_relatorio, COALESCE(grupo_veiculo, 'Outros')
),
-- Media de REFERENCIA: mesmo calculo, mesma semana, mas pela frota TODA
-- (todas as filiais juntas) -- o benchmark contra a empresa inteira.
grupo_veiculo_referencia AS (
  SELECT
    COALESCE(grupo_veiculo, 'Outros') AS grupo_veiculo,
    ROUND((SUM(CASE WHEN km_trecho > 0 THEN valor_liquido ELSE 0 END) / NULLIF(SUM(km_trecho), 0))::numeric, 2) AS custo_km_referencia
  FROM tx_com_km
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
    AND filial_relatorio IS NOT NULL
  GROUP BY COALESCE(grupo_veiculo, 'Outros')
),
grupo_veiculo_agg AS (
  SELECT
    f.filial_relatorio,
    json_agg(
      json_build_object(
        'grupo_veiculo', f.grupo_veiculo,
        'qtd_veiculos', f.qtd_veiculos,
        'gasto_grupo', f.gasto_grupo,
        'custo_km_filial', f.custo_km_filial,
        'custo_km_referencia', r.custo_km_referencia
      ) ORDER BY f.gasto_grupo DESC
    ) AS grupos_veiculo_json
  FROM grupo_veiculo_filial f
  LEFT JOIN grupo_veiculo_referencia r ON r.grupo_veiculo = f.grupo_veiculo
  GROUP BY f.filial_relatorio
),
postos_semana AS (
  SELECT
    c.filial_relatorio,
    c.cnpj_normalizado AS cnpj_posto,
    c.posto_nome_raw AS posto_nome,
    COALESCE(c.cidade_posto, 'N/D') AS cidade_posto,
    COALESCE(c.uf_posto, 'N/D') AS uf_posto,
    c.grupo_combustivel,
    ROUND(SUM(c.litragem)::numeric, 2) AS total_litros,
    ROUND(SUM(c.valor_liquido)::numeric, 2) AS total_gasto,
    ROUND((SUM(c.valor_liquido) / NULLIF(SUM(c.litragem), 0))::numeric, 2) AS preco_medio,
    ROUND(AVG(c.preco_anp_ref)::numeric, 2) AS preco_anp_ref,
    ROUND(((SUM(c.valor_liquido) / NULLIF(SUM(c.litragem), 0) - AVG(c.preco_anp_ref)) / NULLIF(AVG(c.preco_anp_ref), 0) * 100)::numeric, 1) AS desvio_anp,
    COUNT(DISTINCT c.transacao) AS qtd_abastecimentos,
    ROW_NUMBER() OVER (
      PARTITION BY c.filial_relatorio
      ORDER BY SUM(c.valor_liquido) DESC
    ) AS rn
  FROM tx_com_km c
  WHERE c.data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
    AND c.filial_relatorio IS NOT NULL
  GROUP BY c.filial_relatorio, c.cnpj_normalizado, c.posto_nome_raw, c.cidade_posto, c.uf_posto, c.grupo_combustivel
),
postos_agg AS (
  SELECT
    filial_relatorio,
    json_agg(
      json_build_object(
        'cnpj_posto', cnpj_posto,
        'posto', posto_nome,
        'cidade', cidade_posto,
        'uf', uf_posto,
        'combustivel', grupo_combustivel,
        'total_litros', total_litros,
        'total_gasto', total_gasto,
        'preco_medio', preco_medio,
        'preco_anp', preco_anp_ref,
        'desvio_anp', desvio_anp,
        'qtd_abastecimentos', qtd_abastecimentos
      ) ORDER BY total_gasto DESC
    ) AS postos_json
  FROM postos_semana
  WHERE rn <= {{ $('Calcular Período').first().json.top_postos || 8 }}
  GROUP BY filial_relatorio
),
transacoes_detalhe AS (
  SELECT
    filial_relatorio,
    json_agg(
      json_build_object(
        'transacao', transacao,
        'data_hora', TO_CHAR(data_transacao, 'DD/MM/YYYY HH24:MI'),
        'placa', placa,
        'grupo_veiculo', COALESCE(grupo_veiculo, 'Outros'),
        'hodometro', COALESCE(hodometro, 0),
        'km_trecho', COALESCE(km_trecho, 0),
        'litros', ROUND(litragem::numeric, 2),
        'preco_unitario', ROUND(preco_unitario::numeric, 2),
        'valor_total', ROUND(valor_liquido::numeric, 2),
        'combustivel', grupo_combustivel,
        'estabelecimento', posto_nome_raw,
        'cnpj', cnpj_posto,
        'cidade', COALESCE(cidade_posto, 'N/D'),
        'uf', COALESCE(uf_posto, 'N/D'),
        'preco_anp', ROUND(preco_anp_ref::numeric, 2),
        'desvio_anp', CASE WHEN preco_anp_ref > 0 THEN ROUND(((preco_unitario - preco_anp_ref) / preco_anp_ref * 100)::numeric, 1) ELSE NULL END
      ) ORDER BY data_transacao, transacao
    ) AS transacoes_json
  FROM tx_com_km
  WHERE data BETWEEN '{{ $('Calcular Período').first().json.start_date }}' AND '{{ $('Calcular Período').first().json.end_date }}'
    AND filial_relatorio IS NOT NULL
  GROUP BY filial_relatorio
)
SELECT
  fa.filial_relatorio                     AS filial_nome,
  fa.garagem_referencia                   AS garagem,
  COALESCE(ef.email_destino, '')          AS email_gestor,
  COALESCE(ef.email_cc, '')               AS email_cc,
  COALESCE(ef.cc_regional, '')            AS cc_regional,
  COALESCE(cfg_cc.valor, '')              AS cc_global,
  ccfg.consolidado_destinatarios          AS consolidado_destinatarios_db,
  ccfg.consolidado_cc                     AS consolidado_cc_db,
  -- Semana atual
  COALESCE(k.total_litros, 0)             AS total_litros,
  COALESCE(k.total_gasto_comb, 0)         AS total_gasto_comb,
  COALESCE(k.preco_medio_litro, 0)        AS preco_medio_litro,
  COALESCE(k.desvio_anp_ponderado_pct, 0) AS desvio_anp_pct,
  COALESCE(k.qtd_veiculos_ativos, 0)      AS qtd_veiculos_ativos,
  COALESCE(k.total_km, 0)                 AS total_km_calculado,
  COALESCE(k.custo_km_comb_medido, 0)     AS custo_km_comb_medido,
  -- Semana anterior (delta)
  COALESCE(ka.total_litros_ant, 0)        AS total_litros_ant,
  COALESCE(ka.total_gasto_comb_ant, 0)    AS total_gasto_comb_ant,
  COALESCE(ka.preco_medio_litro_ant, 0)   AS preco_medio_litro_ant,
  COALESCE(ka.qtd_veiculos_ativos_ant, 0) AS qtd_veiculos_ativos_ant,
  COALESCE(ka.total_km_ant, 0)            AS total_km_ant,
  COALESCE(ka.custo_km_ant_medido, 0)     AS custo_km_ant_medido,
  -- Detalhes agregados
  COALESCE(cbt.combustivel_json, '[]'::json) AS resumo_combustivel,
  COALESCE(f.frota_json, '[]'::json)         AS frota_ativa,
  COALESCE(gv.grupos_veiculo_json, '[]'::json) AS grupos_veiculo,
  COALESCE(p.postos_json, '[]'::json)        AS postos_utilizados,
  COALESCE(td.transacoes_json, '[]'::json)   AS transacoes_detalhe
FROM filiais_ativas fa
LEFT JOIN torre.email_gritsch_filiais ef ON ef.filial_operacional = fa.garagem_referencia AND ef.ativo = true
-- Fix 24/08/2026: antes era "CROSS JOIN (SELECT valor FROM ... LIMIT 1)" --
-- se a chave 'cc_global' nao existisse na tabela, a subquery voltava ZERO
-- linhas e o CROSS JOIN zerava o relatorio inteiro (nao so o CC). O
-- COALESCE aqui dentro garante sempre 1 linha, e o fallback bate com o
-- mesmo default hardcoded do telemetria (evita CC vazio silencioso).
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
LEFT JOIN kpis_semana      k    ON k.filial_relatorio   = fa.filial_relatorio
LEFT JOIN kpis_ant         ka   ON ka.filial_relatorio  = fa.filial_relatorio
LEFT JOIN combustivel_agg  cbt  ON cbt.filial_relatorio = fa.filial_relatorio
LEFT JOIN frota_agg        f    ON f.filial_relatorio   = fa.filial_relatorio
LEFT JOIN grupo_veiculo_agg gv  ON gv.filial_relatorio  = fa.filial_relatorio
LEFT JOIN postos_agg       p    ON p.filial_relatorio   = fa.filial_relatorio
LEFT JOIN transacoes_detalhe td ON td.filial_relatorio  = fa.filial_relatorio
WHERE f.frota_json IS NOT NULL
ORDER BY fa.filial_relatorio;
