-- ============================================================
-- DDL + Seed: torre.email_gritsch_filiais & torre.email_gritsch_config
-- Centralização de todos os e-mails e destinatários por filial
-- Data: 2026-08-21
-- ============================================================

CREATE SCHEMA IF NOT EXISTS torre;

-- 1. DDL — Tabela de e-mails por filial
-- ============================================================
CREATE TABLE IF NOT EXISTS torre.email_gritsch_filiais (
  id                  SERIAL PRIMARY KEY,
  filial_operacional  VARCHAR(150) NOT NULL UNIQUE,
  email_destino       VARCHAR(255) NOT NULL,
  ativo               BOOLEAN DEFAULT true,
  criado_em           TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  email_cc            TEXT DEFAULT '',
  cc_regional         TEXT DEFAULT '',
  atualizado_em       TIMESTAMPTZ DEFAULT NOW()
);

-- Garante que colunas e restrições existam
ALTER TABLE torre.email_gritsch_filiais 
  ADD COLUMN IF NOT EXISTS ativo BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS criado_em TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS email_cc TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS cc_regional TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS atualizado_em TIMESTAMPTZ DEFAULT NOW();

COMMENT ON TABLE torre.email_gritsch_filiais IS 
  'Configuração centralizada de destinatários de e-mail por filial operacional. '
  'Alimenta os workflows de Telemetria (diário/semanal), Combustível/Ociosidade e PDFs.';

