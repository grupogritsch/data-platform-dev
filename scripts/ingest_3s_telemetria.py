#!/usr/bin/env python3
"""
Ingestão Integrada 3STEC (3S) — Data Platform
Consome a API REST da 3S (https://3stecnologia.eti.br/dataexportapi), extrai cadastro de veículos
e últimas posições GPS, e insere no PostgreSQL DW (bronze.tres_s_veiculos, bronze.tres_s_ultima_posicao
e torre.map_veiculo_rastreador).
"""

import sys
import os
import json
import urllib.request
import urllib.error
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

BASE_URL = "https://3stecnologia.eti.br/dataexportapi"

def get_dw_connection():
    return psycopg2.connect(
        host='192.168.0.37',
        port=5433,
        database=os.getenv('DW_NAME'),
        user=os.getenv('DW_USER'),
        password=os.getenv('DW_PASSWORD'),
        connect_timeout=5
    )

def login_3s(usuario, senha):
    url = f"{BASE_URL}/ValidaLogin"
    payload = json.dumps({"usuario": usuario, "senha": senha}).encode('utf-8')
    headers = {
        'Content-Type': 'application/json',
        'Accept-Encoding': 'identity',
        'User-Agent': 'Mozilla/5.0'
    }

    req = urllib.request.Request(url, data=payload, headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode('utf-8')
            data = json.loads(raw)
            if isinstance(data, str):
                data = json.loads(data)
            token = data.get('token') or data.get('result') if isinstance(data, dict) else data
            return token
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8')
        raise Exception(f"Falha de Autenticação 3S (HTTP {e.code}): {body}")
    except Exception as e:
        raise Exception(f"Erro ao conectar na 3S: {e}")

def fetch_3s_veiculos(token):
    url = f"{BASE_URL}/ListaVeiculos"
    headers = {
        'Authorization': f'Bearer {token}',
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0'
    }

    req = urllib.request.Request(url, headers=headers, method='GET')
    with urllib.request.urlopen(req) as resp:
        raw = resp.read().decode('utf-8')
        data = json.loads(raw)
        if isinstance(data, str):
            data = json.loads(data)
        return data

def fetch_3s_posicoes(token):
    url = f"{BASE_URL}/ListaUltimaPosicaoVeiculos/0"
    headers = {
        'Authorization': f'Bearer {token}',
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0'
    }

    req = urllib.request.Request(url, headers=headers, method='GET')
    with urllib.request.urlopen(req) as resp:
        raw = resp.read().decode('utf-8')
        data = json.loads(raw)
        if isinstance(data, str):
            data = json.loads(data)
        return data

def process_and_load(usuario, senha):
    print(f"1. Autenticando na 3STEC REST API com usuário: {usuario}...")
    token = login_3s(usuario, senha)
    print("✅ Login realizado com sucesso! Token obtido.")

    print("2. Buscando cadastro de veículos da 3S (ListaVeiculos)...")
    veiculos = fetch_3s_veiculos(token)
    print(f"✅ {len(veiculos)} veículos retornados da API 3S.")

    print("3. Buscando últimas posições GPS da 3S (ListaUltimaPosicaoVeiculos/0)...")
    posicoes = fetch_3s_posicoes(token)
    print(f"✅ {len(posicoes)} posições GPS retornadas da API 3S.")

    print("4. Conectando ao PostgreSQL DW para salvar os dados...")
    conn = get_dw_connection()
    cur = conn.cursor()

    count_veiculos = 0
    count_posicoes = 0
    count_mapeamento = 0

    # Inserir no cadastro bronze.tres_s_veiculos
    for v in veiculos:
        if not isinstance(v, dict):
            continue
        placa = (v.get('Placa') or v.get('placa') or '').strip().upper().replace('-', '').replace(' ', '')
        if not placa:
            continue
        
        id_equipamento = v.get('idEquipamento') or v.get('id_equipamento')
        id_veiculo = v.get('idVeiculo') or v.get('id_veiculo')
        num_serie = str(v.get('NumSerie') or v.get('num_serie') or '')
        modelo = v.get('Modelo') or v.get('modelo') or ''
        chassis = v.get('Chassis') or v.get('chassis') or ''
        frota = v.get('Frota') or v.get('frota') or ''
        renavam = str(v.get('Renavam') or v.get('renavam') or '')
        tipo = v.get('Tipo') or v.get('tipo') or ''
        id_cliente = v.get('idCliente') or v.get('id_cliente') or ''

        cur.execute("""
            INSERT INTO bronze.tres_s_veiculos (id_equipamento, id_veiculo, id_cliente, num_serie, placa, frota, modelo, chassis, renavam, tipo, payload_json, ingested_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
            ON CONFLICT (id_equipamento) DO UPDATE SET
                id_veiculo = EXCLUDED.id_veiculo,
                id_cliente = EXCLUDED.id_cliente,
                num_serie = EXCLUDED.num_serie,
                placa = EXCLUDED.placa,
                frota = EXCLUDED.frota,
                modelo = EXCLUDED.modelo,
                chassis = EXCLUDED.chassis,
                renavam = EXCLUDED.renavam,
                tipo = EXCLUDED.tipo,
                payload_json = EXCLUDED.payload_json,
                ingested_at = NOW();
        """, (id_equipamento, id_veiculo, id_cliente, num_serie, placa, frota, modelo, chassis, renavam, tipo, json.dumps(v)))
        count_veiculos += 1

    print(f"✅ {count_veiculos} veículos gravados em bronze.tres_s_veiculos.")

    # Inserir posições em bronze.tres_s_ultima_posicao (snapshot unificado)
    for p in posicoes:
        if not isinstance(p, dict):
            continue
        id_equipamento = p.get('idEquipamento') or p.get('id_equipamento')
        if not id_equipamento:
            continue
        
        id_veiculo = p.get('idVeiculo') or p.get('id_veiculo')
        placa = (p.get('Placa') or p.get('placa') or '').strip().upper().replace('-', '').replace(' ', '')
        num_serie = str(p.get('NumSerie') or p.get('num_serie') or '')
        frota = p.get('Frota') or p.get('frota') or ''
        modelo = p.get('Modelo') or p.get('modelo') or ''
        data_gps_str = p.get('Data') or p.get('dataGps') or p.get('data_gps')
        velocidade = p.get('Velocidade') or p.get('velocidade') or 0
        ignicao_raw = str(p.get('Ignicao') or p.get('ignicao') or '').lower()
        ignicao = True if 'ligado' in ignicao_raw or ignicao_raw == 'true' or ignicao_raw == '1' else False
        
        satelite = p.get('Satelite') or p.get('satelite') or 0
        direcao = p.get('Direcao') or p.get('direcao') or ''
        uf = p.get('UF') or p.get('uf') or ''
        cidade = p.get('Cidade') or p.get('cidade') or ''
        endereco = p.get('Endereco') or p.get('endereco') or ''
        numero = p.get('Numero') or p.get('numero') or 0
        cep = str(p.get('CEP') or p.get('cep') or '')
        
        lat_raw = str(p.get('Latitude') or p.get('latitude') or '0').replace(',', '.')
        lon_raw = str(p.get('Longitude') or p.get('longitude') or '0').replace(',', '.')
        try:
            lat = float(lat_raw)
            lon = float(lon_raw)
        except:
            lat = 0.0
            lon = 0.0

        bloqueio = p.get('Bloqueio') or p.get('bloqueio') or ''
        bat_backup = p.get('BatBackup') or p.get('bat_backup') or ''
        odometro = p.get('Odometro') or p.get('odometro') or 0
        horimetro = p.get('Hourmeter') or p.get('horimetro') or 0

        cur.execute("""
            INSERT INTO bronze.tres_s_ultima_posicao 
            (id_equipamento, id_veiculo, placa, num_serie, frota, modelo, data_gps, velocidade, ignicao, satelite, direcao, uf, cidade, endereco, numero, cep, latitude, longitude, bloqueio, bat_backup, odometro, horimetro, payload_json, atualizado_em)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
            ON CONFLICT (id_equipamento) DO UPDATE SET
                id_veiculo = EXCLUDED.id_veiculo,
                placa = EXCLUDED.placa,
                num_serie = EXCLUDED.num_serie,
                frota = EXCLUDED.frota,
                modelo = EXCLUDED.modelo,
                data_gps = EXCLUDED.data_gps,
                velocidade = EXCLUDED.velocidade,
                ignicao = EXCLUDED.ignicao,
                satelite = EXCLUDED.satelite,
                direcao = EXCLUDED.direcao,
                uf = EXCLUDED.uf,
                cidade = EXCLUDED.cidade,
                endereco = EXCLUDED.endereco,
                numero = EXCLUDED.numero,
                cep = EXCLUDED.cep,
                latitude = EXCLUDED.latitude,
                longitude = EXCLUDED.longitude,
                bloqueio = EXCLUDED.bloqueio,
                bat_backup = EXCLUDED.bat_backup,
                odometro = EXCLUDED.odometro,
                horimetro = EXCLUDED.horimetro,
                payload_json = EXCLUDED.payload_json,
                atualizado_em = NOW();
        """, (id_equipamento, id_veiculo, placa, num_serie, frota, modelo, data_gps_str, velocidade, ignicao, satelite, direcao, uf, cidade, endereco, numero, cep, lat, lon, bloqueio, bat_backup, odometro, horimetro, json.dumps(p)))
        count_posicoes += 1

    print(f"✅ {count_posicoes} posições gravadas em bronze.tres_s_ultima_posicao.")

    # Atualizar mapeamento em massa para todas as placas 3S que pertencem à frota ativa
    cur.execute("""
        INSERT INTO torre.map_veiculo_rastreador (placa, provedor_rastreador, origem_mapeamento, observacao)
        SELECT DISTINCT 
            UPPER(REPLACE(t.placa, '-', '')) AS placa,
            '3STEC' AS provedor_rastreador,
            'API' AS origem_mapeamento,
            'Validado via API 3sTec (ListaVeiculos)' AS observacao
        FROM bronze.tres_s_veiculos t
        JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(v.placa, '-', '')) = UPPER(REPLACE(t.placa, '-', ''))
        WHERE v.situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO')
        ON CONFLICT (placa) DO UPDATE SET
            provedor_rastreador = '3STEC',
            origem_mapeamento = 'API',
            observacao = EXCLUDED.observacao,
            atualizado_em = NOW();
    """)
    count_mapeamento = cur.rowcount
    print(f"✅ {count_mapeamento} placas vinculadas em torre.map_veiculo_rastreador.")

    conn.commit()
    conn.close()

    print(f"\n🎉 PROCESSO 3S CONCLUÍDO COM SUCESSO!")
    print(f"• Veículos 3S cadastrados/atualizados no DW: {count_veiculos}")
    print(f"• Posições GPS gravadas no DW (tres_s_ultima_posicao): {count_posicoes}")
    print(f"• Placas ativas associadas à 3STEC no DW: {count_mapeamento}")

if __name__ == '__main__':
    user = sys.argv[1] if len(sys.argv) > 1 else 'referencia.locadora919'
    password = sys.argv[2] if len(sys.argv) > 2 else 'd01m04'
    process_and_load(user, password)
