-- ============================================================
-- DDL + Seed: torre.email_gritsch_filiais
-- Centralização de todos os e-mails hardcoded dos workflows
-- Data: 2026-08-19
-- ============================================================

-- 1. DDL — Tabela de e-mails por filial
-- ============================================================
CREATE TABLE IF NOT EXISTS torre.email_gritsch_filiais (
  filial_operacional  TEXT PRIMARY KEY,
  email_destino       TEXT NOT NULL,
  email_cc            TEXT DEFAULT '',
  cc_regional         TEXT DEFAULT '',
  ativo               BOOLEAN DEFAULT true,
  atualizado_em       TIMESTAMPTZ DEFAULT NOW()
);

-- Garante que a coluna cc_regional exista em instâncias pré-existentes
ALTER TABLE torre.email_gritsch_filiais 
  ADD COLUMN IF NOT EXISTS cc_regional TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS email_cc TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS ativo BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS atualizado_em TIMESTAMPTZ DEFAULT NOW();

COMMENT ON TABLE torre.email_gritsch_filiais IS 
  'Configuração centralizada de destinatários de e-mail por filial operacional. '
  'Alimenta os workflows de Telemetria (diário/semanal) e Combustível/Ociosidade.';

-- 2. DDL — Tabela de configuração global
-- ============================================================
CREATE TABLE IF NOT EXISTS torre.email_gritsch_config (
  chave       TEXT PRIMARY KEY,
  valor       TEXT NOT NULL,
  descricao   TEXT DEFAULT '',
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE torre.email_gritsch_config IS 
  'Parâmetros globais de configuração de e-mails (CC global, etc).';

-- 3. Seed — CC Global (diretoria e torre que recebem TUDO)
-- ============================================================
INSERT INTO torre.email_gritsch_config (chave, valor, descricao) VALUES
  ('cc_global',
   'sandro@gritsch.com.br,torredecontrole@gritsch.com.br,flavio@gritsch.com.br,fabio.pepplow@gritsch.com.br',
   'Lista de e-mails que recebem cópia de TODOS os relatórios de todas as filiais (Diretoria Nacional + Torre de Controle)')
ON CONFLICT (chave) DO UPDATE SET
  valor = EXCLUDED.valor,
  atualizado_em = NOW();

-- 4. Seed — E-mails por filial (destino + regional CC)
-- ============================================================
-- Legenda:
--   email_destino = quem recebe o e-mail como destinatário principal
--   cc_regional   = gerente regional que recebe cópia das filiais sob sua responsabilidade
--   email_cc      = cópias adicionais específicas da filial (reservado para uso futuro)
--
-- Regionais:
--   Adilson       → CWB (BASE), CWB (ECT)
--   Clovis        → CSC, LDB, MGA, PBC, PGR, GPA
--   Ely           → BSB, CGR, PMW, RVD, GOI, CBL, ITR, CGB, RDN, SNO, SSA
--   Helder Santos → BLN, CHA, CRI, JOI, FLN, CTB, CXJ, POA
--   Paulo Santana → SAO (FREGUESIA), SAO (PERUS)
-- ============================================================

INSERT INTO torre.email_gritsch_filiais 
  (filial_operacional, email_destino, email_cc, cc_regional, ativo)
VALUES
  -- === PARANÁ (Sul) ===
  ('GRITSCH - CWB (BASE)', 'admcwb@gritsch.com.br',                '', 'adilson@gritsch.com.br',        true),
  ('GRITSCH - CWB (DIR)',  'torredecontrole@gritsch.com.br',       '', '',                              true),
  ('GRITSCH - CWB (ECT)',  'admcwb@gritsch.com.br',                '', 'adilson@gritsch.com.br',        true),
  ('GRITSCH - LDB',        'londrina@gritsch.com.br',              '', 'clovis@gritsch.com.br',         true),
  ('GRITSCH - MGA',        'maringa@gritsch.com.br',               '', 'clovis@gritsch.com.br',         true),
  ('GRITSCH - PGR',        'pontagrossa@gritsch.com.br',           '', 'clovis@gritsch.com.br',         true),
  ('GRITSCH - PBC',        'patobranco@gritsch.com.br',            '', 'clovis@gritsch.com.br',         true),
  ('GRITSCH - GPA',        'guarapuava@gritsch.com.br',            '', 'clovis@gritsch.com.br',         true),
  ('GRITSCH - CSC',        'cascavel@gritsch.com.br',              '', 'clovis@gritsch.com.br',         true),
  ('GRITSCH - MATRIZ',     'torredecontrole@gritsch.com.br',       '', '',                              true),

  -- === SANTA CATARINA (Sul) ===
  ('GRITSCH - FLN',        'florianopolis@gritsch.com.br,paulo.fernandes@gritsch.com.br', '', 'helder.santos@gritsch.com.br', true),
  ('GRITSCH - JOI',        'joinville@gritsch.com.br',             '', 'helder.santos@gritsch.com.br', true),
  ('GRITSCH - BLN',        'blumenau@gritsch.com.br',              '', 'helder.santos@gritsch.com.br', true),
  ('GRITSCH - CHA',        'chapeco@gritsch.com.br',               '', 'helder.santos@gritsch.com.br', true),
  ('GRITSCH - CRI',        'criciuma@gritsch.com.br',              '', 'helder.santos@gritsch.com.br', true),
  ('GRITSCH - CTB',        'curitibanos@gritsch.com.br',           '', 'helder.santos@gritsch.com.br', true),

  -- === RIO GRANDE DO SUL (Sul) ===
  ('GRITSCH - POA',        'portoalegre@gritsch.com.br,moises.lima@gritsch.com.br,helder.souza@gritsch.com.br', '', 'helder.santos@gritsch.com.br', true),
  ('GRITSCH - CXJ',        'caxias@gritsch.com.br',               '', 'helder.santos@gritsch.com.br', true),
  ('GRITSCH - RIA',        'gi.ria@gritsch.com.br,guilherme.siqueira@gritsch.com.br', '', 'helder.santos@gritsch.com.br', true),
  ('GRITSCH - PET',        'william.ferreira@gritsch.com.br,gi.pet@gritsch.com.br', '', 'helder.santos@gritsch.com.br', true),

  -- === GOIÁS (Centro-Oeste) ===
  ('GRITSCH - GOI',        'goiania@gritsch.com.br',               '', 'ely@gritsch.com.br',            true),
  ('GRITSCH - RVD',        'rioverde@gritsch.com.br',              '', 'ely@gritsch.com.br',            true),
  ('GRITSCH - ITR',        'itumbiara@gritsch.com.br',             '', 'ely@gritsch.com.br',            true),
  ('GRITSCH - CBL',        'goiania@gritsch.com.br',               '', 'ely@gritsch.com.br',            true),

  -- === MATO GROSSO (Centro-Oeste) ===
  ('GRITSCH - SNO',        'sinop@gritsch.com.br',                 '', 'ely@gritsch.com.br',            true),
  ('GRITSCH - RDN',        'rondonopolis@gritsch.com.br',          '', 'ely@gritsch.com.br',            true),
  ('GRITSCH - CGB',        'cuiaba@gritsch.com.br',                '', 'ely@gritsch.com.br',            true),

  -- === MATO GROSSO DO SUL (Centro-Oeste) ===
  ('GRITSCH - CGR',        'campogrande@gritsch.com.br',           '', 'ely@gritsch.com.br',            true),

  -- === DISTRITO FEDERAL (Centro-Oeste) ===
  ('GRITSCH - BSB',        'brasilia@gritsch.com.br',              '', 'ely@gritsch.com.br',            true),

  -- === SÃO PAULO (Sudeste) ===
  ('GRITSCH - SAO (FREGUESIA)', 'saopaulo@gritsch.com.br',         '', 'paulo.santana@gritsch.com.br', true),
  ('GRITSCH - SAO (PERUS)',     'saopaulo@gritsch.com.br',         '', 'paulo.santana@gritsch.com.br', true),

  -- === BAHIA (Nordeste) ===
  ('GRITSCH - SSA',        'salvador@gritsch.com.br,cristiano.cruz@gritsch.com.br', '', 'ely@gritsch.com.br', true),

  -- === TOCANTINS (Norte) ===
  ('GRITSCH - PMW',        'palmas@gritsch.com.br',                '', 'ely@gritsch.com.br',            true)

ON CONFLICT (filial_operacional) DO UPDATE SET
  email_destino = EXCLUDED.email_destino,
  email_cc      = EXCLUDED.email_cc,
  cc_regional   = EXCLUDED.cc_regional,
  ativo         = EXCLUDED.ativo,
  atualizado_em = NOW();

-- 5. Verificação — Listar tudo
-- ============================================================
SELECT 
  filial_operacional,
  email_destino,
  cc_regional,
  ativo,
  atualizado_em
FROM torre.email_gritsch_filiais
ORDER BY filial_operacional;

-- Config global
SELECT * FROM torre.email_gritsch_config;
