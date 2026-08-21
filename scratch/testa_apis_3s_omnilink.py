#!/usr/bin/env python3
"""
Teste de Conectividade e Retorno das APIs 3STEC e OMNILINK
"""
import sys
import os
sys.path.append('/home/gabriel/Projetos/data-platform-dev')
from dotenv import load_dotenv

load_dotenv('/home/gabriel/Projetos/data-platform-dev/.env')

print("="*80)
print("1. TESTANDO API DA 3STEC")
print("="*80)
try:
    from scripts.ingest_3s_telemetria import login_3s, fetch_3s_veiculos, fetch_3s_posicoes
    u3s = os.getenv('TRES_S_USUARIO')
    p3s = os.getenv('TRES_S_SENHA')
    print(f"Tentando login 3S com usuário: {u3s}")
    token = login_3s(u3s, p3s)
    print(f"✅ Token 3S obtido com sucesso! Token: {token[:20]}...")
    
    veiculos = fetch_3s_veiculos(token)
    print(f"✅ Veículos cadastrados na 3S: {len(veiculos)}")
    
    posicoes = fetch_3s_posicoes(token)
    print(f"✅ Últimas Posições retornadas pela 3S: {len(posicoes)}")
    
    # Amostra de posições
    if posicoes:
        print("Amostra 3S:", posicoes[0])
except Exception as e:
    print(f"❌ Erro na 3STEC: {e}")

print("\n" + "="*80)
print("2. TESTANDO API DA OMNILINK")
print("="*80)
try:
    from scripts.ingest_omnilink_telemetria import call_omnilink_soap
    u_omni = os.getenv('OMNILINK_USUARIO')
    p_omni = os.getenv('OMNILINK_SENHA')
    print(f"Tentando chamada SOAP Omnilink com usuário: {u_omni}")
    omni_pos = call_omnilink_soap('ObtemAllPosicoesAtuais', u_omni, p_omni)
    print(f"✅ Posições retornadas pela Omnilink: {len(omni_pos)}")
    if omni_pos:
        print("Amostra Omnilink:", omni_pos[0])
except Exception as e:
    print(f"❌ Erro na Omnilink: {e}")
