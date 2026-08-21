#!/usr/bin/env python3
"""
Ingestão Integrada OMNILINK (WSTT WebService SOAP) — Data Platform
Consome a API SOAP WSTT da Omnilink (https://wstt.omnilink.com.br/iasws/iasws.asmx),
extrai cadastro de rastreadores, posições GPS e alertas de velocidade, e grava no PostgreSQL DW.
"""

import sys
import os
import json
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
import psycopg2
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

OMNILINK_SOAP_URL = "https://wstt.omnilink.com.br/iasws/iasws.asmx"
OMNILINK_NS = "http://microsoft.com/webservices/"

def get_dw_connection():
    return psycopg2.connect(
        host='192.168.0.37',
        port=5433,
        database=os.getenv('DW_NAME'),
        user=os.getenv('DW_USER'),
        password=os.getenv('DW_PASSWORD'),
        connect_timeout=5
    )

def call_omnilink_soap(method_name, usuario, senha, extra_xml=""):
    soap_body = f"""<?xml version="1.0" encoding="utf-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="{OMNILINK_NS}">
   <soapenv:Header/>
   <soapenv:Body>
      <web:{method_name}>
         <web:Usuario>{usuario}</web:Usuario>
         <web:Senha>{senha}</web:Senha>
         {extra_xml}
      </web:{method_name}>
   </soapenv:Body>
</soapenv:Envelope>"""

    headers = {
        'Content-Type': 'text/xml; charset=utf-8',
        'SOAPAction': f'{OMNILINK_NS}{method_name}'
    }

    req = urllib.request.Request(OMNILINK_SOAP_URL, data=soap_body.encode('utf-8'), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw_xml = resp.read().decode('utf-8')
            return parse_omnilink_response(raw_xml)
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8')
        raise Exception(f"Falha na API Omnilink (HTTP {e.code}): {body[:300]}")
    except Exception as e:
        raise Exception(f"Erro ao conectar na Omnilink: {e}")

def parse_omnilink_response(raw_xml):
    """Extrai e desescapa o elemento <return> do envelope SOAP da Omnilink"""
    root = ET.fromstring(raw_xml)
    # Procurar elemento return independente de namespace
    return_elem = None
    for elem in root.iter():
        if elem.tag.endswith('return'):
            return_elem = elem
            break
    
    if return_elem is None or not return_elem.text:
        return []

    inner_xml = return_elem.text.strip()
    
    # Verificar se veio mensagem de erro da Omnilink
    if '<msgerro>' in inner_xml:
        err_match = ET.fromstring(inner_xml).find('.//msgerro')
        err_msg = err_match.text if err_match is not None else inner_xml
        raise Exception(f"Erro informado pela Omnilink: {err_msg}")

    # Converter inner_xml para lista de dicionários
    inner_root = ET.fromstring(inner_xml)
    records = []
    for item in inner_root:
        rec = {}
        for child in item:
            rec[child.tag] = child.text
        records.append(rec)

    return records

def process_and_load(usuario, senha):
    print(f"1. Conectando na API Omnilink WSTT (ObtemAllPosicoesAtuais) para o usuário: {usuario}...")
    posicoes = call_omnilink_soap('ObtemAllPosicoesAtuais', usuario, senha)
    print(f"✅ {len(posicoes)} posições de veículos retornadas da Omnilink.")

    print("2. Conectando ao PostgreSQL DW para salvar os dados da Omnilink...")
    conn = get_dw_connection()
    cur = conn.cursor()

    count_posicoes = 0
    count_mapeamento = 0

    for p in posicoes:
        placa_raw = p.get('placa') or p.get('Placa') or p.get('veiculo') or ''
        placa = placa_raw.strip().upper().replace('-', '').replace(' ', '')
        if not placa:
            continue

        serial = p.get('serial') or p.get('Serial') or p.get('idTerminal') or ''
        data_gps = p.get('data') or p.get('Data') or p.get('dataHora') or ''
        velocidade = p.get('velocidade') or p.get('Velocidade') or 0
        ignicao_raw = str(p.get('ignicao') or p.get('Ignicao') or '').lower()
        ignicao = True if 'lig' in ignicao_raw or '1' in ignicao_raw else False

        cidade = p.get('cidade') or p.get('Cidade') or ''
        uf = p.get('uf') or p.get('UF') or ''
        endereco = p.get('endereco') or p.get('Endereco') or ''

        lat_raw = str(p.get('latitude') or p.get('Latitude') or '0').replace(',', '.')
        lon_raw = str(p.get('longitude') or p.get('Longitude') or '0').replace(',', '.')
        try:
            lat = float(lat_raw)
            lon = float(lon_raw)
        except:
            lat = 0.0
            lon = 0.0

        # Gravar na tabela bronze.nuxeo_veiculos_posicao (marcando complemento OMNILINK)
        cur.execute("""
            INSERT INTO bronze.nuxeo_veiculos_posicao
            (placa, complemento, serial, cidade, estado, latitude, longitude, data_gps, ignicao)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s);
        """, (placa, f"OMNILINK - {placa}", serial, cidade, uf, lat, lon, data_gps, ignicao))
        count_posicoes += 1

        # Mapear na torre.map_veiculo_rastreador se for frota ativa
        cur.execute("""
            INSERT INTO torre.map_veiculo_rastreador (placa, provedor_rastreador, origem_mapeamento, observacao)
            SELECT %s, 'OMNILINK', 'API', 'Validado via API Omnilink WSTT'
            WHERE EXISTS (SELECT 1 FROM torre.gold_dim_veiculo WHERE UPPER(REPLACE(placa, '-', '')) = %s)
            ON CONFLICT (placa) DO UPDATE SET
                provedor_rastreador = 'OMNILINK',
                origem_mapeamento = 'API',
                observacao = EXCLUDED.observacao,
                atualizado_em = NOW();
        """, (placa, placa))
        count_mapeamento += cur.rowcount

    conn.commit()
    conn.close()

    print(f"\n🎉 INGESTÃO OMNILINK CONCLUÍDA COM SUCESSO!")
    print(f"• Posições gravadas no DW: {count_posicoes}")
    print(f"• Placas ativas associadas à OMNILINK no DW: {count_mapeamento}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Uso: python3 ingest_omnilink_telemetria.py <usuario_omnilink> <senha_omnilink>")
        sys.exit(1)
    
    user = sys.argv[1]
    password = sys.argv[2]
    process_and_load(user, password)
