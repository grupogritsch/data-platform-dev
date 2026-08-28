-- Registro manual de notas fiscais recebidas "por fora" (fora da integração automática
-- torre.integration_truckpag_nfe_vinculos). Usado para ajustar a Leva 2 do fechamento
-- de fatura de combustível sem depender de reformatar a planilha toda semana.
--
-- Preenchimento: uma linha por nota recebida fora do fluxo automático, feita por quem
-- estiver fechando a fatura, referenciando o id da transação que a nota resolve.

CREATE TABLE IF NOT EXISTS torre.truckpag_notas_recolhidas_manual (
    id              SERIAL PRIMARY KEY,
    id_transacao    VARCHAR NOT NULL,   -- = id_transacao_atual / tr.transacao na vw_conciliacao_truckpag_contabilidade
    valor           NUMERIC(14, 2),     -- opcional, só pra conferência (o valor real vem da transação)
    data_recolhida  DATE NOT NULL DEFAULT CURRENT_DATE,
    observacao      TEXT,
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
    criado_por      VARCHAR
);

COMMENT ON TABLE torre.truckpag_notas_recolhidas_manual IS
    'Registro manual de notas fiscais não tributáveis recebidas fora do fluxo automático de vínculo NFe. Usado para ajustar a Leva 2 do fechamento de fatura de combustível Truckpag.';

CREATE INDEX IF NOT EXISTS idx_truckpag_notas_recolhidas_manual_transacao
    ON torre.truckpag_notas_recolhidas_manual (id_transacao);
