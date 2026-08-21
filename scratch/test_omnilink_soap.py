import urllib.request
import xml.etree.ElementTree as ET

url = 'https://wstt.omnilink.com.br/iasws/iasws.asmx'

def test_soap_call(method_name, usuario="__USUARIO__", senha="__SENHA__"):
    soap_body = f"""<?xml version="1.0" encoding="utf-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="http://microsoft.com/webservices/">
   <soapenv:Header/>
   <soapenv:Body>
      <web:{method_name}>
         <web:Usuario>{usuario}</web:Usuario>
         <web:Senha>{senha}</web:Senha>
      </web:{method_name}>
   </soapenv:Body>
</soapenv:Envelope>"""

    headers = {
        'Content-Type': 'text/xml; charset=utf-8',
        'SOAPAction': f'http://microsoft.com/webservices/{method_name}'
    }

    req = urllib.request.Request(url, data=soap_body.encode('utf-8'), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            res = resp.read().decode('utf-8')
            print(f"✅ Método Omnilink {method_name} respondeu (Tamanho: {len(res)} bytes)!")
            print(res[:400])
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode('utf-8')[:300]}")
    except Exception as e:
        print(f"Erro: {e}")

if __name__ == '__main__':
    print("Testando formato SOAP da Omnilink...")
    test_soap_call('ObtemAllPosicoesAtuais')
