-- ============================================================================
-- GOLD — torre.vw_alertas_telemetria_saneados  (REDEFINIDA)
--
-- POR QUE REDEFINIR (21/08/2026):
--
-- A versao anterior desta view fazia a propria unificacao de 3S + Nuxeo, com
-- a regua EMBUTIDA no codigo:
--     caminhoes (Bitruck/Truck/Toco/3/4) -> velocidade > 90
--     demais                             -> velocidade > 110
-- e teto de sanidade fixo em 160 (120 para caminhao).
--
-- Isso passou a concorrer com silver.vw_eventos_seguranca, que faz a mesma
-- unificacao mas com a regua CONFIGURAVEL em silver.ref_limite_velocidade
-- (Caminhao 100 / Van-Pesado 120 / Leve-Medio 130, decidida em 21/08/2026).
--
-- Duas logicas concorrentes e o pior dos mundos: alguem ajusta a regua na
-- tabela de configuracao, reprocessa o historico, e o relatorio nao muda —
-- porque le a outra. Esta view passa a ser uma CASCA sobre o silver.
--
-- O CONTRATO DE COLUNAS E IDENTICO ao da versao anterior, de proposito: o
-- workflow "Torre de Controle - Alertas Telemetria" continua funcionando sem
-- alterar um unico node.
--
-- O QUE SE GANHA:
--   - regua configuravel, com recalculo retroativo do historico
--   - a frota da 3S entra no relatorio (motivo original do projeto)
--   - deteccao independente da configuracao de alerta do fornecedor, que a
--     Nuxeo desligou entre 27/07 e 07/08 sem avisar
--   - leitura fisicamente impossivel marcada por classe, nao por teto unico
--
-- O QUE FOI PRESERVADO DA VERSAO ANTERIOR (era boa ideia e nao existia no
-- nosso silver): excluir veiculo VENDIDO / BAIXADO / ROUBADO. Alerta de
-- veiculo que nao e mais da frota so gera ruido para o gestor.
--
-- POR QUE DROP E NAO "CREATE OR REPLACE" (22/08/2026):
--
-- CREATE OR REPLACE VIEW so aceita acrescentar coluna no fim. Nao aceita mudar
-- o TIPO de uma coluna existente — nem entre numeric e numeric(6,2), que para
-- o Postgres sao tipos distintos:
--     ERROR 42P16: cannot change data type of view column
--                  "velocidade_registrada" from numeric to numeric(6,2)
--
-- A view antiga montava a velocidade em expressao propria e saia como numeric
-- sem precisao. A nova le silver.fato_evento.velocidade, que e numeric(6,2).
--
-- Entao: DROP e CREATE, dentro de uma transacao. Se qualquer passo falhar, o
-- ROLLBACK devolve a view antiga intacta e o relatorio das 8h continua rodando.
-- O DROP e SEM CASCADE de proposito: se algum outro objeto do banco depender
-- desta view, o comando falha e diz o nome dele, em vez de destruir em silencio.
-- (O workflow do n8n so consulta por fora, nao e dependencia de catalogo.)
--
-- Idempotente.
-- ============================================================================

BEGIN;

DROP VIEW IF EXISTS torre.vw_alertas_telemetria_saneados;

