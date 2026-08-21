#!/usr/bin/env python3
"""
Teste de Profundidade Histórica do RetornaDados na 3STEC
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
print(f"✅ Token 3S obtido!")

url = "https://3stecnologia.eti.br/dataexportapi/RetornaDados"

# Testando buscar posições de 1 dia atrás, 3 dias atrás, 10 dias atrás
# idPosicao atual: ~33450352476
# Aproximadamente 1 milhão de posições por dia na 3S:
# 1 dia ~ 1.000.000 IDs
# Vamos testar vários offsets:
offsets = [10000, 50000, 200000, 1000000, 5000000, 15000000]
base_id = 33450352476

for off in offsets:
    id_test = base_id - off
    payload = {
        "idEquipamento": 0,
        "idPosicao": id_test,
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

    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json', 'Accept-Encoding': 'identity'}
    req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if isinstance(data, str):
                data = json.loads(data)
            pos = data.get('Dados', {}).get('Posicao', [])
            if pos:
                dt_primeira = pos[0].get('Data') or pos[0].get('DataGPS')
                dt_ultima = pos[-1].get('Data') or pos[-1].get('DataGPS')
                print(f"Offset -{off:8} (ID {id_test}): {len(pos)} posições | De: {dt_primeira} até {dt_ultima}")
            else:
                print(f"Offset -{off:8} (ID {id_test}): 0 posições")
    except Exception as e:
        print(f"Offset -{off:8}: Erro {e}")
