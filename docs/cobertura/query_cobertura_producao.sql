-- ============================================================================
-- COBERTURA DE RASTREAMENTO — rodar no DW de PRODUCAO
--
-- Objetivo: descobrir quais veiculos do escopo Gritsch estao REALMENTE
-- descobertos, cruzando as tres fontes (3S, Nuxeo, Omnilink).
--
-- O que eu ja apurei aqui, direto da API da 3S (03/08/2026):
--   escopo Gritsch ................ 534
--   presentes na 3S ................ 79   (dos quais 71 transmitindo em 24h)
--   ausentes da 3S ................ 455   <- precisam ser checados na Nuxeo
--
-- As listas estao em docs/cobertura/gritsch_na_3s.csv e gritsch_fora_da_3s.csv
-- ============================================================================


-- ----------------------------------------------------------------------------
-- QUERY 0 — Reconhecimento: como a Nuxeo distingue Nuxeo de Omnilink?
--
-- Rode primeiro. Preciso saber o nome do campo para escrever as demais.
-- Procura em todas as tabelas nuxeo_* alguma coluna que separe as duas
-- operadoras (pode ser 'operadora', 'fornecedor', 'tipo', 'origem'...).
-- ----------------------------------------------------------------------------
SELECT table_name, column_name, data_type
  FROM information_schema.columns
 WHERE table_schema = 'bronze' AND table_name LIKE 'nuxeo%'
 ORDER BY table_name, ordinal_position;

-- E uma amostra do payload cru, que costuma revelar o campo:
SELECT jsonb_pretty(payload_json)
  FROM bronze.nuxeo_veiculos_posicao
 ORDER BY ingested_at DESC LIMIT 1;


-- ----------------------------------------------------------------------------
-- QUERY 1 — Cobertura pela Nuxeo (o numero que falta)
--
-- Ajuste o nome da tabela se necessario. Usa janela de 30 dias para nao
-- classificar como "descoberto" um veiculo que so ficou parado uns dias.
-- ----------------------------------------------------------------------------
WITH escopo AS (
    SELECT upper(regexp_replace(placa, '[\s-]', '', 'g')) AS placa,
           filial_operacional, situacao_veiculo, modelo_raw
      FROM torre.gold_dim_veiculo
     WHERE filial_operacional ILIKE '%GRI%'
       AND situacao_veiculo NOT IN ('VENDIDO', 'DISPONÍVEL PARA VENDA')
),
nuxeo AS (
    SELECT DISTINCT upper(regexp_replace(placa, '[\s-]', '', 'g')) AS placa,
           max(ingested_at) AS visto_em
      FROM bronze.nuxeo_veiculos_posicao
     WHERE ingested_at >= CURRENT_DATE - 30
     GROUP BY 1
)
SELECT count(*)                                          AS escopo_total,
       count(n.placa)                                    AS cobertos_nuxeo,
       count(*) - count(n.placa)                         AS fora_da_nuxeo
  FROM escopo e
  LEFT JOIN nuxeo n ON n.placa = e.placa;


-- ----------------------------------------------------------------------------
-- QUERY 2 — A LISTA QUE VOCE PEDIU: veiculos DESCOBERTOS de verdade
--
-- Cole aqui as 79 placas de docs/cobertura/gritsch_na_3s.csv.
-- Em producao a bronze.tres_s_veiculos esta vazia (o workflow 3S nunca rodou
-- de fato), por isso a lista vai literal.
-- ----------------------------------------------------------------------------
WITH escopo AS (
    SELECT upper(regexp_replace(placa, '[\s-]', '', 'g')) AS placa,
           filial_operacional, situacao_veiculo, modelo_raw, grupo_veiculo
      FROM torre.gold_dim_veiculo
     WHERE filial_operacional ILIKE '%GRI%'
       AND situacao_veiculo NOT IN ('VENDIDO', 'DISPONÍVEL PARA VENDA')
),
na_3s AS (
    SELECT unnest(ARRAY[
      -- SUBSTITUIR pelas 79 placas do CSV, ex: 'BCP0625','BCV8D45','BEB5D93',...
      'PLACA1','PLACA2'
    ]) AS placa
),
na_nuxeo AS (
    SELECT DISTINCT upper(regexp_replace(placa, '[\s-]', '', 'g')) AS placa
      FROM bronze.nuxeo_veiculos_posicao
     WHERE ingested_at >= CURRENT_DATE - 30
)
SELECT e.filial_operacional,
       e.placa,
       e.modelo_raw,
       e.grupo_veiculo,
       e.situacao_veiculo
  FROM escopo e
  LEFT JOIN na_3s    t ON t.placa = e.placa
  LEFT JOIN na_nuxeo n ON n.placa = e.placa
 WHERE t.placa IS NULL AND n.placa IS NULL      -- descoberto nas duas fontes
 ORDER BY e.filial_operacional, e.placa;


