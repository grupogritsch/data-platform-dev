-- ============================================================================
-- SCRIPT DDL: BANCO DE DADOS DW (PRODUÇÃO / DESENVOLVIMENTO)
-- SCHEMA: bronze
-- TABELAS BRUTAS (RAW PAYLOADS) PARA INTEGRAÇÃO NUXEO (SISTEMA DE MAPAS)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS bronze;

-- ----------------------------------------------------------------------------
-- 1. bronze.nuxeo_veiculos_posicao
-- Dados retornados por: GET /rest/report/targetAndPosition/?position=true
-- Contém a lista de veículos cadastrados e sua última posição conhecida.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.nuxeo_veiculos_posicao (
    id              BIGSERIAL PRIMARY KEY,
    placa           VARCHAR(20),
    complemento     TEXT,
    device_id       INT,
    icon            INT,
    serial          VARCHAR(50),
    endereco        TEXT,
    cidade          VARCHAR(150),
    estado          VARCHAR(50),
    pais            VARCHAR(50),
    latitude        NUMERIC(10,6),
    longitude       NUMERIC(10,6),
    data_gps        TEXT,
    ignicao         BOOLEAN,
    bloqueio        BOOLEAN,
    panico          BOOLEAN,
    velocidade      NUMERIC(6,2),
    bateria         BOOLEAN,
    antifurto       TEXT,
    payload_json    JSONB,
    ingested_at     TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS complemento TEXT;
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS device_id INT;
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS icon INT;
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS serial VARCHAR(50);
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS endereco TEXT;
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS cidade VARCHAR(150);
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS estado VARCHAR(50);
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS pais VARCHAR(50);
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS latitude NUMERIC(10,6);
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS longitude NUMERIC(10,6);
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS data_gps TEXT;
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS ignicao BOOLEAN;
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS bloqueio BOOLEAN;
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS panico BOOLEAN;
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS velocidade NUMERIC(6,2);
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS bateria BOOLEAN;
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS antifurto TEXT;
ALTER TABLE bronze.nuxeo_veiculos_posicao ADD COLUMN IF NOT EXISTS payload_json JSONB;

-- ----------------------------------------------------------------------------
-- 2. bronze.nuxeo_posicoes_detalhadas
-- Dados retornados por: GET /rest/report/positionByPlate/?plate=...&begin=...&end=...
-- Contém o histórico detalhado de pontos de GPS/telemetria por veículo.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.nuxeo_posicoes_detalhadas (
    id              BIGSERIAL PRIMARY KEY,
    nuxeo_pos_id    BIGINT,
    placa           VARCHAR(20),
    serial          VARCHAR(50),
    altitude        NUMERIC(8,2),
    endereco        TEXT,
    cidade          VARCHAR(150),
    estado          VARCHAR(50),
    pais            VARCHAR(50),
    latitude        NUMERIC(10,6),
    longitude       NUMERIC(10,6),
    data_gps        TEXT,
    data_server     TEXT,
    ignicao         BOOLEAN,
    bateria         TEXT,
    alerta_bateria  BOOLEAN,
    bloqueio        BOOLEAN,
    panico          BOOLEAN,
    odometro        BIGINT,
    velocidade      NUMERIC(6,2),
    motorista       TEXT,
    cliente         INT,
    tipo_cliente    INT,
    payload_json    JSONB,
    ingested_at     TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 3. bronze.nuxeo_posicao_eventos
-- Dados retornados por: GET /rest/report/lastPositionAndEvent/?begin=...&end=...
-- Contém a última posição e o array de eventos associados por período.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.nuxeo_posicao_eventos (
    id              BIGSERIAL PRIMARY KEY,
    placa           VARCHAR(20),
    complemento     TEXT,
    serial          VARCHAR(50),
    endereco        TEXT,
    cidade          VARCHAR(150),
    estado          VARCHAR(50),
    pais            VARCHAR(50),
    latitude        NUMERIC(10,6),
    longitude       NUMERIC(10,6),
    data_gps        TEXT,
    ignicao         BOOLEAN,
    bloqueio        BOOLEAN,
    panico          BOOLEAN,
    velocidade      NUMERIC(6,2),
    bateria         BOOLEAN,
    antifurto       TEXT,
    qtd_eventos     INT,
    eventos_json    JSONB,
    payload_json    JSONB,
    ingested_at     TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 4. bronze.nuxeo_eventos
-- Dados retornados por: GET /rest/report/events/?begin=...&end=...&plate=...
-- Contém os eventos individuais de telemetria/rastreamento.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.nuxeo_eventos (
    id              BIGSERIAL PRIMARY KEY,
    placa           VARCHAR(20),
    complemento     TEXT,
    nome_evento     TEXT,
    data_evento     TEXT,
    velocidade      NUMERIC(6,2),
    latitude        NUMERIC(10,6),
    longitude       NUMERIC(10,6),
    endereco        TEXT,
    cidade          VARCHAR(150),
    estado          VARCHAR(50),
    pais            VARCHAR(50),
    payload_json    JSONB,
    ingested_at     TIMESTAMPTZ DEFAULT NOW()
);

-- Criando Índices para Alta Performance em Consultas Silver/Gold
CREATE INDEX IF NOT EXISTS idx_nuxeo_veic_placa ON bronze.nuxeo_veiculos_posicao(placa);
CREATE INDEX IF NOT EXISTS idx_nuxeo_pos_placa ON bronze.nuxeo_posicoes_detalhadas(placa);
CREATE INDEX IF NOT EXISTS idx_nuxeo_eventos_placa ON bronze.nuxeo_eventos(placa);
CREATE INDEX IF NOT EXISTS idx_nuxeo_eventos_nome ON bronze.nuxeo_eventos(nome_evento);
