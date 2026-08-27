-- Combustivel DIARIO -- pulso rapido todo dia util, pro gestor ver antes do
-- fechamento semanal completo. v2 (24/08/2026): usuario pediu placa/posto
-- de volta (achou a v1 so-KPI simples demais) -- volume de 1 dia e' pequeno
-- o bastante pra listar tudo sem virar poluicao visual, entao aqui NAO
-- corta em Top N (diferente do semanal): mostra toda placa e todo posto que
-- movimentou no dia. O que continua exclusivo do semanal: CSV em anexo e a
-- comparacao "grupo de veiculo vs. referencia da frota" (analise mais
-- pesada, cabe melhor numa visao de semana do que de 1 dia).
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
    -- Bug real (27/08/2026, achado com dado de producao real de 2 dias
    -- rodando): tinha um filtro aqui cedo (AND c.data >= start_date_ant)
    -- pensado como "otimizacao" pra aliviar o ROW_NUMBER/LAG. Na pratica
    -- isso quebrou o LAG(hodometro): ele so acha o abastecimento anterior
    -- de um veiculo DENTRO da janela carregada -- se o veiculo nao abasteceu
    -- tambem no dia anterior (comum, frota nao abastece todo santo dia),
    -- LAG nao acha nada e km_trecho/custo_km viram N/D pra maioria da
    -- frota, mesmo o veiculo tendo hodometro valido semanas atras. Sem esse
    -- filtro, exatamente igual ao semanal (que nunca teve esse corte): LAG
    -- enxerga o historico completo do veiculo, so os CTEs de KPI/frota/
    -- postos la embaixo e' que recortam pelo dia do relatorio.
),
base_tx AS (
  SELECT * FROM base_tx_raw WHERE rn_dedup = 1
),
-- Coleta ANP de referencia: a pesquisa vigente no dia do relatorio.
-- Mesmo fix do semanal (24/08/2026) -- antes a media pegava toda a historia
-- acumulada da tabela, o que empurrava a referencia pra baixo e inflava o
-- desvio. A ANP publica semanalmente, entao no diario a coleta corrente e' a
-- ultima publicada ate o dia analisado.
anp_semana AS (
  SELECT COALESCE(
    (SELECT MAX(data_coleta) FROM torre.raw_anp_combustiveis
      WHERE data_coleta <= '{{ $('Calcular Período Diário').first().json.end_date }}'),
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
    -- SO posto de bandeira -- ver comentario detalhado no SQL semanal.
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
kpis_dia AS (
  SELECT
    filial_relatorio,
    ROUND(SUM(litragem)::numeric, 2)      AS total_litros,
    ROUND(SUM(valor_liquido)::numeric, 2) AS total_gasto_comb,
    ROUND((SUM(valor_liquido) / NULLIF(SUM(litragem), 0))::numeric, 2) AS preco_medio_litro,
    ROUND(((SUM(valor_liquido) - SUM(valor_anp_esperado)) / NULLIF(SUM(valor_anp_esperado), 0) * 100)::numeric, 1) AS desvio_anp_pct,
    COUNT(DISTINCT placa)                 AS qtd_veiculos_ativos,
    COALESCE(SUM(km_trecho), 0)           AS total_km,
    ROUND((SUM(CASE WHEN km_trecho > 0 THEN valor_liquido ELSE 0 END) / NULLIF(SUM(km_trecho), 0))::numeric, 2) AS custo_km_comb_medido
  FROM tx_com_km
  WHERE data BETWEEN '{{ $('Calcular Período Diário').first().json.start_date }}' AND '{{ $('Calcular Período Diário').first().json.end_date }}'
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
  WHERE data BETWEEN '{{ $('Calcular Período Diário').first().json.start_date_ant }}' AND '{{ $('Calcular Período Diário').first().json.end_date_ant }}'
    AND filial_relatorio IS NOT NULL
  GROUP BY filial_relatorio
),
frota_dia AS (
  SELECT
    filial_relatorio,
    placa,
    grupo_combustivel,
    COALESCE(grupo_veiculo, 'Outros') AS grupo_veiculo,
    COALESCE(SUM(litragem), 0)      AS total_litros,
    COALESCE(SUM(valor_liquido), 0) AS valor_total,
    COALESCE(SUM(km_trecho), 0)     AS km_percorrido
  FROM tx_com_km
  WHERE data BETWEEN '{{ $('Calcular Período Diário').first().json.start_date }}' AND '{{ $('Calcular Período Diário').first().json.end_date }}'
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
  FROM frota_dia
  GROUP BY filial_relatorio
),
postos_dia AS (
  SELECT
    c.filial_relatorio,
    c.cnpj_posto,
    COALESCE(c.posto_nome_raw, 'Posto') AS posto_nome,
    COALESCE(c.cidade_posto, 'N/D') AS cidade_posto,
    COALESCE(c.uf_posto, 'N/D') AS uf_posto,
    c.grupo_combustivel,
    ROUND(SUM(c.litragem)::numeric, 2) AS total_litros,
    ROUND(SUM(c.valor_liquido)::numeric, 2) AS total_gasto,
    ROUND((SUM(c.valor_liquido) / NULLIF(SUM(c.litragem), 0))::numeric, 2) AS preco_medio,
    ROUND(AVG(c.preco_anp_ref)::numeric, 2) AS preco_anp_ref,
    ROUND(((SUM(c.valor_liquido) / NULLIF(SUM(c.litragem), 0) - AVG(c.preco_anp_ref)) / NULLIF(AVG(c.preco_anp_ref), 0) * 100)::numeric, 1) AS desvio_anp
  FROM tx_com_km c
  WHERE c.data BETWEEN '{{ $('Calcular Período Diário').first().json.start_date }}' AND '{{ $('Calcular Período Diário').first().json.end_date }}'
    AND c.filial_relatorio IS NOT NULL
  GROUP BY c.filial_relatorio, c.cnpj_posto, COALESCE(c.posto_nome_raw, 'Posto'), c.cidade_posto, c.uf_posto, c.grupo_combustivel
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
        'desvio_anp', desvio_anp
      ) ORDER BY total_gasto DESC
    ) AS postos_json
  FROM postos_dia
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
  -- Dia atual
  COALESCE(k.total_litros, 0)             AS total_litros,
  COALESCE(k.total_gasto_comb, 0)         AS total_gasto_comb,
  COALESCE(k.preco_medio_litro, 0)        AS preco_medio_litro,
  COALESCE(k.desvio_anp_pct, 0)           AS desvio_anp_pct,
  COALESCE(k.qtd_veiculos_ativos, 0)      AS qtd_veiculos_ativos,
  COALESCE(k.total_km, 0)                 AS total_km_calculado,
  COALESCE(k.custo_km_comb_medido, 0)     AS custo_km_comb_medido,
  -- Dia(s) anterior(es) de comparacao
  COALESCE(ka.total_litros_ant, 0)        AS total_litros_ant,
  COALESCE(ka.total_gasto_comb_ant, 0)    AS total_gasto_comb_ant,
  COALESCE(ka.preco_medio_litro_ant, 0)   AS preco_medio_litro_ant,
  COALESCE(ka.qtd_veiculos_ativos_ant, 0) AS qtd_veiculos_ativos_ant,
  COALESCE(ka.total_km_ant, 0)            AS total_km_ant,
  COALESCE(ka.custo_km_ant_medido, 0)     AS custo_km_ant_medido,
  -- Placas e postos do dia (v2 -- pedido do usuario 24/08/2026)
  COALESCE(f.frota_json, '[]'::json)      AS frota_ativa,
  COALESCE(p.postos_json, '[]'::json)     AS postos_utilizados
FROM filiais_ativas fa
LEFT JOIN torre.email_gritsch_filiais ef ON ef.filial_operacional = fa.garagem_referencia AND ef.ativo = true
-- Mesmo fix do semanal (24/08/2026): COALESCE garante 1 linha mesmo sem a
-- chave 'cc_global' cadastrada, senao o CROSS JOIN zera o relatorio inteiro.
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
LEFT JOIN kpis_dia k  ON k.filial_relatorio  = fa.filial_relatorio
LEFT JOIN kpis_ant  ka ON ka.filial_relatorio = fa.filial_relatorio
LEFT JOIN frota_agg  f  ON f.filial_relatorio  = fa.filial_relatorio
LEFT JOIN postos_agg p  ON p.filial_relatorio  = fa.filial_relatorio
-- So manda pra filial que efetivamente abasteceu no dia -- diferente do
-- semanal (que lista a frota toda mesmo sem gasto), o diario e' um pulso:
-- sem transacao, sem e-mail.
WHERE k.total_litros > 0
ORDER BY fa.filial_relatorio;
