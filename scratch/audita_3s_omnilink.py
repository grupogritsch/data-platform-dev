#!/usr/bin/env python3
"""
Auditoria Profunda de 3STEC e OMNILINK no Banco de Dados
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

print("="*80)
print("1. TODAS AS TABELAS NO DW RELACIONADAS A 3S, OMNILINK E NUXEO")
print("="*80)
cur.execute("""
    SELECT table_schema, table_name, table_type
    FROM information_schema.tables 
    WHERE table_name ILIKE '%3s%' 
       OR table_name ILIKE '%tres%' 
       OR table_name ILIKE '%omni%' 
       OR table_name ILIKE '%nuxeo%'
       OR table_name ILIKE '%telemetria%'
       OR table_name ILIKE '%posicao%'
       OR table_name ILIKE '%evento%'
    ORDER BY table_schema, table_name;
""")
for r in cur.fetchall():
    print(f"Schema: {r[0]} | Tabela: {r[1]} ({r[2]})")

print("\n" + "="*80)
print("2. CONTAGEM E ÚLTIMA TRANSMISSÃO DAS TABELAS DE 3S")
print("="*80)
for tbl in ['bronze.tres_s_veiculos', 'bronze.tres_s_posicoes', 'bronze.tres_s_eventos', 'bronze.tres_s_ultima_posicao', 'bronze.tres_s_raw_response']:
    try:
        cur.execute(f"SELECT COUNT(*) FROM {tbl};")
        cnt = cur.fetchone()[0]
        cur.execute(f"SELECT MAX(ingested_at) FROM {tbl};")
        max_ing = cur.fetchone()[0]
        print(f"  📊 {tbl}: {cnt} registros | Última ingestão: {max_ing}")
    except Exception as e:
        conn.rollback()
        print(f"  ❌ {tbl}: Erro {e}")

print("\n" + "="*80)
print("3. CONTAGEM E ÚLTIMA TRANSMISSÃO DAS TABELAS DE OMNILINK")
print("="*80)
cur.execute("""
    SELECT table_schema, table_name 
    FROM information_schema.tables 
    WHERE table_name ILIKE '%omni%' OR table_name ILIKE '%wstt%';
""")
omni_tables = cur.fetchall()
if not omni_tables:
    print("  ❌ Nenhuma tabela encontrada com nome 'omni' ou 'wstt'!")
else:
    for s, t in omni_tables:
        try:
            cur.execute(f"SELECT COUNT(*), MAX(ingested_at) FROM {s}.{t};")
            r = cur.fetchone()
            print(f"  📊 {s}.{t}: {r[0]} registros | Último ingested_at: {r[1]}")
        except Exception as e:
            conn.rollback()
            print(f"  ❌ {s}.{t}: Erro {e}")

print("\n" + "="*80)
print("4. TABELA MASTER DE VEÍCULOS (GOLD_DIM_VEICULO / MAP_VEICULO_RASTREADOR)")
print("="*80)
cur.execute("""
    SELECT 
        COALESCE(provedor_rastreador, 'SEM_PROVEDOR') AS provedor,
        COUNT(*) AS total_veiculos
    FROM torre.map_veiculo_rastreador
    GROUP BY 1
    ORDER BY total_veiculos DESC;
""")
for r in cur.fetchall():
    print(f"  🚗 Mapeamento Rastreador: {r[0]} -> {r[1]} placas")

print("\n" + "="*80)
print("5. E A TABELA BRONZE.TRES_S_EVENTOS / POSICOES? O QUE TEM DENTRO?")
print("="*80)
try:
    cur.execute("SELECT * FROM bronze.tres_s_posicoes LIMIT 3;")
    print("Colunas tres_s_posicoes:", [desc[0] for desc in cur.description])
    for r in cur.fetchall():
        print(r)
except Exception as e:
    conn.rollback()
    print("Erro em tres_s_posicoes:", e)

try:
    cur.execute("SELECT * FROM bronze.tres_s_ultima_posicao LIMIT 3;")
    print("Colunas tres_s_ultima_posicao:", [desc[0] for desc in cur.description])
    for r in cur.fetchall():
        print(r)
except Exception as e:
    conn.rollback()
    print("Erro em tres_s_ultima_posicao:", e)

cur.close()
conn.close()
