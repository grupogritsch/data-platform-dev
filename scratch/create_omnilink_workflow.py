import json
import os

CREDENTIAL_3S_DW = {
    "postgres": {
        "id": "rpwYRdA37HSZhsvm",
        "name": "Interno - DW"
    }
}

def create_omnilink_workflow(filepath):
    wf = {
        "name": "OMNILINK - 01 - Ingestao Posicoes e Telemetria (WSTT)",
        "nodes": [
            {
                "parameters": {
                    "rule": {
                        "interval": [
                            {
                                "field": "hours",
                                "hoursInterval": 1
                            }
                        ]
                    }
                },
                "id": "00-trigger",
                "name": "00 - A cada 1 hora",
                "type": "n8n-nodes-base.scheduleTrigger",
                "typeVersion": 1.2,
                "position": [ 0, 0 ]
            },
            {
                "parameters": {
                    "method": "POST",
                    "url": "https://wstt.omnilink.com.br/iasws/iasws.asmx",
                    "sendHeaders": True,
                    "headerParameters": {
                        "parameters": [
                            { "name": "Content-Type", "value": "text/xml; charset=utf-8" },
                            { "name": "SOAPAction", "value": "http://microsoft.com/webservices/ObtemAllPosicoesAtuais" }
                        ]
                    },
                    "sendBody": True,
                    "specifyBody": "keypair",
                    "bodyParameters": {
                        "parameters": []
                    },
                    "options": { 
                        "response": {
                            "response": {
                                "responseFormat": "text"
                            }
                        },
                        "timeout": 60000 
                    }
                },
                "id": "01-request",
                "name": "01 - Request ObtemAllPosicoesAtuais (SOAP)",
                "type": "n8n-nodes-base.httpRequest",
                "typeVersion": 4.2,
                "position": [ 220, 0 ],
                "notes": "EDITE: insira seu Usuario e Senha da Omnilink no corpo SOAP XML."
            },
            {
                "parameters": {
                    "jsCode": """// Parse XML de resposta da Omnilink
const rawXml = $json.data || $json.body || '';

// Extrair payload dentro de <return>...</return>
let xmlText = '';
const match = rawXml.match(/<return[^>]*>([\\s\\S]*?)<\\/return>/i);
if (match && match[1]) {
  xmlText = match[1].replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
}

// Regex simples para capturar tags da Omnilink
const items = [];
const itemRegex = /<teleevento>([\\s\\S]*?)<\\/teleevento>/gi;
let m;
while ((m = itemRegex.exec(xmlText)) !== null) {
  const block = m[1];
  const placa = (block.match(/<placa>([^<]*)<\\/placa>/i) || [])[1] || '';
  const serial = (block.match(/<serial>([^<]*)<\\/serial>/i) || [])[1] || '';
  const dataGps = (block.match(/<data>([^<]*)<\\/data>/i) || [])[1] || '';
  const vel = (block.match(/<velocidade>([^<]*)<\\/velocidade>/i) || [])[1] || '0';
  const ign = (block.match(/<ignicao>([^<]*)<\\/ignicao>/i) || [])[1] || '';
  const cidade = (block.match(/<cidade>([^<]*)<\\/cidade>/i) || [])[1] || '';
  const uf = (block.match(/<uf>([^<]*)<\\/uf>/i) || [])[1] || '';
  const lat = (block.match(/<latitude>([^<]*)<\\/latitude>/i) || [])[1] || '0';
  const lon = (block.match(/<longitude>([^<]*)<\\/longitude>/i) || [])[1] || '0';

  if (placa) {
    items.push({
      placa: placa.toUpperCase().replace(/[^A-Z0-9]/g, ''),
      complemento: 'OMNILINK - ' + placa.toUpperCase(),
      serial: serial,
      cidade: cidade,
      estado: uf,
      latitude: parseFloat(lat.replace(',', '.')) || 0,
      longitude: parseFloat(lon.replace(',', '.')) || 0,
      data_gps: dataGps,
      ignicao: ign.toLowerCase().includes('lig')
    });
  }
}

return [{
  json: {
    records: items,
    total: items.length
  }
}];"""
                },
                "id": "02-parse",
                "name": "02 - Parse XML Omnilink",
                "type": "n8n-nodes-base.code",
                "typeVersion": 2,
                "position": [ 440, 0 ]
            },
            {
                "parameters": {
                    "operation": "executeQuery",
                    "query": """INSERT INTO bronze.nuxeo_veiculos_posicao 
(placa, complemento, serial, cidade, estado, latitude, longitude, data_gps, ignicao)
SELECT 
    r->>'placa',
    r->>'complemento',
    r->>'serial',
    r->>'cidade',
    r->>'estado',
    (r->>'latitude')::numeric,
    (r->>'longitude')::numeric,
    r->>'data_gps',
    (r->>'ignicao')::boolean
FROM jsonb_array_elements($1::jsonb) AS r;""",
                    "options": {
                        "queryReplacement": "={{ [ JSON.stringify($json.records) ] }}"
                    }
                },
                "id": "03-carrega-posicoes",
                "name": "03 - Carrega Posicoes Omnilink DW",
                "type": "n8n-nodes-base.postgres",
                "typeVersion": 2.4,
                "position": [ 660, 0 ],
                "credentials": CREDENTIAL_3S_DW
            },
            {
                "parameters": {
                    "operation": "executeQuery",
                    "query": """INSERT INTO torre.map_veiculo_rastreador (placa, provedor_rastreador, origem_mapeamento, observacao)
SELECT DISTINCT 
    UPPER(REPLACE(r->>'placa', '-', '')) AS placa,
    'OMNILINK' AS provedor_rastreador,
    'API' AS origem_mapeamento,
    'Validado via API Omnilink WSTT' AS observacao
FROM jsonb_array_elements($1::jsonb) AS r
JOIN torre.gold_dim_veiculo v ON UPPER(REPLACE(v.placa, '-', '')) = UPPER(REPLACE(r->>'placa', '-', ''))
WHERE v.situacao_veiculo NOT IN ('VENDIDO', 'BAIXADO')
ON CONFLICT (placa) DO UPDATE SET
    provedor_rastreador = 'OMNILINK',
    origem_mapeamento = 'API',
    observacao = EXCLUDED.observacao,
    atualizado_em = NOW();""",
                    "options": {
                        "queryReplacement": "={{ [ JSON.stringify($('02 - Parse XML Omnilink').first().json.records) ] }}"
                    }
                },
                "id": "04-mapeamento",
                "name": "04 - Atualiza Mapeamento Omnilink DW",
                "type": "n8n-nodes-base.postgres",
                "typeVersion": 2.4,
                "position": [ 880, 0 ],
                "credentials": CREDENTIAL_3S_DW
            }
        ],
        "connections": {
            "00 - A cada 1 hora": { "main": [ [ { "node": "01 - Request ObtemAllPosicoesAtuais (SOAP)", "type": "main", "index": 0 } ] ] },
            "01 - Request ObtemAllPosicoesAtuais (SOAP)": { "main": [ [ { "node": "02 - Parse XML Omnilink", "type": "main", "index": 0 } ] ] },
            "02 - Parse XML Omnilink": { "main": [ [ { "node": "03 - Carrega Posicoes Omnilink DW", "type": "main", "index": 0 } ] ] },
            "03 - Carrega Posicoes Omnilink DW": { "main": [ [ { "node": "04 - Atualiza Mapeamento Omnilink DW", "type": "main", "index": 0 } ] ] }
        },
        "settings": { "executionOrder": "v1" }
    }

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow Omnilink criado com sucesso: {filepath}")

if __name__ == '__main__':
    create_omnilink_workflow('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/OMNILINK - 01 - Ingestao Posicoes e Telemetria (WSTT).json')
