#!/usr/bin/env python3
"""
Depuração detalhada do XML retornado pelo HistoricoPosicaoCompleto
"""
import os
import sys
import xml.etree.ElementTree as ET
import urllib.request
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

u3s = os.getenv('TRES_S_USUARIO')
p3s = os.getenv('TRES_S_SENHA')
SOAP_URL = "https://3stecnologia.eti.br/data_export/data_export.asmx"
SOAP_NS = "http://servicos.3stecnologia.com.br/data_export"

# Pegar 1 equipamento que sabemos que tem posições recentes (ex: SFB7D80 ou SFI9C46)
import psycopg2
conn = psycopg2.connect(host='192.168.0.37', port=5433, database='dw', user='gabriel_brittes', password=os.getenv('DW_PASSWORD'))
cur = conn.cursor()
cur.execute("SELECT id_equipamento, placa FROM bronze.tres_s_ultima_posicao WHERE placa = 'SFB7D80' OR placa = 'UBX4D68' LIMIT 1;")
eq = cur.fetchone()
print(f"Testando equipamento: {eq[0]} | Placa: {eq[1]}")

soap_body = f"""<?xml version="1.0" encoding="utf-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="{SOAP_NS}">
   <soapenv:Header/>
   <soapenv:Body>
      <web:HistoricoPosicaoCompleto>
         <web:Usuario>{u3s}</web:Usuario>
         <web:Senha>{p3s}</web:Senha>
         <web:idEquipamento>{eq[0]}</web:idEquipamento>
         <web:DataInicio>01/08/2026 00:00:00</web:DataInicio>
         <web:DataFim>19/08/2026 23:59:59</web:DataFim>
      </web:HistoricoPosicaoCompleto>
   </soapenv:Body>
</soapenv:Envelope>"""

headers = {'Content-Type': 'text/xml; charset=utf-8', 'SOAPAction': f'{SOAP_NS}/HistoricoPosicaoCompleto'}
req = urllib.request.Request(SOAP_URL, data=soap_body.encode('utf-8'), headers=headers)
with urllib.request.urlopen(req, timeout=30) as resp:
    raw_xml = resp.read().decode('utf-8')
    print(f"Tamanho recebido: {len(raw_xml)} bytes")
    print("Primeiros 600 caracteres:\n", raw_xml[:600])

cur.close()
conn.close()
