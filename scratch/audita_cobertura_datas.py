#!/usr/bin/env python3
"""
Auditoria de Cobertura Diária (01/08/2026 a 19/08/2026) no DW
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

print("="*80)
print("1. COBERTURA DIÁRIA EM BRONZE.NUXEO_POSICAO_EVENTOS (NUXEO + OMNILINK)")
print("="*80)
cur.execute("""
    SELECT 
        to_timestamp(data_gps, 'DD/MM/YYYY HH24:MI:SS')::date AS dia,
        CASE 
            WHEN UPPER(COALESCE(complemento, payload_json->>'complement', '')) LIKE '%OMNILINK%' THEN 'OMNILINK'
            ELSE 'NUXEO (GRIT)'
        END AS provedor,
        COUNT(DISTINCT placa) AS qtd_placas,
        COUNT(*) AS total_transmissoes,
        COUNT(CASE WHEN velocidade > 90 THEN 1 END) AS excessos_vel
    FROM bronze.nuxeo_posicao_eventos
    WHERE data_gps IS NOT NULL 
      AND to_timestamp(data_gps, 'DD/MM/YYYY HH24:MI:SS') >= '2026-08-01'::timestamp
      AND to_timestamp(data_gps, 'DD/MM/YYYY HH24:MI:SS') <= '2026-08-19 23:59:59'::timestamp
    GROUP BY 1, 2
    ORDER BY 1 ASC, 2;
""")
rows = cur.fetchall()
for r in rows:
    print(f"  📅 Data: {r[0]} | Provedor: {r[1]:15} | Placas: {r[2]:3} | Posições: {r[3]:6} | Excessos > 90: {r[4]}")

print("\n" + "="*80)
print("2. COBERTURA EM BRONZE.TRES_S_POSICOES / TRES_S_EVENTOS / TRES_S_ULTIMA_POSICAO")
print("="*80)
cur.execute("SELECT COUNT(*) FROM bronze.tres_s_posicoes;")
print(f"  Total em bronze.tres_s_posicoes: {cur.fetchone()[0]}")

cur.execute("SELECT COUNT(*) FROM bronze.tres_s_eventos;")
print(f"  Total em bronze.tres_s_eventos: {cur.fetchone()[0]}")

cur.execute("""
    SELECT 
        COUNT(*) AS total,
        COUNT(DISTINCT placa) AS placas_unicas,
        COUNT(CASE WHEN NULLIF(REPLACE(velocidade, ',', '.'), '')::numeric > 90 THEN 1 END) AS excessos_vel
    FROM bronze.tres_s_ultima_posicao;
""")
r3s = cur.fetchone()
print(f"  Total em bronze.tres_s_ultima_posicao: {r3s[0]} | Placas: {r3s[1]} | Excessos > 90: {r3s[2]}")

cur.close()
conn.close()
