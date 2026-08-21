#!/usr/bin/env python3
"""
Auditoria das Posições e Datas na 3STEC (bronze.tres_s_ultima_posicao)
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

print("--- Análise da tabela bronze.tres_s_ultima_posicao ---")
cur.execute("""
    SELECT 
        COUNT(*) AS total,
        COUNT(CASE WHEN NULLIF(REPLACE(velocidade, ',', '.'), '')::numeric > 80 THEN 1 END) AS vel_acima_80,
        COUNT(CASE WHEN NULLIF(REPLACE(velocidade, ',', '.'), '')::numeric > 100 THEN 1 END) AS vel_acima_100,
        COUNT(CASE WHEN NULLIF(REPLACE(velocidade, ',', '.'), '')::numeric > 110 THEN 1 END) AS vel_acima_110
    FROM bronze.tres_s_ultima_posicao;
""")
r = cur.fetchone()
print(f"Total veículos 3S: {r[0]} | Vel > 80: {r[1]} | Vel > 100: {r[2]} | Vel > 110: {r[3]}")

cur.execute("""
    SELECT 
        placa,
        modelo,
        velocidade,
        data_gps,
        cidade,
        uf
    FROM bronze.tres_s_ultima_posicao
    WHERE NULLIF(REPLACE(velocidade, ',', '.'), '')::numeric > 100
    LIMIT 10;
""")
for row in cur.fetchall():
    print(f"  🚗 3S: {row[0]} | {row[1]} | {row[2]} km/h | Data GPS: {row[3]} | {row[4]}/{row[5]}")

cur.close()
conn.close()
