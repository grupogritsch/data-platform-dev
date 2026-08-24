# 🟨 KPI & Ajustes BD Torre de Controle — Validação Semanal Completa

> Execute os blocos abaixo **sequencialmente** no pgAdmin ou DBeaver conectado ao DW (`Interno - DW`).
> Cada bloco retorna resultados que indicam se há problemas a resolver.

---

## ✅ Bloco 1 — Saúde das Tabelas Core (existência e volume)

```sql
-- 1.1 Tabelas de Integração (fontes brutas)
SELECT 'integration_truckpag_transacoes' AS tabela, COUNT(*) AS registros FROM torre.integration_truckpag_transacoes
UNION ALL SELECT 'integration_truckpag_nfe_vinculos', COUNT(*) FROM torre.integration_truckpag_nfe_vinculos
UNION ALL SELECT 'integration_truckpag_titulos', COUNT(*) FROM torre.integration_truckpag_titulos
UNION ALL SELECT 'raw_anp_combustiveis', COUNT(*) FROM torre.raw_anp_combustiveis
UNION ALL SELECT 'log_anp_arquivos_ingeridos', COUNT(*) FROM torre.log_anp_arquivos_ingeridos
-- 1.2 Dimensões
UNION ALL SELECT 'gold_dim_filial', COUNT(*) FROM torre.gold_dim_filial
UNION ALL SELECT 'gold_dim_veiculo', COUNT(*) FROM torre.gold_dim_veiculo
UNION ALL SELECT 'gold_dim_grupo_combustivel', COUNT(*) FROM torre.gold_dim_grupo_combustivel
UNION ALL SELECT 'gold_dim_modelo_veiculo', COUNT(*) FROM torre.gold_dim_modelo_veiculo
UNION ALL SELECT 'gold_dim_placa_excecao', COUNT(*) FROM torre.gold_dim_placa_excecao
UNION ALL SELECT 'ref_benchmark_km_l', COUNT(*) FROM torre.ref_benchmark_km_l
UNION ALL SELECT 'ref_municipios_brasil', COUNT(*) FROM torre.ref_municipios_brasil
-- 1.3 Fato
UNION ALL SELECT 'gold_fato_fechamento_semanal', COUNT(*) FROM torre.gold_fato_fechamento_semanal_combustivel
ORDER BY tabela;
```

> **Esperado**: Todas as tabelas devem existir e ter `registros > 0`.

---

## ✅ Bloco 2 — Saúde das Materialized Views (última atualização)

```sql
-- 2.1 Verifica quando cada MV foi atualizada pela última vez
SELECT 
  schemaname || '.' || matviewname AS mv_nome,
  CASE WHEN hasdata THEN '✅ COM DADOS' ELSE '❌ VAZIA' END AS status,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || matviewname)) AS tamanho
FROM pg_matviews
WHERE schemaname = 'torre'
ORDER BY matviewname;
```

> **Ação**: Se alguma MV aparecer como `❌ VAZIA`, execute o workflow GOLD correspondente no n8n ou rode `REFRESH MATERIALIZED VIEW torre.<nome_mv>;` manualmente.

---

## ✅ Bloco 3 — Freshness dos Pipelines (última data de cada fonte)

```sql
-- 3.1 TruckPag: última transação ingerida
SELECT 
  'TruckPag' AS fonte,
  MAX(DATE(data_transacao AT TIME ZONE 'America/Sao_Paulo')) AS ultima_data,
  COUNT(DISTINCT DATE(data_transacao AT TIME ZONE 'America/Sao_Paulo')) 
    FILTER (WHERE DATE(data_transacao AT TIME ZONE 'America/Sao_Paulo') >= CURRENT_DATE - 7) AS dias_ultima_semana,
  CURRENT_DATE - MAX(DATE(data_transacao AT TIME ZONE 'America/Sao_Paulo')) AS dias_atraso
FROM torre.integration_truckpag_transacoes;

-- 3.2 ANP: última coleta
SELECT 
  'ANP' AS fonte,
  MAX(data_coleta) AS ultima_coleta,
  CURRENT_DATE - MAX(data_coleta) AS dias_atraso
FROM torre.raw_anp_combustiveis;

-- 3.3 Dim Veículo: última sincronização Bluefleet
SELECT 
  'Dim Veículo' AS fonte,
  MAX(atualizado_em) AS ultima_sync,
  COUNT(*) AS veiculos_cadastrados,
  COUNT(*) FILTER (WHERE situacao_veiculo = 'ATIVO') AS veiculos_ativos
FROM torre.gold_dim_veiculo;

-- 3.4 MV Comparativo ANP: última semana processada
SELECT 
  'Comparativo ANP' AS fonte,
  MAX(semana) AS ultima_semana,
  COUNT(DISTINCT semana) AS total_semanas
FROM torre.gold_mv_comparativo_anp;

-- 3.5 Fechamento Semanal: último registro salvo
SELECT 
  'Fechamento Semanal' AS fonte,
  MAX(semana_inicio) AS ultima_semana,
  MAX(criado_em) AS ultimo_processamento,
  COUNT(DISTINCT filial_nome) AS filiais_salvas
FROM torre.gold_fato_fechamento_semanal_combustivel;
```

