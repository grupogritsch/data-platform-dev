-- ============================================================================
-- BRONZE / 3S — POSICOES  (janela movel de 30 dias)
--
-- ESTRATEGIA: as posicoes deixam de ser descartadas e passam a ser a FONTE DOS
-- ALERTAS, com retencao limitada. Motivo, medido em 03/08/2026:
--
--   - O alerta da 3S cobre 29 de 3.169 veiculos (0,92%).
--   - A retencao de ALERTAS na 3S e de ~36 dias; a de POSICOES, ~5 anos.
--   - Os alertas da 3S batem 1:1 com as posicoes acima do limite:
--     em 07/07/2026 o veiculo TBO 0C67 teve 18 posicoes > 100 km/h e a 3S
--     gerou exatamente 18 alertas, nos MESMOS horarios. O alerta e derivado
--     da amostragem, nao de deteccao continua no equipamento.
--
--   => Derivar o alerta da posicao da cobertura de 100% da frota, controle
--      da regra e recalculo retroativo, sem perder nada.
--
-- CONTRATO HistoricoPosicao (API REST) CONFIRMADO (04/08/2026, 382 registros
-- reais numa janela de 1 dia):
--   idPosicao, Data, Velocidade, Satelite, Altitude, Direcao, UF, Cidade,
--   Bairro, Endereco, Numero, CEP, Latitude, Longitude, POI, Odometro, Horimetro
--   ATENCAO: NAO traz Placa nem idEquipamento -> vem do contexto da chamada
--   (mesma limitacao do metodo SOAP equivalente).
--   dataInicio/dataFim em ISO 8601 sem timezone ("2026-08-03T00:00:00") —
--   DIFERENTE do SOAP, que exigia "dd/MM/yyyy HH:mm:ss".
--   NAO existe mais o metodo "HistoricoPosicaoCompleto" (era exclusivo do
--   SOAP): a API REST unificou tudo em HistoricoPosicao.
--
-- AMOSTRAGEM MEDIDA: mediana de 120 s com ignicao ligada, ate 3600 s parado.
--   Dia ativo ~131 posicoes/veiculo; dia ocioso ~24.
--
-- Idempotente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Tabela particionada por dia.
--
-- NOTA SOBRE A DOUTRINA DO BRONZE: em toda outra tabela o dado fica cru, em
-- TEXT, e a tipagem acontece no silver. Aqui ha UMA excecao deliberada — a
-- coluna data_ref (DATE), porque o Postgres exige um tipo real como chave de
-- particao e nao aceita coluna gerada. O texto original continua intacto em
-- data_gps e em payload_json; data_ref e artefato de particionamento, nao
-- substituicao do dado cru.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.tres_s_posicoes (
    id               BIGSERIAL,
    data_ref         DATE   NOT NULL,        -- chave de particao (derivada de Data)
    id_posicao       TEXT   NOT NULL,
    id_equipamento   TEXT,                   -- do contexto: HistoricoPosicao nao devolve
    data_gps         TEXT,                   -- cru: 'dd/MM/yyyy HH:mm:ss'
    velocidade       TEXT,
    ignicao          TEXT,
    satelite         TEXT,
    altitude         TEXT,
    direcao          TEXT,
    uf               TEXT,
    cidade           TEXT,
    bairro           TEXT,
    endereco         TEXT,
    numero           TEXT,
    cep              TEXT,
    latitude         TEXT,
    longitude        TEXT,
    odometro         TEXT,                   -- fora do manual
    horimetro        TEXT,                   -- fora do manual
    payload_json     JSONB  NOT NULL,
    id_raw_response  BIGINT,
    ingested_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (data_ref, id_posicao)       -- a chave de particao entra na PK
) PARTITION BY RANGE (data_ref);

CREATE INDEX IF NOT EXISTS ix_3s_pos_equip_data
    ON bronze.tres_s_posicoes (id_equipamento, data_ref);

COMMENT ON TABLE bronze.tres_s_posicoes IS
  'Janela movel: expurgo automatico. Ver bronze.fn_expurga_posicoes.';
