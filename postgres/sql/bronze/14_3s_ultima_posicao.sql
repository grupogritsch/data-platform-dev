-- ============================================================================
-- BRONZE / 3S — ULTIMA POSICAO (snapshot, nao historico)
--
-- Tabela de ESTADO ATUAL: uma linha por equipamento, sobrescrita a cada carga.
-- Nao cresce — 3.169 linhas para sempre, ~2,4 MB.
--
-- E o que responde "quem parou de comunicar", base da onda de manutencao do
-- painel de rastreadores. Levantamento de 03/08/2026 achou 6 veiculos Gritsch
-- mudos, um deles ha 511 dias.
--
-- CONTRATO ListaUltimaPosicaoVeiculos/{idVeiculo} (API REST) confirmado em
-- 04/08/2026 (idVeiculo=0 = frota toda, 3.169 registros):
--   idPosicao, Frota, Placa, Modelo, Data, Velocidade, Satelite, Ignicao,
--   Direcao, UF, Cidade, Endereco, Numero, CEP, Latitude, Longitude,
--   idEquipamento, idVeiculo, Bloqueio, BatBackup, Odometro, Hourmeter
--
-- ATENCAO — FORMATO DE DATA MUDOU DO SOAP PARA O REST NESTE MESMO METODO:
--   SOAP (data_export.asmx)    -> ISO 8601: "2024-08-26T21:17:56-03:00"
--   REST (DataExportAPI)       -> "dd/MM/yyyy HH:mm:ss" (ex.: "04/08/2026 11:24:27")
-- Achado real: Gestao-rastreadores/sql/silver/21_fato_detectado.sql tinha uma
-- regex assumindo ISO 8601 para este campo — corrigida em 04/08/2026 junto
-- com esta migracao (senao toda deteccao 3S no painel de rastreadores viraria
-- NULL em silencio). Um parser que assuma formato unico quebra ou grava lixo
-- em silencio — por isso o bronze guarda cru (TEXT) e cada consumidor faz o
-- proprio CASE/regex de formato.
--
-- Idempotente.
-- ============================================================================

CREATE TABLE IF NOT EXISTS bronze.tres_s_ultima_posicao (
    id_equipamento   TEXT PRIMARY KEY,
    id_veiculo       TEXT,
    placa            TEXT,
    num_serie        TEXT,
    frota            TEXT,
    modelo           TEXT,
    data_gps         TEXT,        -- cru, ISO 8601
    velocidade       TEXT,
    ignicao          TEXT,
    satelite         TEXT,
    direcao          TEXT,
    uf               TEXT,
    cidade           TEXT,
    endereco         TEXT,
    numero           TEXT,
    cep              TEXT,
    latitude         TEXT,
    longitude        TEXT,
    bloqueio         TEXT,
    bat_backup       TEXT,
    odometro         TEXT,
    horimetro        TEXT,
    payload_json     JSONB  NOT NULL,
    id_raw_response  BIGINT REFERENCES bronze.tres_s_raw_response(id),
    atualizado_em    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_3s_ultpos_placa ON bronze.tres_s_ultima_posicao (placa);

COMMENT ON TABLE bronze.tres_s_ultima_posicao IS
  'Snapshot do estado atual, com UPSERT por id_equipamento. Nao acumula '
  'historico — para isso existe bronze.tres_s_posicoes (particionada).';

COMMENT ON COLUMN bronze.tres_s_ultima_posicao.data_gps IS
  'Cru, em ISO 8601 (ex.: 2024-08-26T21:17:56-03:00). Formato DIFERENTE dos '
  'metodos de historico, que usam dd/MM/yyyy HH:mm:ss.';

-- ----------------------------------------------------------------------------
-- Carga por upsert.  SELECT bronze.fn_carrega_ultima_posicao($1::jsonb, $2);
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bronze.fn_carrega_ultima_posicao(
    p_registros JSONB,
    p_raw_id    BIGINT DEFAULT NULL
) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_linhas INT;
BEGIN
    INSERT INTO bronze.tres_s_ultima_posicao (
        id_equipamento, id_veiculo, placa, num_serie, frota, modelo, data_gps,
        velocidade, ignicao, satelite, direcao, uf, cidade, endereco, numero,
        cep, latitude, longitude, bloqueio, bat_backup, odometro, horimetro,
        payload_json, id_raw_response, atualizado_em)
    SELECT r->>'idEquipamento', r->>'idVeiculo', r->>'Placa', r->>'NumSerie',
           r->>'Frota', r->>'Modelo', r->>'Data', r->>'Velocidade', r->>'Ignicao',
           r->>'Satelite', r->>'Direcao', r->>'UF', r->>'Cidade', r->>'Endereco',
           r->>'Numero', r->>'CEP', r->>'Latitude', r->>'Longitude',
           r->>'Bloqueio', r->>'BatBackup', r->>'Odometro', r->>'Hourmeter',
           r, p_raw_id, NOW()
      FROM jsonb_array_elements(p_registros) AS r
     WHERE r->>'idEquipamento' IS NOT NULL
    ON CONFLICT (id_equipamento) DO UPDATE
       SET placa = EXCLUDED.placa, num_serie = EXCLUDED.num_serie,
           data_gps = EXCLUDED.data_gps, velocidade = EXCLUDED.velocidade,
           ignicao = EXCLUDED.ignicao, latitude = EXCLUDED.latitude,
           longitude = EXCLUDED.longitude, uf = EXCLUDED.uf,
           cidade = EXCLUDED.cidade, endereco = EXCLUDED.endereco,
           odometro = EXCLUDED.odometro, horimetro = EXCLUDED.horimetro,
           bloqueio = EXCLUDED.bloqueio, bat_backup = EXCLUDED.bat_backup,
           payload_json = EXCLUDED.payload_json,
           id_raw_response = EXCLUDED.id_raw_response,
           atualizado_em = NOW();

    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RETURN v_linhas;
END;
$$;
