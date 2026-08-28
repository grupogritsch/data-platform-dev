-- vw_conciliacao_truckpag_relatorio nao expunha categoria_relatorio_ajustada
-- (achado 28/08/2026 validando a fatura 267384 -- ela e' mais antiga que a
-- coluna ajustada, criada so em contabilidade). Sem isso, a aba Relatorio
-- mostraria transacao ja resolvida via nota manual ainda como "3. Sem nota
-- fiscal" -- coluna adicionada no final, nao quebra quem ja consome as
-- colunas antigas.

CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_relatorio AS
 SELECT fatura_atual AS fatura,
    categoria_relatorio,
    placa,
    garagem,
    data_transacao,
    id_transacao_atual,
    nome_posto,
    cnpj_posto,
    cnpj_filial_nfe,
    natureza_bluefllet,
    valor_item_liquido,
    status_fiscal,
    numero_nota_fiscal,
    nfe_data_emissao,
    nfe_valor_nota,
    chave_nfe_texto AS chave_nfe,
    id_referencia_original,
    fatura_origem_referencia,
    fatura_credito_retorno,
    data_credito_retorno,
    titulo_data_vencimento,
    categoria_relatorio_ajustada
   FROM torre.vw_conciliacao_truckpag_contabilidade;

-- Validacao
SELECT id_transacao_atual, categoria_relatorio, categoria_relatorio_ajustada
FROM torre.vw_conciliacao_truckpag_relatorio
WHERE id_transacao_atual IN ('24358227','24408074','24293121','24153531','24070382')
ORDER BY id_transacao_atual;
