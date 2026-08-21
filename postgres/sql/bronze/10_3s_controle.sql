-- ============================================================================
-- BRONZE / 3S — PLANO DE CONTROLE DA INGESTAO
--
-- REESCRITO em 04/08/2026 para a API REST nova (DataExportAPI), substituindo
-- o webservice SOAP (data_export.asmx). Motivo da troca: a versao SOAP
-- acumulou problemas reais em producao (bloqueio de $env, credencial nativa
-- do n8n quebrando com HTTP 400, bug de gzip nao descompactado que fazia todo
-- carregamento trazer zero registros em silencio). A API REST tem JSON puro,
-- JWT (token flui como dado normal entre nodes, sem precisar de credencial
-- nativa nem de $env), e erros de verdade em HTTP 400/401 (nao mais escondidos
-- num corpo HTTP 200).
--
-- SIMPLIFICADO em relacao a versao SOAP: a API REST tem 8 metodos bem
-- documentados (contra ~70 do SOAP, boa parte fora do manual). Nao ha mais
-- necessidade de um catalogo de metodos (bronze.tres_s_metodo) nem de fila de
-- fanout (bronze.tres_s_ingest_job — alias, nunca chegou a ser usada por
-- nenhum workflow entregue). Watermark e raw_response continuam, porque
-- resolvem um problema real (cursor incremental e auditoria de chamada).
--
-- Idempotente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Watermark — cursores do RetornaDados
--    Um metodo, dominios independentes. Cada um avanca no seu ritmo.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.tres_s_watermark (
    dominio          TEXT PRIMARY KEY,                  -- posicao, alerta_velocidade, ocorrencia_alerta...
    ultimo_id        BIGINT NOT NULL DEFAULT 0,
    habilitado       BOOLEAN NOT NULL DEFAULT TRUE,     -- FALSE => envia -1 (nao coletar)
    atualizado_em    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    id_raw_response  BIGINT
);

COMMENT ON TABLE bronze.tres_s_watermark IS
  'Estado da ingestao incremental. O n8n LE daqui para montar o corpo da '
  'chamada e ESCREVE aqui somente depois do INSERT confirmar. Avancar antes '
  'perde dados em silencio se o insert falhar.';

-- ----------------------------------------------------------------------------
-- 2. Log de respostas cruas — a peca mais importante do bronze
--
--    Guarda o corpo exatamente como veio (JSON, texto). Permite REPARSEAR
--    sem rechamar a API. response_corpo (antes response_xml — a API REST
--    devolve JSON, nao XML).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.tres_s_raw_response (
    id             BIGSERIAL PRIMARY KEY,
    metodo         TEXT NOT NULL,
    params         JSONB NOT NULL DEFAULT '{}'::jsonb,
    http_status    INT,
    duracao_ms     INT,
    tamanho_bytes  INT,
    sucesso        BOOLEAN NOT NULL DEFAULT TRUE,
    erro_msg       TEXT,
    response_corpo TEXT,
    recebido_em    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_raw_sem_senha
        CHECK (NOT (params ?| ARRAY['Senha','senha','password','Usuario','usuario']))
);

CREATE INDEX IF NOT EXISTS ix_3s_raw_metodo_data
    ON bronze.tres_s_raw_response (metodo, recebido_em DESC);
CREATE INDEX IF NOT EXISTS ix_3s_raw_erro
    ON bronze.tres_s_raw_response (recebido_em DESC) WHERE NOT sucesso;

COMMENT ON TABLE bronze.tres_s_raw_response IS
  'Toda chamada HTTP de dado gera uma linha (login nao — nao e dado, e infra '
  'de autenticacao). Toda linha do bronze aponta para ca via id_raw_response: '
  'da para responder "de onde veio esta linha e o que eu pedi para obte-la?".';

-- ----------------------------------------------------------------------------
-- 3. Avanco de watermark — so para frente, nunca para tras
--    Centraliza a invariante num lugar so, em vez de confiar no Code node.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bronze.fn_avanca_watermark(
    p_dominio    TEXT,
    p_novo_id    BIGINT,
    p_raw_id     BIGINT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_atual BIGINT;
BEGIN
    SELECT ultimo_id INTO v_atual
      FROM bronze.tres_s_watermark
     WHERE dominio = p_dominio
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dominio de watermark desconhecido: %', p_dominio;
    END IF;

    -- Retrocesso reprocessaria dados ja ingeridos. Ignora em silencio e
    -- devolve o valor atual, para o chamador nao precisar tratar.
    IF p_novo_id IS NULL OR p_novo_id <= v_atual THEN
        RETURN v_atual;
    END IF;

    UPDATE bronze.tres_s_watermark
       SET ultimo_id       = p_novo_id,
           atualizado_em   = NOW(),
           id_raw_response = COALESCE(p_raw_id, id_raw_response)
     WHERE dominio = p_dominio;

    RETURN p_novo_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. Monitoramento — baseado so em raw_response (sem catalogo de metodos)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW bronze.vw_3s_ingest_status AS
SELECT
    metodo,
    max(recebido_em)                                                      AS ultima_chamada,
    count(*) FILTER (WHERE recebido_em > NOW() - INTERVAL '24 hours')     AS chamadas_24h,
    count(*) FILTER (WHERE NOT sucesso
                       AND recebido_em > NOW() - INTERVAL '24 hours')     AS erros_24h
FROM bronze.tres_s_raw_response
GROUP BY metodo
ORDER BY ultima_chamada DESC NULLS LAST;

-- ============================================================================
-- SEED — dominios do watermark
-- ============================================================================
INSERT INTO bronze.tres_s_watermark (dominio, habilitado)
VALUES
 ('posicao',            TRUE),   -- fonte dos alertas derivados (ver 20_eventos_velocidade.sql)
 ('sensor',              FALSE),
 ('telemetria',          FALSE), -- verificado vazio nesta conta (03/08/2026)
 ('ocorrencia_alerta',   TRUE)   -- cursor unico p/ AlertaVelocidade, AlertaSensor,
                                 -- AlertaTemperatura, CercaAlvo, CercaLogradouro,
                                 -- CercaPoligonal, CercaRota (sequencia compartilhada,
                                 -- confirmado real 04/08/2026)
ON CONFLICT (dominio) DO NOTHING;
