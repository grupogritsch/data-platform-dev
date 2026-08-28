# Automação do export semanal (n8n)

> **Histórico (27/08/2026)**: a entrega final desta automação (geração do
> `.xlsx` + envio do e-mail) foi substituída pela versão em
> [`automacao-fechamento-sheets.md`](automacao-fechamento-sheets.md) —
> Google Sheets + Apps Script, pra não depender de mudança no Docker do n8n.
> **Este documento continua valendo** pra tudo antes disso: as 5 queries
> Postgres, o guard "Tem fatura pendente?", e principalmente os bugs de n8n
> encontrados e corrigidos abaixo (o de timezone na comparação de data é o
> mais importante — vale pra qualquer workflow Postgres deste ambiente).

## Objetivo

Substituir o processo manual atual — copiar e colar o resultado das 3 tabelas/views numa aba e pedir pra uma IA arrumar números/formatação quebrada — por um workflow n8n (a mesma ferramenta já usada hoje pra manipulação de dados) que roda periodicamente (ex: toda quinta-feira), consulta as views de conciliação direto no DW e gera um arquivo já formatado corretamente.

## O problema da Leva 2 dentro dessa automação

A Leva 2 (ver [`planilha-fechamento.md`](planilha-fechamento.md)) depende hoje de um passo manual fora do sistema: notas não tributáveis que chegam "por fora" não entram em `torre.integration_truckpag_nfe_vinculos`, então a view sempre classifica esses itens como `'3. Sem nota fiscal'` até alguém resolver manualmente na hora do fechamento.

Uma automação totalmente "silenciosa" (zero input manual) não tem como saber sozinha quais notas "por fora" já foram recolhidas — essa informação não existe em nenhuma tabela hoje, só na cabeça de quem fecha a fatura.

## Proposta: um registro manual mínimo, em vez de reformatar tudo toda vez

Em vez de mexer na planilha inteira toda semana, um registro pequeno e centralizado:

1. **Nova tabela** (nome sugerido, a confirmar) `torre.truckpag_notas_recolhidas_manual`:
   - `id_transacao` (ou `fatura`) — o que a nota resolve
   - `valor`
   - `data_recolhida`
   - `observacao` (opcional)

   Preenchida por quem estiver fechando, só quando uma nota chega fora do fluxo automático. Vira uma linha digitada, não uma reformatação de planilha inteira.

2. **Ajuste na categorização**: uma transação que hoje cai em `'3. Sem nota fiscal'` só pela ausência em `nfe_vinculos`, mas que tem uma entrada correspondente nessa tabela manual, passa a contar como resolvida — nova categoria (ex: `'3b. Sem nota (recolhida manualmente)'`) ou direto somada à conta de "pronto pra pagar" da Leva 2.

3. O n8n só consulta a view já ajustada — nunca decide isso sozinho, só reflete o que foi registrado manualmente até aquele momento.

## Decisões confirmadas (2026-08-27)

- Nome da tabela de notas manuais: `torre.truckpag_notas_recolhidas_manual` (confirmado).
- Destino: **e-mail** — o n8n envia automaticamente, toda quinta-feira.
- **Destinatário: um só** — o próprio setor do usuário (quem hoje recebe/monta a planilha). Não é uma distribuição por garagem/posto — é um único e-mail com o pacote completo de dados, igual ao relatório de hoje no Excel.
- **Conteúdo do e-mail/anexo**, no mesmo formato de hoje:
  - Resumo (Leva 1 / Leva 2, já com a Leva 2 real via a tabela de notas manuais)
  - Contabilidade (detalhe)
  - Relatorio
  - Rateio por Garagem — usado pro **lançamento de centro de custo**
  - Rateio por Posto
