#!/usr/bin/env python3
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

print("--- Análise de Duplicação por Placa e Data/Hora na Nuxeo ---")
cur.execute("""
    SELECT 
        t.placa,
        COALESCE(evt->>'dateEvent', evt->>'date') AS data_hora,
        NULLIF(REPLACE(evt->>'speed', ',', '.'), '')::numeric AS speed,
        COUNT(*) AS qtd_repeticoes
    FROM bronze.nuxeo_posicao_eventos t,
    LATERAL jsonb_array_elements(t.eventos_json) AS evt
    WHERE t.ingested_at >= CURRENT_DATE - INTERVAL '14 days'
    GROUP BY 1, 2, 3
    HAVING COUNT(*) > 1
    ORDER BY qtd_repeticoes DESC
    LIMIT 10;
""")
rows = cur.fetchall()
for r in rows:
    print(f"Placa: {r[0]} | Data/Hora: {r[1]} | Vel: {r[2]} km/h | Repetições no banco: {r[3]}")

cur.close()
conn.close()
