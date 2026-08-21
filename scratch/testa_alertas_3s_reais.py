#!/usr/bin/env python3
"""
Teste de busca de eventos de velocidade na 3STEC com ID
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

url = "https://3stecnologia.eti.br/dataexportapi/RetornaDados"

# Vamos pedir alertas de velocidade dos últimos 5000 IDs
ultimo_id = 157628925
id_inicio = ultimo_id - 5000

payload = {
    "idEquipamento": 0,
    "idPosicao": 0,
    "idSensor": 0,
    "idMensagem": 0,
    "idTelemetria": 0,
    "idAlertaVelocidade": id_inicio,
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

print(f"Buscando alertas de velocidade na 3S a partir do ID {id_inicio}...")
req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers, method='POST')
with urllib.request.urlopen(req, timeout=60) as resp:
    raw = resp.read().decode('utf-8')
    data = json.loads(raw)
    if isinstance(data, str):
        data = json.loads(data)
    
    dados = data.get('Dados', {})
    alertas = dados.get('AlertaVelocidade', [])
    print(f"✅ Recebidos {len(alertas)} alertas de velocidade da 3STEC!")
    if alertas:
        print("Amostra alerta 0:", alertas[0])
        print("Amostra alerta 1:", alertas[1] if len(alertas) > 1 else "")
        # Analisar campos
        vels = [float(a.get('Velocidade') or 0) for a in alertas]
        print(f"Pico de velocidade nos alertas 3S: {max(vels)} km/h")