> **Esperado**:
> - TruckPag: `dias_atraso` ≤ 2
> - ANP: `dias_atraso` ≤ 15
> - Dim Veículo: `ultima_sync` hoje ou ontem (roda todo dia 04:00)
> - Comparativo ANP: `ultima_semana` = semana passada

---

## ✅ Bloco 4 — Integridade de Dimensões

```sql
-- 4.1 Placas que abasteceram mas NÃO estão na dim_veiculo
SELECT DISTINCT c.placa, c.garagem, COUNT(*) AS abastecimentos, MAX(c.data) AS ultimo
FROM torre.gold_truckpag_combustivel c
LEFT JOIN torre.gold_dim_veiculo v ON c.placa = v.placa
WHERE v.placa IS NULL
  AND c.data >= CURRENT_DATE - 30
  AND NOT c.transacao_estornada
GROUP BY c.placa, c.garagem
ORDER BY abastecimentos DESC;

-- 4.2 Veículos sem grupo_veiculo (impede benchmark)
SELECT placa, modelo_raw, grupo_veiculo
FROM torre.gold_dim_veiculo
WHERE grupo_veiculo IS NULL OR grupo_veiculo = ''
ORDER BY placa;

-- 4.3 Garagens sem mapeamento na dim_filial
SELECT DISTINCT c.garagem, c.filial_nome, COUNT(*) AS abastecimentos
FROM torre.gold_truckpag_combustivel c
LEFT JOIN torre.gold_dim_filial f ON c.garagem = f.garagem
WHERE f.garagem IS NULL
  AND c.data >= CURRENT_DATE - 30
GROUP BY c.garagem, c.filial_nome
ORDER BY abastecimentos DESC;

-- 4.4 Combustíveis sem mapeamento no grupo (aparecem como 'Outros')
SELECT DISTINCT c.nome_combustivel, c.grupo_combustivel, COUNT(*) AS transacoes
FROM torre.gold_truckpag_combustivel c
WHERE c.grupo_combustivel = 'Outros'
  AND c.data >= CURRENT_DATE - 30
  AND NOT c.transacao_estornada
GROUP BY c.nome_combustivel, c.grupo_combustivel
ORDER BY transacoes DESC;
```

> **Ação**: 
> - 4.1 → Rodar `GOLD - 4 - Sincronizacao dim_veiculo` no n8n.
> - 4.3 → Inserir garagem na `gold_dim_filial` via `GOLD - 1`.
> - 4.4 → Inserir na `gold_dim_grupo_combustivel` via `GOLD - 2`.

---

## ✅ Bloco 5 — Benchmark de Eficiência (veículos SEM_REF)

