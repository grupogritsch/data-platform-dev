-- ============================================================================
-- BRONZE / 3S — CADASTRO DE VEICULOS  (metodo ListaVeiculos)
--
-- CONTRATO CONFIRMADO contra a API SOAP em 2026-07-31 (3.169 registros) e
-- RECONFIRMADO contra a API REST (DataExportAPI) em 04/08/2026 (3.170
-- registros) — mesmos nomes de campo nos dois protocolos (mesmo backend),
-- exceto RENAVAM/Renavam (REST usa capitalizacao Title Case). Ver
-- docs/3s-api-contrato.md secao 3.
--
-- DOUTRINA DESTA CAMADA
--   1. Tipos permissivos (TEXT). A ingestao NUNCA pode falhar por dado
--      inesperado. Exemplo real: 23 registros trazem o CHASSI de 17 caracteres
--      dentro do campo <Placa>; um VARCHAR(20) sobrevive, mas um VARCHAR(10)
--      derrubaria a carga inteira. Tipagem e validacao acontecem no silver.
--   2. Fidelidade a origem. Nada de upper(), trim() ou remocao de hifen aqui —
--      normalizar em bronze apaga a evidencia de que a origem esta suja.
--   3. payload_json sempre preenchido. Campo novo que a 3S adicionar continua
--      sendo capturado mesmo sem coluna dedicada.
--   4. Chave natural + procedencia em toda linha.
--
-- Idempotente. Migra tabelas pre-existentes criadas por postgres/scripts/.
-- ============================================================================

CREATE TABLE IF NOT EXISTS bronze.tres_s_veiculos (
    id               BIGSERIAL PRIMARY KEY,
    id_equipamento   TEXT NOT NULL,      -- ID do RASTREADOR
    id_veiculo       TEXT,               -- ID do VEICULO (chave DIFERENTE, ver nota)
    id_cliente       TEXT,
    num_serie        TEXT,
    placa            TEXT,               -- cru: pode conter chassi ou serial
    frota            TEXT,
    modelo           TEXT,
    chassis          TEXT,               -- API devolve <Chassis>; manual diz "Chassi"
    renavam          TEXT,
    tipo             TEXT,               -- Passeio / Caminhao / Van
    payload_json     JSONB NOT NULL,
    id_raw_response  BIGINT REFERENCES bronze.tres_s_raw_response(id),
    ingested_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- --- Migracao de instalacoes anteriores (postgres/scripts/3s_raw_tables.sql) ---
ALTER TABLE bronze.tres_s_veiculos
    ADD COLUMN IF NOT EXISTS id_veiculo      TEXT,
    ADD COLUMN IF NOT EXISTS num_serie       TEXT,
    ADD COLUMN IF NOT EXISTS tipo            TEXT,
    ADD COLUMN IF NOT EXISTS chassis         TEXT,
    ADD COLUMN IF NOT EXISTS id_raw_response BIGINT;

-- VARCHAR(n) -> TEXT: coercao binaria, sem reescrita de tabela.
ALTER TABLE bronze.tres_s_veiculos
    ALTER COLUMN id_equipamento TYPE TEXT,
    ALTER COLUMN placa          TYPE TEXT,
    ALTER COLUMN renavam        TYPE TEXT,
    ALTER COLUMN id_cliente     TYPE TEXT;

-- A coluna antiga "chassi" nunca foi preenchida: o parser procurava a tag do
-- manual (<Chassi>), mas a API devolve <Chassis>. Preserva o que houver e
-- deixa a coluna morta para tras.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='bronze' AND table_name='tres_s_veiculos'
                  AND column_name='chassi') THEN
        UPDATE bronze.tres_s_veiculos
           SET chassis = chassi
         WHERE chassis IS NULL AND chassi IS NOT NULL;
        ALTER TABLE bronze.tres_s_veiculos RENAME COLUMN chassi TO _deprecated_chassi;
        RAISE NOTICE 'Coluna "chassi" renomeada para "_deprecated_chassi" (a API devolve <Chassis>).';
    END IF;
END $$;