- **O que o destinatário faz depois de receber** (tudo manual, fora do escopo da automação):
  1. Lança e dá baixa nas notas no **sistema da Truckpag**.
  2. Encaminha as informações relevantes para as áreas relacionadas (garagens, postos, etc.) conforme necessário — a automação não faz esse encaminhamento seletivo, só entrega o pacote completo pro setor.
  3. Faz o **lançamento da fatura no ERP Bluefleet** — **100% manual, fora de escopo permanentemente**. O usuário foi explícito: não dá pra lançar via banco de dados ou rota de API, e não quer que se tente automatizar isso. A automação para na entrega do e-mail — nunca deve tentar escrever no Bluefleet.

## Camada de banco (finalizada — arquivos em `sql/fechamento_fatura/`)

| Arquivo | O que faz |
|---|---|
| [`01_tabela_notas_recolhidas_manual.sql`](../sql/fechamento_fatura/01_tabela_notas_recolhidas_manual.sql) | Cria `torre.truckpag_notas_recolhidas_manual` |
| [`02_view_contabilidade_ajustada.sql`](../sql/fechamento_fatura/02_view_contabilidade_ajustada.sql) | Cria `vw_conciliacao_truckpag_contabilidade_ajustada` (view aditiva, não mexe na original) |
| [`03_view_resumo_v2.sql`](../sql/fechamento_fatura/03_view_resumo_v2.sql) | Cria `vw_conciliacao_truckpag_resumo_v2` (Leva 1/Leva 2 já considerando notas recolhidas manualmente) |
| [`04_views_rateio.sql`](../sql/fechamento_fatura/04_views_rateio.sql) | Cria `vw_conciliacao_truckpag_rateio_garagem` e `vw_conciliacao_truckpag_rateio_posto` |

**Rodar nessa ordem no DW (Postgres).** São todas `CREATE OR REPLACE VIEW`/`CREATE TABLE IF NOT EXISTS` — não tocam nas views originais (`vw_conciliacao_truckpag_contabilidade`, `_relatorio`, `_resumo`), só adicionam. Depois de rodar, comparar o resultado da `resumo_v2` e das duas rateio contra a `Contabilidade - Fatura 269308.xlsx` pra validar que os números batem antes de considerar certo.

## Workflow n8n (rascunho para importar — [`n8n/fechamento-fatura-combustivel.json`](../n8n/fechamento-fatura-combustivel.json))

Estrutura: 2 gatilhos (Manual, pra teste com data fixa; Schedule toda quinta, que descobre sozinha a próxima fatura em aberto) → 5 queries Postgres (Resumo, Contabilidade, Relatorio, Rateio Garagem, Rateio Posto) filtradas pela `data_vencimento` → cada resultado vira um `.xlsx` (nó `Convert to File`, sem precisar de código customizado) → os 5 arquivos são combinados num único item (`Merge` encadeado) → 1 e-mail com os 5 anexos.

**Isso é um ponto de partida pra importar, não uma peça pronta e testada** — eu não tenho como rodar n8n de verdade aqui, então:

1. No n8n: **Import from File** → selecionar o `.json`.
2. Depois de importar, cada nó Postgres/e-mail vai pedir pra você **selecionar a credencial** (a credencial em si nunca vai dentro do arquivo, por segurança) — usar a credencial já existente do DW e configurar/selecionar uma credencial SMTP.
3. Trocar os placeholders `PREENCHER@empresa.com.br` (remetente) e `PREENCHER-destinatario@empresa.com.br` (destinatário único, seu setor) no nó "Enviar e-mail".
4. Se o node "Merge" da sua versão do n8n não aceitar o modo usado, é só trocar pelo equivalente da sua versão (a lógica é: juntar os 5 binários num item só antes do e-mail).

## Plano de teste

