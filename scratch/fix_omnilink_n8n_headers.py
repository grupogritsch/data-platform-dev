import json

def fix_omnilink_n8n(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        wf = json.load(f)

    for n in wf['nodes']:
        if n['name'].startswith('01 - Request'):
            n['parameters'] = {
                "method": "POST",
                "url": "https://wstt.omnilink.com.br/iasws/iasws.asmx",
                "sendHeaders": True,
                "headerParameters": {
                    "parameters": [
                        {
                            "name": "SOAPAction",
                            "value": "\"http://microsoft.com/webservices/ObtemAllPosicoesAtuais\""
                        }
                    ]
                },
                "sendBody": True,
                "specifyBody": "raw",
                "rawContentType": "text/xml",
                "body": "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:web=\"http://microsoft.com/webservices/\"><soapenv:Header/><soapenv:Body><web:ObtemAllPosicoesAtuais><web:Usuario>__USUARIO_OMNILINK__</web:Usuario><web:Senha>__SENHA_OMNILINK__</web:Senha></web:ObtemAllPosicoesAtuais></soapenv:Body></soapenv:Envelope>",
                "options": {
                    "response": {
                        "response": {
                            "responseFormat": "text"
                        }
                    },
                    "timeout": 60000
                }
            }
            n['notes'] = "EDITE: troque __USUARIO_OMNILINK__ e __SENHA_OMNILINK__ no body pelas credenciais reais da Omnilink."

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow Omnilink corrigido: {filepath}")

if __name__ == '__main__':
    fix_omnilink_n8n('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/OMNILINK - 01 - Ingestao Posicoes e Telemetria (WSTT).json')