CREATE VIEW torre.vw_alertas_telemetria_saneados AS
WITH provedor_nuxeo AS (
    -- A distincao Suntech/Omnilink so existe no campo "complemento" do bronze
    -- da Nuxeo ("ST8310 - GRIT-3745"). O silver nao a carrega, entao ela e
    -- recuperada aqui, uma vez por placa, para o badge de origem do e-mail
    -- continuar mostrando OMNILINK quando for o caso.
    SELECT DISTINCT ON (pn)
           upper(regexp_replace(coalesce(placa, ''), '[\s-]', '', 'g')) AS pn,
           CASE WHEN upper(coalesce(complemento, payload_json ->> 'complement', '')) LIKE '%OMNILINK%'
                THEN 'OMNILINK' ELSE 'NUXEO' END AS provedor
      FROM bronze.nuxeo_posicao_eventos
     WHERE placa IS NOT NULL
     ORDER BY pn, ingested_at DESC
)
SELECT
    e.placa,
    CASE WHEN e.fonte = '3S' THEN '3STEC'
         ELSE COALESCE(pv.provedor, 'NUXEO') END                       AS provedor_rastreador,
    e.velocidade                                                        AS velocidade_registrada,
    to_char(e.data_evento, 'DD/MM/YYYY HH24:MI:SS')                     AS data_hora_alerta,
    e.data_evento                                                       AS data_hora_timestamp,
    e.data_evento::date                                                 AS data_ref,
    e.latitude,
    e.longitude,
    e.endereco,
    e.cidade,
    e.uf                                                                AS estado,
    -- Nome amigavel, no espirito da versao anterior. O limite entra no texto
    -- porque o gestor pergunta "acima de quanto?" — e a resposta agora varia
    -- por classe de veiculo.
    CASE WHEN e.limite_kmh IS NOT NULL
         THEN 'Excesso de Velocidade (limite ' || e.limite_kmh::int || ' km/h)'
         ELSE 'Excesso de Velocidade' END                               AS nome_evento,
    COALESCE(e.filial_operacional, 'DESCONHECIDA')                      AS filial_operacional,
    COALESCE(e.modelo, '')                                              AS modelo,
    COALESCE(e.grupo_veiculo, 'Leve')                                   AS grupo_veiculo,
    COALESCE(e.situacao_veiculo, 'ATIVO')                               AS situacao_veiculo
  FROM silver.vw_eventos_seguranca e
  LEFT JOIN provedor_nuxeo pv ON pv.pn = e.placa AND e.fonte = 'NUXEO'
 WHERE e.tipo_evento = 'EXCESSO_VELOCIDADE'
   -- Leitura fisicamente impossivel: fica registrada no silver e alimenta
   -- silver.vw_rastreadores_suspeitos, mas nunca chega ao e-mail do gestor.
   AND NOT COALESCE(e.velocidade_implausivel, false)
   AND e.velocidade > 0
   -- Preservado da versao anterior desta view
   AND COALESCE(e.situacao_veiculo, '') NOT IN
       ('VENDIDO', 'BAIXADO', 'VEÍCULOS VENDIDOS', 'VEÍCULOS ROUBADOS');

COMMENT ON VIEW torre.vw_alertas_telemetria_saneados IS
  'Casca sobre silver.vw_eventos_seguranca, com o contrato de colunas da '
  'versao anterior preservado para o workflow "Torre de Controle - Alertas '
  'Telemetria" seguir funcionando sem alteracao. A regua de velocidade vive '
  'em silver.ref_limite_velocidade (configuravel, com recalculo retroativo), '
  'nao mais embutida aqui.';

COMMIT;

-- ============================================================================
-- CONFERENCIA (rodar depois do COMMIT)
--
-- 1) O contrato de 16 colunas que o workflow espera continua de pe?
--    Tem de devolver exatamente 16 linhas.
--
--    SELECT ordinal_position, column_name, data_type
--      FROM information_schema.columns
--     WHERE table_schema = 'torre'
--       AND table_name   = 'vw_alertas_telemetria_saneados'
--     ORDER BY ordinal_position;
--
-- 2) A frota da 3S entrou no relatorio? (era o objetivo do projeto —
--    antes este numero era zero)
--
--    SELECT provedor_rastreador, count(*) AS eventos,
--           count(DISTINCT placa) AS placas, max(velocidade_registrada) AS pico
--      FROM torre.vw_alertas_telemetria_saneados
--     GROUP BY 1 ORDER BY 2 DESC;
--
-- 3) A regua nova esta valendo? O texto do evento tem de mostrar
--    100 para caminhao, 120 para van/pesado e 130 para leve/medio.
--
--    SELECT grupo_veiculo, nome_evento, count(*)
--      FROM torre.vw_alertas_telemetria_saneados
--     GROUP BY 1,2 ORDER BY 1;
--
-- 4) Nenhuma leitura impossivel vazou para o e-mail:
--
--    SELECT count(*) FILTER (WHERE velocidade_registrada > 200) AS deve_ser_zero
--      FROM torre.vw_alertas_telemetria_saneados;
-- ============================================================================
