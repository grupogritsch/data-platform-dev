#!/usr/bin/env python3
"""
Teste direto do endpoint RetornaDados da 3STEC
"""
import os
import sys
import json
import urllib.request
import urllib.error
from dotenv import load_dotenv

sys.path.append('/home/gabriel/Projetos/data-platform-dev')
load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

from scripts.ingest_3s_telemetria import login_3s

u3s = os.getenv('TRES_S_USUARIO')
p3s = os.getenv('TRES_S_SENHA')
token = login_3s(u3s, p3s)
print(f"✅ Login 3S com sucesso! Token: {token[:20]}...")

url = "https://3stecnologia.eti.br/dataexportapi/RetornaDados"
payload = {
    "idEquipamento": 0,
    "idPosicao": 0,
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

headers = {
    'Authorization': f'Bearer {token}',
    'Content-Type': 'application/json',
    'Accept-Encoding': 'identity',
    'User-Agent': 'Mozilla/5.0'
}

print("Chamando RetornaDados com idAlertaVelocidade: 0...")
req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers, method='POST')
try:
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read().decode('utf-8')
        print(f"HTTP {resp.status} - Tamanho recebido: {len(raw)} bytes")
        data = json.loads(raw)
        if isinstance(data, str):
            data = json.loads(data)
        
        print("Tipo retornado:", type(data))
        if isinstance(data, dict):
            print("Chaves:", list(data.keys()))
            for k, v in data.items():
                if isinstance(v, list):
                    print(f"  Chave '{k}': {len(v)} itens")
                    if len(v) > 0:
                        print(f"    Amostra de {k}[0]:", v[0])
                else:
                    print(f"  Chave '{k}': {v}")
        elif isinstance(data, list):
            print(f"Lista de {len(data)} itens")
            if len(data) > 0:
                print("Amostra item 0:", data[0])
except urllib.error.HTTPError as e:
    print(f"❌ Erro HTTP {e.code}: {e.read().decode('utf-8')}")
except Exception as e:
    print(f"❌ Erro na chamada: {e}")
