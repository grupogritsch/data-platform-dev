-- ============================================================================
-- BRONZE / 3S — EVENTOS (alertas e cercas)
--
-- E A FONTE DO RELATORIO. Auditado no node "03 - Buscar Alertas Consolidados
-- SQL" de Torre de Controle - Alertas Telemetria.
--
-- CONTRATO tbAlertaVelocidade CONFIRMADO contra a API em 03/08/2026:
--   idOcorrenciaAlerta, idAlerta, VelocidadeLimite, Data, Velocidade, idGateway,
--   Satelite, Altitude, Direcao, UF, Cidade, Bairro, Endereco, Numero, CEP,
--   Latitude, Longitude, idEquipamento, NumSerie
--
-- DUAS DESCOBERTAS QUE DEFINIRAM ESTE DESENHO
--
-- 1. idOcorrenciaAlerta e uma SEQUENCIA UNICA compartilhada por todos os tipos
--    de alerta e cerca. No bootstrap, idAlertaVelocidade, idAlertaSensor,
--    idAlertaTemperatura, idCercaAlvo, idCercaLogradouro, idCercaPoligono e
--    idCercaRota voltaram TODOS com o mesmo valor (156301772).
--    => Uma tabela unica com chave natural em id_ocorrencia_alerta, e UM
--       watermark alimentando os 7 parametros do envelope.
--
-- 2. NAO EXISTE campo <Placa> no evento. Só idEquipamento e NumSerie.
--    => O join ate a placa passa obrigatoriamente por bronze.tres_s_veiculos.
--       Sem o cadastro carregado, o relatorio nao resolve filial nem modelo.
--
-- Idempotente.
-- ============================================================================