```sql
-- 5.1 Cobertura do benchmark atual
SELECT 
  bm.grupo_veiculo, 
  bm.grupo_combustivel, 
  bm.km_l_ref,
  bm.alerta_85pct,
  bm.alerta_70pct,
  bm.tipo_calculo,
  COUNT(DISTINCT v.placa) AS veiculos_cobertos
FROM torre.ref_benchmark_km_l bm
LEFT JOIN torre.gold_dim_veiculo v ON v.grupo_veiculo = bm.grupo_veiculo
GROUP BY bm.grupo_veiculo, bm.grupo_combustivel, bm.km_l_ref, bm.alerta_85pct, bm.alerta_70pct, bm.tipo_calculo
ORDER BY bm.grupo_veiculo, bm.grupo_combustivel;

-- 5.2 Grupos de veículo × combustível SEM referência (aparecem como SEM_REF no relatório)
SELECT 
  v.grupo_veiculo,
  c.grupo_combustivel,
  COUNT(DISTINCT c.placa) AS veiculos_sem_ref,
  ROUND(SUM(c.valor_liquido)::numeric, 2) AS gasto_total_sem_ref
FROM torre.gold_truckpag_combustivel c
JOIN torre.gold_dim_veiculo v ON c.placa = v.placa
LEFT JOIN torre.ref_benchmark_km_l bm 
  ON bm.grupo_veiculo = v.grupo_veiculo 
  AND bm.grupo_combustivel = c.grupo_combustivel
WHERE bm.km_l_ref IS NULL
  AND c.data >= CURRENT_DATE - 30
  AND c.grupo_combustivel NOT IN ('Arla', 'Outros')
  AND NOT c.transacao_estornada
GROUP BY v.grupo_veiculo, c.grupo_combustivel
ORDER BY gasto_total_sem_ref DESC;
```

> **Ação**: Para cada linha retornada no 5.2, inserir na `ref_benchmark_km_l`:
> ```sql
> INSERT INTO torre.ref_benchmark_km_l (grupo_veiculo, grupo_combustivel, km_l_ref, alerta_85pct, alerta_70pct, tipo_calculo)
> VALUES ('Toco', 'Diesel', 5.5, 4.68, 3.85, 'PONDERADO_60_40');
> ```

---

## ✅ Bloco 6 — Cobertura ANP (postos sem referência direta)

```sql
-- 6.1 Cobertura geral ANP na última semana (% de transações com match direto)
WITH postos AS (
  SELECT 
    REGEXP_REPLACE(c.cnpj_posto, '[^0-9]', '', 'g') AS cnpj,
    c.grupo_combustivel,
    SUM(c.valor_liquido) AS valor,
    MAX(ca.preco_anp_ref) AS ref_anp,
    MAX(ca.nivel_referencia) AS nivel
  FROM torre.gold_truckpag_combustivel c
  LEFT JOIN torre.gold_mv_comparativo_anp ca 
    ON ca.cnpj_posto = REGEXP_REPLACE(c.cnpj_posto, '[^0-9]', '', 'g')
    AND ca.grupo_combustivel = c.grupo_combustivel
    AND ca.semana = DATE_TRUNC('week', c.data)::date
  WHERE c.data >= CURRENT_DATE - 14
    AND NOT c.transacao_estornada
    AND c.grupo_combustivel NOT IN ('Arla', 'Outros')
  GROUP BY cnpj, c.grupo_combustivel
)
SELECT
  COUNT(*) AS total_combinacoes,
  COUNT(CASE WHEN ref_anp IS NOT NULL THEN 1 END) AS com_ref_anp,
  COUNT(CASE WHEN ref_anp IS NULL THEN 1 END) AS sem_ref_anp,
  ROUND(100.0 * COUNT(CASE WHEN ref_anp IS NOT NULL THEN 1 END) / NULLIF(COUNT(*), 0), 1) AS pct_cobertura,
  ROUND(SUM(CASE WHEN ref_anp IS NULL THEN valor ELSE 0 END)::numeric, 2) AS valor_sem_ref
FROM postos;

-- 6.2 Distribuição por nível de referência ANP
WITH postos AS (
  SELECT 
    REGEXP_REPLACE(c.cnpj_posto, '[^0-9]', '', 'g') AS cnpj,
    c.grupo_combustivel,
    MAX(ca.nivel_referencia) AS nivel
  FROM torre.gold_truckpag_combustivel c
  LEFT JOIN torre.gold_mv_comparativo_anp ca 
    ON ca.cnpj_posto = REGEXP_REPLACE(c.cnpj_posto, '[^0-9]', '', 'g')
    AND ca.grupo_combustivel = c.grupo_combustivel
    AND ca.semana = DATE_TRUNC('week', c.data)::date
  WHERE c.data >= CURRENT_DATE - 14
    AND NOT c.transacao_estornada
    AND c.grupo_combustivel NOT IN ('Arla', 'Outros')
  GROUP BY cnpj, c.grupo_combustivel
)
SELECT 
  COALESCE(nivel, 'SEM_REF') AS nivel_referencia,
  COUNT(*) AS qtd,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM postos
GROUP BY nivel
ORDER BY qtd DESC;
```

