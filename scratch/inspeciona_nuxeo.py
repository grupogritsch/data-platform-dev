#!/usr/bin/env python3
"""
Inspeção detalhada de bronze.nuxeo_posicao_eventos
"""
import os
import json
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

print("--- 1. Colunas de bronze.nuxeo_posicao_eventos ---")
cur.execute("""
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_schema = 'bronze' AND table_name = 'nuxeo_posicao_eventos';
""")
for r in cur.fetchall():
    print(r)

print("\n--- 2. Amostra de 5 linhas de bronze.nuxeo_posicao_eventos ---")
cur.execute("""
    SELECT placa, eventos_json, ingested_at 
    FROM bronze.nuxeo_posicao_eventos 
    WHERE eventos_json IS NOT NULL 
    LIMIT 5;
""")
for r in cur.fetchall():
    print(f"Placa: {r[0]} | Ingested: {r[2]}")
    print(f"Eventos JSON: {json.dumps(r[1], indent=2, ensure_ascii=False)[:300]}...\n")

print("\n--- 3. Tipos de eventos presentes no JSON ---")
cur.execute("""
    SELECT DISTINCT evt->>'event' AS tipo_evento, COUNT(*)
    FROM bronze.nuxeo_posicao_eventos t,
    LATERAL jsonb_array_elements(t.eventos_json) AS evt
    GROUP BY 1
    ORDER BY 2 DESC
    LIMIT 20;
""")
for r in cur.fetchall():
    print(f"Evento: {r[0]} | Qtd: {r[1]}")

print("\n--- 4. Formato das datas dentro do JSON ---")
cur.execute("""
    SELECT evt->>'date', evt->>'speed', evt->>'event'
    FROM bronze.nuxeo_posicao_eventos t,
    LATERAL jsonb_array_elements(t.eventos_json) AS evt
    LIMIT 10;
""")
for r in cur.fetchall():
    print(f"Data: {r[0]} | Speed: {r[1]} | Event: {r[2]}")

cur.close()
conn.close()