Fatura com vencimento em **02/09/2026** — ainda sem planilha manual nem lançamento no Bluefleet, serve como teste limpo:
1. Rodar os 4 scripts SQL no DW (se ainda não rodados).
2. Executar o workflow n8n manualmente (gatilho "Teste manual", que já fixa `data_vencimento = 2026-09-02`).
3. Conferir o e-mail recebido: os 5 anexos abrem certo no Excel (sem número quebrado, sem notação científica na chave NFe), e os valores de Resumo/Rateio parecem coerentes.
4. Reportar de volta o que quebrou (import do JSON, erro de query, formatação do anexo, etc.) pra eu ajustar.

## Achados do primeiro teste (2026-08-27)

- Import do `.json` funcionou de primeira, sem ajuste.
- **Pegadinha real do n8n**: o botão "Execute Workflow" no topo do canvas dispara **todas** as triggers do fluxo ao mesmo tempo, não só uma. Como o workflow tem 2 triggers (Manual, pro teste; Schedule, pra produção), rodar pelo botão global dispara os dois — e como "Próxima fatura (auto)" pode não achar nenhuma fatura futura (retorna nulo), a execução por esse caminho gera consulta vazia, o que pode confundir qual resultado você está olhando.
  - **Mitigação pra testar**: desativar o nó "Toda quinta-feira" enquanto testa, ou disparar especificamente a partir do nó "Teste manual".
  - **Correção de robustez aplicada**: adicionado o nó `Tem fatura pendente?` (Filter) logo depois de `Fatura alvo`, que corta o fluxo ali se `data_vencimento` vier vazio — em vez de deixar passar pra frente e rodar as 5 queries com data nula silenciosamente.
- Confirmado via query de diagnóstico: valor da data e conexão do banco chegam certos no n8n (mesma base "dw", mesmo host da conexão usada no DBeaver).
- **Segundo teste**: pipeline de dados rodou 100% (5 queries + 5 conversões + 4 merges, tudo verde) até travar em "Enviar e-mail" — e travou antes mesmo de tentar o SMTP. Causa: os 5 nós `Convert to File` estavam todos configurados pra escrever a saída sob o **mesmo nome binário `data`**, então ao mesclar em cadeia, um sobrescrevia o outro — sobrava 1 anexo de verdade, mas o e-mail esperava 5 propriedades (`data`, `data1`...`data4`) que não existiam. Corrigido dando um nome único de saída pra cada um (`anexo_resumo`, `anexo_contabilidade`, `anexo_relatorio`, `anexo_rateio_garagem`, `anexo_rateio_posto`), refletido tanto nos nós de conversão quanto na lista de anexos do "Enviar e-mail".

### Investigação "No output data returned" (em aberto)

Sintoma: as 5 queries retornam zero linhas dentro do n8n, mas a **query exata que o n8n gera**, copiada e colada no DBeaver, retorna as 9 linhas da fatura 271797 normalmente.

Já descartado por teste direto:
- Texto/sintaxe da query (o texto gerado pelo n8n foi extraído e roda perfeitamente no DBeaver).
- Valor da data (`2026-09-02` chega correto em `Fatura alvo` e resolve certo na expressão).
- Host/porta da credencial (idênticos ao `.env`, mesma conexão usada no DBeaver).
- Usuário/permissões (mesmas credenciais nos dois).
- Ambiguidade de trigger dupla (trigger de Schedule foi desativada; roda só o caminho manual).

Mudança aplicada preventivamente: as 5 queries passaram a usar **query parameters** (`$1` + `queryReplacement`) em vez de interpolação de string `'{{ }}'`, que é o método recomendado pelo próprio n8n. Isso remove toda a classe de problema de escaping/interpolação.

Diagnóstico decisivo a rodar (query de agregação — sempre retorna 1 linha, então nunca dá "no output"):

```sql
SELECT count(*) AS total_linhas_view,
       count(*) FILTER (WHERE titulo_data_vencimento = '2026-09-02'::date) AS linhas_da_data,
       min(titulo_data_vencimento) AS menor_venc,
       max(titulo_data_vencimento) AS maior_venc,
       current_user AS usuario
FROM torre.vw_conciliacao_truckpag_contabilidade_ajustada;
```

