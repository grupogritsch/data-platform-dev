-- ============================================================================
-- MIGRACAO ONE-OFF — SOAP (data_export.asmx) -> REST (DataExportAPI)
-- Rodar UMA VEZ, em 04/08/2026, antes de reaplicar 10_3s_controle.sql a
-- 14_3s_ultima_posicao.sql (nas suas versoes atuais, ja reescritas para REST).
--
-- POR QUE ISTO E SEGURO: todas as tabelas abaixo tem ZERO linhas reais de
-- producao. A unica execucao completa que chegou a rodar (workflow 3S - 10,
-- SOAP) bateu num bug de gzip nao descompactado e gravou so 4 linhas de LIXO
-- em bronze.tres_s_raw_response (JSON serializado de um objeto interno do
-- Node.js, nao XML de verdade) — nada com valor a preservar. As demais
-- tabelas (veiculos, eventos, posicoes, ultima_posicao) nunca chegaram a
-- carregar nada por causa desse mesmo bug.
--
-- O QUE NAO E TOCADO: nada em silver.* (fato_evento, ref_tipo_evento,
-- ref_limite_velocidade, fn_deriva_eventos_velocidade, etc.) — nenhuma dessas
-- pecas depende do protocolo SOAP vs REST, so dos NOMES DE COLUNA do bronze,
-- que nao mudaram. Nada em torre.* nem no dominio do Gestao-rastreadores.
--
-- Apos rodar este script, reaplique NESTA ORDEM:
--   postgres/sql/bronze/10_3s_controle.sql
--   postgres/sql/bronze/11_3s_veiculos.sql
--   postgres/sql/bronze/12_3s_eventos.sql
--   postgres/sql/bronze/13_3s_posicoes.sql
--   postgres/sql/bronze/14_3s_ultima_posicao.sql
-- ============================================================================

-- Tabelas de dado (a de posicoes e particionada — CASCADE remove as particoes
-- tres_s_posicoes_YYYYMMDD junto)
DROP TABLE IF EXISTS bronze.tres_s_posicoes        CASCADE;
DROP TABLE IF EXISTS bronze.tres_s_ultima_posicao  CASCADE;
DROP TABLE IF EXISTS bronze.tres_s_eventos         CASCADE;
DROP TABLE IF EXISTS bronze.tres_s_veiculos        CASCADE;
DROP TABLE IF EXISTS bronze.tres_s_raw_response    CASCADE;
DROP TABLE IF EXISTS bronze.tres_s_watermark       CASCADE;

-- Controle SOAP-era que nunca chegou a ser usado pelos workflows entregues
-- (fila de fanout) ou que nao se aplica mais (catalogo de ~70 metodos SOAP —
-- a API REST tem 8, documentados, sem necessidade de catalogo)
DROP TABLE IF EXISTS bronze.tres_s_ingest_job      CASCADE;
DROP TABLE IF EXISTS bronze.tres_s_metodo          CASCADE;
DROP VIEW  IF EXISTS bronze.vw_3s_ingest_status    CASCADE;

-- Funcoes (CASCADE ja teria derrubado o que dependia delas via view; isto
-- limpa as proprias funcoes, que CREATE OR REPLACE nao remove sozinho se a
-- assinatura mudar)
DROP FUNCTION IF EXISTS bronze.fn_avanca_watermark(text, bigint, bigint)   CASCADE;
DROP FUNCTION IF EXISTS bronze.fn_carrega_veiculos(jsonb, bigint)         CASCADE;
DROP FUNCTION IF EXISTS bronze.fn_carrega_eventos(jsonb, text, bigint)   CASCADE;
DROP FUNCTION IF EXISTS bronze.fn_carrega_posicoes(jsonb, text, bigint) CASCADE;
DROP FUNCTION IF EXISTS bronze.fn_garante_particao_posicao(date)         CASCADE;
DROP FUNCTION IF EXISTS bronze.fn_expurga_posicoes(int)                  CASCADE;
DROP FUNCTION IF EXISTS bronze.fn_carrega_ultima_posicao(jsonb, bigint) CASCADE;
