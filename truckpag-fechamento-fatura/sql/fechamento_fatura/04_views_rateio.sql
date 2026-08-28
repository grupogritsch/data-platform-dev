-- Substituem as abas "Rateio por Garagem" e "Rateio por Posto" (hoje fórmulas Excel
-- SUMIFS em cima da aba Contabilidade -- ver docs/planilha-fechamento.md). Usam a
-- categoria ajustada (02_view_contabilidade_ajustada.sql) pra já refletir a Leva 2 real.

CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_rateio_garagem AS
SELECT
    fatura_atual AS fatura,
    garagem,
    sum(CASE WHEN categoria_relatorio_ajustada IN ('1. Com nota fiscal recolhida', '1b. Sem nota (recolhida manualmente)') THEN valor_item_liquido ELSE 0 END) AS notas_recolhidas,
    sum(CASE WHEN categoria_relatorio_ajustada = '2. Abastecimento cancelado (sem nota)' THEN valor_item_liquido ELSE 0 END) AS cancelado,
    sum(CASE WHEN categoria_relatorio_ajustada = '3. Sem nota fiscal' THEN valor_item_liquido ELSE 0 END) AS sem_nota,
    sum(CASE WHEN categoria_relatorio_ajustada = '4. Crédito de estorno (desconto)' THEN valor_item_liquido ELSE 0 END) AS creditos_estorno,
    sum(valor_item_liquido) AS total_garagem
FROM torre.vw_conciliacao_truckpag_contabilidade_ajustada
GROUP BY fatura_atual, garagem;

CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_rateio_posto AS
SELECT
    fatura_atual AS fatura,
    nome_posto,
    cnpj_posto,
    sum(CASE WHEN categoria_relatorio_ajustada IN ('1. Com nota fiscal recolhida', '1b. Sem nota (recolhida manualmente)') THEN valor_item_liquido ELSE 0 END) AS notas_recolhidas,
    sum(CASE WHEN categoria_relatorio_ajustada = '2. Abastecimento cancelado (sem nota)' THEN valor_item_liquido ELSE 0 END) AS cancelado,
    sum(CASE WHEN categoria_relatorio_ajustada = '3. Sem nota fiscal' THEN valor_item_liquido ELSE 0 END) AS sem_nota,
    sum(CASE WHEN categoria_relatorio_ajustada = '4. Crédito de estorno (desconto)' THEN valor_item_liquido ELSE 0 END) AS creditos_estorno,
    sum(valor_item_liquido) AS total_posto,
    sum(valor_item_liquido) / NULLIF(sum(sum(valor_item_liquido)) OVER (PARTITION BY fatura_atual), 0) AS percentual_participacao
FROM torre.vw_conciliacao_truckpag_contabilidade_ajustada
GROUP BY fatura_atual, nome_posto, cnpj_posto;
