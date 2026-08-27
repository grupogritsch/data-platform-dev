# -*- coding: utf-8 -*-
"""Cria 'Torre de Controle - Alertas Pedagio Semanal.json'.

Clona credenciais/typeVersion do workflow de combustivel semanal (mesmo
Postgres 'Interno - DW', mesmo SMTP). Estrutura identica, menos o node
'Salvar Fechamento no DW' -- aquele INSERT e' especifico de combustivel
(tabela gold_fato_fechamento_semanal_combustivel); nao existe tabela
equivalente pra pedagio, entao o workflow termina no envio.

ATENCAO ccEmail: e' propriedade da collection 'options' no emailSend v2.1.
No nivel superior o n8n IGNORA em silencio. Ver memoria do projeto.
"""
import io
import json
import sys
import uuid

sys.stdout.reconfigure(encoding='utf-8')

BASE = r'\\wsl.localhost\Ubuntu\home\gabriel\Projetos\data-platform-dev\Workflows - n8n'
ARQ_COMB = BASE + r'\Torre de Controle - Alertas Combustivel e Ociosidade Semanal.json'
ARQ_PED = BASE + r'\Torre de Controle - Alertas Pedagio Semanal.json'
SCR = r'C:\Users\GABRIE~1.BRI\AppData\Local\Temp\claude\--wsl-localhost-Ubuntu-home-gabriel-Projetos-data-platform-dev\ec95a802-0dfb-4662-b90d-9f31f379223b\scratchpad'

comb = json.load(io.open(ARQ_COMB, encoding='utf-8'))
nc = {x['name']: x for x in comb['nodes']}


def clona(node, novo_nome, pos):
    n = json.loads(json.dumps(node))
    n['id'] = str(uuid.uuid4())
    n['name'] = novo_nome
    n['position'] = pos
    n.pop('webhookId', None)
    return n


sql = io.open(SCR + r'\sql_pedagio_semanal.sql', encoding='utf-8').read()
js_filial = io.open(SCR + r'\html_pedagio_semanal_filial.js', encoding='utf-8').read()
js_consol = io.open(SCR + r'\html_pedagio_semanal_consolidado.js', encoding='utf-8').read()

nodes = []

nodes.append(clona(nc['Executar Manualmente'], 'Executar Manualmente', [-400, 300]))

# Cron: terca 08:00. O combustivel semanal roda terca 07:00 -- 1h de folga
# pra nao competir pelo mesmo slot nem pela mesma conexao do Postgres.
n_cron = clona(nc['Disparo Semanal (Segunda-Feira)'], 'Disparo Semanal (Terça 08h)', [-400, 460])
n_cron['parameters'] = {'rule': {'interval': [{'field': 'cronExpression', 'expression': '0 8 * * 2'}]}}
nodes.append(n_cron)

# Config: top_pracas no lugar de top_postos. Mantem data_inicio/fim_custom,
# porque o node 'Calcular Período' (clonado do combustivel) le esses campos.
n_cfg = clona(nc['⚙️ Configurações'], '⚙️ Configurações', [-160, 380])
n_cfg['parameters'] = {
    'assignments': {'assignments': [
        {'id': 'param-modo-producao', 'name': 'modo_producao', 'value': False, 'type': 'boolean'},
        {'id': 'param-email-teste', 'name': 'email_teste', 'value': 'gabriel.brittes@gritsch.com.br', 'type': 'string'},
        {'id': 'param-top-pracas', 'name': 'top_pracas', 'value': 8, 'type': 'number'},
        {'id': 'param-data-inicio-custom', 'name': 'data_inicio_custom', 'value': '', 'type': 'string'},
        {'id': 'param-data-fim-custom', 'name': 'data_fim_custom', 'value': '', 'type': 'string'},
    ]},
    'options': {},
}
nodes.append(n_cfg)

# Calcular Periodo: identico ao do combustivel (mesma regra seg-a-seg,
# fechamento na terca). Trocado so top_postos -> top_pracas no retorno.
n_per = clona(nc['Calcular Período'], 'Calcular Período', [80, 380])
code_per = n_per['parameters']['jsCode']
assert 'top_postos: cfg.top_postos' in code_per, 'assinatura esperada nao encontrada no Calcular Período'
n_per['parameters']['jsCode'] = code_per.replace('top_postos: cfg.top_postos', 'top_pracas: cfg.top_pracas')
nodes.append(n_per)

n_sql = clona(nc['Buscar Dados Consolidados'], 'Buscar Dados Pedágio', [320, 380])
n_sql['parameters']['query'] = sql
nodes.append(n_sql)

