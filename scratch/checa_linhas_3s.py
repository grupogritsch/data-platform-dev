#!/usr/bin/env python3
import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

conn = psycopg2.connect(host='192.168.0.37', port=5433, database='dw', user='gabriel_brittes', password=os.getenv('DW_PASSWORD'))
cur = conn.cursor()

cur.execute("SELECT COUNT(*) FROM bronze.tres_s_posicoes;")
print(f"Linhas em bronze.tres_s_posicoes: {cur.fetchone()[0]}")

cur.execute("SELECT * FROM bronze.tres_s_watermark;")
print("Watermarks:", cur.fetchall())

cur.close()
conn.close()
