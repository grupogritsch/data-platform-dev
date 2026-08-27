# Fontes dos relatórios de combustível e pedágio

Os workflows `.json` desta pasta (`Workflows - n8n/`) são exports do n8n —
o SQL e o JavaScript dos nodes ficam embutidos como string dentro do JSON,
o que é ruim pra editar direto. Esta pasta guarda a versão "fonte" desses
mesmos arquivos, mais os scripts Python que aplicam essa fonte de volta no
`.json` do workflow real.

Ver `docs/torre-controle-relatorios-email.md` na raiz do repo pro contexto
completo (arquitetura, status de cada relatório, bugs já encontrados).

## Como editar

1. Edita o `.sql` ou `.js` aqui dentro (não no `.json` do workflow direto).
2. Roda o script Python correspondente — ele lê os arquivos desta pasta e
   grava de volta no `.json` real em `Workflows - n8n/`:
   - `combustivel/aplica_combustivel_cc.py` → atualiza o **semanal**
     (SQL, os dois templates HTML, e o `options.ccEmail`/`attachments` dos
     nodes de envio)
   - `combustivel/cria_workflow_diario.py` → **recria do zero** o workflow
     **diário** inteiro (clona credenciais/typeVersion do semanal, não
     precisa reconfigurar Postgres/SMTP na mão)
   - `pedagio/cria_workflow_pedagio.py` → mesma lógica do diário de
     combustível, mas pro pedágio semanal
3. Reimporta o `.json` atualizado no n8n.
4. **Confere o `modo_producao`** no node "⚙️ Configurações" depois de
   importar — o import sobrescreve esse valor pelo que está salvo no
   arquivo (sempre `false` por padrão de segurança).

## Testando sem Postgres

Os scripts `roda_*.js` (mesma pasta de onde estes arquivos foram copiados,
`scratchpad` da sessão que criou isso — pode não existir mais) simulavam a
execução dos Code nodes fora do n8n, usando um JSON de dados reais
exportado do banco como mock. Se precisar recriar esse fluxo de teste: o
padrão é simular `$input`/`$` como funções que devolvem os dados que o node
receberia de verdade, `new Function(...)` pra rodar o `jsCode` como se fosse
o node, e checar a saída (`out.json.htmlEmail`, `out.binary`).
