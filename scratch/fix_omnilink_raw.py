import json

def fix_omnilink_wf(filepath):
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
                            "name": "Content-Type",
                            "value": "text/xml; charset=utf-8"
                        },
                        {
                            "name": "SOAPAction",
                            "value": "\"http://microsoft.com/webservices/ObtemAllPosicoesAtuais\""
                        }
                    ]
                },
                "sendBody": True,
                "contentType": "raw",
                "rawContentType": "text/xml",
                "body": "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:web=\"http://microsoft.com/webservices/\"><soapenv:Header/><soapenv:Body><web:ObtemAllPosicoesAtuais><web:Usuario>gabriel.brittes@gritsch.com.br</web:Usuario><web:Senha>Gab#2026.</web:Senha></web:ObtemAllPosicoesAtuais></soapenv:Body></soapenv:Envelope>",
                "options": {
                    "response": {
                        "response": {
                            "responseFormat": "text"
                        }
                    },
                    "timeout": 60000
                }
            }
            n['notes'] = "Credenciais oficiais Omnilink pré-configuradas (gabriel.brittes@gritsch.com.br)."

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow Omnilink 01 corrigido com contentType: 'raw' -> {filepath}")

if __name__ == '__main__':
    fix_omnilink_wf('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/OMNILINK - 01 - Ingestao Posicoes e Telemetria (WSTT).json')