> **Esperado**: `pct_cobertura` ≥ 80%. Nível `MUNICIPIO` é ideal, `VIZINHO` aceitável. O fallback no relatório (Estado/Nacional/Frota) garante que o gestor nunca veja "sem referência".

---

## ✅ Bloco 7 — Abastecimentos Suspeitos e Anomalias

```sql
-- 7.1 Hodômetros zerados na última semana
SELECT placa, data, hodometro, litragem, valor_liquido, garagem,
       COALESCE(NULLIF(nome_fantasia_posto, ''), razao_social_posto) AS posto
FROM torre.gold_truckpag_combustivel
WHERE data >= CURRENT_DATE - 7
  AND (hodometro <= 0 OR hodometro IS NULL)
  AND NOT transacao_estornada
  AND grupo_combustivel NOT IN ('Arla', 'Outros')
ORDER BY data DESC
LIMIT 30;

-- 7.2 Saltos de hodômetro > 15.000 km (último mês)
WITH ordenado AS (
  SELECT 
    placa, data_transacao, hodometro,
    LAG(hodometro) OVER (PARTITION BY placa ORDER BY data_transacao) AS hod_ant
  FROM torre.gold_truckpag_combustivel
  WHERE hodometro > 0 AND NOT transacao_estornada
    AND data >= CURRENT_DATE - 30
)
SELECT placa, data_transacao, hodometro, hod_ant, 
       (hodometro - hod_ant) AS salto_km
FROM ordenado
WHERE hod_ant > 0 AND hodometro > hod_ant AND (hodometro - hod_ant) > 15000
ORDER BY salto_km DESC
LIMIT 20;

-- 7.3 MV de Abastecimentos Suspeitos (top 20 por score de risco)
SELECT *
FROM torre.gold_mv_abastecimentos_suspeitos
ORDER BY score_risco DESC NULLS LAST
LIMIT 20;

-- 7.4 Transações estornadas na última semana
SELECT placa, data, litragem, valor_liquido, garagem,
       COALESCE(NULLIF(nome_fantasia_posto, ''), razao_social_posto) AS posto
FROM torre.gold_truckpag_combustivel
WHERE data >= CURRENT_DATE - 7
  AND transacao_estornada
ORDER BY data DESC;
```

---

## ✅ Bloco 8 — KPIs Consolidados (bater com o relatório)

```sql
-- 8.1 Resumo geral da última semana por filial (comparar com e-mail)
SELECT 
  CASE 
    WHEN c.garagem IN ('GRITSCH - CWB (BASE)', 'GRITSCH - CWB (ECT)') THEN 'Gritsch Curitiba (Base)'
    WHEN c.garagem = 'GRITSCH - MATRIZ' THEN 'Gritsch Curitiba (Matriz)'
    ELSE c.filial_nome
  END AS filial,
  COUNT(DISTINCT c.placa) AS veiculos,
  ROUND(SUM(c.litragem)::numeric, 2) AS litros,
  ROUND(SUM(c.valor_liquido)::numeric, 2) AS gasto_total,
  ROUND((SUM(c.valor_liquido) / NULLIF(SUM(c.litragem), 0))::numeric, 2) AS preco_medio_litro,
  COUNT(*) AS abastecimentos
FROM torre.gold_truckpag_combustivel c
WHERE c.data BETWEEN '2026-07-27' AND '2026-08-02'
  AND NOT c.transacao_estornada
  AND c.grupo_combustivel NOT IN ('Arla', 'Outros')
  AND c.garagem NOT IN ('GRITSCH - CWB (DIR)')
GROUP BY filial
ORDER BY gasto_total DESC;

-- 8.2 Total geral do grupo (deve bater com e-mail da Diretoria)
SELECT 
  COUNT(DISTINCT c.placa) AS veiculos,
  ROUND(SUM(c.litragem)::numeric, 2) AS litros,
  ROUND(SUM(c.valor_liquido)::numeric, 2) AS gasto_total,
  ROUND((SUM(c.valor_liquido) / NULLIF(SUM(c.litragem), 0))::numeric, 2) AS preco_medio
FROM torre.gold_truckpag_combustivel c
WHERE c.data BETWEEN '2026-07-27' AND '2026-08-02'
  AND NOT c.transacao_estornada
  AND c.grupo_combustivel NOT IN ('Arla', 'Outros')
  AND c.garagem NOT IN ('GRITSCH - CWB (DIR)');

-- 8.3 Fechamento semanal salvo no DW (deve bater com 8.1)
SELECT filial_nome, total_litros, total_gasto, preco_medio_litro, 
       qtd_veiculos_ativos, total_km_rodado, custo_por_km
FROM torre.gold_fato_fechamento_semanal_combustivel
WHERE semana_inicio = '2026-07-27'
ORDER BY total_gasto DESC;
```

