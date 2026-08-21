-- ============================================================================
-- SCRIPT DDL: BANCO DE DADOS DW (PRODUÇÃO / DESENVOLVIMENTO)
-- SCHEMA: bronze
-- TABELAS BRUTAS (RAW PAYLOADS) PARA INTEGRAÇÃO 3S TECNOLOGIA (WEBSERVICE SOAP)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS bronze;

-- ----------------------------------------------------------------------------
-- 1. bronze.tres_s_veiculos (Cadastro de Veículos / Equipamentos 3S)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.tres_s_veiculos (
    id              BIGSERIAL PRIMARY KEY,
    id_equipamento  VARCHAR(50),
    placa           VARCHAR(20),
    frota           TEXT,
    modelo          TEXT,
    chassi          VARCHAR(100),
    renavam         VARCHAR(50),
    id_cliente      VARCHAR(50),
    payload_json    JSONB,
    ingested_at     TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 2. bronze.tres_s_posicoes (Histórico e Última Posição GPS 3S)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.tres_s_posicoes (
    id              BIGSERIAL PRIMARY KEY,
    id_posicao      VARCHAR(50),
    id_equipamento  VARCHAR(50),
    placa           VARCHAR(20),
    frota           TEXT,
    modelo          TEXT,
    data_gps        TEXT,
    velocidade      NUMERIC(6,2),
    satelite        INT,
    ignicao         TEXT,
    direcao         TEXT,
    uf              VARCHAR(10),
    cidade          VARCHAR(150),
    bairro          VARCHAR(150),
    endereco        TEXT,
    numero          VARCHAR(50),
    cep             VARCHAR(20),
    latitude        NUMERIC(10,6),
    longitude       NUMERIC(10,6),
    payload_json    JSONB,
    ingested_at     TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 3. bronze.tres_s_eventos (Ocorrências de Velocidade, Cercas e Sensores 3S)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.tres_s_eventos (
    id              BIGSERIAL PRIMARY KEY,
    id_alerta       VARCHAR(50),
    id_equipamento  VARCHAR(50),
    placa           VARCHAR(20),
    tipo_evento     TEXT, -- 'EXCESSO_VELOCIDADE', 'CERCA_ALVO', 'SENSOR'
    data_evento     TEXT,
    velocidade      NUMERIC(6,2),
    velocidade_limite NUMERIC(6,2),
    alvo            TEXT,
    violacao        TEXT,
    raio            NUMERIC(10,2),
    id_gateway      VARCHAR(50),
    payload_json    JSONB,
    ingested_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_3s_veic_placa ON bronze.tres_s_veiculos(placa);
CREATE INDEX IF NOT EXISTS idx_3s_pos_placa ON bronze.tres_s_posicoes(placa);
CREATE INDEX IF NOT EXISTS idx_3s_evt_placa ON bronze.tres_s_eventos(placa);
