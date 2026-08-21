-- ============================================================================
-- SILVER — TETO DE PLAUSIBILIDADE DE VELOCIDADE
--
-- POR QUE EXISTE (medido em 21/08/2026):
--
-- Um rastreador defeituoso reportava velocidades fisicamente impossiveis:
--     BDU6J33  VW 9-170 DELIVERY   29 eventos, 10 acima de 150, MAXIMA 233 km/h
--     BDE1E73  CARGO 816            1 evento,   1 acima de 150, MAXIMA 255 km/h
-- Caminhao leve nao faz 233 km/h. Sozinho, o BDU6J33 respondia por 78% dos
-- eventos da classe Toco e por 10 das 11 leituras impossiveis.
--
-- Distribuicao medida, que fundamenta os tetos abaixo:
--     Leve     161 eventos,  29 acima de 150,  0 acima de 180   (plausivel: carro faz)
--     Medio    134,           9 acima de 150,  0 acima de 180   (plausivel)
--     Pesado   104,           0 acima de 150                    (maxima real 148)
--     Bitruck   76,           0                                 (maxima real 120)
--     Truck     39,           0                                 (maxima real 110)
--     Toco      37,          11 acima de 150,  5 acima de 180   (SO esta classe)
--
-- ATENCAO — ISTO NAO SUBSTITUI MANUTENCAO. Um rastreador que reporta 233 km/h
-- tambem nao e confiavel quando reporta 105: TODOS os eventos do BDU6J33 sao
-- suspeitos, nao so os gritantes. A marcacao evita que numero impossivel chegue
-- ao relatorio da diretoria; consertar o equipamento e o que resolve.
--
-- MARCA, nao apaga: o registro continua em silver.fato_evento e visivel na
-- view, com a flag. Filtrar em silencio esconderia o defeito — e e justamente
-- olhando esses registros que se descobre qual rastreador precisa de reparo.
--
-- Idempotente.
-- ============================================================================

-- Teto por escopo, na MESMA tabela e com a MESMA precedencia da regua de
-- velocidade (PLACA > FILIAL > TIPO > GLOBAL), para nao inventar um segundo
-- lugar de configuracao.
ALTER TABLE silver.ref_limite_velocidade
    ADD COLUMN IF NOT EXISTS teto_plausivel_kmh NUMERIC(5,1);

COMMENT ON COLUMN silver.ref_limite_velocidade.teto_plausivel_kmh IS
  'Acima disto a leitura e considerada fisicamente impossivel para a classe e '
  'marcada como suspeita no relatorio. NULL = sem teto.';

-- Tetos com folga sobre a maxima real observada em cada classe, para nao
-- marcar comportamento legitimo. O caso do Leve e o mais delicado: ha 29
-- eventos entre 150 e 174 que sao REAIS (verificado posicao a posicao num
-- Polo a 174 km/h na BR-080), por isso o teto e 200 e nao 150.
UPDATE silver.ref_limite_velocidade SET teto_plausivel_kmh = 150
 WHERE escopo = 'TIPO' AND chave IN ('Toco', 'Truck', 'Bitruck', '3/4');

UPDATE silver.ref_limite_velocidade SET teto_plausivel_kmh = 170
 WHERE escopo = 'TIPO' AND chave = 'Pesado';

UPDATE silver.ref_limite_velocidade SET teto_plausivel_kmh = 200
 WHERE escopo = 'GLOBAL';

-- Resolucao do teto, espelhando fn_limite_velocidade
CREATE OR REPLACE FUNCTION silver.fn_teto_plausivel(
    p_placa TEXT, p_tipo TEXT, p_filial TEXT, p_data DATE
) RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT l.teto_plausivel_kmh
      FROM silver.ref_limite_velocidade l
     WHERE l.vigente_de <= p_data
       AND (l.vigente_ate IS NULL OR l.vigente_ate >= p_data)
       AND l.teto_plausivel_kmh IS NOT NULL
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
-- View do relatorio, agora com a marcacao
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW silver.vw_eventos_seguranca AS
SELECT e.*,
       d.modelo_raw          AS modelo,
       d.grupo_veiculo,
       d.filial_operacional,
       d.situacao_veiculo,
       (d.filial_operacional ILIKE '%GRI%')  AS escopo_gritsch,
       (d.placa IS NULL)                     AS sem_cadastro,
       -- Leitura acima do teto fisico da classe. O relatorio deve EXCLUIR
       -- estas linhas do numero que vai para a diretoria, e usa-las para
       -- gerar a lista de rastreadores a inspecionar.
       (e.velocidade > silver.fn_teto_plausivel(
            e.placa, d.grupo_veiculo, d.filial_operacional, e.data_evento::date))
                                             AS velocidade_implausivel
  FROM silver.fato_evento e
  LEFT JOIN (
        SELECT upper(regexp_replace(coalesce(placa, ''), '[\s-]', '', 'g')) AS placa,
               modelo_raw, grupo_veiculo, filial_operacional, situacao_veiculo
          FROM torre.gold_dim_veiculo
       ) d ON d.placa = e.placa
 WHERE EXISTS (
        SELECT 1 FROM silver.ref_tipo_evento tx
         WHERE tx.fonte         = e.fonte
           AND tx.tipo_canonico = e.tipo_evento
           AND tx.categoria     = 'SEGURANCA')
   -- Ver 21_eventos_nuxeo.sql: excesso de velocidade so pelo DERIVADO, para
   -- nao contar duas vezes o que o fornecedor tambem alertou.
   AND NOT (e.tipo_evento = 'EXCESSO_VELOCIDADE' AND e.origem_deteccao = 'API');

COMMENT ON VIEW silver.vw_eventos_seguranca IS
  'Base do relatorio de telemetria: eventos de seguranca das tres origens, com '
  'regua unica por classe. Use velocidade_implausivel = false para o numero '
  'oficial; = true para a lista de rastreadores suspeitos de defeito.';

-- ----------------------------------------------------------------------------
-- Lista de rastreadores a inspecionar — o produto acionavel desta analise
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW silver.vw_rastreadores_suspeitos AS
SELECT placa, modelo, grupo_veiculo, filial_operacional, fonte,
       count(*)                                              AS eventos_total,
       count(*) FILTER (WHERE velocidade_implausivel)        AS leituras_impossiveis,
       max(velocidade)                                       AS velocidade_maxima,
       min(data_evento)::date                                AS desde,
       max(data_evento)::date                                AS ate
  FROM silver.vw_eventos_seguranca
 WHERE tipo_evento = 'EXCESSO_VELOCIDADE'
 GROUP BY 1,2,3,4,5
HAVING count(*) FILTER (WHERE velocidade_implausivel) > 0
 ORDER BY 7 DESC;

COMMENT ON VIEW silver.vw_rastreadores_suspeitos IS
  'Veiculos com leitura de velocidade fisicamente impossivel — candidatos a '
  'chamado de manutencao. Em 21/08/2026: BDU6J33 (233 km/h num 9-170 Delivery) '
  'e BDE1E73 (255 km/h num Cargo 816).';
