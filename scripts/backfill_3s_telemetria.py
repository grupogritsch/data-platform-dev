#!/usr/bin/env python3
"""
Backfill Completo 3STEC (01/08/2026 a 19/08/2026)
Consome a API SOAP da 3S (HistoricoPosicaoCompleto) e insere no PostgreSQL DW (bronze.tres_s_posicoes).
"""
import os
import sys
import json
import time
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

u3s = os.getenv('TRES_S_USUARIO')
p3s = os.getenv('TRES_S_SENHA')

SOAP_URL = "https://3stecnologia.eti.br/data_export/data_export.asmx"
SOAP_NS = "http://servicos.3stecnologia.com.br/data_export"

def get_dw_conn():
    return psycopg2.connect(
        host='192.168.0.37', port=5433, database='dw',
        user='gabriel_brittes', password=os.getenv('DW_PASSWORD')
    )

def prepare_dw():
    conn = get_dw_conn()
    cur = conn.cursor()
    cur.execute("""
        ALTER TABLE bronze.tres_s_posicoes ADD COLUMN IF NOT EXISTS placa VARCHAR(20);
        ALTER TABLE bronze.tres_s_posicoes ADD COLUMN IF NOT EXISTS data_hora_timestamp TIMESTAMP;
        CREATE INDEX IF NOT EXISTS idx_tres_s_pos_id_eq ON bronze.tres_s_posicoes (id_equipamento);
        CREATE INDEX IF NOT EXISTS idx_tres_s_pos_placa ON bronze.tres_s_posicoes (placa);
    """)
    conn.commit()
    cur.close()
    conn.close()

def fetch_historico_equipamento(id_equipamento, placa, data_ini, data_fim):
    soap_body = f"""<?xml version="1.0" encoding="utf-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="{SOAP_NS}">
   <soapenv:Header/>
   <soapenv:Body>
      <web:HistoricoPosicaoCompleto>
         <web:Usuario>{u3s}</web:Usuario>
         <web:Senha>{p3s}</web:Senha>
         <web:idEquipamento>{id_equipamento}</web:idEquipamento>
         <web:DataInicio>{data_ini}</web:DataInicio>
         <web:DataFim>{data_fim}</web:DataFim>
      </web:HistoricoPosicaoCompleto>
   </soapenv:Body>
</soapenv:Envelope>"""

    headers = {
        'Content-Type': 'text/xml; charset=utf-8',
        'SOAPAction': f'{SOAP_NS}/HistoricoPosicaoCompleto'
    }

    req = urllib.request.Request(SOAP_URL, data=soap_body.encode('utf-8'), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            xml_resp = resp.read().decode('utf-8')
            return parse_3s_xml(xml_resp, id_equipamento, placa)
    except Exception as e:
        return []

def parse_3s_xml(raw_xml, id_equipamento, placa):
    records = []
    try:
        if '&lt;Posicao&gt;' in raw_xml or '&lt;tbPosicao&gt;' in raw_xml:
            import html
            raw_xml = html.unescape(raw_xml)
        
        root = ET.fromstring(raw_xml)
        for tb in root.iter('tbPosicao'):
            data_dict = {}
            for child in tb:
                data_dict[child.tag] = child.text

            id_pos = data_dict.get('idPosicao')
            if not id_pos:
                continue

            dt_gps = data_dict.get('Data') or data_dict.get('DataGPS') or ''
            vel_str = data_dict.get('Velocidade') or '0'
            ign = data_dict.get('Ignicao') or ''
            sat = data_dict.get('Satelite') or ''
            alt = data_dict.get('Altitude') or ''
            direc = data_dict.get('Direcao') or ''
            uf = data_dict.get('UF') or ''
            cidade = data_dict.get('Cidade') or ''
            bairro = data_dict.get('Bairro') or ''
            end = data_dict.get('Endereco') or ''
            num = data_dict.get('Numero') or ''
            cep = data_dict.get('CEP') or ''
            lat = data_dict.get('Latitude') or ''
            lon = data_dict.get('Longitude') or ''
            odo = data_dict.get('Odometro') or ''
            hor = data_dict.get('Horimetro') or ''

            dt_ref = None
            dt_ts = None
            if dt_gps and len(dt_gps) >= 10:
                try:
                    dt_ts = datetime.strptime(dt_gps[:19], '%d/%m/%Y %H:%M:%S')
                    dt_ref = dt_ts.date()
                except:
                    pass

            records.append((
                dt_ref, str(id_pos), str(id_equipamento), placa, dt_gps, dt_ts,
                vel_str, ign, sat, alt, direc, uf, cidade, bairro, end, num, cep,
                lat, lon, odo, hor, json.dumps(data_dict)
            ))
    except Exception as e:
        pass

    return records

def run_3s_backfill(max_workers=10):
    prepare_dw()
    print("="*80)
    print("INICIANDO BACKFILL 3STEC (01/08/2026 a 19/08/2026)")
    print("="*80)

    conn = get_dw_conn()
    cur = conn.cursor()

    # Buscar equipamentos com placas válidas cadastradas
    cur.execute("""
        SELECT DISTINCT 
            t.id_equipamento,
            UPPER(REPLACE(REPLACE(t.placa, '-', ''), ' ', '')) AS placa,
            t.modelo
        FROM bronze.tres_s_veiculos t
        WHERE t.id_equipamento IS NOT NULL 
          AND t.placa IS NOT NULL 
          AND LENGTH(t.placa) >= 7
        ORDER BY t.id_equipamento DESC;
    """)
    equipamentos = cur.fetchall()
    print(f"Total de equipamentos 3S elegíveis para backfill: {len(equipamentos)}")

    data_ini = "01/08/2026 00:00:00"
    data_fim = "19/08/2026 23:59:59"

    insert_sql = """
        INSERT INTO bronze.tres_s_posicoes (
            data_ref, id_posicao, id_equipamento, placa, data_gps, data_hora_timestamp,
            velocidade, ignicao, satelite, altitude, direcao, uf, cidade, bairro, endereco,
            numero, cep, latitude, longitude, odometro, horimetro, payload_json, ingested_at
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW()
        );
    """

    total_gravados = 0
    processados = 0

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(fetch_historico_equipamento, eq[0], eq[1], data_ini, data_fim): eq
            for eq in equipamentos
        }

        batch_records = []
        for future in as_completed(futures):
            eq = futures[future]
            processados += 1
            try:
                res = future.result()
                if res:
                    batch_records.extend(res)
                    if len(batch_records) >= 1000:
                        psycopg2.extras.execute_batch(cur, insert_sql, batch_records, page_size=1000)
                        conn.commit()
                        total_gravados += len(batch_records)
                        batch_records = []

                if processados % 50 == 0 or processados == len(equipamentos):
                    if batch_records:
                        psycopg2.extras.execute_batch(cur, insert_sql, batch_records, page_size=1000)
                        conn.commit()
                        total_gravados += len(batch_records)
                        batch_records = []
                    print(f"Progresso 3S: {processados}/{len(equipamentos)} veículos ({processados*100//len(equipamentos)}%) | Posições gravadas: {total_gravados}")

            except Exception as e:
                print(f"Erro no equipamento {eq[0]}: {e}")

    print(f"\n🎉 BACKFILL 3STEC FINALIZADO! Total de {total_gravados} posições gravadas no DW!")
    cur.close()
    conn.close()

if __name__ == '__main__':
    run_3s_backfill(max_workers=12)
