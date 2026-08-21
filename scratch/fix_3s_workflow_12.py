import json

USER_3S = "referencia.locadora919"
PASS_3S = "d01m04"
CREDENTIAL_3S_DW = {
    "postgres": {
        "id": "rpwYRdA37HSZhsvm",
        "name": "Interno - DW"
    }
}

def fix_workflow_12(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        wf = json.load(f)

    for n in wf['nodes']:
        if 'postgres' in n['type']:
            n['credentials'] = CREDENTIAL_3S_DW
        
        if n['name'] == '02 - Login':
            n['parameters']['sendBody'] = True
            n['parameters']['specifyBody'] = 'json'
            n['parameters']['jsonBody'] = f'{{\n  "usuario": "{USER_3S}",\n  "senha": "{PASS_3S}"\n}}'

        elif n['name'] == '03 - Request RetornaDados':
            if 'headerParameters' in n['parameters']:
                for p in n['parameters']['headerParameters']['parameters']:
                    if p['name'] == 'Authorization':
                        p['value'] = '="Bearer " + ($(\'02 - Login\').first().json.token || $(\'02 - Login\').first().json.result || \'\')'

        elif n['name'] == '04 - Grava Raw Response':
            n['parameters']['options'] = {
                'queryReplacement': '={{ [ JSON.stringify($(\'03 - Request RetornaDados\').all().map(i => i.json)) ] }}'
            }

    # Add Node 09: Consolida Alertas na Torre if not present
    has_node9 = any(n['name'] == '09 - Consolida Alertas na Torre' for n in wf['nodes'])
    if not has_node9:
        node9 = {
            "parameters": {
                "operation": "executeQuery",
                "query": "SELECT torre.fn_processa_alertas_3s() AS alertas_processados;"
            },
            "id": "09-consolida-alertas",
            "name": "09 - Consolida Alertas na Torre",
            "type": "n8n-nodes-base.postgres",
            "typeVersion": 2.4,
            "position": [ 1300, 0 ],
            "credentials": CREDENTIAL_3S_DW
        }
        wf['nodes'].append(node9)
        wf['connections']['07 - Carrega Eventos'] = {
            "main": [ [ { "node": "09 - Consolida Alertas na Torre", "type": "main", "index": 0 } ] ]
        }

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow 12 enriquecido com sucesso: {filepath}")

if __name__ == '__main__':
    fix_workflow_12('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 12 - Ingestao Eventos (RetornaDados Incremental).json')
