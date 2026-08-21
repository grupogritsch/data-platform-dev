-- ============================================================================
-- SILVER — EVENTOS DA NUXEO  (Suntech / Omnilink)
--
-- Fecha o buraco encontrado em 20/08/2026: silver.fato_evento tinha SO os
-- eventos derivados da 3S. Os 214 mil registros de bronze.nuxeo_posicao_eventos
-- e os alertas da API da 3S (bronze.tres_s_eventos) nunca entravam no silver —
-- nao havia carregador para a Nuxeo, e a funcao da 3S existia mas nenhum
-- workflow a chamava.
--
-- CONTRATO CONFIRMADO contra dado real em 20/08/2026:
--   bronze.nuxeo_posicao_eventos.eventos_json e um ARRAY de objetos com
--   exatamente tres chaves:
--       { "speed": "0", "dateEvent": "19/08/2026 23:50:54",
--         "nameEvent": "Perda de conexao de rede" }
--
-- DUAS ARMADILHAS MEDIDAS NO DADO REAL:
--
-- 1. DUPLICACAO DE ~17x. A Nuxeo devolve a JANELA RECENTE de eventos do
--    veiculo a cada snapshot, entao o mesmo evento reaparece em ~17 linhas
--    diferentes. Medido: 11.941 entradas de "Modo de direcao ativo" para 687
--    eventos unicos. Dos 72.477 registros no array, so ~4.200 sao eventos de
--    verdade. Sem deduplicar, todo numero do relatorio sairia 17x inflado.
--    Chave natural adotada: (placa, dateEvent, nameEvent).
--
-- 2. O EVENTO NAO TRAZ POSICAO. Cada item do array so tem velocidade, data e
--    nome. A latitude/longitude da LINHA e a posicao do veiculo no momento do
--    SNAPSHOT, que pode ser horas depois do evento — usa-la direto colocaria o
--    evento no lugar errado. Solucao: entre as ~17 linhas que contem o mesmo
--    evento, escolhe-se a de data_gps MAIS PROXIMA do dateEvent. E uma
--    aproximacao, nao a posicao exata, e esta documentado como tal.
--
-- Idempotente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Categoria do evento
--
--    A Nuxeo mistura alerta de seguranca (excesso de velocidade) com telemetria
--    operacional (ignicao ligada/desligada, modo de estacionamento). Sao ~11 mil
--    entradas de ignicao contra ~9 mil de velocidade: sem separar, o operacional
--    afoga o que importa em qualquer relatorio.
--
--    Guardamos os dois — o silver nao descarta — mas rotulados, para o consumo
--    filtrar com um WHERE simples em vez de listar nome por nome.
-- ----------------------------------------------------------------------------
ALTER TABLE silver.ref_tipo_evento
    ADD COLUMN IF NOT EXISTS categoria TEXT NOT NULL DEFAULT 'OPERACIONAL';

ALTER TABLE silver.ref_tipo_evento
    DROP CONSTRAINT IF EXISTS ck_ref_tipo_evento_categoria;
ALTER TABLE silver.ref_tipo_evento
    ADD CONSTRAINT ck_ref_tipo_evento_categoria
    CHECK (categoria IN ('SEGURANCA', 'OPERACIONAL'));

COMMENT ON COLUMN silver.ref_tipo_evento.categoria IS
  'SEGURANCA = merece acao (velocidade, sensor, cerca). OPERACIONAL = estado do '
  'veiculo/rastreador (ignicao, estacionamento, perda de conexao). O relatorio '
  'de telemetria consome SEGURANCA; o painel de rastreadores usa OPERACIONAL '
  'para saber quem parou de comunicar.';

