#!/usr/bin/env python3
"""
Backfill Completo NUXEO & OMNILINK (01/08/2026 a 19/08/2026)
Consome a API REST da Nuxeo dia a dia e insere no PostgreSQL DW (bronze.nuxeo_posicao_eventos)
"""
import os
import sys
import json
import urllib.request
import urllib.parse
from datetime import datetime, timedelta
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

NUXEO_LOGIN_URL = "https://api.nuxeo.com.br/rest/user/login/"
NUXEO_REPORT_URL = "https://api.nuxeo.com.br/rest/report/lastPositionAndEvent/"

def get_dw_conn():
    return psycopg2.connect(
        host='192.168.0.37', port=5433, database='dw',
        user='gabriel_brittes', password=os.getenv('DW_PASSWORD')
    )

def auth_nuxeo():
    payload = json.dumps({"client": "Gritsch", "login": "Gritsch", "psw": "gr1tsch"}).encode('utf-8')
    req = urllib.request.Request(NUXEO_LOGIN_URL, data=payload, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        return data.get('token')

def fetch_period(token, begin_str, end_str):
    url = f"{NUXEO_REPORT_URL}?begin={urllib.parse.quote(begin_str)}&end={urllib.parse.quote(end_str)}"
    req = urllib.request.Request(url, headers={'X-Auth-Token': token})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        return data.get('positions') or data.get('targets') or data if isinstance(data, list) else []

def run_backfill():
    print("="*80)
    print("INICIANDO BACKFILL NUXEO & OMNILINK (01/08/2026 a 19/08/2026)")
    print("="*80)
    
    token = auth_nuxeo()
    print("✅ Autenticado na Nuxeo com sucesso!")

    conn = get_dw_conn()
    cur = conn.cursor()

    start_date = datetime(2026, 8, 1)
    end_date = datetime(2026, 8, 19, 23, 59, 59)
    current = start_date

    insert_sql = """
        INSERT INTO bronze.nuxeo_posicao_eventos (
            placa, complemento, serial, endereco, cidade, estado, pais,
            latitude, longitude, data_gps, ignicao, bloqueio, panico, velocidade,
            bateria, antifurto, qtd_eventos, eventos_json, payload_json, ingested_at
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW()
        );
    """

    total_inseridos = 0

    while current < end_date:
        next_day = min(current + timedelta(days=1), end_date)
        begin_str = current.strftime("%d/%m/%Y %H:%M:%S")
        end_str = next_day.strftime("%d/%m/%Y %H:%M:%S")

        print(f"📥 Buscando Nuxeo/Omnilink: {begin_str} até {end_str}...")
        try:
            positions = fetch_period(token, begin_str, end_str)
            print(f"   -> {len(positions)} posições retornadas da API.")

            records = []
            for pos in positions:
                placa = pos.get('identifier')
                comp = pos.get('complement')
                serial = pos.get('serial')
                addr = pos.get('address')
                city = pos.get('city')
                state = pos.get('state')
                country = pos.get('country')
                lat = pos.get('latitude')
                lon = pos.get('longitude')
                dt_gps = pos.get('dateGps')
                ign = pos.get('ignition')
                blk = pos.get('block')
                panic = pos.get('panic')
                spd = pos.get('speed')
                bat = pos.get('baterry')
                anti = str(pos.get('antiTheft') or '')
                evts = pos.get('events') or []

                records.append((
                    placa, comp, serial, addr, city, state, country,
                    lat, lon, dt_gps, ign, blk, panic, spd, bat, anti,
                    len(evts), json.dumps(evts), json.dumps(pos)
                ))

            if records:
                psycopg2.extras.execute_batch(cur, insert_sql, records, page_size=1000)
                conn.commit()
                total_inseridos += len(records)
                print(f"   ✅ {len(records)} registros gravados no DW (Total acumulado: {total_inseridos})")

        except Exception as e:
            conn.rollback()
            print(f"   ❌ Erro na janela {begin_str} a {end_str}: {e}")

        current = next_day

    print(f"\n🎉 BACKFILL NUXEO/OMNILINK CONCLUÍDO! Total inserido: {total_inseridos} registros.")
    cur.close()
    conn.close()

if __name__ == '__main__':
    run_backfill()