Interpretação: `total_linhas_view = 0` → n8n fala com um banco vazio/diferente (o `inet_server_addr()` deu `172.18.0.2`, IP de rede Docker — um mesmo hostname pode resolver diferente de dentro do container). `total_linhas_view > 0` e `linhas_da_data = 0` → dados existem mas a comparação de data não bate (timezone/tipo na sessão). Ambos > 0 → dados visíveis, problema é no node.

### Hipótese principal: diferença de fuso horário entre a sessão do n8n e a do DBeaver

A [documentação oficial do node Postgres do n8n](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.postgres/common-issues/) documenta exatamente essa classe de problema: *"Inconsistent timezone handling between n8n and Postgres can cause data interpretation errors"* e *"the `pg` package parses DATE values into ISO 8601 datetime strings, adding unwanted time/timezone components"*.

Se `titulo_data_vencimento` for `timestamp with time zone` (provável — na view original `data_original_referencia` é `timestamp with time zone`), a comparação `= '2026-09-02'::date` depende do fuso da **sessão**:

- DBeaver (máquina Windows, `America/Sao_Paulo`): `'2026-09-02'` → meia-noite de Brasília → **bate**
- n8n (container Docker, normalmente `UTC`): `'2026-09-02'` → meia-noite UTC → **não bate**

Mesmo texto de query, mesmo banco, mesmo usuário, nenhum erro, resultado vazio — bate com todas as evidências.

Query pra confirmar (rodar no n8n **e** no DBeaver, comparando o `fuso_da_sessao`):

```sql
SELECT titulo_data_vencimento,
       pg_typeof(titulo_data_vencimento) AS tipo_da_coluna,
       current_setting('TimeZone') AS fuso_da_sessao
FROM torre.vw_conciliacao_truckpag_contabilidade_ajustada
LIMIT 5;
```

**Correção aplicada** (boa independentemente do resultado): as 5 queries deixaram de usar igualdade exata de data e passaram a usar intervalo do dia, que é imune à diferença de fuso:

```sql
WHERE titulo_data_vencimento >= $1::date
  AND titulo_data_vencimento < ($1::date + INTERVAL '1 day')
```

Se a confirmação vier positiva, vale também padronizar o fuso do container n8n (variável de ambiente `GENERIC_TIMEZONE` / `TZ`) pra evitar que esse tipo de divergência volte em outros workflows.

**CONFIRMADO (2026-08-28)**: a correção de intervalo resolveu. Todas as 5 queries passaram a retornar dado real — Resumo 9 linhas (fatura 271797), Contabilidade 1234, Relatorio 1234, Rateio Garagem 29, Rateio Posto 199. A causa era mesmo a comparação de data exata contra coluna com fuso horário, com a sessão do n8n (container) num fuso diferente da sessão do DBeaver.

> **Lição pra quem herdar isto**: nunca comparar data exata (`= 'YYYY-MM-DD'::date`) contra coluna de timestamp com fuso, em ferramenta que roda em container. Use sempre intervalo do dia (`>= data AND < data + 1 dia`).

### Bug seguinte: operação inválida no Convert to File

Depois que as queries voltaram a trazer dado, os 5 nós `Convert to File` não geravam saída (triângulo vermelho no campo "Operation"). Causa: a operação estava escrita como `toXlsx`, que não existe. As operações válidas do node são `csv`, `html`, `ics`, `json`, `ods`, `rtf`, `text`, `xls`, `xlsx`, `toBinary`. Corrigido para `xlsx` nos 5 nós.

### Bug seguinte: parâmetro errado nos nós Merge

Erro do n8n: `"You need to define at least one pair of fields in 'Fields to Match' to match on"`, vindo de `combineByFields.ts`. Causa: o parâmetro que escolhe o submodo do Merge (`mode: combine`) se chama **`combineBy`**, não `combinationMode` como eu tinha usado — e o valor certo pra juntar por posição é **`combineByPosition`**, não `mergeByPosition`. Como o parâmetro que escrevi não existia, o n8n caía no padrão (`combineByFields`), que exige campos de correspondência. Corrigido nos 4 nós Merge para `combineBy: "combineByPosition"`.