-- Tipos da 3S: seguranca, EXCETO cerca.
--
-- Bug real (21/08/2026): aqui havia um UPDATE ... WHERE fonte = '3S' sem
-- ressalva, que marcava TUDO como seguranca. Ele desfazia, a cada reaplicacao
-- do arquivo, a decisao de negocio de tratar cerca como operacional — e as 381
-- cercas voltavam para o relatorio sem ninguem pedir. Script que sobrescreve
-- decisao do usuario e armadilha: o efeito so aparece muito depois.
--
-- Decisao registrada em 21/08/2026: cruzamento de cerca NAO e evento olhado
-- hoje, porque a configuracao das cercas na 3S nao esta revisada. Fica como
-- operacional. O que havia de valioso ali (os excessos de velocidade nos
-- trechos com "Limite 60kmh" no nome) ja foi resgatado antes, pela regra de
-- ocorrencia='VELOCIDADE' em fn_carrega_eventos_api.
--
-- Para reverter quando a configuracao for revisada (as cercas de "Risco
-- Fronteira" provavelmente merecem voltar):
--     UPDATE silver.ref_tipo_evento SET categoria = 'SEGURANCA'
--      WHERE tipo_canonico = 'CERCA';
UPDATE silver.ref_tipo_evento SET categoria = 'SEGURANCA'
 WHERE fonte = '3S' AND tipo_canonico <> 'CERCA';

UPDATE silver.ref_tipo_evento SET categoria = 'OPERACIONAL'
 WHERE fonte = '3S' AND tipo_canonico = 'CERCA';

-- ----------------------------------------------------------------------------
-- 2. Taxonomia da Nuxeo
--
--    IMPORTANTE: a Nuxeo ja tem alerta de velocidade CONFIGURADO POR CLASSE
--    ("Vans", "Caminhoes", "Leves"). Os tres viram EXCESSO_VELOCIDADE aqui,
--    porque a classe do veiculo ja vive em silver.dim_veiculo.grupo_veiculo —
--    guardar a classe no nome do evento seria duplicar dimensao dentro do fato.
--    O nome original fica preservado em tipo_origem para auditoria.
--
--    ATENCAO: nao sabemos quais LIMITES a Nuxeo usa nesses alertas. Se forem
--    diferentes dos configurados em silver.ref_limite_velocidade para a 3S, o
--    relatorio vai comparar reguas diferentes. Conferir na plataforma da Nuxeo.
-- ----------------------------------------------------------------------------
INSERT INTO silver.ref_tipo_evento (fonte, tipo_origem, tipo_canonico, categoria) VALUES
    ('NUXEO', 'Vans Excesso Velocidade',       'EXCESSO_VELOCIDADE',   'SEGURANCA'),
    ('NUXEO', 'Caminhões Excesso Velocidade',  'EXCESSO_VELOCIDADE',   'SEGURANCA'),
    ('NUXEO', 'Leves Excesso Velocidade',      'EXCESSO_VELOCIDADE',   'SEGURANCA'),
    ('NUXEO', 'Entrou em modo reboque',        'MODO_REBOQUE',         'SEGURANCA'),
    ('NUXEO', 'Ignição Ligada',                'IGNICAO_LIGADA',       'OPERACIONAL'),
    ('NUXEO', 'Ignição Desligada',             'IGNICAO_DESLIGADA',    'OPERACIONAL'),
    ('NUXEO', 'Modo de direção ativo',         'MODO_DIRECAO',         'OPERACIONAL'),
    ('NUXEO', 'Modo de estacionamento ativo',  'MODO_ESTACIONAMENTO',  'OPERACIONAL'),
    ('NUXEO', 'Perda de conexão de rede',      'PERDA_CONEXAO',        'OPERACIONAL'),
    ('NUXEO', 'Alerta de correção de GPS',     'CORRECAO_GPS',         'OPERACIONAL'),
    ('NUXEO', 'Dispositivo parado',            'DISPOSITIVO_PARADO',   'OPERACIONAL')
ON CONFLICT (fonte, tipo_origem) DO UPDATE
   SET tipo_canonico = EXCLUDED.tipo_canonico,
       categoria     = EXCLUDED.categoria;

-- ----------------------------------------------------------------------------
-- 3. Carga dos eventos da Nuxeo
--
--    p_de/p_ate filtram pela data do EVENTO (nao a da ingestao), porque o mesmo
--    evento aparece em snapshots de varios dias.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION silver.fn_carrega_eventos_nuxeo(
    p_de  DATE DEFAULT CURRENT_DATE - 7,
    p_ate DATE DEFAULT CURRENT_DATE
) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_linhas INT;
BEGIN
    INSERT INTO silver.fato_evento (
        fonte, origem_deteccao, tipo_evento, id_externo,
        placa, id_equipamento, data_evento, velocidade, limite_kmh,
        latitude, longitude, endereco, bairro, cidade, uf)
    SELECT DISTINCT ON (e.placa_norm, e.data_evt, e.nome_evt)
           'NUXEO',
           'API',
           COALESCE(tx.tipo_canonico, 'NAO_MAPEADO'),
           -- chave natural: placa + instante + nome do evento
           e.placa_norm || '|' || to_char(e.data_evt, 'YYYYMMDDHH24MISS') || '|' || e.nome_evt,
           e.placa_norm,
           e.serial,
           e.data_evt,
           e.velocidade,
           NULL,              -- a Nuxeo nao informa qual limite disparou o alerta
           e.latitude, e.longitude, e.endereco, NULL, e.cidade, e.estado
      FROM (
            SELECT upper(regexp_replace(coalesce(t.placa,''), '[\s-]', '', 'g')) AS placa_norm,
                   t.serial,
                   to_timestamp(evt->>'dateEvent', 'DD/MM/YYYY HH24:MI:SS')      AS data_evt,
                   evt->>'nameEvent'                                             AS nome_evt,
                   nullif(evt->>'speed', '')::numeric                            AS velocidade,
                   t.latitude, t.longitude, t.endereco, t.cidade, t.estado,
                   -- distancia no tempo entre o snapshot e o evento; usada so
                   -- para escolher a linha cuja posicao melhor aproxima o local
                   abs(extract(epoch FROM
                        to_timestamp(t.data_gps, 'DD/MM/YYYY HH24:MI:SS')
                      - to_timestamp(evt->>'dateEvent', 'DD/MM/YYYY HH24:MI:SS')))
                                                                                 AS dist_seg
              FROM bronze.nuxeo_posicao_eventos t,
                   LATERAL jsonb_array_elements(t.eventos_json) evt
             WHERE t.eventos_json IS NOT NULL
               AND jsonb_typeof(t.eventos_json) = 'array'
               AND evt->>'dateEvent' IS NOT NULL
               AND evt->>'nameEvent' IS NOT NULL
           ) e
      LEFT JOIN silver.ref_tipo_evento tx
             ON tx.fonte = 'NUXEO' AND tx.tipo_origem = e.nome_evt
     WHERE e.placa_norm <> ''
       AND e.data_evt::date BETWEEN p_de AND p_ate
     -- DISTINCT ON resolve a duplicacao de ~17x; o ORDER BY escolhe, entre as
     -- copias, a do snapshot temporalmente mais proximo do evento.
     ORDER BY e.placa_norm, e.data_evt, e.nome_evt, e.dist_seg NULLS LAST
    ON CONFLICT (fonte, origem_deteccao, tipo_evento, id_externo) DO NOTHING;

    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RETURN v_linhas;
END; $$;

COMMENT ON FUNCTION silver.fn_carrega_eventos_nuxeo IS
  'Deduplica o array de eventos da Nuxeo (que repete cada evento ~17x, um por '
  'snapshot) pela chave (placa, dateEvent, nameEvent). A posicao gravada e a do '
  'snapshot mais proximo no tempo — APROXIMACAO, nao o local exato do evento, '
  'porque o evento em si nao traz coordenada.';

-- ----------------------------------------------------------------------------
-- 4. Visao pronta para o relatorio de telemetria
--    Junta as tres origens ja filtradas por seguranca e resolvidas contra a
--    dimensao de veiculo.
-- ----------------------------------------------------------------------------
-- A dimensao usada aqui e torre.gold_dim_veiculo (frota INTEIRA, ~21.947
-- veiculos), NAO silver.dim_veiculo.
--
-- Erro real encontrado em 21/08/2026: a view juntava com silver.dim_veiculo,
-- que e o recorte Gritsch (792 veiculos, filial ILIKE '%GRI%'). Como os
-- eventos da API da 3S vem da frota toda, 19 de cada 20 linhas sairam com
-- modelo/grupo/filial NULOS — relatorio sem dimensao nao serve para nada.
-- O relatorio de telemetria e da EMPRESA (~30 filiais); o recorte Gritsch
-- pertence ao painel de rastreadores, que e outro consumidor.
--
-- A coluna escopo_gritsch continua disponivel para quem quiser filtrar.
CREATE OR REPLACE VIEW silver.vw_eventos_seguranca AS
SELECT e.*,
       d.modelo_raw          AS modelo,
       d.grupo_veiculo,
       d.filial_operacional,
       d.situacao_veiculo,
       (d.filial_operacional ILIKE '%GRI%')                AS escopo_gritsch,
       (d.placa IS NULL)                                   AS sem_cadastro
  FROM silver.fato_evento e
  LEFT JOIN (
        -- placa normalizada do mesmo jeito que em silver.dim_veiculo, para o
        -- join casar com a placa ja normalizada de silver.fato_evento
        SELECT upper(regexp_replace(coalesce(placa, ''), '[\s-]', '', 'g')) AS placa,
               modelo_raw, grupo_veiculo, filial_operacional, situacao_veiculo
          FROM torre.gold_dim_veiculo
       ) d ON d.placa = e.placa
 -- EXISTS e nao JOIN: varios tipo_origem mapeiam para o MESMO tipo_canonico
 -- (CERCA_ALVO, CERCA_LOGRADOURO, CERCA_POLIGONAL e CERCA_ROTA viram 'CERCA'),
 -- entao um JOIN por tipo_canonico multiplicaria cada evento de cerca por 4.
 -- EXISTS filtra sem poder duplicar linha.
 WHERE EXISTS (
        SELECT 1 FROM silver.ref_tipo_evento tx
         WHERE tx.fonte         = e.fonte
           AND tx.tipo_canonico = e.tipo_evento
           AND tx.categoria     = 'SEGURANCA')
   -- CONTAGEM DUPLA: excesso de velocidade chega por DOIS caminhos — o alerta
   -- configurado no fornecedor ('API') e a nossa derivacao a partir da posicao
   -- ('DERIVADO'). O mesmo excesso pode existir nos dois, e o relatorio somaria
   -- duas vezes.
   --
   -- O relatorio usa so o DERIVADO, porque e a unica versao que:
   --   - aplica a MESMA regua as duas fontes (as do fornecedor divergiam:
   --     Nuxeo 105/130/140 contra as nossas 100/120/130)
   --   - cobre 100% da frota, nao so os veiculos que alguem configurou
   --   - continua funcionando quando o fornecedor desliga o alerta, como a
   --     Nuxeo fez entre 27/07 e 07/08/2026
   --
   -- Os alertas 'API' continuam em silver.fato_evento para reconciliacao e
   -- auditoria — so nao alimentam o relatorio.
   AND NOT (e.tipo_evento = 'EXCESSO_VELOCIDADE' AND e.origem_deteccao = 'API');

COMMENT ON VIEW silver.vw_eventos_seguranca IS
  'Eventos que merecem acao, das tres origens (3S derivado, 3S API, Nuxeo), '
  'resolvidos contra a frota INTEIRA do Bluefleet. escopo_gritsch marca o '
  'recorte da locadora; sem_cadastro marca evento cujo veiculo nao existe na '
  'dimensao (placa suja na origem, ex.: chassi no lugar da placa).';

COMMENT ON VIEW silver.vw_eventos_seguranca IS
  'Eventos que merecem acao, das tres origens (3S derivado, 3S API, Nuxeo), '
  'ja com modelo/grupo/filial. Base do relatorio de telemetria. O operacional '
  '(ignicao, estacionamento) fica de fora — consulte silver.fato_evento direto '
  'se precisar dele.';
