-- ============================================================================
-- SILVER — LIMITES DE VELOCIDADE E DERIVACAO DE EVENTOS
--
-- Substitui a dependencia do alerta configurado na 3S (que cobre 0,92% da
-- frota e retem 36 dias) por regra propria sobre as posicoes (100% da frota,
-- 5 anos de retencao na origem, limite alteravel com recalculo retroativo).
--
-- A regra foi VALIDADA contra o comportamento da 3S: uma posicao acima do
-- limite gera um evento. Em 07/07/2026, TBO 0C67 teve 18 posicoes > 100 km/h
-- e a 3S emitiu exatamente 18 alertas, nos mesmos horarios.
--
-- Idempotente.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS silver;

-- ----------------------------------------------------------------------------
-- 1. Limites configuraveis, com escopo hierarquico
--    Resolucao: PLACA > FILIAL > TIPO > GLOBAL (o mais especifico vence).
--    Historico por vigencia: mudar o limite nao reescreve o passado.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.ref_limite_velocidade (
    id             SERIAL PRIMARY KEY,
    escopo         TEXT NOT NULL CHECK (escopo IN ('GLOBAL','TIPO','FILIAL','PLACA')),
    chave          TEXT,                              -- NULL quando escopo='GLOBAL'
    limite_kmh     NUMERIC(5,1) NOT NULL CHECK (limite_kmh > 0),
    tolerancia_kmh NUMERIC(5,1) NOT NULL DEFAULT 0,   -- margem antes de gerar evento
    vigente_de     DATE NOT NULL DEFAULT CURRENT_DATE,
    vigente_ate    DATE,
    observacao     TEXT,
    CONSTRAINT ck_chave_por_escopo
        CHECK ((escopo = 'GLOBAL' AND chave IS NULL) OR (escopo <> 'GLOBAL' AND chave IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_limite_vigente
    ON silver.ref_limite_velocidade (escopo, COALESCE(chave,''), vigente_de);

COMMENT ON TABLE silver.ref_limite_velocidade IS
  'Regra de negocio sob nosso controle. Alterar o limite aqui e reprocessar '
  'recalcula o historico — impossivel com o alerta configurado na 3S.';

-- Semente: os dois limites que a 3S usava (100 e 110 km/h).
-- 100 vira o padrao global; ajustar conforme a politica da operacao.
INSERT INTO silver.ref_limite_velocidade (escopo, chave, limite_kmh, tolerancia_kmh, vigente_de, observacao)
VALUES ('GLOBAL', NULL, 100, 0, DATE '2026-01-01',
        'Padrao. Espelha o limite de 100 km/h que a 3S aplicava a 915 dos 1.166 alertas observados.')
ON CONFLICT DO NOTHING;

-- Resolve o limite de uma placa numa data
CREATE OR REPLACE FUNCTION silver.fn_limite_velocidade(
    p_placa TEXT, p_tipo TEXT, p_filial TEXT, p_data DATE
) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT (l.limite_kmh + l.tolerancia_kmh)
      FROM silver.ref_limite_velocidade l
     WHERE l.vigente_de <= p_data
       AND (l.vigente_ate IS NULL OR l.vigente_ate >= p_data)
       AND ( (l.escopo='PLACA'  AND l.chave = p_placa)
          OR (l.escopo='FILIAL' AND l.chave = p_filial)
          OR (l.escopo='TIPO'   AND l.chave = p_tipo)
          OR (l.escopo='GLOBAL') )
     ORDER BY CASE l.escopo WHEN 'PLACA' THEN 1 WHEN 'FILIAL' THEN 2
                            WHEN 'TIPO' THEN 3 ELSE 4 END,
              l.vigente_de DESC
     LIMIT 1;
$$;

-- ----------------------------------------------------------------------------
-- 2. Fato de evento unificado (3S + Nuxeo, API + derivado)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.fato_evento (
    id                BIGSERIAL PRIMARY KEY,
    fonte             TEXT NOT NULL,        -- '3S' | 'NUXEO'
    origem_deteccao   TEXT NOT NULL         -- 'API' = alerta do fornecedor
                      CHECK (origem_deteccao IN ('API','DERIVADO')),
    tipo_evento       TEXT NOT NULL,        -- taxonomia canonica
    id_externo        TEXT NOT NULL,        -- idOcorrenciaAlerta (API) | idPosicao (derivado)

    placa             TEXT,
    id_equipamento    TEXT,
    data_evento       TIMESTAMPTZ NOT NULL, -- tipado UMA vez, aqui
    velocidade        NUMERIC(6,2),
    limite_kmh        NUMERIC(5,1),
    excesso_kmh       NUMERIC(6,2) GENERATED ALWAYS AS (velocidade - limite_kmh) STORED,

    latitude          NUMERIC(10,6),
    longitude         NUMERIC(10,6),
    endereco          TEXT,
    bairro            TEXT,
    cidade            TEXT,
    uf                TEXT,

    criado_em         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_fato_evento UNIQUE (fonte, origem_deteccao, tipo_evento, id_externo)
);

CREATE INDEX IF NOT EXISTS ix_fato_evento_data   ON silver.fato_evento (data_evento DESC);
CREATE INDEX IF NOT EXISTS ix_fato_evento_placa  ON silver.fato_evento (placa, data_evento DESC);
CREATE INDEX IF NOT EXISTS ix_fato_evento_origem ON silver.fato_evento (origem_deteccao, data_evento DESC);

COMMENT ON COLUMN silver.fato_evento.origem_deteccao IS
  'API = alerta emitido pelo fornecedor. DERIVADO = calculado por nos a partir '
  'da posicao. Manter os dois durante o periodo de validacao paralela permite '
  'reconciliar; depois o API pode ser desligado.';

-- ----------------------------------------------------------------------------
-- 3. Derivacao a partir das posicoes
--    Uma posicao acima do limite = um evento (regra validada contra a 3S).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION silver.fn_deriva_eventos_velocidade(
    p_de  DATE DEFAULT CURRENT_DATE - 1,
    p_ate DATE DEFAULT CURRENT_DATE
) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_linhas INT;
BEGIN
    INSERT INTO silver.fato_evento (
        fonte, origem_deteccao, tipo_evento, id_externo,
        placa, id_equipamento, data_evento, velocidade, limite_kmh,
        latitude, longitude, endereco, bairro, cidade, uf)
    SELECT '3S', 'DERIVADO', 'EXCESSO_VELOCIDADE', p.id_posicao,
           upper(regexp_replace(coalesce(v.placa,''), '[\s-]', '', 'g')),
           p.id_equipamento,
           to_timestamp(p.data_gps, 'DD/MM/YYYY HH24:MI:SS'),
           replace(p.velocidade, ',', '.')::numeric,
           lim.limite,
           nullif(replace(p.latitude , ',', '.'), '')::numeric,
           nullif(replace(p.longitude, ',', '.'), '')::numeric,
           p.endereco, nullif(p.bairro,''), p.cidade, p.uf
      FROM bronze.tres_s_posicoes p
      JOIN bronze.tres_s_veiculos v ON v.id_equipamento = p.id_equipamento
      -- A classificacao usada na regua vem do BLUEFLEET (grupo_veiculo), nao do
      -- campo Tipo da 3S. Medido em 20/08/2026: o Tipo da 3S traz "Passeio" em
      -- 3.153 dos 3.170 veiculos — e campo com valor padrao, nao classificacao.
      -- O grupo_veiculo distingue Leve/Medio/Pesado/Toco/Bitruck/Truck/3-4/Moto,
      -- que e como a operacao realmente pensa a frota. O Tipo fica so como
      -- reserva para veiculo que exista na 3S mas nao na dimensao do Bluefleet.
      -- Dimensao da frota INTEIRA, nao o recorte Gritsch (silver.dim_veiculo).
      -- Corrigido em 21/08/2026: com o recorte, veiculo de outra filial ficava
      -- sem grupo_veiculo e caia na regua GLOBAL em vez da regua da classe
      -- dele — um caminhao de outra filial seria avaliado a 130 em vez de 100.
      -- O relatorio de telemetria e da empresa (~30 filiais).
      LEFT JOIN (
            SELECT upper(regexp_replace(coalesce(placa, ''), '[\s-]', '', 'g')) AS placa,
                   grupo_veiculo, filial_operacional
              FROM torre.gold_dim_veiculo
           ) d ON d.placa = upper(regexp_replace(coalesce(v.placa,''), '[\s-]', '', 'g'))
      CROSS JOIN LATERAL (
            SELECT silver.fn_limite_velocidade(
                     upper(regexp_replace(coalesce(v.placa,''), '[\s-]', '', 'g')),
                     COALESCE(d.grupo_veiculo, v.tipo),
                     d.filial_operacional,   -- habilita regua por filial, se um dia precisar
                     p.data_ref) AS limite
      ) lim
     WHERE p.data_ref BETWEEN p_de AND p_ate
       AND p.velocidade IS NOT NULL
       AND lim.limite IS NOT NULL
       AND replace(p.velocidade, ',', '.')::numeric > lim.limite
    ON CONFLICT (fonte, origem_deteccao, tipo_evento, id_externo) DO NOTHING;

    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RETURN v_linhas;
END; $$;

-- ----------------------------------------------------------------------------
-- 3b. Taxonomia canonica
--     Cada fonte nomeia o mesmo evento de um jeito. Sem esta traducao os
--     registros da API e os derivados nao se encontram na reconciliacao —
--     foi exatamente o que aconteceu no primeiro teste ('ALERTA_VELOCIDADE'
--     vs 'EXCESSO_VELOCIDADE'). Tambem substitui o LIKE '%excesso%' que o
--     relatorio faz hoje sobre o rotulo da Nuxeo.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.ref_tipo_evento (
    fonte        TEXT NOT NULL,
    tipo_origem  TEXT NOT NULL,
    tipo_canonico TEXT NOT NULL,
    PRIMARY KEY (fonte, tipo_origem)
);

INSERT INTO silver.ref_tipo_evento (fonte, tipo_origem, tipo_canonico) VALUES
    ('3S','ALERTA_VELOCIDADE','EXCESSO_VELOCIDADE'),
    ('3S','ALERTA_SENSOR',    'SENSOR'),
    ('3S','ALERTA_TEMPERATURA','TEMPERATURA'),
    ('3S','CERCA_ALVO',       'CERCA'),
    ('3S','CERCA_LOGRADOURO', 'CERCA'),
    ('3S','CERCA_POLIGONAL',  'CERCA'),
    ('3S','CERCA_ROTA',       'CERCA')
ON CONFLICT (fonte, tipo_origem) DO UPDATE SET tipo_canonico = EXCLUDED.tipo_canonico;

-- ----------------------------------------------------------------------------
-- 4. Ingestao dos alertas da API para o mesmo fato (validacao paralela)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION silver.fn_carrega_eventos_api(
    p_de DATE DEFAULT CURRENT_DATE - 7, p_ate DATE DEFAULT CURRENT_DATE
) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_linhas INT;
BEGIN
    INSERT INTO silver.fato_evento (
        fonte, origem_deteccao, tipo_evento, id_externo,
        placa, id_equipamento, data_evento, velocidade, limite_kmh,
        latitude, longitude, endereco, bairro, cidade, uf)
    SELECT '3S', 'API',
           -- A OCORRENCIA tem precedencia sobre o tipo do alerta.
           -- Descoberto em 21/08/2026: parte das cercas da 3S tem LIMITE DE
           -- VELOCIDADE proprio configurado (ex.: "Clementina X Curva Banana
           -- nao pavimentada Limite 60kmh"), e disparam com ocorrencia
           -- 'VELOCIDADE'. Isso e excesso de velocidade num trecho especifico,
           -- nao cruzamento de cerca — classificar como CERCA esconderia
           -- justamente o alerta mais util que a 3S produz.
           CASE WHEN upper(coalesce(e.ocorrencia,'')) = 'VELOCIDADE'
                     THEN 'EXCESSO_VELOCIDADE'
                ELSE COALESCE(tx.tipo_canonico, e.tipo_evento)
           END,
           e.id_ocorrencia_alerta::text,
           upper(regexp_replace(coalesce(v.placa,''), '[\s-]', '', 'g')),
           e.id_equipamento,
           to_timestamp(e.data_evento, 'DD/MM/YYYY HH24:MI:SS'),
           nullif(replace(e.velocidade, ',', '.'), '')::numeric,
           nullif(replace(e.velocidade_limite, ',', '.'), '')::numeric,
           nullif(replace(e.latitude , ',', '.'), '')::numeric,
           nullif(replace(e.longitude, ',', '.'), '')::numeric,
           e.endereco, nullif(e.bairro,''), e.cidade, e.uf
      FROM bronze.tres_s_eventos e
      LEFT JOIN bronze.tres_s_veiculos v ON v.id_equipamento = e.id_equipamento
      LEFT JOIN silver.ref_tipo_evento tx
             ON tx.fonte = '3S' AND tx.tipo_origem = e.tipo_evento
     WHERE to_timestamp(e.data_evento,'DD/MM/YYYY HH24:MI:SS')::date BETWEEN p_de AND p_ate
    ON CONFLICT (fonte, origem_deteccao, tipo_evento, id_externo) DO NOTHING;

    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RETURN v_linhas;
END; $$;

-- ----------------------------------------------------------------------------
-- 5. Reconciliacao — compara o que derivamos com o que a 3S emitiu.
--    Enquanto os dois rodarem em paralelo, esta view e o teste de aceite.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW silver.vw_reconciliacao_eventos AS
SELECT data_evento::date                                        AS dia,
       placa,
       count(*) FILTER (WHERE origem_deteccao = 'API')           AS alertas_3s,
       count(*) FILTER (WHERE origem_deteccao = 'DERIVADO')      AS derivados,
       count(*) FILTER (WHERE origem_deteccao = 'DERIVADO')
         - count(*) FILTER (WHERE origem_deteccao = 'API')       AS diferenca
  FROM silver.fato_evento
 WHERE tipo_evento = 'EXCESSO_VELOCIDADE'
 GROUP BY 1, 2;

COMMENT ON VIEW silver.vw_reconciliacao_eventos IS
  'diferenca = 0 significa que a regra propria reproduz o alerta do fornecedor. '
  'Positiva e o esperado na frota sem alerta configurado na 3S (99% dos veiculos).';
