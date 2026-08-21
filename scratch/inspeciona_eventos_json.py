#!/usr/bin/env python3
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

print("--- 1. Linhas com eventos_json não vazio ---")
cur.execute("""
    SELECT placa, eventos_json, data_gps, velocidade, cidade, estado, ingested_at
    FROM bronze.nuxeo_posicao_eventos
    WHERE eventos_json IS NOT NULL AND jsonb_array_length(eventos_json) > 0
    LIMIT 3;
""")
rows = cur.fetchall()
for r in rows:
    print(f"Placa: {r[0]} | data_gps: {r[2]} | vel: {r[3]} | local: {r[4]}/{r[5]} | ingested_at: {r[6]}")
    print(f"JSON:\n{json.dumps(r[1], indent=2, ensure_ascii=False)}\n")

print("--- 2. Chaves presentes no primeiro elemento do eventos_json ---")
cur.execute("""
    SELECT DISTINCT jsonb_object_keys(evt)
    FROM bronze.nuxeo_posicao_eventos t,
    LATERAL jsonb_array_elements(t.eventos_json) AS evt
    LIMIT 30;
""")
print([r[0] for r in cur.fetchall()])

cur.close()
conn.close()
