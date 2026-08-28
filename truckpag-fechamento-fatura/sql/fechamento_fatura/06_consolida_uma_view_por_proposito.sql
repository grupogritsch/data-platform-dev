-- Consolidacao pedida pelo usuario (28/08/2026): so 1 view de contabilidade,
-- so 1 view de resumo -- sem duplicar original + "_ajustada"/"_v2" lado a lado.
--
-- O que muda:
--   1. torre.vw_conciliacao_truckpag_contabilidade ganha uma coluna nova no
--      final (categoria_relatorio_ajustada) -- mantem categoria_relatorio
--      como estava (auditoria: "o que o sistema detectou sozinho"), a nova
--      coluna e' "o que vale de verdade" (considerando nota recolhida por
--      fora, registrada em torre.truckpag_notas_recolhidas_manual).
--      Coluna so ADICIONADA no final -- CREATE OR REPLACE VIEW aceita isso
--      sem quebrar quem ja consome as colunas antigas.
--   2. torre.vw_conciliacao_truckpag_resumo passa a usar
--      categoria_relatorio_ajustada no pivot (mesma estrutura de sempre:
--      fatura, ord, item, valor -- 9 linhas, LEVA 1/LEVA 2/TOTAL).
--   3. torre.vw_conciliacao_truckpag_rateio_garagem e _rateio_posto passam a
--      ler direto de vw_conciliacao_truckpag_contabilidade (nao mais de
--      _ajustada, que este script apaga).
--   4. Apaga vw_conciliacao_truckpag_contabilidade_ajustada e
--      vw_conciliacao_truckpag_resumo_v2 -- redundantes depois do passo 1-2.
--
-- ATENCAO -- rodar 1) primeiro e CONFERIR que nao aparece nada inesperado
-- antes de rodar o resto. Se aparecer alguma view/objeto que voce nao
-- reconhece na lista, PARE e me manda o resultado antes de continuar.

-- 1) Checagem de seguranca: quem mais depende de _ajustada e _resumo_v2
-- além do que eu já sei (rateio_garagem, rateio_posto, e os workflows n8n
-- que não estão rodando)?
SELECT DISTINCT dependent_ns.nspname AS schema, dependent_view.relname AS view_dependente,
       source_table.relname AS depende_de
FROM pg_depend
JOIN pg_rewrite ON pg_depend.objid = pg_rewrite.oid
JOIN pg_class AS dependent_view ON pg_rewrite.ev_class = dependent_view.oid
JOIN pg_class AS source_table ON pg_depend.refobjid = source_table.oid
JOIN pg_namespace dependent_ns ON dependent_ns.oid = dependent_view.relnamespace
WHERE source_table.relname IN (
    'vw_conciliacao_truckpag_contabilidade_ajustada',
    'vw_conciliacao_truckpag_resumo_v2'
)
AND dependent_view.relname NOT IN (
    'vw_conciliacao_truckpag_contabilidade_ajustada',
    'vw_conciliacao_truckpag_resumo_v2'
);

