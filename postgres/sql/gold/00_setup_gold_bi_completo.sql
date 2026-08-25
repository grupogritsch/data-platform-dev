-- ============================================================================
-- MASTER SETUP: CRIAÇÃO COMPLETA DA CAMADA GOLD PARA O LOOKER STUDIO / BI
--
-- Executa todos os módulos Gold da plataforma em ordem de dependência:
-- 1. Abastecimento & Combustível (TruckPag + ANP)
-- 2. Pedágio & Concessionárias (TAGs)
-- 3. Telemetria & Segurança (3S + Nuxeo + Omnilink)
-- 4. Manutenção & Gestão de Frota (Bluefleet + Insumos)
-- 5. Painel Executivo Diretoria & Matriz 360° de Filiais (Looker Studio)
--
-- Uso no psql / DBeaver / terminal:
-- docker exec -i postgres psql -U admin -d dw < postgres/sql/gold/00_setup_gold_bi_completo.sql
--
-- Data: 2026-08-25
-- ============================================================================

\echo '>>> 1. Criando views Gold de Abastecimento e Combustível...'
\ir 41_gold_abastecimento.sql

\echo '>>> 2. Criando views Gold de Pedágio e Concessionárias...'
\ir 42_gold_pedagio.sql

\echo '>>> 3. Criando views Gold de Telemetria e Rastreadores...'
\ir 43_gold_telemetria_rastreador.sql

\echo '>>> 4. Criando views Gold de Manutenção e Frota...'
\ir 44_gold_manutencao_frota.sql

\echo '>>> 5. Criando views Gold da Matriz Executiva da Diretoria...'
\ir 45_gold_diretoria_reuniao_filiais.sql

\echo '>>> Setup da camada Gold concluído com sucesso!'
