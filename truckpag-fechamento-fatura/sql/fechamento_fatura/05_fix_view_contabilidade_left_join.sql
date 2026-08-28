-- Fix na view BASE torre.vw_conciliacao_truckpag_contabilidade (achado 28/08/2026,
-- investigando gap de R$1.461,90 na fatura 263144 -- usuario recebeu R$435.406,01,
-- banco mostrava R$433.944,11).
--
-- Essa view nunca tinha sido versionada em lugar nenhum do repo (so existia ao
-- vivo no banco) -- essa e' a primeira vez que o SQL dela fica registrado aqui.
-- Peguei a definicao real via `pg_get_viewdef('torre.vw_conciliacao_truckpag_contabilidade'::regclass, true)`
-- no DBeaver e apliquei so as 3 mudancas abaixo, todo o resto e' identico ao original.
--
-- CAUSA RAIZ: `ti JOIN tr ON tr.transacao = ti.transacao_id` era INNER JOIN.
-- Toda vez que um item de cobranca (integration_truckpag_titulo_itens) nao tem
-- transacao correspondente em integration_truckpag_transacoes (a ingestao de
-- Transacoes roda so incremental/diario, enquanto Titulos roda com backfill --
-- se o cursor incremental de Transacoes for resetado sem backfill do periodo,
-- transacoes antigas somem de la, mesmo que o item de cobranca continue existindo),
-- a linha inteira desaparecia da view -- nao caia nem em "3. Sem nota fiscal",
-- sumia sem deixar rastro nenhum. Exemplo real, fatura 263144: 5 transacoes
-- (22838161, 22829582, 22830387, 22820741, 22813771) somando R$1.461,90.
--
-- FIX (3 mudancas cirurgicas, resto da view intocado):
--   1. `JOIN` -> `LEFT JOIN` na tabela tr (recupera a linha)
--   2. `valor_item_liquido`: `tr.valor` -> `COALESCE(tr.valor, ti.valor)` --
--      sem isso a linha aparece mas com o valor NULL (nao resolve o gap de verdade)
--   3. `id_transacao_atual`: `tr.transacao` -> `ti.transacao_id` -- ti.transacao_id
--      e' o mesmo valor de tr.transacao quando ha match (e' a propria condicao do
--      JOIN), mas nunca fica NULL -- preserva a chave pra linkar com
--      torre.truckpag_notas_recolhidas_manual mesmo nessas linhas sem match.
--
-- Efeito colateral esperado (correto, nao e' bug novo): linhas recuperadas caem
-- em categoria_relatorio = '3. Sem nota fiscal' por padrao (nfe/tr_origem/cred
-- continuam None pra elas, ja que dependem de tr.transacao pra fazer join --
-- deixado assim de proposito, e' o comportamento mais conservador ate alguem
-- investigar por que a transacao sumiu de integration_truckpag_transacoes).
--
-- Validacao apos aplicar: total da view pra fatura 263144 deve bater com
-- R$435.406,01 (torre.integration_truckpag_titulos.valor_total).

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
    ti.transacao_id AS id_transacao_atual,  -- FIX 3: era tr.transacao (fica NULL sem match)
    nfe.numero_nfe AS numero_nota_fiscal,
    tr.nome_fantasia_posto AS nome_posto,
    tr.cnpj_posto,
    nfe.cnpj_destinatario AS cnpj_filial_nfe,
        CASE
            WHEN tr.transacao_estornada IS NOT NULL AND (tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])) THEN COALESCE(tr.valor, ti.valor) * '-1'::integer::numeric
            ELSE COALESCE(tr.valor, ti.valor)  -- FIX 2: era so tr.valor (fica NULL sem match)
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
    ''''::text || nfe.chave_nfe::text AS chave_nfe_texto
   FROM torre.integration_truckpag_titulo_itens ti
     LEFT JOIN torre.integration_truckpag_transacoes tr ON tr.transacao::text = ti.transacao_id::text  -- FIX 1: era JOIN (inner)
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
