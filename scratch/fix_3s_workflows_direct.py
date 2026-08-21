import json

USER_3S = "referencia.locadora919"
PASS_3S = "d01m04"
CREDENTIAL_3S_DW = {
    "postgres": {
        "id": "rpwYRdA37HSZhsvm",
        "name": "Interno - DW"
    }
}

def create_clean_workflow_10(filepath):
    wf = {
        "name": "3S - 10 - Ingestao Cadastro (ListaVeiculos)",
        "nodes": [
            {
                "parameters": {
                    "rule": {
                        "interval": [
                            {
                                "field": "cronExpression",
                                "expression": "0 5 * * *"
                            }
                        ]
                    }
                },
                "id": "00-trigger",
                "name": "00 - Diario 05h",
                "type": "n8n-nodes-base.scheduleTrigger",
                "typeVersion": 1.2,
                "position": [ 0, 0 ]
            },
            {
                "parameters": {
                    "method": "POST",
                    "url": "https://3stecnologia.eti.br/dataexportapi/ValidaLogin",
                    "sendHeaders": True,
                    "headerParameters": {
                        "parameters": [
                            { "name": "Content-Type", "value": "application/json" },
                            { "name": "Accept-Encoding", "value": "identity" }
                        ]
                    },
                    "sendBody": True,
                    "specifyBody": "json",
                    "jsonBody": f"{{\n  \"usuario\": \"{USER_3S}\",\n  \"senha\": \"{PASS_3S}\"\n}}",
                    "options": { "timeout": 60000 }
                },
                "id": "01-login",
                "name": "01 - Login",
                "type": "n8n-nodes-base.httpRequest",
                "typeVersion": 4.2,
                "position": [ 220, 0 ]
            },
            {
                "parameters": {
                    "method": "GET",
                    "url": "https://3stecnologia.eti.br/dataexportapi/ListaVeiculos",
                    "sendHeaders": True,
                    "headerParameters": {
                        "parameters": [
                            { "name": "Authorization", "value": "=\"Bearer \" + ($('01 - Login').first().json.token || $('01 - Login').first().json.result || '')" },
                            { "name": "Accept-Encoding", "value": "identity" }
                        ]
                    },
                    "options": { "timeout": 60000 }
                },
                "id": "02-request",
                "name": "02 - Request ListaVeiculos",
                "type": "n8n-nodes-base.httpRequest",
                "typeVersion": 4.2,
                "position": [ 440, 0 ]
            },
            {
                "parameters": {
                    "jsCode": """const allItems = $input.all().map(i => i.json);
return [{
  json: {
    records: allItems,
    total: allItems.length
  }
}];"""
                },
                "id": "03-agrupa",
                "name": "03 - Agrupa Registros",
                "type": "n8n-nodes-base.code",
                "typeVersion": 2,
                "position": [ 660, 0 ]
            },
            {
                "parameters": {
                    "operation": "executeQuery",
                    "query": "SELECT bronze.fn_carrega_veiculos($1::jsonb, NULL) AS linhas;",
                    "options": {
                        "queryReplacement": "={{ [ JSON.stringify($json.records) ] }}"
                    }
                },
                "id": "04-carrega",
                "name": "04 - Carrega Veiculos DW",
                "type": "n8n-nodes-base.postgres",
                "typeVersion": 2.4,
                "position": [ 880, 0 ],
                "credentials": CREDENTIAL_3S_DW
            },
            {
                "parameters": {
                    "operation": "executeQuery",
                    "query": """INSERT INTO torre.map_veiculo_rastreador (placa, provedor_rastreador, origem_mapeamento, observacao)
SELECT DISTINCT 
    UPPER(REPLACE(t.placa, '-', '')) AS placa,
    '3STEC' AS provedor_rastreador,
    'API' AS origem_mapeamento,
    'Validado via API 3sTec (ListaVeiculos)' AS observacao
FROM bronze.tres_s_veiculos t
JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(v.placa, '-', '')) = UPPER(REPLACE(t.placa, '-', ''))
WHERE v.situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO')
ON CONFLICT (placa) DO UPDATE SET
    provedor_rastreador = '3STEC',
    origem_mapeamento = 'API',
    observacao = EXCLUDED.observacao,
    atualizado_em = NOW();"""
                },
                "id": "05-mapeamento",
                "name": "05 - Atualiza Mapeamento Frota Ativa",
                "type": "n8n-nodes-base.postgres",
                "typeVersion": 2.4,
                "position": [ 1100, 0 ],
                "credentials": CREDENTIAL_3S_DW
            }
        ],
        "connections": {
            "00 - Diario 05h": { "main": [ [ { "node": "01 - Login", "type": "main", "index": 0 } ] ] },
            "01 - Login": { "main": [ [ { "node": "02 - Request ListaVeiculos", "type": "main", "index": 0 } ] ] },
            "02 - Request ListaVeiculos": { "main": [ [ { "node": "03 - Agrupa Registros", "type": "main", "index": 0 } ] ] },
            "03 - Agrupa Registros": { "main": [ [ { "node": "04 - Carrega Veiculos DW", "type": "main", "index": 0 } ] ] },
            "04 - Carrega Veiculos DW": { "main": [ [ { "node": "05 - Atualiza Mapeamento Frota Ativa", "type": "main", "index": 0 } ] ] }
        },
        "settings": { "executionOrder": "v1" }
    }

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow 10 recriado com arquitetura limpa: {filepath}")

