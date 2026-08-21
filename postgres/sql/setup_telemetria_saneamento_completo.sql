-- ============================================================================
-- SETUP COMPLETO: SANEAMENTO DE TELEMETRIA + CONFIGURAÇÃO CENTRALIZADA
-- 
-- Executa em ordem:
-- 1. Criação das tabelas de configuração de e-mails (torre.email_gritsch_filiais / torre.email_gritsch_config)
-- 2. Carga inicial (seed) atualizada com todas as filiais ativas (incluindo RIA/Santa Maria, PET/Pelotas, FLN, SSA)
-- 3. Criação da View unificada e saneada de telemetria (torre.vw_alertas_telemetria_saneados)
--    - Filtro de pontos sombra (> 160 km/h)
--    - Filtro de caminhões em excesso (> 120 km/h)
--    - Enriquecimento com cadastro Master Gold e provedor de rastreamento (3STEC, Nuxeo, Omnilink)
-- 4. Criação da View de auditoria de anomalias descartadas (torre.vw_telemetria_anomalias_descartadas)
-- 5. Criação da View de destinatários de e-mail (torre.vw_email_destinatarios_filiais)
--
-- Data: 2026-08-19
-- ============================================================================

\echo '>>> 1. Configurando tabelas de e-mails...'
\ir setup_email_gritsch_filiais.sql

\echo '>>> 2. Criando views de saneamento e auditoria de telemetria...'
\ir torre_views_alertas_telemetria.sql

\echo '>>> 3. Setup de telemetria concluído com sucesso!'
