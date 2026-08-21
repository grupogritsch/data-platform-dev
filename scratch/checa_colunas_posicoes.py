#!/usr/bin/env python3
"""
Checa colunas da tabela bronze.tres_s_posicoes e adapta
"""
import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

conn = psycopg2.connect(
    host='192.168.0.37', port=5433, database='dw',
    user='gabriel_brittes', password=os.getenv('DW_PASSWORD')
)
cur = conn.cursor()

cur.execute("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'tres_s_posicoes';")
print("Colunas de bronze.tres_s_posicoes:")
for r in cur.fetchall():
    print(f"  {r[0]} ({r[1]})")

cur.close()
conn.close()
