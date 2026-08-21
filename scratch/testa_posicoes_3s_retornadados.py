#!/usr/bin/env python3
"""
Teste amplo dos endpoints de eventos e posições da 3STEC
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

# Testar pedir posições com idPosicao
# O idPosicao max era 33450352476
id_pos = 33450352476 - 500

payload = {
    "idEquipamento": 0,
    "idPosicao": id_pos,
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

print(f"Buscando posições na 3S a partir de idPosicao = {id_pos}...")
req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers, method='POST')
with urllib.request.urlopen(req, timeout=60) as resp:
    raw = resp.read().decode('utf-8')
    data = json.loads(raw)
    if isinstance(data, str):
        data = json.loads(data)
    
    dados = data.get('Dados', {})
    pos = dados.get('Posicao', [])
    print(f"✅ Recebidas {len(pos)} posições contínuas da 3STEC!")
    if pos:
        print("Amostra posição 0:", pos[0])
        vels = [float(p.get('Velocidade') or 0) for p in pos]
        print(f"Total posições com vel > 0: {len([v for v in vels if v > 0])}")
        print(f"Pico de velocidade: {max(vels)} km/h")
