#!/usr/bin/env python3
"""
Sincronização ao Vivo das 3.179 Posições da 3STEC no PostgreSQL DW
"""
import os
import sys
import json
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

sys.path.append('/home/gabriel/Projetos/data-platform-dev')
load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

from scripts.ingest_3s_telemetria import login_3s, fetch_3s_posicoes

conn = psycopg2.connect(
    host='192.168.0.37',
    port=5433,
    database='dw',
    user='gabriel_brittes',
    password=os.getenv('DW_PASSWORD')
)
cur = conn.cursor()

print("1. Autenticando e buscando posições ao vivo na 3STEC...")
u3s = os.getenv('TRES_S_USUARIO')
p3s = os.getenv('TRES_S_SENHA')
token = login_3s(u3s, p3s)
posicoes = fetch_3s_posicoes(token)
print(f"✅ {len(posicoes)} posições recebidas da 3STEC.")

print("2. Atualizando bronze.tres_s_ultima_posicao no DW...")
cur.execute("""
    CREATE TABLE IF NOT EXISTS bronze.tres_s_ultima_posicao (
        id_equipamento VARCHAR(50) PRIMARY KEY,
        id_veiculo VARCHAR(50),
        placa VARCHAR(20),
        modelo VARCHAR(100),
        data_gps VARCHAR(50),
        velocidade VARCHAR(20),
        cidade VARCHAR(100),
        uf VARCHAR(10),
        latitude VARCHAR(50),
        longitude VARCHAR(50),
        payload_json JSONB,
        atualizado_em TIMESTAMPTZ DEFAULT NOW()
    );
""")

upsert_sql = """
    INSERT INTO bronze.tres_s_ultima_posicao (
        id_equipamento, id_veiculo, placa, modelo, data_gps, velocidade,
        cidade, uf, latitude, longitude, payload_json, atualizado_em
    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
    ON CONFLICT (id_equipamento) DO UPDATE SET
        id_veiculo = EXCLUDED.id_veiculo,
        placa = EXCLUDED.placa,
        modelo = EXCLUDED.modelo,
        data_gps = EXCLUDED.data_gps,
        velocidade = EXCLUDED.velocidade,
        cidade = EXCLUDED.cidade,
        uf = EXCLUDED.uf,
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude,
        payload_json = EXCLUDED.payload_json,
        atualizado_em = NOW();
"""

records = []
for p in posicoes:
    id_eq = str(p.get('idEquipamento') or '')
    id_v = str(p.get('idVeiculo') or '')
    placa_raw = p.get('Placa') or ''
    placa_limpa = placa_raw.replace(' ', '').replace('-', '').upper()
    modelo = p.get('Modelo') or ''
    data_gps = p.get('Data') or ''
    vel = str(p.get('Velocidade') or 0)
    cidade = p.get('Cidade') or ''
    uf = p.get('UF') or ''
    lat = str(p.get('Latitude') or '').replace(',', '.')
    lon = str(p.get('Longitude') or '').replace(',', '.')
    records.append((id_eq, id_v, placa_limpa, modelo, data_gps, vel, cidade, uf, lat, lon, json.dumps(p)))

psycopg2.extras.execute_batch(cur, upsert_sql, records, page_size=500)
conn.commit()
print(f"✅ {len(records)} registros da 3STEC sincronizados no DW com sucesso!")

print("\n--- TESTANDO A VIEW CONSOLIDADA APÓS A CARGA ---")
cur.execute("""
    SELECT 
        provedor_rastreador,
        COUNT(*) AS total_alertas,
        COUNT(DISTINCT placa) AS total_veiculos,
        MAX(velocidade_registrada) AS vel_max,
        ROUND(AVG(velocidade_registrada)::numeric, 1) AS vel_media
    FROM torre.vw_alertas_telemetria_saneados
    GROUP BY provedor_rastreador
    ORDER BY total_alertas DESC;
""")
for r in cur.fetchall():
    print(f"  📡 {r[0]:10} -> {r[1]:4} alertas | {r[2]:3} veículos | Pico: {r[3]:.0f} km/h | Média: {r[4]} km/h")

cur.close()
conn.close()