COMMENT ON COLUMN bronze.tres_s_posicoes.id_equipamento IS
  'HistoricoPosicao NAO devolve idEquipamento nem Placa — o carregador recebe '
  'o valor do contexto da chamada. Via RetornaDados o campo pode vir no '
  'proprio registro; a funcao de carga aceita as duas origens.';

-- ----------------------------------------------------------------------------
-- Gestao de particoes
-- ----------------------------------------------------------------------------

-- Cria a particao DIARIA da data, MAS so se nenhuma particao existente ja
-- cobrir aquele dia.
--
-- Erro real de producao (20/08/2026):
--   partition "tres_s_posicoes_20260819" would overlap partition
--   "tres_s_posicoes_2026_08"
-- Havia particoes MENSAIS pre-existentes (ago-dez/2026) criadas por
-- scratch/cria_particoes_3s.py, fora desta esteira, mais uma particao DEFAULT.
-- Criar a diaria por cima sobrepoe e o Postgres recusa — derrubando a carga.
--
-- Em vez de impor um esquema, a funcao respeita o que ja existe.
CREATE OR REPLACE FUNCTION bronze.fn_garante_particao_posicao(p_data DATE)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_nome TEXT; v_existente TEXT;
BEGIN
    -- 1) Ja existe particao cuja FAIXA contem esta data? (mensal ou diaria)
    SELECT c.relname INTO v_existente
      FROM pg_class c
      JOIN pg_inherits i ON i.inhrelid = c.oid
     WHERE i.inhparent = 'bronze.tres_s_posicoes'::regclass
       AND c.relpartbound IS NOT NULL
       AND pg_get_expr(c.relpartbound, c.oid) LIKE 'FOR VALUES FROM%'
       AND p_data >= (substring(pg_get_expr(c.relpartbound, c.oid)
                                from 'FROM \(''([0-9-]+)''\)'))::date
       AND p_data <  (substring(pg_get_expr(c.relpartbound, c.oid)
                                from 'TO \(''([0-9-]+)''\)'))::date
     LIMIT 1;
    IF v_existente IS NOT NULL THEN
        RETURN v_existente;
    END IF;

    -- 2) Existe particao DEFAULT? Entao QUALQUER data ja tem destino e nao ha
    --    nada a criar. Este banco tem bronze.tres_s_posicoes_default.
    SELECT c.relname INTO v_existente
      FROM pg_class c
      JOIN pg_inherits i ON i.inhrelid = c.oid
     WHERE i.inhparent = 'bronze.tres_s_posicoes'::regclass
       AND pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT'
     LIMIT 1;
    IF v_existente IS NOT NULL THEN
        RETURN v_existente;
    END IF;

    -- 3) Nenhuma cobertura encontrada: cria a diaria.
    --    O CREATE fica protegido porque as checagens acima dependem de LER a
    --    definicao da particao no catalogo, e isso pode falhar por um formato
    --    inesperado de faixa. Se colidir mesmo assim, a data JA esta coberta —
    --    o INSERT seguinte funciona igual, e nao ha razao para derrubar a
    --    carga dos ~108 veiculos por causa disso.
    v_nome := 'tres_s_posicoes_' || to_char(p_data, 'YYYYMMDD');
    BEGIN
        EXECUTE format(
            'CREATE TABLE bronze.%I PARTITION OF bronze.tres_s_posicoes
             FOR VALUES FROM (%L) TO (%L)', v_nome, p_data, p_data + 1);
        RETURN v_nome;
    EXCEPTION
        -- duplicate_table: corrida entre duas execucoes criando a mesma.
        -- invalid_object_definition: sobreposicao com particao existente.
        WHEN duplicate_table OR invalid_object_definition THEN
            RETURN 'ja_coberta';
    END;
END; $$;

-- Expurgo: DROP de particao e instantaneo e nao gera bloat, ao contrario de
-- DELETE em massa numa tabela unica de milhoes de linhas.
--
-- Le a FAIXA de cada particao no catalogo, em vez de deduzir a data pelo nome.
-- A versao anterior so reconhecia o padrao diario (tres_s_posicoes_YYYYMMDD) e
-- ignorava as particoes MENSAIS pre-existentes — que portanto nunca seriam
-- expurgadas, e o volume cresceria para sempre sem ninguem notar.
CREATE OR REPLACE FUNCTION bronze.fn_expurga_posicoes(p_dias INT DEFAULT 30)
RETURNS TABLE(particao TEXT, removida BOOLEAN) LANGUAGE plpgsql AS $$
DECLARE r RECORD; v_corte DATE := CURRENT_DATE - p_dias;
BEGIN
    FOR r IN
        SELECT c.relname,
               (substring(pg_get_expr(c.relpartbound, c.oid)
                          from 'TO \(''([0-9-]+)''\)'))::date AS fim
          FROM pg_class c
          JOIN pg_inherits i ON i.inhrelid = c.oid
         WHERE i.inhparent = 'bronze.tres_s_posicoes'::regclass
           AND c.relpartbound IS NOT NULL
           AND pg_get_expr(c.relpartbound, c.oid) LIKE 'FOR VALUES FROM%'
    LOOP
        -- O limite superior da faixa e EXCLUSIVO. So remove quando o intervalo
        -- INTEIRO ja saiu da janela — nao da para remover meio mes.
        -- Consequencia pratica: com particao mensal a retencao efetiva vai de
        -- 30 a 60 dias, em vez dos 30 exatos que a particao diaria daria.
        IF r.fim IS NOT NULL AND r.fim <= v_corte THEN
            EXECUTE format('DROP TABLE bronze.%I', r.relname);
            particao := r.relname; removida := TRUE; RETURN NEXT;
        END IF;
    END LOOP;
END; $$;

COMMENT ON FUNCTION bronze.fn_expurga_posicoes IS
  'Chamar diariamente. Remove particoes cuja faixa inteira ja saiu da janela de '
  'p_dias, seja o esquema diario ou mensal. Com particao DIARIA a retencao e '
  'exata; com particao MENSAL fica entre 30 e 60 dias, porque o mes so sai '
  'quando envelhece por completo.';

-- ----------------------------------------------------------------------------
-- Carga idempotente.
--   SELECT bronze.fn_carrega_posicoes($1::jsonb, $2::text, $3::bigint);
-- p_id_equipamento: usado quando o registro nao traz o campo (o caso do
-- HistoricoPosicao). Se o registro trouxer, o do registro prevalece.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bronze.fn_carrega_posicoes(
    p_registros      JSONB,
    p_id_equipamento TEXT   DEFAULT NULL,
    p_raw_id         BIGINT DEFAULT NULL
) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_linhas INT; r RECORD;
BEGIN
    -- Garante as particoes de todas as datas presentes no lote
    FOR r IN
        SELECT DISTINCT to_date(left(x->>'Data', 10), 'DD/MM/YYYY') AS d
          FROM jsonb_array_elements(p_registros) AS x
         WHERE x->>'Data' IS NOT NULL
    LOOP
        PERFORM bronze.fn_garante_particao_posicao(r.d);
    END LOOP;

    INSERT INTO bronze.tres_s_posicoes (
        data_ref, id_posicao, id_equipamento, data_gps, velocidade, ignicao,
        satelite, altitude, direcao, uf, cidade, bairro, endereco, numero, cep,
        latitude, longitude, odometro, horimetro, payload_json, id_raw_response)
    SELECT to_date(left(x->>'Data',10),'DD/MM/YYYY'),
           x->>'idPosicao',
           COALESCE(x->>'idEquipamento', p_id_equipamento),
           x->>'Data', x->>'Velocidade', x->>'Ignicao', x->>'Satelite',
           x->>'Altitude', x->>'Direcao', x->>'UF', x->>'Cidade', x->>'Bairro',
           x->>'Endereco', x->>'Numero', x->>'CEP', x->>'Latitude',
           x->>'Longitude', x->>'Odometro', x->>'Horimetro',
           x, p_raw_id
      FROM jsonb_array_elements(p_registros) AS x
     WHERE x->>'idPosicao' IS NOT NULL AND x->>'Data' IS NOT NULL
    ON CONFLICT (data_ref, id_posicao) DO NOTHING;

    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RETURN v_linhas;
END; $$;

-- Posicoes LIGADAS no plano de controle (a estrategia mudou)
UPDATE bronze.tres_s_watermark SET habilitado = TRUE WHERE dominio = 'posicao';
