import json
import os

wf12_path = '/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 12 - Ingestao Eventos (RetornaDados Incremental).json'
wf13_path = '/home/gabriel/Projetos/data-platform-dev/Workflows - n8n/3S - 13 - Ingestao Posicoes (Escopo Gritsch, Janela D-1).json'

# 1. Corrigir coluna em 3S - 12
with open(wf12_path, 'r', encoding='utf-8') as f:
    wf = json.load(f)

for n in wf['nodes']:
    if n['name'] == '07 - Avanca Watermark':
        n['parameters']['query'] = "UPDATE bronze.tres_s_watermark SET ultimo_id = $1::bigint, atualizado_em = NOW() WHERE dominio = 'ocorrencia_alerta';"

with open(wf12_path, 'w', encoding='utf-8') as f:
    json.dump(wf, f, indent=2, ensure_ascii=False)

print(f"✅ Workflow 3S - 12 corrigido (atualizado_em): {wf12_path}")

# 2. Excluir 3S - 13
if os.path.exists(wf13_path):
    os.remove(wf13_path)
    print(f"🗑️ Workflow 3S - 13 excluído com sucesso: {wf13_path}")
