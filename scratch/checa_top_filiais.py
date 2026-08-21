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

print("--- Ranking de Filiais nas últimas 2 semanas ---")
cur.execute("""
    SELECT 
        filial_operacional,
        COUNT(*) AS total_alertas,
        COUNT(DISTINCT placa) AS qtd_veiculos,
        MAX(velocidade_registrada) AS vel_max,
        ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media
    FROM torre.vw_alertas_telemetria_saneados
    WHERE data_hora_timestamp >= CURRENT_DATE - INTERVAL '14 days'
    GROUP BY filial_operacional
    ORDER BY total_alertas DESC
    LIMIT 10;
""")
for r in cur.fetchall():
    print(f"🏢 {r[0]}: {r[1]} alertas | {r[2]} veículos | Pico: {r[3]} km/h | Média: {r[4]} km/h")

cur.close()
conn.close()
