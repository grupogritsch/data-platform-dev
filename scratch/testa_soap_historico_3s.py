#!/usr/bin/env python3
"""
Teste de Métodos Históricos da 3STEC (SOAP e REST) para Backfill
"""
import os
import sys
import json
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

u3s = os.getenv('TRES_S_USUARIO')
p3s = os.getenv('TRES_S_SENHA')

SOAP_URL = "https://3stecnologia.eti.br/data_export/data_export.asmx"
SOAP_NS = "http://servicos.3stecnologia.com.br/data_export"

def test_soap_historico(id_equipamento, data_ini, data_fim):
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
    with urllib.request.urlopen(req, timeout=30) as resp:
        xml_resp = resp.read().decode('utf-8')
        return xml_resp

print("1. Testando HistoricoPosicaoCompleto na 3STEC para 1 equipamento...")
# Vamos pegar 1 equipamento da tabela tres_s_veiculos
import psycopg2
conn = psycopg2.connect(
    host='192.168.0.37', port=5433, database='dw',
    user='gabriel_brittes', password=os.getenv('DW_PASSWORD')
)
cur = conn.cursor()
cur.execute("SELECT id_equipamento, placa, modelo FROM bronze.tres_s_veiculos WHERE placa IS NOT NULL AND placa != '' LIMIT 1;")
eq = cur.fetchone()
print(f"Testando equipamento: {eq[0]} | Placa: {eq[1]} | Modelo: {eq[2]}")

try:
    xml_out = test_soap_historico(eq[0], "01/08/2026 00:00:00", "19/08/2026 23:59:59")
    print(f"✅ Tamanho resposta XML: {len(xml_out)} bytes")
    # Verificar se veio dados
    if "tbPosicao" in xml_out or "Posicao" in xml_out:
        print("✅ Dados de posições retornados com sucesso!")
        print("Trecho:", xml_out[:500])
    else:
        print("Resposta:", xml_out[:400])
except Exception as e:
    print(f"❌ Erro SOAP: {e}")

cur.close()
conn.close()