n_hf = clona(nc['Gerar HTML por Filial'], 'Gerar HTML por Filial', [560, 260])
n_hf['parameters']['jsCode'] = js_filial
nodes.append(n_hf)

n_hc = clona(nc['Consolidar Geral (Diretoria)'], 'Consolidar Geral (Diretoria)', [560, 500])
n_hc['parameters']['jsCode'] = js_consol
nodes.append(n_hc)

# --- Envios: ccEmail SEMPRE dentro de options ------------------------------
n_ef = clona(nc['Enviar Email + CSV por Filial'], 'Enviar Email + CSV por Filial', [800, 260])
n_ef['parameters']['subject'] = "=Controle de Pedágio | {{ $json.filial_nome }} | {{ $('Calcular Período').first().json.dataRef }}"
n_ef['parameters']['options'] = {
    'appendAttribution': False,
    'attachments': 'attachment_frota,attachment_pracas,attachment_passagens,logo_truckpag',
    'ccEmail': '={{ $json.ccFinal }}',
}
n_ef['parameters'].pop('ccEmail', None)
nodes.append(n_ef)

n_ec = clona(nc['Enviar Consolidado (Diretoria)'], 'Enviar Consolidado (Diretoria)', [800, 500])
n_ec['parameters']['subject'] = "=Visão Geral Semanal | Controle de Pedágio | {{ $('Calcular Período').first().json.dataRef }}"
n_ec['parameters']['options'] = {
    'appendAttribution': False,
    'attachments': 'logo_truckpag',
    'ccEmail': '={{ $json.ccFinal }}',
}
n_ec['parameters'].pop('ccEmail', None)
nodes.append(n_ec)

connections = {
    'Executar Manualmente': {'main': [[{'node': '⚙️ Configurações', 'type': 'main', 'index': 0}]]},
    'Disparo Semanal (Terça 08h)': {'main': [[{'node': '⚙️ Configurações', 'type': 'main', 'index': 0}]]},
    '⚙️ Configurações': {'main': [[{'node': 'Calcular Período', 'type': 'main', 'index': 0}]]},
    'Calcular Período': {'main': [[{'node': 'Buscar Dados Pedágio', 'type': 'main', 'index': 0}]]},
    'Buscar Dados Pedágio': {'main': [[
        {'node': 'Gerar HTML por Filial', 'type': 'main', 'index': 0},
        {'node': 'Consolidar Geral (Diretoria)', 'type': 'main', 'index': 0},
    ]]},
    'Gerar HTML por Filial': {'main': [[{'node': 'Enviar Email + CSV por Filial', 'type': 'main', 'index': 0}]]},
    'Consolidar Geral (Diretoria)': {'main': [[{'node': 'Enviar Consolidado (Diretoria)', 'type': 'main', 'index': 0}]]},
}

wf = {
    'name': 'Torre de Controle - Alertas Pedagio Semanal',
    'nodes': nodes,
    'connections': connections,
    'settings': comb.get('settings', {'executionOrder': 'v1'}),
    'meta': comb.get('meta', {}),
    'id': 'TorreControlePedagioSemanal',
    'tags': comb.get('tags', []),
}

io.open(ARQ_PED, 'w', encoding='utf-8').write(json.dumps(wf, ensure_ascii=False, indent=2))
print('Criado:', ARQ_PED)
print('Nodes:', len(nodes))
for n in nodes:
    print('  -', n['name'], '|', n['type'])

# --- Verificacao pos-gravacao ----------------------------------------------
print()
conf = json.load(io.open(ARQ_PED, encoding='utf-8'))
cn = {x['name']: x for x in conf['nodes']}
for nome in ['Enviar Email + CSV por Filial', 'Enviar Consolidado (Diretoria)']:
    p = cn[nome]['parameters']
    assert 'ccEmail' not in p, 'ccEmail no nivel errado em ' + nome
    assert p['options'].get('ccEmail'), 'options.ccEmail ausente em ' + nome
    assert 'logo_truckpag' in p['options']['attachments'], 'logo ausente em ' + nome
    print('OK %-32s options.ccEmail + logo conferidos' % nome)

print('OK %-32s mode=%s' % ('Gerar HTML por Filial',
                            cn['Gerar HTML por Filial']['parameters'].get('mode')))
print('OK %-32s credencial Postgres: %s' % ('Buscar Dados Pedágio',
                                            cn['Buscar Dados Pedágio']['credentials']['postgres']['name']))