-- 2) Contabilidade: mesma view do 05_fix_view_contabilidade_left_join.sql,
-- so acrescentando categoria_relatorio_ajustada no final.
CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_contabilidade AS
SELECT tr.cnpj_cliente,
    COALESCE(tr.garagem, veic.filial_operacional::character varying, 'VERIFICAR BACKFILL'::character varying) AS garagem,
    tr.matricula_veiculo,
    tr.placa,
        CASE
            WHEN tr.nome_combustivel::text ~~* '%ARLA%'::text THEN 'ARLA'::text
            ELSE 'COMBUSTÍVEL'::text
        END AS natureza_bluefllet,
    ti.titulo_id AS fatura_atual,
    tr.data_transacao,
    ti.transacao_id AS id_transacao_atual,
    nfe.numero_nfe AS numero_nota_fiscal,
    tr.nome_fantasia_posto AS nome_posto,
    tr.cnpj_posto,
    nfe.cnpj_destinatario AS cnpj_filial_nfe,
        CASE
            WHEN tr.transacao_estornada IS NOT NULL AND (tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])) THEN COALESCE(tr.valor, ti.valor) * '-1'::integer::numeric
            ELSE COALESCE(tr.valor, ti.valor)
        END AS valor_item_liquido,
        CASE
            WHEN tr.transacao_estornada IS NOT NULL AND (tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])) THEN 'ESTORNO (CRÉDITO)'::text
            ELSE 'ABASTECIMENTO (DÉBITO)'::text
        END AS tipo_lancamento,
        CASE
            WHEN tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text]) THEN tr.transacao_estornada
            ELSE NULL::character varying
        END AS id_referencia_original,
        CASE
            WHEN tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text]) THEN ti_origem.titulo_id
            ELSE NULL::text
        END AS fatura_origem_referencia,
        CASE
            WHEN tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text]) THEN tr_origem.data_transacao
            ELSE NULL::timestamp with time zone
        END AS data_original_referencia,
        CASE
            WHEN tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text]) THEN tr_origem.valor
            ELSE NULL::numeric
        END AS valor_cobrado_na_epoca,
        CASE
            WHEN nfe.chave_nfe IS NOT NULL THEN 'NFE VINCULADA'::text
            WHEN upper(tr.servico::text) = 'PEDAGIO'::text THEN 'ISENTO (PEDAGIO)'::text
            WHEN tr.transacao_estornada IS NOT NULL AND (tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])) THEN 'CRÉDITO / ESTORNO'::text
            WHEN (tr.transacao::text IN ( SELECT t2.transacao_estornada
               FROM torre.integration_truckpag_transacoes t2
              WHERE t2.transacao_estornada IS NOT NULL AND (t2.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])))) THEN 'ISENTO (ABASTECIMENTO CANCELADO)'::text
            ELSE 'PENDENTE DE NOTA'::text
        END AS status_fiscal,
    nfe.operacao AS nfe_tipo_operacao,
    nfe.data_emissao AS nfe_data_emissao,
    nfe.valor_total AS nfe_valor_nota,
    nfe.chave_nfe,
        CASE
            WHEN nfe.chave_nfe IS NOT NULL THEN '1. Com nota fiscal recolhida'::text
            WHEN upper(tr.servico::text) = 'PEDAGIO'::text THEN '5. Pedágio (isento de nota)'::text
            WHEN tr.transacao_estornada IS NOT NULL AND (tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])) THEN '4. Crédito de estorno (desconto)'::text
            WHEN (tr.transacao::text IN ( SELECT t2.transacao_estornada
               FROM torre.integration_truckpag_transacoes t2
              WHERE t2.transacao_estornada IS NOT NULL AND (t2.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])))) THEN '2. Abastecimento cancelado (sem nota)'::text
            ELSE '3. Sem nota fiscal'::text
        END AS categoria_relatorio,
    tit.data_geracao AS titulo_data_geracao,
    tit.data_vencimento AS titulo_data_vencimento,
    tit.valor_total AS titulo_valor_total,
    cred.fatura_credito_retorno,
    cred.data_credito_retorno,
    cred.transacao_origem IS NOT NULL AS tem_credito_gerado,
    ''''::text || nfe.chave_nfe::text AS chave_nfe_texto,
    -- NOVO: categoria final, considerando nota recolhida "por fora" (registrada
    -- manualmente). E' o que vale pra decidir quanto realmente falta pagar.
        CASE
            WHEN (CASE
                WHEN nfe.chave_nfe IS NOT NULL THEN '1. Com nota fiscal recolhida'::text
                WHEN upper(tr.servico::text) = 'PEDAGIO'::text THEN '5. Pedágio (isento de nota)'::text
                WHEN tr.transacao_estornada IS NOT NULL AND (tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])) THEN '4. Crédito de estorno (desconto)'::text
                WHEN (tr.transacao::text IN ( SELECT t2.transacao_estornada
                   FROM torre.integration_truckpag_transacoes t2
                  WHERE t2.transacao_estornada IS NOT NULL AND (t2.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])))) THEN '2. Abastecimento cancelado (sem nota)'::text
                ELSE '3. Sem nota fiscal'::text
            END) = '3. Sem nota fiscal'
                 AND EXISTS (
                     SELECT 1 FROM torre.truckpag_notas_recolhidas_manual m
                     WHERE m.id_transacao = ti.transacao_id::text
                 )
            THEN '1b. Sem nota (recolhida manualmente)'::text
            ELSE (CASE
                WHEN nfe.chave_nfe IS NOT NULL THEN '1. Com nota fiscal recolhida'::text
                WHEN upper(tr.servico::text) = 'PEDAGIO'::text THEN '5. Pedágio (isento de nota)'::text
                WHEN tr.transacao_estornada IS NOT NULL AND (tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])) THEN '4. Crédito de estorno (desconto)'::text
                WHEN (tr.transacao::text IN ( SELECT t2.transacao_estornada
                   FROM torre.integration_truckpag_transacoes t2
                  WHERE t2.transacao_estornada IS NOT NULL AND (t2.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])))) THEN '2. Abastecimento cancelado (sem nota)'::text
                ELSE '3. Sem nota fiscal'::text
            END)
        END AS categoria_relatorio_ajustada
   FROM torre.integration_truckpag_titulo_itens ti
     LEFT JOIN torre.integration_truckpag_transacoes tr ON tr.transacao::text = ti.transacao_id::text
     LEFT JOIN torre.integration_truckpag_transacoes tr_origem ON tr_origem.transacao::text = tr.transacao_estornada::text AND (tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text]))
     LEFT JOIN ( SELECT integration_truckpag_titulo_itens.transacao_id,
            max(integration_truckpag_titulo_itens.titulo_id::bigint)::text AS titulo_id
           FROM torre.integration_truckpag_titulo_itens
          WHERE integration_truckpag_titulo_itens.titulo_id::text <> ALL (ARRAY['16'::text, '0'::text, ''::text])
          GROUP BY integration_truckpag_titulo_itens.transacao_id) ti_origem ON ti_origem.transacao_id::text = tr_origem.transacao::text
     LEFT JOIN torre.integration_truckpag_nfe_vinculos nfe ON nfe.id_transacao::text = tr.transacao::text
     LEFT JOIN ( SELECT DISTINCT ON (integration_truckpag_titulos.titulo_id) integration_truckpag_titulos.titulo_id,
            integration_truckpag_titulos.data_geracao,
            integration_truckpag_titulos.data_vencimento,
            integration_truckpag_titulos.valor_total
           FROM torre.integration_truckpag_titulos
          ORDER BY integration_truckpag_titulos.titulo_id, integration_truckpag_titulos.updated_at DESC NULLS LAST) tit ON tit.titulo_id::text = ti.titulo_id::text
     LEFT JOIN ( SELECT c.transacao_estornada AS transacao_origem,
            max(cti.titulo_id::bigint)::text AS fatura_credito_retorno,
            max(c.data_transacao) AS data_credito_retorno
           FROM torre.integration_truckpag_transacoes c
             LEFT JOIN torre.integration_truckpag_titulo_itens cti ON cti.transacao_id::text = c.transacao::text AND (cti.titulo_id::text <> ALL (ARRAY['16'::text, '0'::text, ''::text]))
          WHERE c.transacao_estornada IS NOT NULL AND (c.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text]))
          GROUP BY c.transacao_estornada) cred ON cred.transacao_origem::text = tr.transacao::text
     LEFT JOIN torre.gold_dim_veiculo veic ON veic.placa = tr.placa::text;

-- 3) Resumo: mesma estrutura de sempre (fatura, ord, item, valor), agora
-- puxando de categoria_relatorio_ajustada.
CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_resumo AS
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
    FROM torre.vw_conciliacao_truckpag_contabilidade
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

-- 4) Rateio: repontar pra vw_conciliacao_truckpag_contabilidade (ja tem a
-- coluna ajustada agora), nao mais pra _ajustada.
CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_rateio_garagem AS
SELECT
    fatura_atual AS fatura,
    garagem,
    sum(CASE WHEN categoria_relatorio_ajustada IN ('1. Com nota fiscal recolhida', '1b. Sem nota (recolhida manualmente)') THEN valor_item_liquido ELSE 0 END) AS notas_recolhidas,
    sum(CASE WHEN categoria_relatorio_ajustada = '2. Abastecimento cancelado (sem nota)' THEN valor_item_liquido ELSE 0 END) AS cancelado,
    sum(CASE WHEN categoria_relatorio_ajustada = '3. Sem nota fiscal' THEN valor_item_liquido ELSE 0 END) AS sem_nota,
    sum(CASE WHEN categoria_relatorio_ajustada = '4. Crédito de estorno (desconto)' THEN valor_item_liquido ELSE 0 END) AS creditos_estorno,
    sum(valor_item_liquido) AS total_garagem
FROM torre.vw_conciliacao_truckpag_contabilidade
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
FROM torre.vw_conciliacao_truckpag_contabilidade
GROUP BY fatura_atual, nome_posto, cnpj_posto;

-- 5) Aposenta as views redundantes. So roda isto depois de conferir o
-- resultado do passo 1 (nada inesperado dependendo delas).
-- Ordem importa: _resumo_v2 depende de _ajustada, entao apaga _resumo_v2
-- primeiro (senao Postgres recusa apagar _ajustada com dependente vivo).
DROP VIEW IF EXISTS torre.vw_conciliacao_truckpag_resumo_v2;
DROP VIEW IF EXISTS torre.vw_conciliacao_truckpag_contabilidade_ajustada;

-- 6) Validacao final -- os 3 numeros tem que bater com R$435.406,01
-- (fatura 263144).
SELECT 'contabilidade' AS origem, sum(valor_item_liquido) AS total
FROM torre.vw_conciliacao_truckpag_contabilidade WHERE fatura_atual = '263144'
UNION ALL
SELECT 'resumo (linha TOTAL)', valor
FROM torre.vw_conciliacao_truckpag_resumo WHERE fatura = '263144' AND item = 'TOTAL DA FATURA (conferência)'
UNION ALL
SELECT 'rateio_garagem (soma)', sum(total_garagem)
FROM torre.vw_conciliacao_truckpag_rateio_garagem WHERE fatura = '263144'
UNION ALL
SELECT 'rateio_posto (soma)', sum(total_posto)
FROM torre.vw_conciliacao_truckpag_rateio_posto WHERE fatura = '263144';