-- ----------------------------------------------------------------------------
-- QUERY 3 — Resumo por filial (para levar ao seu senior)
-- ----------------------------------------------------------------------------
WITH escopo AS (
    SELECT upper(regexp_replace(placa, '[\s-]', '', 'g')) AS placa, filial_operacional
      FROM torre.gold_dim_veiculo
     WHERE filial_operacional ILIKE '%GRI%'
       AND situacao_veiculo NOT IN ('VENDIDO', 'DISPONÍVEL PARA VENDA')
),
na_3s AS (SELECT unnest(ARRAY['PLACA1','PLACA2']) AS placa),   -- idem QUERY 2
na_nuxeo AS (
    SELECT DISTINCT upper(regexp_replace(placa, '[\s-]', '', 'g')) AS placa
      FROM bronze.nuxeo_veiculos_posicao
     WHERE ingested_at >= CURRENT_DATE - 30
)
SELECT e.filial_operacional,
       count(*)                                                        AS frota,
       count(t.placa)                                                  AS na_3s,
       count(n.placa)                                                  AS na_nuxeo,
       count(*) FILTER (WHERE t.placa IS NULL AND n.placa IS NULL)      AS descobertos,
       round(100.0 * count(*) FILTER (WHERE t.placa IS NULL AND n.placa IS NULL)
             / count(*), 1)                                            AS pct_descoberto
  FROM escopo e
  LEFT JOIN na_3s    t ON t.placa = e.placa
  LEFT JOIN na_nuxeo n ON n.placa = e.placa
 GROUP BY 1
 ORDER BY descobertos DESC;


-- ----------------------------------------------------------------------------
-- QUERY 4 — Veiculos que aparecem em MAIS DE UMA fonte
--
-- Se um veiculo estiver na 3S e na Nuxeo ao mesmo tempo, o silver vai
-- duplicar os eventos. Precisamos de uma regra de precedencia por veiculo.
-- ----------------------------------------------------------------------------
WITH escopo AS (
    SELECT upper(regexp_replace(placa, '[\s-]', '', 'g')) AS placa, filial_operacional
      FROM torre.gold_dim_veiculo
     WHERE filial_operacional ILIKE '%GRI%'
       AND situacao_veiculo NOT IN ('VENDIDO', 'DISPONÍVEL PARA VENDA')
),
na_3s AS (SELECT unnest(ARRAY['PLACA1','PLACA2']) AS placa),   -- idem QUERY 2
na_nuxeo AS (
    SELECT DISTINCT upper(regexp_replace(placa, '[\s-]', '', 'g')) AS placa
      FROM bronze.nuxeo_veiculos_posicao
     WHERE ingested_at >= CURRENT_DATE - 30
)
SELECT e.placa, e.filial_operacional
  FROM escopo e
  JOIN na_3s    t ON t.placa = e.placa
  JOIN na_nuxeo n ON n.placa = e.placa
 ORDER BY e.filial_operacional, e.placa;


-- ----------------------------------------------------------------------------
-- QUERY 5 — Tamanho atual das tabelas de posicao (dimensiona o ganho de espaco)
-- ----------------------------------------------------------------------------
SELECT relname AS tabela,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS tamanho,
       n_live_tup AS linhas_aprox
  FROM pg_class c
  JOIN pg_namespace ns ON ns.oid = c.relnamespace
  LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
 WHERE ns.nspname = 'bronze' AND c.relkind = 'r'
 ORDER BY pg_total_relation_size(c.oid) DESC;
