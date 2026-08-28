-- Fallback pra silver.truckpag_analitico_transacao (achado 28/08/2026,
-- investigando a fatura 263144 mais a fundo).
--
-- Descoberta: as transacoes que sumiam de torre.integration_truckpag_transacoes
-- (fix 05/06) tem status 'PENDENTE' do lado da TruckPag -- a API legada
-- (/Transacoes) parece nao devolver transacao pendente, so finalizada. MAS o
-- dado NAO esta perdido: a integracao da API NOVA (rota "analitico de
-- transacoes", ja com bronze+silver montados) TEM essas mesmas transacoes,
-- com status visivel. Confirmado: as 5 da fatura 263144 estao la, com os
-- mesmos valores exatos. No total sao 28 transacoes PENDENTE na empresa
-- (R$10.194,21) -- pequeno, mas real, e provavelmente recorrente enquanto
-- a TruckPag nao finalizar essas transacoes do lado dela.
--
-- Fix: LEFT JOIN silver.truckpag_analitico_transacao (sat) como fallback,
-- SO quando a tabela legada (tr) nao tiver match -- legada continua sendo
-- a fonte de verdade quando existe, sat so preenche o buraco.
--
-- Limitacao conhecida (aceitavel): a deteccao de estorno (tr.transacao_estornada)
-- nao se estende pras linhas resolvidas via sat -- pra essas linhas, o
-- calculo trata como "nao e estorno", o que e' correto pros casos conhecidos
-- (todas COMPRA/PENDENTE), mas se um dia aparecer uma pendente que na
-- verdade e ESTORNADA, ela vai ser categorizada como abastecimento normal,
-- nao credito. Se isso importar, avaliar sat.transacao_status = 'ESTORNADA'
-- como sinal adicional depois.

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
    -- NOVO: status na TruckPag pra quem cair no fallback (NULL quando a
    -- linha veio da tabela legada -- essa ja e' sempre finalizada).
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
     LEFT JOIN torre.gold_dim_veiculo veic ON veic.placa = COALESCE(tr.placa, sat.veiculo_placa)::text;

-- Validacao: as 5 transacoes da fatura 263144 devem aparecer com placa/posto
-- preenchidos agora (nao mais NULL).
SELECT id_transacao_atual, placa, nome_posto, valor_item_liquido, categoria_relatorio_ajustada, status_truckpag_pendente
FROM torre.vw_conciliacao_truckpag_contabilidade
WHERE fatura_atual = '263144'
  AND id_transacao_atual IN ('22838161','22829582','22830387','22820741','22813771')
ORDER BY id_transacao_atual;
