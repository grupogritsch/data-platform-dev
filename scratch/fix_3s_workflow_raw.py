import json

def fix_3s_raw_response(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        wf = json.load(f)

    for n in wf['nodes']:
        if n['name'] == '03 - Grava Raw Response':
            node02_name = [x['name'] for x in wf['nodes'] if x['name'].startswith('02 - Request')][0]
            n['parameters']['options'] = {
                'queryReplacement': "={{ [ JSON.stringify($('" + node02_name + "').all().map(i => i.json)) ] }}"
            }

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow corrigido: {filepath}")

if __name__ == '__main__':
    fix_3s_raw_response('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 10 - Ingestao Cadastro (ListaVeiculos).json')
    fix_3s_raw_response('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 11 - Ingestao Ultima Posicao.json')
