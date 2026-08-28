-- Mesma estrutura/pivot da vw_conciliacao_truckpag_resumo original, mas usando a
-- categoria ajustada -- então "Notas fiscais recolhidas" já inclui o que foi
-- resolvido manualmente, e "Sem nota fiscal" só mostra o que realmente ainda falta.

CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_resumo_v2 AS
WITH base AS (
    SELECT
        fatura_atual,
        sum(CASE
                WHEN categoria_relatorio_ajustada IN ('1. Com nota fiscal recolhida', '1b. Sem nota (recolhida manualmente)')
                THEN valor_item_liquido ELSE 0
            END) AS notas_recolhidas,
        sum(CASE WHEN categoria_relatorio_ajustada = '4. Crédito de estorno (desconto)' THEN valor_item_liquido ELSE 0 END) AS creditos_estorno,
        sum(CASE WHEN categoria_relatorio_ajustada = '2. Abastecimento cancelado (sem nota)' THEN valor_item_liquido ELSE 0 END) AS cancelado,
        sum(CASE WHEN categoria_relatorio_ajustada = '3. Sem nota fiscal' THEN valor_item_liquido ELSE 0 END) AS sem_nota,
        sum(valor_item_liquido) AS total_fatura
    FROM torre.vw_conciliacao_truckpag_contabilidade_ajustada
    GROUP BY fatura_atual
)
SELECT
    b.fatura_atual AS fatura,
    l.ord,
    l.item,
    l.valor
FROM base b
CROSS JOIN LATERAL (VALUES
    (1, 'LEVA 1', NULL::numeric),
    (2, '  (+) Notas fiscais recolhidas', b.notas_recolhidas),
    (3, '  (-) Créditos de estorno', b.creditos_estorno),
    (4, '  (=) Pagamento no vencimento', b.notas_recolhidas + b.creditos_estorno),
    (5, 'LEVA 2', NULL::numeric),
    (6, '  (+) Abastecimento cancelado', b.cancelado),
    (7, '  (+) Sem nota fiscal (ainda pendente)', b.sem_nota),
    (8, '  (=) Saldo a pagar', b.cancelado + b.sem_nota),
    (9, 'TOTAL DA FATURA (conferência)', b.total_fatura)
) l(ord, item, valor);