-- --- Chave natural: idempotencia da ingestao ---
-- Sem isso, todo rerun duplica a tabela inteira. E o defeito mais grave do
-- bronze atual: nenhuma tabela tem chave natural.
DO $$
DECLARE v_dup BIGINT;
BEGIN
    SELECT count(*) INTO v_dup FROM (
        SELECT id_equipamento FROM bronze.tres_s_veiculos
         WHERE id_equipamento IS NOT NULL
         GROUP BY id_equipamento HAVING count(*) > 1
    ) d;

    IF v_dup > 0 THEN
        RAISE WARNING
          'UNIQUE NAO criada: % id_equipamento duplicados. Deduplicar antes:%'
          '  DELETE FROM bronze.tres_s_veiculos a USING bronze.tres_s_veiculos b%'
          '   WHERE a.id_equipamento = b.id_equipamento AND a.id < b.id;',
          v_dup, chr(10), chr(10);
    ELSE
        CREATE UNIQUE INDEX IF NOT EXISTS uq_3s_veiculos_equipamento
            ON bronze.tres_s_veiculos (id_equipamento);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_3s_veiculos_placa     ON bronze.tres_s_veiculos (placa);
CREATE INDEX IF NOT EXISTS ix_3s_veiculos_id_veic   ON bronze.tres_s_veiculos (id_veiculo);
CREATE INDEX IF NOT EXISTS ix_3s_veiculos_num_serie ON bronze.tres_s_veiculos (num_serie);

-- ----------------------------------------------------------------------------
-- Documentacao das armadilhas encontradas no contrato real
-- ----------------------------------------------------------------------------
COMMENT ON COLUMN bronze.tres_s_veiculos.id_equipamento IS
  'ID do RASTREADOR. E o parametro aceito por RetornaDados e HistoricoPosicao*. '
  'Formato yyyyMMddHHmmss. Chave natural desta tabela.';

COMMENT ON COLUMN bronze.tres_s_veiculos.id_veiculo IS
  'ID do VEICULO. NAO documentado no manual v2.8 e DIFERENTE de id_equipamento '
  'em 3.168 dos 3.169 registros — ambos unicos, ambos yyyyMMddHHmmss. '
  'Confundir os dois quebra qualquer join.';

COMMENT ON COLUMN bronze.tres_s_veiculos.placa IS
  'CRU, sem normalizacao. Na amostra de 3.169: 3.119 Mercosul, 3 formato antigo, '
  '23 contendo o CHASSI (veiculo nao emplacado), 1 numero serial de TAG, '
  '23 outros formatos. O silver decide o que e placa valida — filtrar aqui '
  'esconderia o problema.';

COMMENT ON COLUMN bronze.tres_s_veiculos.chassis IS
  'A API devolve a tag <Chassis>. O manual v2.8 documenta <Chassi> (sem s), '
  'e por isso a coluna antiga nunca foi preenchida. Vazio ou "0" em 177 registros.';

COMMENT ON COLUMN bronze.tres_s_veiculos.num_serie IS
  'Serial do rastreador. Fora do manual. Candidato a chave de reconciliacao '
  'com a Nuxeo, onde a placa nao bate.';

COMMENT ON COLUMN bronze.tres_s_veiculos.id_raw_response IS
  'Procedencia: aponta para a chamada HTTP que originou esta linha.';

-- ----------------------------------------------------------------------------
-- Carga idempotente — chamada pelo n8n com o array JSON no parametro $1.
--
-- Uma instrucao, sem concatenacao de string: elimina a injecao de SQL e o
-- esc() manual dos Code nodes atuais.
--
--   SELECT bronze.fn_carrega_veiculos($1::jsonb, $2::bigint);
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bronze.fn_carrega_veiculos(
    p_registros JSONB,
    p_raw_id    BIGINT DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_linhas INT;
BEGIN
    INSERT INTO bronze.tres_s_veiculos (
        id_equipamento, id_veiculo, id_cliente, num_serie, placa,
        frota, modelo, chassis, renavam, tipo, payload_json, id_raw_response
    )
    SELECT r->>'idEquipamento', r->>'idVeiculo', r->>'idCliente',
           r->>'NumSerie',      r->>'Placa',     r->>'Frota',
           r->>'Modelo',        r->>'Chassis',   r->>'Renavam',
           r->>'Tipo',          r,               p_raw_id
      FROM jsonb_array_elements(p_registros) AS r
     WHERE r->>'idEquipamento' IS NOT NULL
    ON CONFLICT (id_equipamento) DO UPDATE
       SET id_veiculo      = EXCLUDED.id_veiculo,
           id_cliente      = EXCLUDED.id_cliente,
           num_serie       = EXCLUDED.num_serie,
           placa           = EXCLUDED.placa,
           frota           = EXCLUDED.frota,
           modelo          = EXCLUDED.modelo,
           chassis         = EXCLUDED.chassis,
           renavam         = EXCLUDED.renavam,
           tipo            = EXCLUDED.tipo,
           payload_json    = EXCLUDED.payload_json,
           id_raw_response = EXCLUDED.id_raw_response,
           ingested_at     = NOW();

    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RETURN v_linhas;
END;
$$;
