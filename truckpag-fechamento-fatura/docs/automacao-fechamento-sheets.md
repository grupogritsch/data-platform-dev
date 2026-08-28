# Automação do fechamento — versão Google Sheets (27/08/2026)

> Substitui a entrega final da versão descrita em
> [`automacao-fechamento.md`](automacao-fechamento.md) — aquele documento
> continua valendo como histórico (os bugs de n8n encontrados lá, principalmente
> o de timezone na comparação de data, valem pra qualquer workflow Postgres
> deste ambiente, não só este). O que mudou aqui é só a ponta final: em vez
> de gerar o `.xlsx` dentro do n8n (que exigia `NODE_FUNCTION_ALLOW_EXTERNAL=xlsx`
> no container Docker) e mandar o e-mail direto de lá, agora o n8n só escreve
> os dados numa Planilha Google, e um Apps Script preso nela cuida do e-mail.

## Por que mudar

1. A empresa está padronizando em **Google Workspace** — Sheets já é a
   ferramenta que o setor usa hoje pra montar a planilha manual.
2. A versão anterior (xlsx no n8n) precisava de uma mudança de infraestrutura
   (variável de ambiente no container + restart) só pra gerar um arquivo com
   várias abas. Essa dependência de Docker some.
3. Apps Script roda inteiramente dentro do Google Workspace — nada pra
   manter, nenhum servidor, nenhum container.

## Arquitetura

```
n8n (só busca e escreve, roda quinta 06h)
  Trigger → Fatura alvo → Tem fatura pendente?
    → [5x: query Postgres → Limpar aba → Escrever aba]  (Resumo, Contabilidade,
       Relatorio, Rateio Garagem, Rateio Posto)
    → (barreira de sincronização) → Escrever Info (data_vencimento + timestamp)

Google Apps Script (preso na planilha, roda quinta 08h — depois do n8n)
  enviarFechamentoSemanal()
    → lê a última linha da aba Info
    → se não foi atualizada hoje: sai em silêncio (sem fatura pendente essa semana)
    → exporta a planilha inteira como .xlsx (nativo do Sheets, todas as abas)
    → envia por e-mail pro destinatário único, com o .xlsx em anexo
```

Arquivos:
- [`n8n/fechamento-fatura-combustivel-sheets.json`](../n8n/fechamento-fatura-combustivel-sheets.json) — workflow novo.
- [`n8n/EnviarFechamentoSemanal.gs`](../n8n/EnviarFechamentoSemanal.gs) — Apps Script.

## O que foi reaproveitado do workflow original (sem alteração)

Os dois triggers, "Fatura alvo", "Tem fatura pendente?" e as 5 queries
Postgres (Resumo/Contabilidade/Relatorio/Rateio Garagem/Rateio Posto) são
**exatamente os mesmos** do workflow anterior — inclusive o fix de comparar
data por intervalo (`>= $1::date AND < $1::date + INTERVAL '1 day'`) em vez
de igualdade exata, por causa do timezone do container (ver
`automacao-fechamento.md` pra entender esse bug, ele volta se alguém
"simplificar" a query de volta pra igualdade).

## O que mudou

Removido: os 5 nós `Convert to File`/o Code node "Montar XLSX (5 abas)"
(biblioteca SheetJS) e o nó "Enviar e-mail" do n8n.

Novo, por dataset (5x): **Limpar aba** (Google Sheets, operação `clear`,
`wholeSheet` — apaga o conteúdo da semana anterior) → **Escrever aba**
(Google Sheets, operação `append`, `columns.mappingMode: autoMapInputData`
— mapeia as colunas do resultado da query automaticamente pelos nomes,
sem precisar listar campo por campo).

Novo, 1x no final: **Escrever Info** — acrescenta uma linha na aba "Info"
com `data_vencimento` e `atualizado_em` (timestamp). Diferente das 5 abas
de dado, esta **não é limpa toda semana** — vira um log histórico de cada
fechamento processado, e é o que o Apps Script lê pra decidir se manda
e-mail.

## Configuração (fazer uma vez)

1. **Criar a Planilha Google** no Workspace da empresa, com 6 abas (nome
   exato, sensível a maiúscula): `Resumo`, `Contabilidade`, `Relatorio`,
   `Rateio Garagem`, `Rateio Posto`, `Info`. Na aba `Info`, colocar cabeçalho
   na linha 1: `data_vencimento` | `atualizado_em`.
2. Copiar o **ID da planilha** (a parte da URL entre `/d/` e `/edit`).
3. **Importar** `n8n/fechamento-fatura-combustivel-sheets.json` no n8n.
4. Em **todo node "Limpar aba \*"/"Escrever aba \*"/"Escrever Info"** (11 ao
   todo): trocar `PREENCHER-ID-DA-PLANILHA` pelo ID copiado no passo 2, e
   selecionar/criar a credencial Google Sheets OAuth2 (conta de serviço ou
   OAuth do Workspace — precisa ter acesso de edição na planilha).
5. Nos nodes Postgres, selecionar a credencial do DW (igual antes).
6. **Extensões → Apps Script** na planilha → colar o conteúdo de
   `EnviarFechamentoSemanal.gs` inteiro.
7. Trocar `DESTINATARIO` no topo do script pelo e-mail real.
8. Rodar a função `configurarGatilhoSemanal` uma vez (▶ no editor,
   selecionando essa função) — cria o gatilho de quinta-feira 8h. Na
   primeira execução o Google vai pedir autorização (escopos de Gmail +
   Drive) — aceitar.

## Plano de teste

1. Rodar o workflow n8n manualmente (trigger "Teste manual", fatura
   02/09/2026 como no teste original) e conferir que as 6 abas da planilha
   ficaram preenchidas certinho (sem número quebrado, sem notação
   científica na chave NFe — mesma checagem do teste original).
2. No editor do Apps Script, rodar a função `testarEnvioAgora` (não espera
   quinta-feira, não depende da checagem de "atualizado hoje") e conferir
   que o e-mail chegou com o `.xlsx` de 6 abas em anexo, abrindo certo no
   Excel.
3. Só depois disso, rodar `configurarGatilhoSemanal` pra produção de
   verdade.

## Fora de escopo (mesmo guardrail de sempre)

Nunca propor ou tentar automatizar o lançamento da fatura no ERP Bluefleet
via banco de dados ou API. Fica manual — decisão explícita do usuário.
