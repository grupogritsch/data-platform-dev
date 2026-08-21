#!/usr/bin/env python3
"""
Diagnóstico Profundo da Origem dos Dados de Telemetria e Mapeamento de Rastreadores
"""
import os
import json
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
print("1. INVESTIGAÇÃO DE MAP_VEICULO_RASTREADOR E PROVEDORES")
print("="*80)
try:
    cur.execute("SELECT DISTINCT provedor_rastreador, COUNT(*) FROM torre.map_veiculo_rastreador GROUP BY 1;")
    for r in cur.fetchall():
        print(f"map_veiculo_rastreador: {r[0]} -> {r[1]} placas")
except Exception as e:
    conn.rollback()
    print(f"Erro map_veiculo_rastreador: {e}")

try:
    cur.execute("SELECT placa, provedor_rastreador FROM torre.map_veiculo_rastreador WHERE placa IN ('TBQ1G08', 'SFM3H49', 'UBA9H34', 'SEL1F45', 'UBK4B52');")
    for r in cur.fetchall():
        print(f"Placa {r[0]} mapeada como: {r[1]}")
except Exception as e:
    conn.rollback()
    print(e)

print("\n" + "="*80)
print("2. INVESTIGAÇÃO DE EVENTOS DE VELOCIDADE EM BRONZE.NUXEO_POSICAO_EVENTOS")
print("="*80)
cur.execute("""
    SELECT 
        t.placa,
        t.cidade,
        t.estado,
        t.data_gps,
        t.velocidade,
        t.qtd_eventos,
        jsonb_array_length(t.eventos_json) AS len_eventos,
        t.ingested_at
    FROM bronze.nuxeo_posicao_eventos t
    WHERE t.eventos_json IS NOT NULL 
      AND jsonb_array_length(t.eventos_json) > 0
      AND t.ingested_at >= CURRENT_DATE - INTERVAL '14 days'
    LIMIT 10;
""")
for r in cur.fetchall():
    print(f"Placa: {r[0]} | Local: {r[1]}/{r[2]} | GPS: {r[3]} | Vel: {r[4]} | QtdEvt: {r[5]} (Array: {r[6]}) | Ingested: {r[7]}")

print("\n" + "="*80)
print("3. QUAIS PLACAS DISTINTAS TÊM EVENTOS NO NUXEO NOS ÚLTIMOS 14 DIAS?")
print("="*80)
cur.execute("""
    SELECT 
        t.placa,
        COUNT(*) AS qtd_registros,
        COUNT(DISTINCT COALESCE(evt->>'dateEvent', evt->>'date')) AS datas_distintas,
        MIN(COALESCE(evt->>'dateEvent', evt->>'date')) AS min_date,
        MAX(COALESCE(evt->>'dateEvent', evt->>'date')) AS max_date,
        MAX(NULLIF(REPLACE(evt->>'speed', ',', '.'), '')::numeric) AS vel_max
    FROM bronze.nuxeo_posicao_eventos t,
    LATERAL jsonb_array_elements(t.eventos_json) AS evt
    WHERE t.ingested_at >= CURRENT_DATE - INTERVAL '14 days'
    GROUP BY t.placa
    ORDER BY qtd_registros DESC;
""")
for r in cur.fetchall():
    print(f"Placa: {r[0]} | Registros: {r[1]} | Datas Distintas: {r[2]} | Período: {r[3]} até {r[4]} | VelMax: {r[5]}")

print("\n" + "="*80)
print("4. EXISTEM OUTROS EVENTOS OU VELOCIDADES NA NUXEO ALÉM DO ARRAY EVENTOS_JSON?")
print("="*80)
cur.execute("""
    SELECT 
        COUNT(*) AS total_posicoes,
        COUNT(DISTINCT t.placa) AS total_placas,
        COUNT(CASE WHEN t.velocidade > 80 THEN 1 END) AS vel_acima_80,
        COUNT(CASE WHEN t.velocidade > 100 THEN 1 END) AS vel_acima_100,
        COUNT(CASE WHEN t.velocidade > 110 THEN 1 END) AS vel_acima_110
    FROM bronze.nuxeo_posicao_eventos t
    WHERE t.ingested_at >= CURRENT_DATE - INTERVAL '14 days';
""")
r = cur.fetchone()
print(f"Total posições: {r[0]} | Placas: {r[1]} | Vel > 80: {r[2]} | Vel > 100: {r[3]} | Vel > 110: {r[4]}")

print("\n" + "="*80)
print("5. 3STEC: ONDE ESTÃO OS EVENTOS DA 3STEC?")
print("="*80)
cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'bronze' AND table_name LIKE '%tres%' OR table_name LIKE '%3s%';")
for r in cur.fetchall():
    print(f"Tabela 3S: {r[0]}")

cur.execute("SELECT COUNT(*) FROM bronze.tres_s_veiculos;")
print(f"Veículos 3S: {cur.fetchone()[0]}")

cur.execute("SELECT COUNT(*) FROM bronze.tres_s_eventos;")
print(f"Eventos 3S: {cur.fetchone()[0]}")

cur.close()
conn.close()