def create_clean_workflow_11(filepath):
    wf = {
        "name": "3S - 11 - Ingestao Ultima Posicao",
        "nodes": [
            {
                "parameters": {
                    "rule": {
                        "interval": [
                            {
                                "field": "minutes",
                                "minutesInterval": 30
                            }
                        ]
                    }
                },
                "id": "00-trigger",
                "name": "00 - A cada 30 min",
                "type": "n8n-nodes-base.scheduleTrigger",
                "typeVersion": 1.2,
                "position": [ 0, 0 ]
            },
            {
                "parameters": {
                    "method": "POST",
                    "url": "https://3stecnologia.eti.br/dataexportapi/ValidaLogin",
                    "sendHeaders": True,
                    "headerParameters": {
                        "parameters": [
                            { "name": "Content-Type", "value": "application/json" },
                            { "name": "Accept-Encoding", "value": "identity" }
                        ]
                    },
                    "sendBody": True,
                    "specifyBody": "json",
                    "jsonBody": f"{{\n  \"usuario\": \"{USER_3S}\",\n  \"senha\": \"{PASS_3S}\"\n}}",
                    "options": { "timeout": 60000 }
                },
                "id": "01-login",
                "name": "01 - Login",
                "type": "n8n-nodes-base.httpRequest",
                "typeVersion": 4.2,
                "position": [ 220, 0 ]
            },
            {
                "parameters": {
                    "method": "GET",
                    "url": "https://3stecnologia.eti.br/dataexportapi/ListaUltimaPosicaoVeiculos/0",
                    "sendHeaders": True,
                    "headerParameters": {
                        "parameters": [
                            { "name": "Authorization", "value": "=\"Bearer \" + ($('01 - Login').first().json.token || $('01 - Login').first().json.result || '')" },
                            { "name": "Accept-Encoding", "value": "identity" }
                        ]
                    },
                    "options": { "timeout": 60000 }
                },
                "id": "02-request",
                "name": "02 - Request UltimaPosicao",
                "type": "n8n-nodes-base.httpRequest",
                "typeVersion": 4.2,
                "position": [ 440, 0 ]
            },
            {
                "parameters": {
                    "jsCode": """const allItems = $input.all().map(i => i.json);
return [{
  json: {
    records: allItems,
    total: allItems.length
  }
}];"""
                },
                "id": "03-agrupa",
                "name": "03 - Agrupa Registros",
                "type": "n8n-nodes-base.code",
                "typeVersion": 2,
                "position": [ 660, 0 ]
            },
            {
                "parameters": {
                    "operation": "executeQuery",
                    "query": "SELECT bronze.fn_carrega_ultima_posicao($1::jsonb, NULL) AS linhas;",
                    "options": {
                        "queryReplacement": "={{ [ JSON.stringify($json.records) ] }}"
                    }
                },
                "id": "04-carrega",
                "name": "04 - Carrega Ultima Posicao DW",
                "type": "n8n-nodes-base.postgres",
                "typeVersion": 2.4,
                "position": [ 880, 0 ],
                "credentials": CREDENTIAL_3S_DW
            }
        ],
        "connections": {
            "00 - A cada 30 min": { "main": [ [ { "node": "01 - Login", "type": "main", "index": 0 } ] ] },
            "01 - Login": { "main": [ [ { "node": "02 - Request UltimaPosicao", "type": "main", "index": 0 } ] ] },
            "02 - Request UltimaPosicao": { "main": [ [ { "node": "03 - Agrupa Registros", "type": "main", "index": 0 } ] ] },
            "03 - Agrupa Registros": { "main": [ [ { "node": "04 - Carrega Ultima Posicao DW", "type": "main", "index": 0 } ] ] }
        },
        "settings": { "executionOrder": "v1" }
    }

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow 11 recriado com arquitetura limpa: {filepath}")

if __name__ == '__main__':
    create_clean_workflow_10('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 10 - Ingestao Cadastro (ListaVeiculos).json')
    create_clean_workflow_11('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 11 - Ingestao Ultima Posicao.json')
