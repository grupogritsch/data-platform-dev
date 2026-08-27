# -*- coding: utf-8 -*-
"""Cria 'Torre de Controle - Alertas Combustivel Diario.json' do zero,
clonando credenciais/typeVersion dos nodes equivalentes do semanal (assim
conecta no mesmo Postgres/SMTP sem precisar reconfigurar nada na mao).
Grafo mais enxuto que o semanal: sem CSV, sem 'Salvar Fechamento no DW'."""
import io
import json
import sys
import uuid

sys.stdout.reconfigure(encoding='utf-8')

BASE = r'\\wsl.localhost\Ubuntu\home\gabriel\Projetos\data-platform-dev\Workflows - n8n'
ARQ_SEMANAL = BASE + r'\Torre de Controle - Alertas Combustivel e Ociosidade Semanal.json'
ARQ_DIARIO = BASE + r'\Torre de Controle - Alertas Combustivel Diario.json'
SCR = r'C:\Users\GABRIE~1.BRI\AppData\Local\Temp\claude\--wsl-localhost-Ubuntu-home-gabriel-Projetos-data-platform-dev\ec95a802-0dfb-4662-b90d-9f31f379223b\scratchpad'

semanal = json.load(io.open(ARQ_SEMANAL, encoding='utf-8'))
n_sem = {x['name']: x for x in semanal['nodes']}


def novo_id():
    return str(uuid.uuid4())


def clona_base(node_semanal, novo_nome, pos):
    """Copia type/typeVersion/credentials, troca id/nome/posicao."""
    n = json.loads(json.dumps(node_semanal))  # deep copy
    n['id'] = novo_id()
    n['name'] = novo_nome
    n['position'] = pos
    return n


sql_diario = io.open(SCR + r'\sql_combustivel_diario.sql', encoding='utf-8').read()
periodo_diario = io.open(SCR + r'\calcula_periodo_diario.js', encoding='utf-8').read()
html_filial = io.open(SCR + r'\html_combustivel_diario_filial.js', encoding='utf-8').read()
html_consol = io.open(SCR + r'\html_combustivel_diario_consolidado.js', encoding='utf-8').read()

nodes = []

# 1) Trigger manual
n_manual = clona_base(n_sem['Executar Manualmente'], 'Executar Manualmente', [-400, 300])
nodes.append(n_manual)

# 2) Trigger agendado -- 08:00 seg-sex, 30min apos o telemetria (07:30) e
# claramente separado do semanal (terca 07:00).
n_cron = clona_base(n_sem['Disparo Semanal (Segunda-Feira)'], 'Disparo Diário (Seg-Sex 08h)', [-400, 460])
n_cron['parameters'] = {'rule': {'interval': [{'field': 'cronExpression', 'expression': '0 8 * * 1-5'}]}}
nodes.append(n_cron)

# 3) Configuracoes -- sem top_postos/data_custom (nao usados no diario)
n_cfg = clona_base(n_sem['⚙️ Configurações'], '⚙️ Configurações Diário', [-160, 380])
n_cfg['parameters'] = {
    'assignments': {
        'assignments': [
            {'id': 'param-modo-producao', 'name': 'modo_producao', 'value': False, 'type': 'boolean'},
            {'id': 'param-email-teste', 'name': 'email_teste', 'value': 'gabriel.brittes@gritsch.com.br', 'type': 'string'},
            {'id': 'param-top-postos', 'name': 'top_postos', 'value': 8, 'type': 'number'},
        ]
    },
    'options': {},
}
nodes.append(n_cfg)

# 4) Calcular Periodo Diario
n_periodo = clona_base(n_sem['Calcular Período'], 'Calcular Período Diário', [80, 380])
n_periodo['parameters']['jsCode'] = periodo_diario
nodes.append(n_periodo)

# 5) Buscar Dados Diario (Postgres)
n_sql = clona_base(n_sem['Buscar Dados Consolidados'], 'Buscar Dados Diário', [320, 380])
n_sql['parameters']['query'] = sql_diario
nodes.append(n_sql)

