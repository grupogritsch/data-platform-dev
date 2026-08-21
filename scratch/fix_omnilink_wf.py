import json

def fix_omnilink_node1(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        wf = json.load(f)

    for n in wf['nodes']:
        if n['name'].startswith('01 - Request'):
            n['parameters']['sendBody'] = True
            n['parameters']['specifyBody'] = 'raw'
            n['parameters']['rawContentType'] = 'text/xml; charset=utf-8'
            n['parameters']['body'] = """<?xml version="1.0" encoding="utf-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="http://microsoft.com/webservices/">
   <soapenv:Header/>
   <soapenv:Body>
      <web:ObtemAllPosicoesAtuais>
         <web:Usuario>__USUARIO_OMNILINK__</web:Usuario>
         <web:Senha>__SENHA_OMNILINK__</web:Senha>
      </web:ObtemAllPosicoesAtuais>
   </soapenv:Body>
</soapenv:Envelope>"""
            n['notes'] = "EDITE: substitua __USUARIO_OMNILINK__ e __SENHA_OMNILINK__ pelas suas credenciais da Omnilink."

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow Omnilink ajustado: {filepath}")

if __name__ == '__main__':
    fix_omnilink_node1('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/OMNILINK - 01 - Ingestao Posicoes e Telemetria (WSTT).json')