CREATE TABLE IF NOT EXISTS bronze.tres_s_eventos (
    id                   BIGSERIAL PRIMARY KEY,

    -- Chave natural: sequencia unica compartilhada por todos os tipos
    id_ocorrencia_alerta BIGINT NOT NULL,
    tipo_evento          TEXT   NOT NULL,   -- ALERTA_VELOCIDADE, ALERTA_SENSOR,
                                            -- CERCA_ALVO, CERCA_ROTA, ...
    id_alerta            TEXT,              -- config do alerta (yyyyMMddHHmmss)

    -- Identificacao do ativo (NAO ha Placa aqui)
    id_equipamento       TEXT,
    num_serie            TEXT,
    id_gateway           TEXT,

    -- Quando
    data_evento          TEXT,              -- cru: 'dd/MM/yyyy HH:mm:ss'. Tipagem no silver.

    -- Medidas comuns
    velocidade           TEXT,
    satelite             TEXT,
    altitude             TEXT,
    direcao              TEXT,

    -- Localizacao (o relatorio usa como coluna "Local")
    uf                   TEXT,
    cidade               TEXT,
    bairro               TEXT,
    endereco             TEXT,
    numero               TEXT,
    cep                  TEXT,
    latitude             TEXT,
    longitude            TEXT,

    -- Especificos por tipo (nulos quando nao se aplicam)
    velocidade_limite    TEXT,              -- ALERTA_VELOCIDADE
    id_sensor            TEXT,              -- ALERTA_SENSOR
    sensor               TEXT,              -- ALERTA_SENSOR
    estado               TEXT,              -- ALERTA_SENSOR
    descricao            TEXT,              -- CERCA_*
    ocorrencia           TEXT,              -- CERCA_*: ENTRADA / SAIDA
    nivel_risco          TEXT,              -- CERCA_*
    raio                 TEXT,              -- CERCA_*

    payload_json         JSONB  NOT NULL,
    id_raw_response      BIGINT REFERENCES bronze.tres_s_raw_response(id),
    ingested_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Migracao de instalacoes anteriores (postgres/scripts/3s_raw_tables.sql criava
-- uma tabela mais pobre, sem chave natural e sem os campos de localizacao)
ALTER TABLE bronze.tres_s_eventos
    ADD COLUMN IF NOT EXISTS id_ocorrencia_alerta BIGINT,
    ADD COLUMN IF NOT EXISTS num_serie            TEXT,
    ADD COLUMN IF NOT EXISTS satelite             TEXT,
    ADD COLUMN IF NOT EXISTS altitude             TEXT,
    ADD COLUMN IF NOT EXISTS direcao              TEXT,
    ADD COLUMN IF NOT EXISTS uf                   TEXT,
    ADD COLUMN IF NOT EXISTS cidade               TEXT,
    ADD COLUMN IF NOT EXISTS bairro               TEXT,
    ADD COLUMN IF NOT EXISTS endereco             TEXT,
    ADD COLUMN IF NOT EXISTS numero               TEXT,
    ADD COLUMN IF NOT EXISTS cep                  TEXT,
    ADD COLUMN IF NOT EXISTS latitude             TEXT,
    ADD COLUMN IF NOT EXISTS longitude            TEXT,
    ADD COLUMN IF NOT EXISTS id_sensor            TEXT,
    ADD COLUMN IF NOT EXISTS sensor               TEXT,
    ADD COLUMN IF NOT EXISTS estado               TEXT,
    ADD COLUMN IF NOT EXISTS descricao            TEXT,
    ADD COLUMN IF NOT EXISTS ocorrencia           TEXT,
    ADD COLUMN IF NOT EXISTS nivel_risco          TEXT,
    ADD COLUMN IF NOT EXISTS id_raw_response      BIGINT;

DO $$
DECLARE v_dup BIGINT;
BEGIN
    SELECT count(*) INTO v_dup FROM (
        SELECT id_ocorrencia_alerta FROM bronze.tres_s_eventos
         WHERE id_ocorrencia_alerta IS NOT NULL
         GROUP BY id_ocorrencia_alerta HAVING count(*) > 1) d;

    IF v_dup > 0 THEN
        RAISE WARNING 'UNIQUE nao criada: % id_ocorrencia_alerta duplicados. Deduplicar antes.', v_dup;
    ELSE
        CREATE UNIQUE INDEX IF NOT EXISTS uq_3s_eventos_ocorrencia
            ON bronze.tres_s_eventos (id_ocorrencia_alerta);
    END IF;
END $$;

-- O relatorio filtra por tipo e periodo, e junta por equipamento
CREATE INDEX IF NOT EXISTS ix_3s_eventos_tipo_ingest
    ON bronze.tres_s_eventos (tipo_evento, ingested_at DESC);
CREATE INDEX IF NOT EXISTS ix_3s_eventos_equip
    ON bronze.tres_s_eventos (id_equipamento);

COMMENT ON COLUMN bronze.tres_s_eventos.id_ocorrencia_alerta IS
  'Sequencia UNICA compartilhada por todos os tipos de alerta e cerca — '
  'confirmado no bootstrap, onde os 7 dominios devolveram o mesmo valor. '
  'Por isso um watermark so alimenta os 7 parametros do envelope.';

COMMENT ON COLUMN bronze.tres_s_eventos.id_equipamento IS
  'O evento NAO traz <Placa>. Resolver via bronze.tres_s_veiculos.id_equipamento. '
  'Sem o cadastro carregado o relatorio nao resolve filial nem modelo.';

COMMENT ON COLUMN bronze.tres_s_eventos.data_evento IS
  'Cru, no formato dd/MM/yyyy HH:mm:ss. Conversao para timestamptz no silver, '
  'uma vez so — hoje o relatorio faz to_timestamp() a cada consulta.';

-- ----------------------------------------------------------------------------
-- Carga idempotente por tipo de evento.
--   SELECT bronze.fn_carrega_eventos($1::jsonb, 'ALERTA_VELOCIDADE', $2::bigint);
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bronze.fn_carrega_eventos(
    p_registros JSONB,
    p_tipo      TEXT,
    p_raw_id    BIGINT DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_linhas INT;
BEGIN
    INSERT INTO bronze.tres_s_eventos (
        id_ocorrencia_alerta, tipo_evento, id_alerta, id_equipamento, num_serie,
        id_gateway, data_evento, velocidade, satelite, altitude, direcao,
        uf, cidade, bairro, endereco, numero, cep, latitude, longitude,
        velocidade_limite, id_sensor, sensor, estado,
        descricao, ocorrencia, nivel_risco, raio,
        payload_json, id_raw_response
    )
    SELECT (r->>'idOcorrenciaAlerta')::BIGINT, p_tipo, r->>'idAlerta',
           r->>'idEquipamento', r->>'NumSerie', r->>'idGateway',
           r->>'Data', r->>'Velocidade', r->>'Satelite', r->>'Altitude', r->>'Direcao',
           r->>'UF', r->>'Cidade', r->>'Bairro', r->>'Endereco', r->>'Numero',
           r->>'CEP', r->>'Latitude', r->>'Longitude',
           r->>'VelocidadeLimite', r->>'idSensor', r->>'Sensor', r->>'Estado',
           r->>'Descricao', COALESCE(r->>'Ocorrencia', r->>'Violacao'),
           r->>'NivelRisco', r->>'Raio',
           r, p_raw_id
      FROM jsonb_array_elements(p_registros) AS r
     WHERE r->>'idOcorrenciaAlerta' IS NOT NULL
    ON CONFLICT (id_ocorrencia_alerta) DO NOTHING;

    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RETURN v_linhas;
END;
$$;

-- ============================================================================
-- AJUSTE DO WATERMARK conforme o comportamento real observado
--
-- Removido em 04/08/2026 (pivo SOAP -> REST): este bloco inseria/ajustava
-- bronze.tres_s_watermark com colunas que so faziam sentido para o envelope
-- SOAP (parametro_soap, tag_id_resposta). A tabela foi simplificada em
-- postgres/sql/bronze/10_3s_controle.sql, que ja semeia diretamente os 4
-- dominios usados hoje (posicao, sensor, telemetria, ocorrencia_alerta) com
-- o habilitado correto de cada um. Nada a fazer aqui.
-- ============================================================================
