-- View aditiva (não substitui a vw_conciliacao_truckpag_contabilidade original, que pode
-- ter outros consumidores). Acrescenta uma categoria ajustada que reconhece as notas
-- recolhidas manualmente (ver 01_tabela_notas_recolhidas_manual.sql).

CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_contabilidade_ajustada AS
SELECT
    c.*,
    CASE
        WHEN c.categoria_relatorio = '3. Sem nota fiscal'
             AND EXISTS (
                 SELECT 1
                 FROM torre.truckpag_notas_recolhidas_manual m
                 WHERE m.id_transacao = c.id_transacao_atual
             )
        THEN '1b. Sem nota (recolhida manualmente)'
        ELSE c.categoria_relatorio
    END AS categoria_relatorio_ajustada
FROM torre.vw_conciliacao_truckpag_contabilidade c;