# 6) Gerar HTML por Filial Diario
n_html_f = clona_base(n_sem['Gerar HTML por Filial'], 'Gerar HTML por Filial Diário', [560, 260])
n_html_f['parameters']['jsCode'] = html_filial
nodes.append(n_html_f)

# 7) Consolidar Geral Diario
n_html_c = clona_base(n_sem['Consolidar Geral (Diretoria)'], 'Consolidar Geral Diário (Diretoria)', [560, 500])
n_html_c['parameters']['jsCode'] = html_consol
nodes.append(n_html_c)

# 8 e 9) Nodes de envio -- so o anexo da logo (o diario nao manda CSV).
# ATENCAO (bug real, 24/08/2026): ccEmail e attachments sao propriedades da
# COLLECTION 'options' no emailSend v2.1. ccEmail no nivel superior de
# parameters e' SILENCIOSAMENTE IGNORADO pelo n8n -- roda sem erro e nao
# manda copia nenhuma. Por isso o dict de options abaixo SEMPRE inclui
# ccEmail, e o nivel superior e' limpo logo em seguida.
OPTS_ENVIO = {
    'appendAttribution': False,
    'attachments': 'logo_truckpag',
    'ccEmail': '={{ $json.ccFinal }}',
}

n_env_f = clona_base(n_sem['Enviar Email + CSV por Filial'], 'Enviar Email Diário por Filial', [800, 260])
n_env_f['parameters']['subject'] = "=Combustível Hoje | {{ $json.filial_nome }} | {{ $('Calcular Período Diário').first().json.dataRef }}"
n_env_f['parameters']['options'] = dict(OPTS_ENVIO)
n_env_f['parameters'].pop('ccEmail', None)
nodes.append(n_env_f)

n_env_c = clona_base(n_sem['Enviar Consolidado (Diretoria)'], 'Enviar Consolidado Diário (Diretoria)', [800, 500])
n_env_c['parameters']['subject'] = "=Combustível Hoje | Visão Geral | {{ $('Calcular Período Diário').first().json.dataRef }}"
n_env_c['parameters']['options'] = dict(OPTS_ENVIO)
n_env_c['parameters'].pop('ccEmail', None)
nodes.append(n_env_c)

connections = {
    'Executar Manualmente': {'main': [[{'node': '⚙️ Configurações Diário', 'type': 'main', 'index': 0}]]},
    'Disparo Diário (Seg-Sex 08h)': {'main': [[{'node': '⚙️ Configurações Diário', 'type': 'main', 'index': 0}]]},
    '⚙️ Configurações Diário': {'main': [[{'node': 'Calcular Período Diário', 'type': 'main', 'index': 0}]]},
    'Calcular Período Diário': {'main': [[{'node': 'Buscar Dados Diário', 'type': 'main', 'index': 0}]]},
    'Buscar Dados Diário': {'main': [[
        {'node': 'Gerar HTML por Filial Diário', 'type': 'main', 'index': 0},
        {'node': 'Consolidar Geral Diário (Diretoria)', 'type': 'main', 'index': 0},
    ]]},
    'Gerar HTML por Filial Diário': {'main': [[{'node': 'Enviar Email Diário por Filial', 'type': 'main', 'index': 0}]]},
    'Consolidar Geral Diário (Diretoria)': {'main': [[{'node': 'Enviar Consolidado Diário (Diretoria)', 'type': 'main', 'index': 0}]]},
}

wf = {
    'name': 'Torre de Controle - Alertas Combustivel Diario',
    'nodes': nodes,
    'connections': connections,
    'settings': semanal.get('settings', {'executionOrder': 'v1'}),
    'meta': semanal.get('meta', {}),
    'id': 'TorreControleCombustivelDiario',
    'tags': semanal.get('tags', []),
}

io.open(ARQ_DIARIO, 'w', encoding='utf-8').write(json.dumps(wf, ensure_ascii=False, indent=2))
print('Criado:', ARQ_DIARIO)
print('Nodes:', len(nodes))
for n in nodes:
    print(' -', n['name'], '|', n['type'])
