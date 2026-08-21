#!/usr/bin/env python3
"""
Investigação dos IDs dos Veículos na Nuxeo (grit vs omnilink)
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
print("1. ESTRUTURA DE COLUNAS DE BRONZE.NUXEO_POSICAO_EVENTOS")
print("="*80)
cur.execute("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'nuxeo_posicao_eventos';")
for col in cur.fetchall():
    print(f"  Coluna: {col[0]} ({col[1]})")

print("\n" + "="*80)
print("2. AMOSTRAS DE IDENTIFICADORES NA TABELA NUXEO")
print("="*80)
cur.execute("""
    SELECT 
        id,
        placa,
        placa_nuxeo,
        veiculo,
        cidade,
        estado,
        velocidade,
        ingested_at
    FROM bronze.nuxeo_posicao_eventos
    LIMIT 15;
""")
for r in cur.fetchall():
    print(f"ID: {r[0]} | Placa: {r[1]} | PlacaNuxeo: {r[2]} | Veiculo: {r[3]} | Vel: {r[6]}")

print("\n" + "="*80)
print("3. ANÁLISE DE PADRÕES NO ID / VEICULO (grit vs omnilink)")
print("="*80)
cur.execute("""
    SELECT 
        CASE 
            WHEN LOWER(id) LIKE '%omni%' OR LOWER(veiculo) LIKE '%omni%' OR LOWER(placa_nuxeo) LIKE '%omni%' THEN 'OMNILINK'
            WHEN LOWER(id) LIKE '%grit%' OR LOWER(veiculo) LIKE '%grit%' OR LOWER(placa_nuxeo) LIKE '%grit%' THEN 'NUXEO (GRIT)'
            ELSE 'OUTRO'
        END AS tipo_identificado,
        COUNT(DISTINCT placa) AS total_placas,
        COUNT(*) AS total_posicoes
    FROM bronze.nuxeo_posicao_eventos
    GROUP BY 1;
""")
for r in cur.fetchall():
    print(f"  📌 Tipo: {r[0]} -> {r[1]} placas | {r[2]} registros")

print("\n" + "="*80)
print("4. AMOSTRAS DETALHADAS DE OMNILINK VS GRIT")
print("="*80)
cur.execute("""
    SELECT 
        id,
        placa,
        placa_nuxeo,
        veiculo,
        velocidade
    FROM bronze.nuxeo_posicao_eventos
    WHERE LOWER(id) LIKE '%omni%' OR LOWER(veiculo) LIKE '%omni%' OR LOWER(placa_nuxeo) LIKE '%omni%'
    LIMIT 10;
""")
for r in cur.fetchall():
    print(f"  📡 OMNILINK: ID={r[0]} | Placa={r[1]} | PlacaNuxeo={r[2]} | Veiculo={r[3]} | Vel={r[4]}")

cur.execute("""
    SELECT 
        id,
        placa,
        placa_nuxeo,
        veiculo,
        velocidade
    FROM bronze.nuxeo_posicao_eventos
    WHERE LOWER(id) LIKE '%grit%' OR LOWER(veiculo) LIKE '%grit%' OR LOWER(placa_nuxeo) LIKE '%grit%'
    LIMIT 10;
""")
for r in cur.fetchall():
    print(f"  📡 GRIT: ID={r[0]} | Placa={r[1]} | PlacaNuxeo={r[2]} | Veiculo={r[3]} | Vel={r[4]}")

cur.close()
conn.close()