### Bug seguinte: e-mail chegava sem assunto resolvido e sem anexo

Duas causas diferentes no mesmo nó "Enviar e-mail":

1. **Assunto veio literal** (`Fechamento fatura... vencimento {{ $('Fatura alvo').item.json.data_vencimento }}`, sem resolver): campos de texto simples do n8n só são tratados como **expressão** se o valor salvo começar com `=`. Nos campos de query SQL isso não importou (o editor de código resolve `{{ }}` de qualquer forma), mas no campo "Subject" precisa do `=` explícito. Corrigido prefixando o valor com `=`.
2. **Anexo não veio**: o parâmetro que inventei (`options.attachmentsUi.attachmentsBinary`, uma lista de objetos) não existe nesse node — confundi com a estrutura de outro node (tipo Gmail). O campo real, confirmado direto no [código-fonte do n8n](https://github.com/n8n-io/n8n/blob/master/packages/nodes-base/nodes/EmailSend/v2/send.operation.ts), é **`options.fileAttachments`**: uma string simples com os nomes das propriedades binárias separados por vírgula.

## Mudança de escopo: de 5 arquivos para 1 arquivo com 5 abas

O usuário queria desde o início um único `.xlsx` com 5 abas (igual à planilha manual de hoje), não 5 arquivos separados. Pesquisei um template do n8n.io que alegava resolver isso só com "Merge em modo Combine All", mas **isso é tecnicamente incorreto** — confirmado contra a documentação oficial, o node `Convert to File` gera uma aba por arquivo, sem suporte a múltiplas abas, e concatenar bytes de dois `.xlsx` (que são ZIPs por dentro) não produz um workbook válido, produz arquivo corrompido. Não seguimos por esse caminho.

**Solução real**: um nó **Code** (JavaScript) usando a biblioteca `xlsx` (SheetJS) — a mesma que o próprio node nativo `Convert to File` usa por baixo dos panos, então bem provavelmente já está presente no `node_modules` do n8n, sem precisar instalar nada.

**Pré-requisito de infraestrutura** (self-hosted, precisa ser feito uma vez no ambiente do n8n):
```
NODE_FUNCTION_ALLOW_EXTERNAL=xlsx
```
e reiniciar o serviço/container do n8n. Sem isso, o Code node vai dar erro `Cannot find module 'xlsx'`.

**Nova estrutura do workflow**: os 5 nós `Convert to File` foram removidos. As 5 queries (Resumo, Contabilidade, Relatorio, Rateio Garagem, Rateio Posto) agora alimentam direto a cadeia de 4 nós `Merge` (mantidos só como "barreira de sincronização" — garantem que o Code node só rode depois que as 5 queries terminarem; o conteúdo que passa por eles não é mais usado). O `Merge 4` alimenta o novo nó **"Montar XLSX (5 abas)"**, que:
- Busca os resultados das 5 queries por nome (`$('Resumo').all()`, `$('Contabilidade').all()`, etc.) — não depende da forma como o Merge combinou os dados.
- Monta um workbook com `XLSX.utils.book_new()` + `book_append_sheet()`, uma aba por dataset.
- Gera um único binário `planilha_fechamento` com nome de arquivo incluindo a data de vencimento.

O nó "Enviar e-mail" foi ajustado pra anexar só essa propriedade: `fileAttachments: "planilha_fechamento"`.

## Fora de escopo (guardrail explícito do usuário)

Nunca propor ou tentar automatizar o **lançamento da fatura no ERP Bluefleet** via banco de dados ou API. Essa etapa fica manual — decisão explícita do usuário, não uma limitação técnica a "resolver depois".
