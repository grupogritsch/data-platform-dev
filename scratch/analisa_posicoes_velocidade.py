#!/usr/bin/env python3
"""
Diagnóstico de Excesso de Velocidade Real na Telemetria de Posições (bronze.nuxeo_posicao_eventos)
"""
import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

conn = psycopg2.connect(
    host='192.168.0.37',
    port=5433,
    database='dw',
    user='gabriel_brittes',
    password=os.getenv('DW_PASSWORD')
)
cur = conn.cursor()

print("--- 1. Análise da coluna de posições (velocidade instantânea) ---")
cur.execute("""
    WITH posicoes AS (
        SELECT 
            UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) AS placa,
            t.velocidade,
            t.data_gps,
            to_timestamp(t.data_gps, 'DD/MM/YYYY HH24:MI:SS') AS dt_timestamp,
            t.cidade,
            t.estado,
            t.endereco,
            t.latitude,
            t.longitude,
            COALESCE(v.filial_operacional, 'DESCONHECIDA') AS filial,
            COALESCE(v.modelo_raw, '') AS modelo,
            COALESCE(v.grupo_veiculo, 'Leve') AS grupo_veiculo
        FROM bronze.nuxeo_posicao_eventos t
        LEFT JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) = v.placa
        WHERE t.ingested_at >= CURRENT_DATE - INTERVAL '14 days'
          AND t.velocidade > 0
    )
    SELECT 
        filial,
        COUNT(DISTINCT placa) AS qtd_veiculos,
        COUNT(*) AS total_posicoes_excesso,
        MAX(velocidade) AS vel_max,
        ROUND(AVG(velocidade)::numeric, 1) AS vel_media
    FROM posicoes
    WHERE (grupo_veiculo IN ('Bitruck', 'Truck', 'Toco', '3/4') AND velocidade > 90 AND velocidade <= 120)
       OR (grupo_veiculo NOT IN ('Bitruck', 'Truck', 'Toco', '3/4') AND velocidade > 110 AND velocidade <= 160)
    GROUP BY filial
    ORDER BY total_posicoes_excesso DESC;
""")
filiais = cur.fetchall()
print("Filiais com excessos reais (Caminhões > 90 km/h, Leves/Vans > 110 km/h):")
for f in filiais:
    print(f"  🏢 {f[0]}: {f[1]} veículos | {f[2]} ocorrências | Pico: {f[3]} km/h | Média: {f[4]} km/h")

print("\n--- 2. Top Veículos com Excesso Real de Velocidade ---")
cur.execute("""
    WITH posicoes AS (
        SELECT 
            UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) AS placa,
            t.velocidade,
            t.data_gps,
            to_timestamp(t.data_gps, 'DD/MM/YYYY HH24:MI:SS') AS dt_timestamp,
            t.cidade,
            t.estado,
            COALESCE(v.filial_operacional, 'DESCONHECIDA') AS filial,
            COALESCE(v.modelo_raw, '') AS modelo,
            COALESCE(v.grupo_veiculo, 'Leve') AS grupo_veiculo
        FROM bronze.nuxeo_posicao_eventos t
        LEFT JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) = v.placa
        WHERE t.ingested_at >= CURRENT_DATE - INTERVAL '14 days'
          AND t.velocidade > 0
    )
    SELECT 
        placa,
        filial,
        modelo,
        grupo_veiculo,
        COUNT(*) AS qtd_ocorrencias,
        MAX(velocidade) AS vel_max,
        ROUND(AVG(velocidade)::numeric, 1) AS vel_media
    FROM posicoes
    WHERE (grupo_veiculo IN ('Bitruck', 'Truck', 'Toco', '3/4') AND velocidade > 90 AND velocidade <= 120)
       OR (grupo_veiculo NOT IN ('Bitruck', 'Truck', 'Toco', '3/4') AND velocidade > 110 AND velocidade <= 160)
    GROUP BY placa, filial, modelo, grupo_veiculo
    ORDER BY qtd_ocorrencias DESC
    LIMIT 15;
""")
veiculos = cur.fetchall()
for v in veiculos:
    print(f"  🚗 {v[0]} | Filial: {v[1]} | {v[2]} ({v[3]}) | {v[4]}x | Pico: {v[5]} km/h | Média: {v[6]} km/h")

cur.close()
conn.close()
