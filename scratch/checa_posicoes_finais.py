#!/usr/bin/env python3
"""
Checa totalização atualizada após ingestão da 3STEC
"""
import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

conn = psycopg2.connect(host='192.168.0.37', port=5433, database='dw', user='gabriel_brittes', password=os.getenv('DW_PASSWORD'))
cur = conn.cursor()

print("--- CONSOLIDAÇÃO ATUALIZADA NO DW ---")
cur.execute("""
    SELECT 
        provedor_rastreador,
        COUNT(*) AS total_alertas,
        COUNT(DISTINCT placa) AS total_veiculos,
        MAX(velocidade_registrada) AS vel_max,
        ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media
    FROM torre.vw_alertas_telemetria_saneados
    WHERE data_hora_timestamp >= '2026-08-01 00:00:00'::timestamp
      AND data_hora_timestamp <= '2026-08-19 23:59:59'::timestamp
    GROUP BY provedor_rastreador
    ORDER BY total_alertas DESC;
""")
for r in cur.fetchall():
    print(f"  📡 {r[0]:10} -> {r[1]:5} alertas | {r[2]:3} veículos | Pico: {r[3]:.0f} km/h | Média: {r[4]} km/h")

cur.close()
conn.close()
