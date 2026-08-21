#!/usr/bin/env python3
import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

conn = psycopg2.connect(host='192.168.0.37', port=5433, database='dw', user='gabriel_brittes', password=os.getenv('DW_PASSWORD'))
cur = conn.cursor()

cur.execute("SELECT COUNT(*) FROM bronze.tres_s_posicoes;")
print(f"Linhas em bronze.tres_s_posicoes: {cur.fetchone()[0]}")

cur.execute("""
    SELECT 
        COUNT(*) AS total_alertas,
        COUNT(DISTINCT placa) AS total_veiculos,
        MAX(velocidade_registrada) AS vel_max
    FROM torre.vw_alertas_telemetria_saneados
    WHERE provedor_rastreador = '3STEC';
""")
r = cur.fetchone()
print(f"3STEC na View Saneada: {r[0]} alertas | {r[1]} veículos | Pico: {r[2]} km/h")

cur.close()
conn.close()
