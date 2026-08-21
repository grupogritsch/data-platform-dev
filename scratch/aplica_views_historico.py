#!/usr/bin/env python3
"""
Aplica views definitivas com histórico 3STEC
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

with open('/home/gabriel/Projetos/data-platform-dev/postgres/sql/torre_views_alertas_telemetria.sql', 'r') as f:
    sql = f.read()

cur.execute(sql)
conn.commit()
print("✅ Views atualizadas no DW com sucesso!")

cur.close()
conn.close()
