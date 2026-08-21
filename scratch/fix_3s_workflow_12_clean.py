import json

USER_3S = "referencia.locadora919"
PASS_3S = "d01m04"
CREDENTIAL_3S_DW = {
    "postgres": {
        "id": "rpwYRdA37HSZhsvm",
        "name": "Interno - DW"
    }
}

def create_clean_workflow_12(filepath):
    wf = {
        "name": "3S - 12 - Ingestao Eventos (RetornaDados Incremental)",
        "nodes": [
            {
                "parameters": {
                    "rule": {
                        "interval": [
                            {
                                "field": "minutes",
                                "minutesInterval": 15
                            }
                        ]
                    }
                },
                "id": "00-trigger",
                "name": "00 - A cada 15 min",
                "type": "n8n-nodes-base.scheduleTrigger",
                "typeVersion": 1.2,
                "position": [ 0, 0 ]
            },
            {
                "parameters": {
                    "operation": "executeQuery",
                    "query": "SELECT ultimo_id FROM bronze.tres_s_watermark WHERE dominio = 'ocorrencia_alerta';"
                },
                "id": "01-watermark",
                "name": "01 - Le Watermark",
                "type": "n8n-nodes-base.postgres",
                "typeVersion": 2.4,
                "position": [ 200, 0 ],
                "credentials": CREDENTIAL_3S_DW
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
                "id": "02-login",
                "name": "02 - Login",
                "type": "n8n-nodes-base.httpRequest",
                "typeVersion": 4.2,
                "position": [ 400, 0 ]
            },
            {
                "parameters": {
                    "method": "POST",
                    "url": "https://3stecnologia.eti.br/dataexportapi/RetornaDados",
                    "sendHeaders": True,
                    "headerParameters": {
                        "parameters": [
                            { "name": "Authorization", "value": "=\"Bearer \" + ($('02 - Login').first().json.token || $('02 - Login').first().json.result || '')" },
                            { "name": "Content-Type", "value": "application/json" },
                            { "name": "Accept-Encoding", "value": "identity" }
                        ]
                    },
                    "sendBody": True,
                    "specifyBody": "json",
                    "jsonBody": "={\n  \"idEquipamento\": 0,\n  \"idPosicao\": 0,\n  \"idSensor\": 0,\n  \"idMensagem\": 0,\n  \"idTelemetria\": 0,\n  \"idAlertaVelocidade\": {{ $('01 - Le Watermark').first().json.ultimo_id || 0 }},\n  \"idAlertaSensor\": 0,\n  \"idAlertaTemperatura\": 0,\n  \"idAlertaTempoOperacaoContinua\": 0,\n  \"idAlertaJornadaDiaria\": 0,\n  \"idAlertaMovimentacaoindevida\": 0,\n  \"idCercaAlvo\": 0,\n  \"idCercaCheckPoint\": 0,\n  \"idCercaLogradouro\": 0,\n  \"idCercaPoligonal\": 0,\n  \"idCercaRota\": 0\n}",
                    "options": { "timeout": 60000 }
                },
                "id": "03-request",
                "name": "03 - Request RetornaDados",
                "type": "n8n-nodes-base.httpRequest",
                "typeVersion": 4.2,
                "position": [ 600, 0 ]
            },
            {
                "parameters": {
                    "jsCode": """const res = $json.Dados || $json.dados || $json || {};
const alertasVel = res.AlertaVelocidade || [];

let maxId = $('01 - Le Watermark').first().json.ultimo_id || 0;
const registros = [];

for (const a of alertasVel) {
  const idAlerta = parseInt(a.idAlertaVelocidade || a.idOcorrenciaAlerta, 10);
  if (!isNaN(idAlerta) && idAlerta > maxId) {
    maxId = idAlerta;
  }
  registros.push(a);
}

return [{
  json: {
    records: registros,
    total: registros.length,
    maxId: maxId
  }
}];"""
                },
                "id": "04-split",
                "name": "04 - Parse Alertas Velocidade",
                "type": "n8n-nodes-base.code",
                "typeVersion": 2,
                "position": [ 800, 0 ]
            },
            {
                "parameters": {
                    "operation": "executeQuery",
                    "query": "SELECT bronze.fn_carrega_eventos($1::jsonb, 'ALERTA_VELOCIDADE', NULL) AS linhas;",
                    "options": {
                        "queryReplacement": "={{ [ JSON.stringify($json.records) ] }}"
                    }
                },
                "id": "05-carrega-eventos",
                "name": "05 - Carrega Eventos DW",
                "type": "n8n-nodes-base.postgres",
                "typeVersion": 2.4,
                "position": [ 1000, 0 ],
                "credentials": CREDENTIAL_3S_DW
            },
            {
                "parameters": {
                    "operation": "executeQuery",
                    "query": "SELECT torre.fn_processa_alertas_3s() AS alertas_processados;"
                },
                "id": "06-consolida-relatorio",
                "name": "06 - Consolida Relatorio Velocidade",
                "type": "n8n-nodes-base.postgres",
                "typeVersion": 2.4,
                "position": [ 1200, 0 ],
                "credentials": CREDENTIAL_3S_DW
            },
            {
                "parameters": {
                    "operation": "executeQuery",
                    "query": "UPDATE bronze.tres_s_watermark SET ultimo_id = $1::bigint, updated_at = NOW() WHERE dominio = 'ocorrencia_alerta';",
                    "options": {
                        "queryReplacement": "={{ [ $('04 - Parse Alertas Velocidade').first().json.maxId ] }}"
                    }
                },
                "id": "07-watermark-update",
                "name": "07 - Avanca Watermark",
                "type": "n8n-nodes-base.postgres",
                "typeVersion": 2.4,
                "position": [ 1400, 0 ],
                "credentials": CREDENTIAL_3S_DW
            }
        ],
        "connections": {
            "00 - A cada 15 min": { "main": [ [ { "node": "01 - Le Watermark", "type": "main", "index": 0 } ] ] },
            "01 - Le Watermark": { "main": [ [ { "node": "02 - Login", "type": "main", "index": 0 } ] ] },
            "02 - Login": { "main": [ [ { "node": "03 - Request RetornaDados", "type": "main", "index": 0 } ] ] },
            "03 - Request RetornaDados": { "main": [ [ { "node": "04 - Parse Alertas Velocidade", "type": "main", "index": 0 } ] ] },
            "04 - Parse Alertas Velocidade": { "main": [ [ { "node": "05 - Carrega Eventos DW", "type": "main", "index": 0 } ] ] },
            "05 - Carrega Eventos DW": { "main": [ [ { "node": "06 - Consolida Relatorio Velocidade", "type": "main", "index": 0 } ] ] },
            "06 - Consolida Relatorio Velocidade": { "main": [ [ { "node": "07 - Avanca Watermark", "type": "main", "index": 0 } ] ] }
        },
        "settings": { "executionOrder": "v1" }
    }

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow 3S - 12 recriado com arquitetura limpa: {filepath}")

if __name__ == '__main__':
    create_clean_workflow_12('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 12 - Ingestao Eventos (RetornaDados Incremental).json')
