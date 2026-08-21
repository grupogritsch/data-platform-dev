import json
import os

CREDENTIAL_3S_DW = {
    "postgres": {
        "id": "rpwYRdA37HSZhsvm",
        "name": "Interno - DW"
    }
}

def fix_postgres_credentials(filepath):
    if not os.path.exists(filepath):
        return

    with open(filepath, 'r', encoding='utf-8') as f:
        wf = json.load(f)

    for n in wf['nodes']:
        if 'postgres' in n['type']:
            n['credentials'] = CREDENTIAL_3S_DW

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Credencial 'Interno - DW' corrigida no workflow: {filepath}")

if __name__ == '__main__':
    fix_postgres_credentials('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 10 - Ingestao Cadastro (ListaVeiculos).json')
    fix_postgres_credentials('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 11 - Ingestao Ultima Posicao.json')
    fix_postgres_credentials('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 12 - Ingestao Eventos (RetornaDados Incremental).json')
    fix_postgres_credentials('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 13 - Ingestao Posicoes (Escopo Gritsch, Janela D-1).json')
