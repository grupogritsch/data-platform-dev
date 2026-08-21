#!/usr/bin/env python3
"""
Ingestão Contínua e Robusta de Telemetria 3STEC (Posições e Velocidades)
Consome o endpoint RetornaDados com idPosicao incremental e grava no PostgreSQL DW (bronze.tres_s_posicoes).
"""
import os
import sys
import json
import urllib.request
import urllib.error
from datetime import datetime
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

sys.path.append('/home/gabriel/Projetos/data-platform-dev')
load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

from scripts.ingest_3s_telemetria import login_3s

def get_dw_conn():
    return psycopg2.connect(
        host='192.168.0.37', port=5433, database='dw',
        user='gabriel_brittes', password=os.getenv('DW_PASSWORD')
    )

def run_ingest(max_batches=20):
    print("="*80)
    print("INGESTÃO DE TELEMETRIA 3STEC EM TEMPO REAL (RetornaDados -> DW)")
    print("="*80)

    u3s = os.getenv('TRES_S_USUARIO')
    p3s = os.getenv('TRES_S_SENHA')
    token = login_3s(u3s, p3s)
    print("✅ Token 3S obtido!")

    conn = get_dw_conn()
    cur = conn.cursor()

    cur.execute("SELECT ultimo_id FROM bronze.tres_s_watermark WHERE dominio = 'posicao';")
    row = cur.fetchone()
    ultimo_id = row[0] if row and row[0] > 0 else 0

    url = "https://3stecnologia.eti.br/dataexportapi/RetornaDados"
    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json', 'Accept-Encoding': 'identity'}

    if ultimo_id == 0:
        print("Obtendo ID mais recente na 3STEC...")
        p_init = {"idEquipamento":0,"idPosicao":0,"idSensor":0,"idMensagem":0,"idTelemetria":0,"idAlertaVelocidade":0,"idAlertaSensor":0,"idAlertaTemperatura":0,"idAlertaTempoOperacaoContinua":0,"idAlertaJornadaDiaria":0,"idAlertaMovimentacaoindevida":0,"idCercaAlvo":0,"idCercaCheckPoint":0,"idCercaLogradouro":0,"idCercaPoligonal":0,"idCercaRota":0}
        req_init = urllib.request.Request(url, data=json.dumps(p_init).encode('utf-8'), headers=headers, method='POST')
        with urllib.request.urlopen(req_init, timeout=30) as resp:
            d_init = json.loads(resp.read().decode('utf-8'))
            if isinstance(d_init, str): d_init = json.loads(d_init)
            pos_list = d_init.get('Dados', {}).get('Posicao', [])
            curr_pos_id = pos_list[0].get('idPosicao', 0) if pos_list else 0
            # Começar 200.000 posições atrás para pegar histórico recente de todas as viagens ativas
            ultimo_id = max(0, curr_pos_id - 200000)
            print(f"Cursor inicial configurado para: {ultimo_id} (ID atual: {curr_pos_id})")

    insert_sql = """
        INSERT INTO bronze.tres_s_posicoes (
            data_ref, id_posicao, id_equipamento, placa, data_gps, data_hora_timestamp,
            velocidade, ignicao, satelite, altitude, direcao, uf, cidade, bairro, endereco,
            numero, cep, latitude, longitude, odometro, horimetro, payload_json, ingested_at
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW()
        );
    """

    total_ingeridos = 0

    for batch in range(1, max_batches + 1):
        payload = {
            "idEquipamento": 0,
            "idPosicao": ultimo_id,
            "idSensor": 0,
            "idMensagem": 0,
            "idTelemetria": 0,
            "idAlertaVelocidade": 0,
            "idAlertaSensor": 0,
            "idAlertaTemperatura": 0,
            "idAlertaTempoOperacaoContinua": 0,
            "idAlertaJornadaDiaria": 0,
            "idAlertaMovimentacaoindevida": 0,
            "idCercaAlvo": 0,
            "idCercaCheckPoint": 0,
            "idCercaLogradouro": 0,
            "idCercaPoligonal": 0,
            "idCercaRota": 0
        }

        req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers, method='POST')
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                raw = resp.read().decode('utf-8')
                data = json.loads(raw)
                if isinstance(data, str): data = json.loads(data)

                posicoes = data.get('Dados', {}).get('Posicao', [])
                if not posicoes:
                    print(f"Lote {batch}: Sem novas posições após ID {ultimo_id}.")
                    break

                records = []
                max_pos_id = ultimo_id
                for p in posicoes:
                    p_id = p.get('idPosicao')
                    if not p_id: continue
                    try:
                        p_id_int = int(p_id)
                        if p_id_int > max_pos_id: max_pos_id = p_id_int
                    except:
                        pass

                    placa_raw = p.get('Placa') or ''
                    placa = placa_raw.replace(' ', '').replace('-', '').upper()
                    dt_gps = p.get('Data') or p.get('DataGPS') or ''
                    vel_str = str(p.get('Velocidade') or '0')
                    ign = str(p.get('Ignicao') or '')
                    sat = str(p.get('Satelite') or '')
                    alt = str(p.get('Altitude') or '')
                    direc = str(p.get('Direcao') or '')
                    uf = str(p.get('UF') or '')
                    cidade = str(p.get('Cidade') or '')
                    bairro = str(p.get('Bairro') or '')
                    end = str(p.get('Endereco') or '')
                    num = str(p.get('Numero') or '')
                    cep = str(p.get('CEP') or '')
                    lat = str(p.get('Latitude') or '')
                    lon = str(p.get('Longitude') or '')
                    odo = str(p.get('Odometro') or '')
                    hor = str(p.get('Horimetro') or '')
                    eq_id = str(p.get('idEquipamento') or '')

                    dt_ref = None
                    dt_ts = None
                    if dt_gps and len(dt_gps) >= 10:
                        try:
                            dt_ts = datetime.strptime(dt_gps[:19], '%d/%m/%Y %H:%M:%S')
                            dt_ref = dt_ts.date()
                        except:
                            pass

                    records.append((
                        dt_ref, str(p_id), eq_id, placa, dt_gps, dt_ts,
                        vel_str, ign, sat, alt, direc, uf, cidade, bairro, end,
                        num, cep, lat, lon, odo, hor, json.dumps(p)
                    ))

                if records:
                    psycopg2.extras.execute_batch(cur, insert_sql, records, page_size=1000)
                    cur.execute("""
                        UPDATE bronze.tres_s_watermark 
                        SET ultimo_id = %s, atualizado_em = NOW() 
                        WHERE dominio = 'posicao';
                    """, (max_pos_id,))
                    conn.commit()
                    total_ingeridos += len(records)
                    ultimo_id = max_pos_id
                    print(f"Lote {batch:2}: ✅ {len(records)} posições salvas no DW. Último ID: {ultimo_id}")

        except Exception as e:
            conn.rollback()
            print(f"Erro no lote {batch}: {e}")
            break

    print(f"\n🎉 Processamento finalizado! Total gravado no DW: {total_ingeridos} posições.")
    cur.close()
    conn.close()

if __name__ == '__main__':
    run_ingest(max_batches=20)
