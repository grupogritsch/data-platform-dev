import json
import os

USER_3S = "referencia.locadora919"
PASS_3S = "d01m04"

def embed_credentials(filepath):
    if not os.path.exists(filepath):
        print(f"⚠️ Arquivo não encontrado: {filepath}")
        return

    with open(filepath, 'r', encoding='utf-8') as f:
        wf = json.load(f)

    for n in wf['nodes']:
        if n['name'] == '01 - Login':
            n['parameters']['sendBody'] = True
            n['parameters']['specifyBody'] = 'json'
            n['parameters']['jsonBody'] = f'{{\n  "usuario": "{USER_3S}",\n  "senha": "{PASS_3S}"\n}}'
            if 'notes' in n:
                n['notes'] = "Credenciais oficiais 3S pré-configuradas (referencia.locadora919)."

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Credenciais 3S incorporadas com sucesso: {filepath}")

# Update .env file with TRES_S credentials
env_path = '/home/gabriel/Projetos/data-platform-dev/.env'
if os.path.exists(env_path):
    with open(env_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if 'TRES_S_USUARIO' not in content:
        content += f"\n# 3STEC Credentials\nTRES_S_USUARIO={USER_3S}\nTRES_S_SENHA={PASS_3S}\n"
        with open(env_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"✅ Arquivo .env atualizado com TRES_S_USUARIO e TRES_S_SENHA")

if __name__ == '__main__':
    embed_credentials('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 10 - Ingestao Cadastro (ListaVeiculos).json')
    embed_credentials('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 11 - Ingestao Ultima Posicao.json')
    embed_credentials('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 12 - Ingestao Eventos (RetornaDados Incremental).json')
    embed_credentials('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 13 - Ingestao Posicoes (Escopo Gritsch, Janela D-1).json')
