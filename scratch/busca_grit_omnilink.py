#!/usr/bin/env python3
"""
Investigação dos campos no payload_json da Nuxeo e tabelas correlatas
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

print("--- Amostras de payload_json em bronze.nuxeo_posicao_eventos ---")
cur.execute("""
    SELECT 
        placa,
        serial,
        complemento,
        payload_json
    FROM bronze.nuxeo_posicao_eventos
    LIMIT 5;
""")
for r in cur.fetchall():
    print(f"Placa: {r[0]} | Serial: {r[1]} | Complemento: {r[2]} | Payload: {r[3]}")

print("\n--- Outras tabelas de Nuxeo (bronze.nuxeo_veiculos_posicao, etc) ---")
try:
    cur.execute("SELECT * FROM bronze.nuxeo_veiculos_posicao LIMIT 5;")
    cols = [desc[0] for desc in cur.description]
    print("Colunas nuxeo_veiculos_posicao:", cols)
    for r in cur.fetchall():
        print(dict(zip(cols, r)))
except Exception as e:
    conn.rollback()
    print(e)

print("\n--- Investigação de 'grit' e 'omnilink' em todo o payload_json ou serial ---")
cur.execute("""
    SELECT 
        CASE 
            WHEN LOWER(t.payload_json::text) LIKE '%omnilink%' OR LOWER(t.serial) LIKE '%omnilink%' OR LOWER(t.complemento) LIKE '%omnilink%' THEN 'OMNILINK'
            WHEN LOWER(t.payload_json::text) LIKE '%grit%' OR LOWER(t.serial) LIKE '%grit%' OR LOWER(t.complemento) LIKE '%grit%' THEN 'NUXEO (GRIT)'
            ELSE 'OUTRO'
        END AS identificador,
        COUNT(DISTINCT t.placa) AS qtd_placas,
        COUNT(*) AS total_linhas
    FROM bronze.nuxeo_posicao_eventos t
    GROUP BY 1;
""")
for r in cur.fetchall():
    print(f"  📌 {r[0]}: {r[1]} placas | {r[2]} linhas")

cur.execute("""
    SELECT 
        t.placa,
        t.serial,
        t.complemento,
        t.payload_json->>'id',
        t.payload_json->>'idVeiculo',
        t.payload_json->>'vehicleId',
        t.payload_json->>'tracker',
        t.payload_json->>'provider',
        t.payload_json
    FROM bronze.nuxeo_posicao_eventos t
    WHERE LOWER(t.payload_json::text) LIKE '%omnilink%'
    LIMIT 5;
""")
for r in cur.fetchall():
    print("OMNILINK MATCH:", r[:8])

cur.execute("""
    SELECT 
        t.placa,
        t.serial,
        t.complemento,
        t.payload_json->>'id',
        t.payload_json->>'idVeiculo',
        t.payload_json->>'vehicleId',
        t.payload_json->>'tracker',
        t.payload_json->>'provider',
        t.payload_json
    FROM bronze.nuxeo_posicao_eventos t
    WHERE LOWER(t.payload_json::text) LIKE '%grit%'
    LIMIT 5;
""")
for r in cur.fetchall():
    print("GRIT MATCH:", r[:8])

cur.close()
conn.close()
