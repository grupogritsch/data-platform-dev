import json

def fix_omnilink(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        wf = json.load(f)

    for n in wf['nodes']:
        if n['name'].startswith('01 - Request'):
            n['parameters']['options'] = {
                "response": {
                    "response": {
                        "responseFormat": "text",
                        "fullResponse": False
                    }
                },
                "timeout": 60000
            }
        
        if n['name'].startswith('02 - Parse'):
            n['parameters']['jsCode'] = """// Parse XML de resposta da Omnilink
let rawXml = '';
if (typeof $json === 'string') {
  rawXml = $json;
} else if ($json.data) {
  rawXml = typeof $json.data === 'string' ? $json.data : JSON.stringify($json.data);
} else if ($json.body) {
  rawXml = typeof $json.body === 'string' ? $json.body : JSON.stringify($json.body);
} else {
  rawXml = JSON.stringify($json);
}

// Extrair payload dentro de <return>...</return>
let xmlText = rawXml;
const match = rawXml.match(/<return[^>]*>([\\s\\S]*?)<\\/return>/i);
if (match && match[1]) {
  xmlText = match[1].replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
}

// Verificar se veio mensagem de erro da Omnilink
if (xmlText.includes('<msgerro>') || xmlText.includes('Usuário ou Senha')) {
  const errMatch = (xmlText.match(/<msgerro>([^<]*)<\\/msgerro>/i) || [])[1] || 'Erro de autenticacao/permissao na Omnilink';
  throw new Error(`Erro Omnilink: ${errMatch}`);
}

// Capturar tags dos veiculos na Omnilink
const items = [];
const itemRegex = /<teleevento>([\\s\\S]*?)<\\/teleevento>/gi;
let m;
while ((m = itemRegex.exec(xmlText)) !== null) {
  const block = m[1];
  const placa = (block.match(/<placa>([^<]*)<\\/placa>/i) || [])[1] || '';
  const serial = (block.match(/<serial>([^<]*)<\\/serial>/i) || [])[1] || '';
  const dataGps = (block.match(/<data>([^<]*)<\\/data>/i) || [])[1] || '';
  const vel = (block.match(/<velocidade>([^<]*)<\\/velocidade>/i) || [])[1] || '0';
  const ign = (block.match(/<ignicao>([^<]*)<\\/ignicao>/i) || [])[1] || '';
  const cidade = (block.match(/<cidade>([^<]*)<\\/cidade>/i) || [])[1] || '';
  const uf = (block.match(/<uf>([^<]*)<\\/uf>/i) || [])[1] || '';
  const lat = (block.match(/<latitude>([^<]*)<\\/latitude>/i) || [])[1] || '0';
  const lon = (block.match(/<longitude>([^<]*)<\\/longitude>/i) || [])[1] || '0';

  if (placa) {
    items.push({
      placa: placa.toUpperCase().replace(/[^A-Z0-9]/g, ''),
      complemento: 'OMNILINK - ' + placa.toUpperCase(),
      serial: serial,
      cidade: cidade,
      estado: uf,
      latitude: parseFloat(lat.replace(',', '.')) || 0,
      longitude: parseFloat(lon.replace(',', '.')) || 0,
      data_gps: dataGps,
      ignicao: ign.toLowerCase().includes('lig')
    });
  }
}

return [{
  json: {
    records: items,
    total: items.length
  }
}];"""

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print(f"✅ Workflow Omnilink corrigido com fullResponse: False e parser robusto: {filepath}")

if __name__ == '__main__':
    fix_omnilink('/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/OMNILINK - 01 - Ingestao Posicoes e Telemetria (WSTT).json')