> **Ação**: Compare 8.1 vs 8.3 — os valores devem ser idênticos. Se não, o nó `Salvar Fechamento no DW` teve algum problema.

---

## 📊 Mapa Completo do Schema `torre.*` (38 objetos)

| Camada | Objetos | Qtd |
|---|---|---|
| **Integration** (raw) | `integration_truckpag_transacoes`, `_nfe_vinculos`, `_titulos`, `_titulo_itens`, `_backfill_log` | 5 |
| **Raw** | `raw_anp_combustiveis`, `log_anp_arquivos_ingeridos` | 2 |
| **Ref** (seed/lookup) | `ref_benchmark_km_l`, `ref_municipios_brasil` | 2 |
| **Gold Dimensões** | `gold_dim_filial`, `gold_dim_veiculo`, `gold_dim_grupo_combustivel`, `gold_dim_modelo_veiculo`, `gold_dim_placa_excecao`, `gold_hist_veiculo` | 6 |
| **Gold Views** | `gold_truckpag_combustivel`, `gold_truckpag_pedagio`, `gold_v_projecao_mes_atual`, `gold_v_custo_operacional_mensal` | 4 |
| **Gold MVs** | `gold_mv_kpis_combustivel_mensal`, `_diario`, `_pedagio_mensal`, `_pedagio_diario`, `_semanal`, `_bimestral`, `_semestral`, `_eficiencia_placa_mensal`, `_benchmark_eficiencia_grupo`, `_abastecimentos_suspeitos`, `_ranking_veiculo`, `_comparativo_anp`, `_evolucao_mensal_combustivel`, `_suspeitos_mensal`, `_custo_veiculo_mensal`, `_ranking_postos`, `_atividade_frota_mensal`, `_preco_combustivel_mensal`, `_painel_filial_mensal`, `_painel_executivo_mensal`, `_desvio_comportamento_mensal` | 21 |
| **Gold Fato** | `gold_fato_fechamento_semanal_combustivel` | 1 |

---

## 📌 Checklist de Ações Pós-Validação

| # | Verificação | Ação |
|---|---|---|
| 1 | Tabela com 0 registros | Executar workflow GOLD correspondente no n8n |
| 2 | Freshness TruckPag > 2 dias | Verificar `TRUCKPAG LEGADO - 1` no n8n |
| 3 | ANP > 15 dias sem coleta | Verificar `ANP Combustíveis - Ingestão` no n8n |
| 4 | Dim Veículo desatualizada | Executar `GOLD - 4 - Sincronizacao dim_veiculo` |
| 5 | Placas sem dim_veiculo | Executar `GOLD - 4` |
| 6 | Garagem sem dim_filial | Atualizar `GOLD - 1` com nova garagem |
| 7 | Veículos SEM_REF | Inserir na `ref_benchmark_km_l` |
| 8 | MV vazia ou desatualizada | `REFRESH MATERIALIZED VIEW torre.<mv>;` |
| 9 | Cobertura ANP < 80% | Executar `GOLD - 16 - MV Comparativo ANP` |
| 10 | Hodômetros zerados | Reportar à operação / TruckPag |
| 11 | Totais 8.1 ≠ 8.3 | Re-executar workflow Torre de Controle |
