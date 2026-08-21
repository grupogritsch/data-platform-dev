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

print("--- 3STEC: bronze.tres_s_eventos ---")
cur.execute("SELECT COUNT(*), MIN(ingested_at), MAX(ingested_at) FROM bronze.tres_s_eventos;")
print("Eventos 3S:", cur.fetchone())

print("--- 3STEC: bronze.tres_s_veiculos ---")
cur.execute("SELECT COUNT(*), MIN(ingested_at), MAX(ingested_at) FROM bronze.tres_s_veiculos;")
print("Veículos 3S:", cur.fetchone())

print("--- OMNILINK: bronze.omnilink_posicoes ---")
try:
    cur.execute("SELECT COUNT(*), MIN(ingested_at), MAX(ingested_at) FROM bronze.omnilink_posicoes;")
    print("Omnilink:", cur.fetchone())
except Exception as e:
    conn.rollback()
    print("Omnilink table:", e)

cur.close()
conn.close()
