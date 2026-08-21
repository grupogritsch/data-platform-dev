import json

def fix_workflow(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        wf = json.load(f)

    for n in wf['nodes']:
        if n['name'] == '01 - Login':
            n['parameters']['sendBody'] = True
            n['parameters']['specifyBody'] = 'json'
            n['parameters']['jsonBody'] = '{\n  "usuario": "__USUARIO__",\n  "senha": "__SENHA__"\n}'
            if 'contentType' in n['parameters']: del n['parameters']['contentType']
            if 'rawContentType' in n['parameters']: del n['parameters']['rawContentType']
            if 'body' in n['parameters']: del n['parameters']['body']
            n['parameters']['options'] = {'timeout': 60000}
        
        elif n['name'].startswith('02 - Request'):
            if 'headerParameters' in n['parameters']:
                for p in n['parameters']['headerParameters']['parameters']:
                    if p['name'] == 'Authorization':
                        p['value'] = '="Bearer " + ($(\'01 - Login\').first().json.token || $(\'01 - Login\').first().json.result || \'\')'
            n['parameters']['options'] = {'timeout': 60000}

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow corrigido com sucesso: {filepath}")

if __name__ == '__main__':
    fix_workflow('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 10 - Ingestao Cadastro (ListaVeiculos).json')
    fix_workflow('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 11 - Ingestao Ultima Posicao.json')
