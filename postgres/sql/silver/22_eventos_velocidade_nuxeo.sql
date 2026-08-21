-- ============================================================================
-- SILVER — EXCESSO DE VELOCIDADE DERIVADO DAS POSICOES DA NUXEO
--
-- POR QUE ISTO EXISTE (medido em 21/08/2026):
--
-- Os alertas de velocidade CONFIGURADOS na plataforma da Nuxeo pararam de
-- chegar, cada um numa data diferente:
--     Caminhoes Excesso Velocidade  -> ultimo em 27/07
--     Leves Excesso Velocidade      -> ultimo em 31/07
--     Vans Excesso Velocidade       -> ultimo em 07/08
-- Enquanto isso os eventos AUTOMATICOS do rastreador (ignicao, estacionamento,
-- perda de conexao) continuavam chegando normalmente no mesmo feed. Ou seja: a
-- integracao esta viva, o que sumiu foi a CONFIGURACAO do alerta do lado deles.
-- 25 dias sem um unico caminhao acima de 105 km/h numa frota que roda todo dia
-- nao e frota comportada, e alerta desligado.
--
-- E a MESMA licao que motivou a virada na 3S: alerta configurado no fornecedor
-- e fragil, porque depende de alguem nao mexer. Derivar da posicao nos da:
--   - independencia da configuracao de terceiros
--   - REGUA UNICA (silver.ref_limite_velocidade) para 3S e Nuxeo. As reguas
--     medidas na Nuxeo eram 105/130/140 contra as nossas 100/120/130 — veiculo
--     igual aparecia diferente conforme quem rastreava
--   - cobertura de 100% dos veiculos, nao so os que alguem configurou
--
-- FONTE: bronze.nuxeo_posicao_eventos (219.149 posicoes, 260 veiculos,
-- 02/07 a 21/08, 3.070 acima de 100 km/h).
--
-- Idempotente.
-- ============================================================================

CREATE OR REPLACE FUNCTION silver.fn_deriva_eventos_velocidade_nuxeo(
    p_de  DATE DEFAULT CURRENT_DATE - 1,
    p_ate DATE DEFAULT CURRENT_DATE
) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_linhas INT;
BEGIN
    INSERT INTO silver.fato_evento (
        fonte, origem_deteccao, tipo_evento, id_externo,
        placa, id_equipamento, data_evento, velocidade, limite_kmh,
        latitude, longitude, endereco, bairro, cidade, uf)
    -- DISTINCT ON: a mesma posicao (placa + instante do GPS) pode aparecer em
    -- mais de uma linha, porque a tabela guarda um snapshot por coleta. Sem
    -- isto o mesmo excesso viraria varios eventos.
    SELECT DISTINCT ON (p.pn, p.dt)
           'NUXEO', 'DERIVADO', 'EXCESSO_VELOCIDADE',
           -- chave natural: placa + instante. Nao ha idPosicao na Nuxeo.
           p.pn || '|' || to_char(p.dt, 'YYYYMMDDHH24MISS'),
           p.pn,
           p.serial,
           p.dt,
           p.velocidade,
           lim.limite,
           p.latitude, p.longitude, p.endereco, NULL, p.cidade, p.estado
      FROM (
            SELECT n.*,
                   upper(regexp_replace(coalesce(n.placa, ''), '[\s-]', '', 'g')) AS pn,
                   to_timestamp(n.data_gps, 'DD/MM/YYYY HH24:MI:SS')              AS dt
              FROM bronze.nuxeo_posicao_eventos n
             WHERE n.data_gps ~ '^\d{2}/\d{2}/\d{4}'
               AND n.velocidade IS NOT NULL
           ) p
      -- Dimensao da frota INTEIRA (nao o recorte Gritsch): o relatorio de
      -- telemetria e da empresa. E daqui que sai o grupo_veiculo que resolve
      -- a regua — o mesmo criterio aplicado na derivacao da 3S.
      LEFT JOIN (
            SELECT upper(regexp_replace(coalesce(placa, ''), '[\s-]', '', 'g')) AS placa,
                   grupo_veiculo, filial_operacional
              FROM torre.gold_dim_veiculo
           ) d ON d.placa = p.pn
      CROSS JOIN LATERAL (
            SELECT silver.fn_limite_velocidade(
                     p.pn, d.grupo_veiculo, d.filial_operacional, p.dt::date) AS limite
      ) lim
     WHERE p.pn <> ''
       AND p.dt::date BETWEEN p_de AND p_ate
       AND lim.limite IS NOT NULL
       AND p.velocidade > lim.limite
     ORDER BY p.pn, p.dt, p.ingested_at DESC
    ON CONFLICT (fonte, origem_deteccao, tipo_evento, id_externo) DO NOTHING;

    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RETURN v_linhas;
END; $$;

COMMENT ON FUNCTION silver.fn_deriva_eventos_velocidade_nuxeo IS
  'Excesso de velocidade derivado das posicoes da Nuxeo, com a MESMA regua da '
  '3S (silver.ref_limite_velocidade por grupo_veiculo). Substitui os alertas '
  'configurados na plataforma da Nuxeo, que pararam entre 27/07 e 07/08/2026 '
  'e usavam limites diferentes dos nossos (105/130/140 contra 100/120/130).';
