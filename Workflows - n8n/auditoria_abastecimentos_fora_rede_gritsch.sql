-- ============================================================
-- AUDITORIA DE ABASTECIMENTOS FORA DA REDE TRUCKPAG — GRITSCH
-- Data de Validação: 11/08/2026
-- Regra de Negócio:
--   1. Regra de Empresa: Unidade/CentroCusto NOT LIKE '%REFERÊNCIA%' AND NOT LIKE '%LOCAÇÃO%'
--   2. Regra de Fatura TruckPag: NumeroDocumento LIKE '%FAT%' ou PagarReceberDe LIKE '%TRUCKPAG%'
--   3. O que NÃO tiver 'FAT' nem 'TRUCKPAG' = Abastecimento/Arla Por Fora (Manuais/Notas)
-- ============================================================

-- ------------------------------------------------------------
-- 1. QUERY RESUMO MENSAL (CONSOLIDADOR EXCLUSIVO GRITSCH)
-- ------------------------------------------------------------
SELECT 
    FORMAT(DataCompetencia, 'yyyy-MM')                                   AS ano_mes,
    Natureza,
    ROUND(SUM(CASE 
      WHEN NumeroDocumento LIKE '%FAT%' 
        OR UPPER(PagarReceberDe) LIKE '%TRUCKPAG%' 
      THEN ValorNatureza ELSE 0 
    END), 2)                                                             AS gasto_truckpag_faturas,
    ROUND(SUM(CASE 
      WHEN (NumeroDocumento NOT LIKE '%FAT%' OR NumeroDocumento IS NULL)
       AND (UPPER(PagarReceberDe) NOT LIKE '%TRUCKPAG%' OR PagarReceberDe IS NULL)
      THEN ValorNatureza ELSE 0 
    END), 2)                                                             AS gasto_por_fora_gritsch,
    ROUND(SUM(ValorNatureza), 2)                                         AS gasto_total_gritsch,
    ROUND(
      SUM(CASE WHEN (NumeroDocumento NOT LIKE '%FAT%' OR NumeroDocumento IS NULL) AND (UPPER(PagarReceberDe) NOT LIKE '%TRUCKPAG%' OR PagarReceberDe IS NULL) THEN ValorNatureza ELSE 0 END) / 
      NULLIF(SUM(ValorNatureza), 0) * 100
    , 2)                                                                 AS pct_por_fora
FROM dbo.LancamentosComNaturezas
WHERE (
    UPPER(Natureza) LIKE '%COMBUSTÍVEL%' 
 OR UPPER(Natureza) LIKE '%COMBUSTIVEL%' 
 OR UPPER(Natureza) LIKE '%ARLA%'
)
AND DataCompetencia >= '2026-07-01'
AND UPPER(COALESCE(Unidade, CentroCusto, '')) NOT LIKE '%REFERÊNCIA%'
AND UPPER(COALESCE(Unidade, CentroCusto, '')) NOT LIKE '%REFERENCIA%'
AND UPPER(COALESCE(Unidade, CentroCusto, '')) NOT LIKE '%LOCAÇÃO%'
AND UPPER(COALESCE(Unidade, CentroCusto, '')) NOT LIKE '%LOCACAO%'
GROUP BY FORMAT(DataCompetencia, 'yyyy-MM'), Natureza
ORDER BY ano_mes DESC, Natureza;


-- ------------------------------------------------------------
-- 2. QUERY ANALÍTICA DETALHADA (LINHA POR LINHA DAS NOTAS POR FORA)
-- ------------------------------------------------------------
SELECT 
    FORMAT(DataCompetencia, 'yyyy-MM-dd')          AS data_competencia,
    COALESCE(NULLIF(Unidade, ''), CentroCusto)     AS unidade_gritsch,
    PagarReceberDe                                  AS fornecedor_pago,
    NumeroDocumento                                 AS numero_documento,
    Natureza                                        AS natureza_despesa,
    ValorNatureza                                   AS valor_pago,
    Descricao                                       AS descricao_lancamento
FROM dbo.LancamentosComNaturezas
WHERE (
    UPPER(Natureza) LIKE '%COMBUSTÍVEL%' 
 OR UPPER(Natureza) LIKE '%COMBUSTIVEL%' 
 OR UPPER(Natureza) LIKE '%ARLA%'
)
AND DataCompetencia >= '2026-07-01'
AND (NumeroDocumento NOT LIKE '%FAT%' OR NumeroDocumento IS NULL)
AND (UPPER(PagarReceberDe) NOT LIKE '%TRUCKPAG%' OR PagarReceberDe IS NULL)
AND UPPER(COALESCE(Unidade, CentroCusto, '')) NOT LIKE '%REFERÊNCIA%'
AND UPPER(COALESCE(Unidade, CentroCusto, '')) NOT LIKE '%REFERENCIA%'
AND UPPER(COALESCE(Unidade, CentroCusto, '')) NOT LIKE '%LOCAÇÃO%'
AND UPPER(COALESCE(Unidade, CentroCusto, '')) NOT LIKE '%LOCACAO%'
ORDER BY DataCompetencia DESC, ValorNatureza DESC;
