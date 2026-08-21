import json
import os

USER_OMNILINK = "gabriel.brittes@gritsch.com.br"
PASS_OMNILINK = "Gab#2026."

def embed_omnilink_wf(filepath):
    if not os.path.exists(filepath):
        return

    with open(filepath, 'r', encoding='utf-8') as f:
        wf = json.load(f)

    for n in wf['nodes']:
        if n['name'].startswith('01 - Request'):
            n['parameters']['body'] = f'<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="http://microsoft.com/webservices/"><soapenv:Header/><soapenv:Body><web:ObtemAllPosicoesAtuais><web:Usuario>{USER_OMNILINK}</web:Usuario><web:Senha>{PASS_OMNILINK}</web:Senha></web:ObtemAllPosicoesAtuais></soapenv:Body></soapenv:Envelope>'
            n['notes'] = "Credenciais oficiais Omnilink pré-configuradas (gabriel.brittes@gritsch.com.br)."

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Credenciais Omnilink incorporadas com sucesso: {filepath}")

# Update .env
env_path = '/home/gabriel/Projetos/data-platform-dev/.env'
if os.path.exists(env_path):
    with open(env_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if 'OMNILINK_USUARIO' not in content:
        content += f"\n# OMNILINK Credentials\nOMNILINK_USUARIO={USER_OMNILINK}\nOMNILINK_SENHA={PASS_OMNILINK}\n"
        with open(env_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print("✅ Arquivo .env atualizado com OMNILINK_USUARIO e OMNILINK_SENHA")

if __name__ == '__main__':
    embed_omnilink_wf('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/OMNILINK - 01 - Ingestao Posicoes e Telemetria (WSTT).json')