-- 2. DDL — Tabela de configuração global
-- ============================================================
CREATE TABLE IF NOT EXISTS torre.email_gritsch_config (
  chave         TEXT PRIMARY KEY,
  valor         TEXT NOT NULL,
  descricao     TEXT DEFAULT '',
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE torre.email_gritsch_config IS 
  'Parâmetros globais de configuração de e-mails (CC global, etc).';

-- 3. Seed — Configurações Globais e Consolidados
-- ============================================================
INSERT INTO torre.email_gritsch_config (chave, valor, descricao) VALUES
  ('cc_global',
   'torredecontrole@gritsch.com.br,flavio@gritsch.com.br,fabio.pepplow@gritsch.com.br',
   'Lista de e-mails que recebem cópia de TODOS os relatórios de todas as filiais (Diretoria Operacional + Torre de Controle)'),
  ('consolidado_destinatarios',
   'jefferson@gritsch.com.br',
   'Destinatário principal do relatório consolidado nacional da Diretoria (Diretor de Operações)'),
  ('consolidado_cc',
   'sandro@gritsch.com.br,torredecontrole@gritsch.com.br,flavio@gritsch.com.br,fabio.pepplow@gritsch.com.br',
   'Lista de e-mails em cópia do relatório consolidado nacional (Gerente Nacional de Frota + Torre de Controle)')
ON CONFLICT (chave) DO UPDATE SET
  valor = EXCLUDED.valor,
  descricao = EXCLUDED.descricao,
  atualizado_em = NOW();

-- 4. Seed — E-mails por filial
-- ============================================================
INSERT INTO torre.email_gritsch_filiais 
  (id, filial_operacional, email_destino, ativo, criado_em, email_cc, cc_regional, atualizado_em)
VALUES
  (1,  'GRITSCH - BLN',             'blumenau@gritsch.com.br',        true, '2026-07-01 11:50:30.634', 'alan.chimenes@gritsch.com.br;sandro@gritsch.com.br',                                  'helder.santos@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (2,  'GRITSCH - BSB',             'brasilia@gritsch.com.br',        true, '2026-07-01 11:50:30.634', 'andre.moreira@gritsch.com.br;sandro@gritsch.com.br',                                  'ely@gritsch.com.br',           '2026-08-19 12:26:51.179 -0300'),
  (3,  'GRITSCH - CBL',             'goiania@gritsch.com.br',         true, '2026-04-16 15:39:43.720', 'carlos.ribeiro@gritsch.com.br;sandro@gritsch.com.br',                                 'ely@gritsch.com.br',           '2026-08-19 12:26:51.179 -0300'),
  (4,  'GRITSCH - CGB',             'cuiaba@gritsch.com.br',          true, '2026-07-01 11:50:30.634', 'edeni.silva@gritsch.com.br;sandro@gritsch.com.br',                                    'paulo.kirsch@gritsch.com.br',  '2026-08-19 12:26:51.179 -0300'),
  (5,  'GRITSCH - CGR',             'campogrande@gritsch.com.br',     true, '2026-07-01 11:50:30.634', 'weverton.nascimento@gritsch.com.br;sandro@gritsch.com.br',                            'paulo.kirsch@gritsch.com.br',  '2026-08-19 12:26:51.179 -0300'),
  (6,  'GRITSCH - CHA',             'chapeco@gritsch.com.br',         true, '2026-07-01 11:50:30.634', 'eloir.sokul@gritsch.com.br;adriano.lavall@gritsch.com.br;sandro@gritsch.com.br',      'helder.santos@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (7,  'GRITSCH - CRI',             'criciuma@gritsch.com.br',        true, '2026-07-01 11:50:30.634', 'wesley.batista@gritsch.com.br;sandro@gritsch.com.br',                                 'helder.santos@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (8,  'GRITSCH - CSC',             'cascavel@gritsch.com.br',        true, '2026-07-01 11:50:30.634', 'hernani.oliveira@gritsch.com.br;sandro@gritsch.com.br',                               'clovis@gritsch.com.br',        '2026-08-19 12:26:51.179 -0300'),
  (9,  'GRITSCH - CTB',             'curitibanos@gritsch.com.br',     true, '2026-07-01 11:50:30.634', 'roberto.posanski@gritsch.com.br;sandro@gritsch.com.br',                              'helder.santos@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (10, 'GRITSCH - CWB (BASE)',      'admcwb@gritsch.com.br',          true, '2026-07-01 11:50:30.634', 'anderson.alves@gritsch.com.br;sandro@gritsch.com.br',                                 'adilson@gritsch.com.br',       '2026-08-19 12:26:51.179 -0300'),
  (11, 'GRITSCH - CWB (DIR)',       'torredecontrole@gritsch.com.br', true, '2026-07-01 11:50:30.634', 'fabio.pepplow@gritsch.com.br',                                                        'flavio@gritsch.com.br',        '2026-08-19 12:26:51.179 -0300'),
  (12, 'GRITSCH - CWB (ECT)',       'admcwb@gritsch.com.br',          true, '2026-07-01 11:50:30.634', 'anderson.alves@gritsch.com.br;sandro@gritsch.com.br',                                 'adilson@gritsch.com.br',       '2026-08-19 12:26:51.179 -0300'),
  (13, 'GRITSCH - CXJ',             'caxias@gritsch.com.br',          true, '2026-07-01 11:50:30.634', 'helen.biano@gritsch.com.br;sandro@gritsch.com.br',                                    'helder.santos@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (14, 'GRITSCH - FLN',             'florianopolis@gritsch.com.br',   true, '2026-07-01 11:50:30.634', 'paulo.fernandes@gritsch.com.br;jose.ventura@gritsch.com.br;sandro@gritsch.com.br',   'helder.santos@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (15, 'GRITSCH - GOI',             'goiania@gritsch.com.br',         true, '2026-07-01 11:50:30.634', 'carlos.ribeiro@gritsch.com.br;sandro@gritsch.com.br',                                 'ely@gritsch.com.br',           '2026-08-19 12:26:51.179 -0300'),
  (16, 'GRITSCH - GPA',             'guarapuava@gritsch.com.br',      true, '2026-07-01 11:50:30.634', 'elisson.santos@gritsch.com.br;sandro@gritsch.com.br',                                 'clovis@gritsch.com.br',        '2026-08-19 12:26:51.179 -0300'),
  (17, 'GRITSCH - ITR',             'itumbiara@gritsch.com.br',       true, '2026-07-01 11:50:30.634', 'sandro@gritsch.com.br',                                                               'ely@gritsch.com.br',           '2026-08-19 12:26:51.179 -0300'),
  (18, 'GRITSCH - JOI',             'joinville@gritsch.com.br',       true, '2026-07-01 11:50:30.634', 'rudimar.bueno@gritsch.com.br;sandro@gritsch.com.br',                                  'helder.santos@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (19, 'GRITSCH - LDB',             'londrina@gritsch.com.br',        true, '2026-07-01 11:50:30.634', 'carlos.kozan@gritsch.com.br;sandro@gritsch.com.br',                                   'clovis@gritsch.com.br',        '2026-08-19 12:26:51.179 -0300'),
  (20, 'GRITSCH - MATRIZ',          'torredecontrole@gritsch.com.br', true, '2026-04-16 15:39:43.720', 'fabio.pepplow@gritsch.com.br',                                                        'flavio@gritsch.com.br',        '2026-08-19 12:26:51.179 -0300'),
  (21, 'GRITSCH - MGA',             'maringa@gritsch.com.br',         true, '2026-07-01 11:50:30.634', 'ricardo.navarrete@gritsch.com.br;sandro@gritsch.com.br',                              'clovis@gritsch.com.br',        '2026-08-19 12:26:51.179 -0300'),
  (22, 'GRITSCH - PBC',             'patobranco@gritsch.com.br',      true, '2026-07-01 11:50:30.634', 'jefferson.silva@gritsch.com.br;sandro@gritsch.com.br',                                'clovis@gritsch.com.br',        '2026-08-19 12:26:51.179 -0300'),
  (23, 'GRITSCH - PGR',             'pontagrossa@gritsch.com.br',     true, '2026-07-01 11:50:30.634', 'anderson.santos@gritsch.com.br;sandro@gritsch.com.br',                                'clovis@gritsch.com.br',        '2026-08-19 12:26:51.179 -0300'),
  (24, 'GRITSCH - PMW',             'palmas@gritsch.com.br',          true, '2026-07-01 11:50:30.634', 'sandro@gritsch.com.br',                                                               'ely@gritsch.com.br',           '2026-08-19 12:26:51.179 -0300'),
  (25, 'GRITSCH - POA',             'portoalegre@gritsch.com.br',     true, '2026-07-01 11:50:30.634', 'moises.lima@gritsch.com.br,helder.souza@gritsch.com.br;sandro@gritsch.com.br',        'helder.santos@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (26, 'GRITSCH - RDN',             'rondonopolis@gritsch.com.br',    true, '2026-07-01 11:50:30.634', 'marcio.silva@gritsch.com.br;sandro@gritsch.com.br',                                   'paulo.kirsch@gritsch.com.br',  '2026-08-19 12:26:51.179 -0300'),
  (27, 'GRITSCH - RVD',             'rioverde@gritsch.com.br',        true, '2026-07-01 11:50:30.634', 'weslei.silva@gritsch.com.br;sandro@gritsch.com.br',                                   'ely@gritsch.com.br',           '2026-08-19 12:26:51.179 -0300'),
  (28, 'GRITSCH - SAO (FREGUESIA)', 'saopaulo@gritsch.com.br',        true, '2026-07-01 11:50:30.634', 'adilson.carolino@gritsch.com.br;andressa.rocha@gritsch.com.br;sandro@gritsch.com.br', 'paulo.santana@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (29, 'GRITSCH - SAO (PERUS)',     'saopaulo@gritsch.com.br',        true, '2026-07-01 11:50:30.634', 'adilson.carolino@gritsch.com.br;andressa.rocha@gritsch.com.br;sandro@gritsch.com.br', 'paulo.santana@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (30, 'GRITSCH - SNO',             'sinop@gritsch.com.br',           true, '2026-07-01 11:50:30.634', 'willian.costa@gritsch.com.br;poliana.oliveira@gritsch.com.br;sandro@gritsch.com.br',  'paulo.kirsch@gritsch.com.br',  '2026-08-19 12:26:51.179 -0300'),
  (31, 'GRITSCH - SSA',             'salvador@gritsch.com.br',        true, '2026-07-01 11:50:30.634', 'cristiano.cruz@gritsch.com.br;sandro@gritsch.com.br',                                 'ely@gritsch.com.br',           '2026-08-19 12:26:51.179 -0300'),
  (32, 'DESCONHECIDA',              'torredecontrole@gritsch.com.br', true, '2026-04-16 15:39:43.720', 'fabio.pepplow@gritsch.com.br;gabriel.brittes@gritsch.com.br',                         'flavio@gritsch.com.br',        '2026-08-19 12:09:45.761 -0300'),
  (33, 'GRITSCH - PET',             'gi.pet@gritsch.com.br',          true, '2026-08-12 20:32:53.823', 'william.ferreira@gritsch.com.br;sandro@gritsch.com.br',                               'helder.santos@gritsch.com.br', '2026-08-19 12:26:51.179 -0300'),
  (34, 'GRITSCH - RIA',             'gi.ria@gritsch.com.br',          true, '2026-08-12 20:34:11.923', 'guilherme.siqueira@gritsch.com.br;sandro@gritsch.com.br',                             'helder.santos@gritsch.com.br', '2026-08-19 12:26:51.179 -0300')
ON CONFLICT (id) DO UPDATE SET
  filial_operacional  = EXCLUDED.filial_operacional,
  email_destino       = EXCLUDED.email_destino,
  ativo               = EXCLUDED.ativo,
  criado_em           = EXCLUDED.criado_em,
  email_cc            = EXCLUDED.email_cc,
  cc_regional         = EXCLUDED.cc_regional,
  atualizado_em       = EXCLUDED.atualizado_em;

SELECT setval(pg_get_serial_sequence('torre.email_gritsch_filiais', 'id'), COALESCE(max(id), 1)) FROM torre.email_gritsch_filiais;

-- 5. DDL — View de Destinatários de E-mail
-- ============================================================
DROP VIEW IF EXISTS torre.vw_email_destinatarios_filiais CASCADE;

CREATE OR REPLACE VIEW torre.vw_email_destinatarios_filiais AS
SELECT 
  f.filial_operacional,
  f.email_destino,
  f.email_cc,
  f.cc_regional,
  COALESCE(c.valor, 'torredecontrole@gritsch.com.br,flavio@gritsch.com.br,fabio.pepplow@gritsch.com.br'::text) AS cc_global,
  f.ativo
FROM torre.email_gritsch_filiais f
CROSS JOIN (
  SELECT valor FROM torre.email_gritsch_config WHERE chave = 'cc_global' LIMIT 1
) c
WHERE f.ativo = true;

