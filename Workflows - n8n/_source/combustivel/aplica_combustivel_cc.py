# -*- coding: utf-8 -*-
"""Aplica a SQL/JS atualizados (CC completo) e acrescenta o ccEmail que
faltava no node 'Enviar Consolidado (Diretoria)'."""
import io
import json

BASE = r'\\wsl.localhost\Ubuntu\home\gabriel\Projetos\data-platform-dev\Workflows - n8n'
ARQ = BASE + r'\Torre de Controle - Alertas Combustivel e Ociosidade Semanal.json'
SCR = r'C:\Users\GABRIE~1.BRI\AppData\Local\Temp\claude\--wsl-localhost-Ubuntu-home-gabriel-Projetos-data-platform-dev\ec95a802-0dfb-4662-b90d-9f31f379223b\scratchpad'

d = json.load(io.open(ARQ, encoding='utf-8'))
n = {x['name']: x for x in d['nodes']}

nova_sql = io.open(SCR + r'\sql_combustivel_semanal.sql', encoding='utf-8').read()
n['Buscar Dados Consolidados']['parameters']['query'] = nova_sql
print('SQL atualizada: %d chars' % len(nova_sql))

novo_filial = io.open(SCR + r'\html_combustivel_semanal_filial.js', encoding='utf-8').read()
n['Gerar HTML por Filial']['parameters']['jsCode'] = novo_filial
print('Gerar HTML por Filial atualizado: %d chars' % len(novo_filial))

novo_consol = io.open(SCR + r'\html_combustivel_semanal_consolidado.js', encoding='utf-8').read()
n['Consolidar Geral (Diretoria)']['parameters']['jsCode'] = novo_consol
print('Consolidar Geral (Diretoria) atualizado: %d chars' % len(novo_consol))

# --- Nodes de envio --------------------------------------------------------
# ATENCAO (bug real, 24/08/2026): no emailSend v2.1 do n8n, ccEmail e
# attachments sao propriedades da COLLECTION 'options'. ccEmail posto no
# nivel superior de parameters e' SILENCIOSAMENTE IGNORADO -- roda sem erro
# e simplesmente nao manda copia. Foi o que quebrou o CC do combustivel
# enquanto o telemetria (que sempre teve options.ccEmail) funcionava.
# NUNCA escrever parameters['ccEmail'] -- sempre parameters['options']['ccEmail'].
# A logo TruckPag entra como anexo inline: o n8n da cid=nomeDaPropriedade
# a todo item de options.attachments, referenciado como cid:logo_truckpag.
ENVIOS = {
    'Enviar Email + CSV por Filial': 'attachment_frota,attachment_postos,attachment_transacoes',
    'Enviar Consolidado (Diretoria)': '',
}

for nome, anexos_base in ENVIOS.items():
    p = n[nome]['parameters']
    lixo = p.pop('ccEmail', None)  # remove residuo do lugar errado, se houver
    if lixo is not None:
        print('%s: removido ccEmail do nivel errado (%r)' % (nome, lixo))

    opts = p.setdefault('options', {})
    opts['ccEmail'] = '={{ $json.ccFinal }}'

    partes = [x.strip() for x in (opts.get('attachments') or anexos_base).split(',') if x.strip()]
    if 'logo_truckpag' not in partes:
        partes.append('logo_truckpag')
    opts['attachments'] = ','.join(partes)
    print('%s.options = %s' % (nome, json.dumps(opts, ensure_ascii=False)))

io.open(ARQ, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False, indent=2))
print('\nOK — gravado.')

# --- Verificacao pos-gravacao ----------------------------------------------
conf = json.load(io.open(ARQ, encoding='utf-8'))
nc = {x['name']: x for x in conf['nodes']}
for nome in ENVIOS:
    p = nc[nome]['parameters']
    assert 'ccEmail' not in p, 'ccEmail voltou pro nivel errado em ' + nome
    assert p['options'].get('ccEmail'), 'options.ccEmail ausente em ' + nome
    print('verificado: %s -> options.ccEmail OK' % nome)
