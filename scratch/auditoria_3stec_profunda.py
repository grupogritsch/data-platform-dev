#!/usr/bin/env python3
"""
Auditoria Completa da 3STEC: API ao Vivo, DW e Filiais
"""
import os
import sys
import psycopg2
from dotenv import load_dotenv

sys.path.append('/home/gabriel/Projetos/data-platform-dev')
load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

from scripts.ingest_3s_telemetria import login_3s, fetch_3s_veiculos, fetch_3s_posicoes

conn = psycopg2.connect(
    host='192.168.0.37',
    port=5433,
    database='dw',
    user='gabriel_brittes',
    password=os.getenv('DW_PASSWORD')
)
cur = conn.cursor()

print("="*80)
print("1. CONSULTANDO A API AO VIVO DA 3STEC (AGORA)")
print("="*80)
u3s = os.getenv('TRES_S_USUARIO')
p3s = os.getenv('TRES_S_SENHA')
token = login_3s(u3s, p3s)
print(f"✅ Login 3S com sucesso!")

posicoes_3s = fetch_3s_posicoes(token)
print(f"Total de posições retornadas pela API 3S agora: {len(posicoes_3s)}")

# Análise de datas e velocidades na API 3S
from datetime import datetime
datas_gps = []
excesso_3s = []
for p in posicoes_3s:
    # Exemplo: '19/08/2026 15:10:00'
    dt_str = p.get('Data') or p.get('dataGps') or ''
    vel = float(p.get('Velocidade') or 0)
    placa = p.get('Placa') or ''
    modelo = p.get('Modelo') or ''
    cidade = p.get('Cidade') or ''
    uf = p.get('UF') or ''
    if vel > 80:
        excesso_3s.append((placa, modelo, vel, dt_str, cidade, uf))

print(f"Total de veículos na API 3S com velocidade > 80 km/h agora: {len(excesso_3s)}")
print("\nTop 15 veículos com velocidade > 80 km/h na API 3STEC AO VIVO:")
for ex in sorted(excesso_3s, key=lambda x: x[2], reverse=True)[:15]:
    print(f"  🚗 3S Placa: {ex[0]} | Modelo: {ex[1]} | Vel: {ex[2]} km/h | Data GPS: {ex[3]} | Local: {ex[4]}/{ex[5]}")

print("\n" + "="*80)
print("2. CRUZANDO OS VEÍCULOS DA 3STEC COM O CADASTRO MASTER DE FILIAIS (GOLD_DIM_VEICULO)")
print("="*80)
cur.execute("""
    SELECT 
        COALESCE(v.filial_operacional, 'SEM_FILIAL_CADASTRADA') AS filial,
        COUNT(*) AS total_veiculos_3s
    FROM bronze.tres_s_veiculos t
    LEFT JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) = v.placa
    GROUP BY 1
    ORDER BY total_veiculos_3s DESC
    LIMIT 20;
""")
for r in cur.fetchall():
    print(f"  🏢 Filial 3STEC: {r[0]:30} -> {r[1]} veículos")

print("\n" + "="*80)
print("3. NA FILIAL GRITSCH - GOI: EXISTEM VEÍCULOS 3STEC EM GOIÂNIA?")
print("="*80)
cur.execute("""
    SELECT 
        t.placa,
        t.modelo,
        COALESCE(v.filial_operacional, 'DESCONHECIDA') AS filial,
        COALESCE(v.grupo_veiculo, 'Leve') AS grupo,
        p.velocidade,
        p.data_gps,
        p.cidade,
        p.uf
    FROM bronze.tres_s_veiculos t
    LEFT JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) = v.placa
    LEFT JOIN bronze.tres_s_ultima_posicao p ON p.id_equipamento = t.id_equipamento
    WHERE v.filial_operacional LIKE '%GOI%' OR p.cidade ILIKE '%Goiânia%'
    LIMIT 10;
""")
res_goi = cur.fetchall()
if not res_goi:
    print("  ⚠️ Nenhum veículo da 3STEC pertence à filial GRITSCH - GOI no cadastro Master!")
else:
    for r in res_goi:
        print(f"  Placa: {r[0]} | Modelo: {r[1]} | Filial: {r[2]} | Vel: {r[4]} km/h | Data: {r[5]} | Local: {r[6]}/{r[7]}")

print("\n" + "="*80)
print("4. ATUALIZANDO A TABELA BRONZE.TRES_S_ULTIMA_POSICAO COM OS DADOS FRESCOS DA API")
print("="*80)
# Vamos ver quantas linhas a API trouxe
print(f"Atualizando {len(posicoes_3s)} posições no DW...")
for p in posicoes_3s:
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
    
    cur.execute("""
        INSERT INTO bronze.tres_s_ultima_posicao (
            id_equipamento, id_veiculo, placa, modelo, data_gps, velocidade,
            cidade, uf, latitude, longitude, payload_json, atualizado_em
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
        ON CONFLICT (id_equipamento) DO UPDATE SET
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
    """, (id_eq, id_v, placa_limpa, modelo, data_gps, vel, cidade, uf, lat, lon, psycopg2.extras.Json(p) if hasattr(psycopg2, 'extras') else json.dumps(p)))

conn.commit()
print("✅ bronze.tres_s_ultima_posicao atualizada com sucesso com dados da API ao vivo!")

cur.close()
conn.close()
