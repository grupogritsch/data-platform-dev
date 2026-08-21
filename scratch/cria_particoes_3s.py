#!/usr/bin/env python3
"""
Auditoria e Criação de Partições de bronze.tres_s_posicoes
"""
import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

conn = psycopg2.connect(host='192.168.0.37', port=5433, database='dw', user='gabriel_brittes', password=os.getenv('DW_PASSWORD'))
cur = conn.cursor()

print("--- Partições existentes em bronze.tres_s_posicoes ---")
cur.execute("""
    SELECT inhrelid::regclass, inhparent::regclass 
    FROM pg_inherits 
    WHERE inhparent = 'bronze.tres_s_posicoes'::regclass;
""")
for r in cur.fetchall():
    print(f"  Partição: {r[0]}")

print("\n--- Criando partições de 2026 e partição DEFAULT para bronze.tres_s_posicoes ---")
cur.execute("""
    -- Criar partições mensais para 2026
    CREATE TABLE IF NOT EXISTS bronze.tres_s_posicoes_2026_08 PARTITION OF bronze.tres_s_posicoes
        FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');

    CREATE TABLE IF NOT EXISTS bronze.tres_s_posicoes_2026_09 PARTITION OF bronze.tres_s_posicoes
        FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');

    CREATE TABLE IF NOT EXISTS bronze.tres_s_posicoes_2026_10 PARTITION OF bronze.tres_s_posicoes
        FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');

    CREATE TABLE IF NOT EXISTS bronze.tres_s_posicoes_2026_11 PARTITION OF bronze.tres_s_posicoes
        FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');

    CREATE TABLE IF NOT EXISTS bronze.tres_s_posicoes_2026_12 PARTITION OF bronze.tres_s_posicoes
        FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

    -- Partição default para qualquer data
    CREATE TABLE IF NOT EXISTS bronze.tres_s_posicoes_default PARTITION OF bronze.tres_s_posicoes DEFAULT;
""")
conn.commit()
print("✅ Partições de 2026 e DEFAULT criadas com sucesso!")

cur.close()
conn.close()
