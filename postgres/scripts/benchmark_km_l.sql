-- ============================================================
-- torre.ref_benchmark_km_l
-- Referência de eficiência KM/L por grupo de veículo e combustível
-- Valores fornecidos pela gestão operacional Gritsch (Jul/2026)
-- Média ponderada: 60% Rodoviário + 40% Urbano quando ambos disponíveis
-- ============================================================

DROP TABLE IF EXISTS torre.ref_benchmark_km_l;

CREATE TABLE torre.ref_benchmark_km_l (
    id               SERIAL PRIMARY KEY,
    grupo_veiculo    VARCHAR(100) NOT NULL,
    grupo_combustivel VARCHAR(50) NOT NULL,
    km_l_rodov       NUMERIC(6,2),   -- referência rodoviária
    km_l_urb         NUMERIC(6,2),   -- referência urbana
    km_l_ref         NUMERIC(6,2) NOT NULL, -- valor usado no relatório
    alerta_70pct     NUMERIC(6,2) NOT NULL, -- abaixo disso = CRÍTICO
    alerta_85pct     NUMERIC(6,2) NOT NULL, -- abaixo disso = ATENÇÃO
    tipo_calculo     VARCHAR(30)  NOT NULL  -- RODOV / URB / PONDERADO_60_40
);

-- Leve
INSERT INTO torre.ref_benchmark_km_l (grupo_veiculo, grupo_combustivel, km_l_rodov, km_l_urb, km_l_ref, alerta_70pct, alerta_85pct, tipo_calculo) VALUES
  ('Leve',           'Gasolina', 14.55, 12.43, ROUND(14.55 * 0.6 + 12.43 * 0.4, 2), ROUND((14.55 * 0.6 + 12.43 * 0.4) * 0.70, 2), ROUND((14.55 * 0.6 + 12.43 * 0.4) * 0.85, 2), 'PONDERADO_60_40'),
  ('Leve',           'Álcool',   10.93,  9.60, ROUND(10.93 * 0.6 +  9.60 * 0.4, 2), ROUND((10.93 * 0.6 +  9.60 * 0.4) * 0.70, 2), ROUND((10.93 * 0.6 +  9.60 * 0.4) * 0.85, 2), 'PONDERADO_60_40'),

-- Médio
  ('Médio',          'Gasolina', 11.48, 10.69, ROUND(11.48 * 0.6 + 10.69 * 0.4, 2), ROUND((11.48 * 0.6 + 10.69 * 0.4) * 0.70, 2), ROUND((11.48 * 0.6 + 10.69 * 0.4) * 0.85, 2), 'PONDERADO_60_40'),
  ('Médio',          'Álcool',    9.80,  7.69, ROUND( 9.80 * 0.6 +  7.69 * 0.4, 2), ROUND(( 9.80 * 0.6 +  7.69 * 0.4) * 0.70, 2), ROUND(( 9.80 * 0.6 +  7.69 * 0.4) * 0.85, 2), 'PONDERADO_60_40'),

-- Kombi
  ('Kombi',          'Álcool',    8.95,  8.90, ROUND( 8.95 * 0.6 +  8.90 * 0.4, 2), ROUND(( 8.95 * 0.6 +  8.90 * 0.4) * 0.70, 2), ROUND(( 8.95 * 0.6 +  8.90 * 0.4) * 0.85, 2), 'PONDERADO_60_40'),

-- Pesado (usa rodoviário por padrão — perfil dominante)
  ('Pesado',         'Diesel',   10.01,  8.50, 10.01, ROUND(10.01 * 0.70, 2), ROUND(10.01 * 0.85, 2), 'RODOV'),

-- Moto
  ('Moto',           'Gasolina', NULL,  31.00, 31.00, ROUND(31.00 * 0.70, 2), ROUND(31.00 * 0.85, 2), 'URB'),

-- Caminhões (sempre rodoviário)
  ('Caminhão 4.2 Ton', 'Diesel',  5.71,  5.52,  5.71, ROUND(5.71 * 0.70, 2), ROUND(5.71 * 0.85, 2), 'RODOV'),
  ('Caminhão 5 Ton',   'Diesel',  5.90,  5.69,  5.90, ROUND(5.90 * 0.70, 2), ROUND(5.90 * 0.85, 2), 'RODOV'),
  ('Caminhão 5.5 Ton', 'Diesel',  5.92,  5.63,  5.92, ROUND(5.92 * 0.70, 2), ROUND(5.92 * 0.85, 2), 'RODOV'),
  ('Caminhão 6 Ton',   'Diesel',  5.97,  5.77,  5.97, ROUND(5.97 * 0.70, 2), ROUND(5.97 * 0.85, 2), 'RODOV'),
  ('Caminhão 7.5 Ton', 'Diesel',  5.85,  4.90,  5.85, ROUND(5.85 * 0.70, 2), ROUND(5.85 * 0.85, 2), 'RODOV'),
  ('Caminhão 9 Ton',   'Diesel',  5.11,  4.57,  5.11, ROUND(5.11 * 0.70, 2), ROUND(5.11 * 0.85, 2), 'RODOV'),
  ('Caminhão 10.5 Ton','Diesel',  4.10,  3.89,  4.10, ROUND(4.10 * 0.70, 2), ROUND(4.10 * 0.85, 2), 'RODOV'),
  ('Caminhão 12 Ton',  'Diesel',  3.90,  3.50,  3.90, ROUND(3.90 * 0.70, 2), ROUND(3.90 * 0.85, 2), 'RODOV'),
  ('Caminhão 17 Ton',  'Diesel',  3.60,  3.30,  3.60, ROUND(3.60 * 0.70, 2), ROUND(3.60 * 0.85, 2), 'RODOV');

-- Índices
CREATE INDEX idx_benchmark_grupo_veiculo   ON torre.ref_benchmark_km_l (grupo_veiculo);
CREATE INDEX idx_benchmark_combustivel     ON torre.ref_benchmark_km_l (grupo_combustivel);
CREATE INDEX idx_benchmark_grupo_comb      ON torre.ref_benchmark_km_l (grupo_veiculo, grupo_combustivel);

SELECT
    grupo_veiculo,
    grupo_combustivel,
    km_l_rodov,
    km_l_urb,
    km_l_ref      AS "Ref (usada)",
    alerta_85pct  AS "Atenção (<85%)",
    alerta_70pct  AS "Crítico (<70%)",
    tipo_calculo
FROM torre.ref_benchmark_km_l
ORDER BY grupo_veiculo, grupo_combustivel;
