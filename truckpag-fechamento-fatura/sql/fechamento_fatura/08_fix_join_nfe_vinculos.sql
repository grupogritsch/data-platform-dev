-- Fix no JOIN da NFe (achado 28/08/2026, logo depois do fallback silver
-- em 07_fallback_silver_analitico.sql).
--
-- Usuario conferiu direto: as 5 transacoes "sumidas" TEM nota fiscal
-- vinculada em torre.integration_truckpag_nfe_vinculos (por id_transacao).
-- Mas a view continuava mostrando elas como "3. Sem nota fiscal" -- mesma
-- classe de bug do id_transacao_atual (05/06): o JOIN da nfe usava
-- `nfe.id_transacao = tr.transacao`, e tr e' NULL pra essas 5 (vem so de
-- integration_truckpag_transacoes, que nao tem essas linhas -- ver
-- 05_fix_view_contabilidade_left_join.sql). Como tr.transacao e' NULL, o
-- join nunca achava a nfe, mesmo ela existindo de verdade.
--
-- Fix: trocar a chave do JOIN de tr.transacao pra ti.transacao_id -- que
-- e' o mesmo valor quando tr existe (e' a propria condicao do JOIN entre
-- ti e tr), mas nunca fica NULL. Mesmo raciocinio do fix anterior.
--
-- Efeito: essas 5 transacoes (e qualquer outra na mesma situacao) devem
-- passar de "3. Sem nota fiscal" pra "1. Com nota fiscal recolhida" --
-- BOA noticia: elas ja tem nota, so a view nao estava enxergando.

CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_contabilidade AS
SELECT COALESCE(tr.cnpj_cliente, sat.cliente_cnpj)::character varying(20) AS cnpj_cliente,
    COALESCE(tr.garagem, veic.filial_operacional::character varying, 'VERIFICAR BACKFILL'::character varying) AS garagem,
    tr.matricula_veiculo,
    COALESCE(tr.placa, sat.veiculo_placa)::character varying(10) AS placa,
        CASE
            WHEN COALESCE(tr.nome_combustivel, sat.combustivel_nome) ~~* '%ARLA%'::text THEN 'ARLA'::text
            ELSE 'COMBUSTÍVEL'::text
        END AS natureza_bluefllet,
    ti.titulo_id AS fatura_atual,
    COALESCE(tr.data_transacao, sat.transacao_data::timestamptz) AS data_transacao,
    ti.transacao_id AS id_transacao_atual,
    nfe.numero_nfe AS numero_nota_fiscal,
    COALESCE(tr.nome_fantasia_posto, sat.estabelecimento_nome)::character varying(255) AS nome_posto,
    COALESCE(tr.cnpj_posto, sat.estabelecimento_cnpj)::character varying(20) AS cnpj_posto,
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
            WHEN upper(COALESCE(tr.servico, sat.servico_nome)::text) = 'PEDAGIO'::text THEN 'ISENTO (PEDAGIO)'::text
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
            WHEN upper(COALESCE(tr.servico, sat.servico_nome)::text) = 'PEDAGIO'::text THEN '5. Pedágio (isento de nota)'::text
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
        CASE
            WHEN (CASE
                WHEN nfe.chave_nfe IS NOT NULL THEN '1. Com nota fiscal recolhida'::text
                WHEN upper(COALESCE(tr.servico, sat.servico_nome)::text) = 'PEDAGIO'::text THEN '5. Pedágio (isento de nota)'::text
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
                WHEN upper(COALESCE(tr.servico, sat.servico_nome)::text) = 'PEDAGIO'::text THEN '5. Pedágio (isento de nota)'::text
                WHEN tr.transacao_estornada IS NOT NULL AND (tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])) THEN '4. Crédito de estorno (desconto)'::text
                WHEN (tr.transacao::text IN ( SELECT t2.transacao_estornada
                   FROM torre.integration_truckpag_transacoes t2
                  WHERE t2.transacao_estornada IS NOT NULL AND (t2.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text])))) THEN '2. Abastecimento cancelado (sem nota)'::text
                ELSE '3. Sem nota fiscal'::text
            END)
        END AS categoria_relatorio_ajustada,
    sat.transacao_status AS status_truckpag_pendente
   FROM torre.integration_truckpag_titulo_itens ti
     LEFT JOIN torre.integration_truckpag_transacoes tr ON tr.transacao::text = ti.transacao_id::text
     LEFT JOIN silver.truckpag_analitico_transacao sat ON sat.transacao_id::text = ti.transacao_id::text AND tr.transacao IS NULL
     LEFT JOIN torre.integration_truckpag_transacoes tr_origem ON tr_origem.transacao::text = tr.transacao_estornada::text AND (tr.transacao_estornada::text <> ALL (ARRAY['0'::text, ''::text]))
     LEFT JOIN ( SELECT integration_truckpag_titulo_itens.transacao_id,
            max(integration_truckpag_titulo_itens.titulo_id::bigint)::text AS titulo_id
           FROM torre.integration_truckpag_titulo_itens
          WHERE integration_truckpag_titulo_itens.titulo_id::text <> ALL (ARRAY['16'::text, '0'::text, ''::text])
          GROUP BY integration_truckpag_titulo_itens.transacao_id) ti_origem ON ti_origem.transacao_id::text = tr_origem.transacao::text
     LEFT JOIN torre.integration_truckpag_nfe_vinculos nfe ON nfe.id_transacao::text = ti.transacao_id::text
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
     LEFT JOIN torre.gold_dim_veiculo veic ON veic.placa = COALESCE(tr.placa, sat.veiculo_placa)::text;

-- Validacao: as 5 devem virar "1. Com nota fiscal recolhida" agora.
SELECT id_transacao_atual, chave_nfe, numero_nota_fiscal, categoria_relatorio_ajustada
FROM torre.vw_conciliacao_truckpag_contabilidade
WHERE fatura_atual = '263144'
  AND id_transacao_atual IN ('22838161','22829582','22830387','22820741','22813771')
ORDER BY id_transacao_atual;

-- Confere se o resumo da fatura 263144 fechou igual ao esperado (Leva 1
-- deve subir, Sem nota deve cair pra so' o que sobrar de verdade pendente).
SELECT * FROM torre.vw_conciliacao_truckpag_resumo WHERE fatura = '263144' ORDER BY ord;
