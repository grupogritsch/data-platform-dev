# Planilha de Fechamento

Arquivo de referência: [`referencia/Contabilidade - Fatura 269308.xlsx`](../referencia/Contabilidade%20-%20Fatura%20269308.xlsx)

## Arquitetura de dados (contexto)

Existem **duas integrações da Truckpag** no DW (Postgres):

- **API legada** — tabelas `torre.integration_truckpag_titulos`, `torre.integration_truckpag_titulo_itens`, `torre.integration_truckpag_transacoes`, `torre.integration_truckpag_nfe_vinculos`. Já 100% funcional e estável — é a fonte das 3 views de conciliação abaixo.
- **API nova** (documentada em [`referencia/API - TruckPag - Meios de Pagamentos.html`](../referencia/API%20-%20TruckPag%20-%20Meios%20de%20Pagamentos.html)) — hoje só a rota **"analítico de transações"** é consumida, já com camadas bronze e silver montadas. As demais rotas dessa API nova são o alvo da ingestão futura (ver [`ingestao/README.md`](../ingestao/README.md)).

Também existe `torre.gold_dim_veiculo` — dimensão de veículo (camada gold), usada como fallback de garagem nas views abaixo.

**Importante:** fatura de **combustível** e fatura de **pedágio** são faturas com numeração diferente (títulos diferentes). As 3 views abaixo (e as abas Resumo/Contabilidade/Relatorio) são usadas **somente para a fatura de combustível**.

## Views de conciliação (schema `torre`)

### `vw_conciliacao_truckpag_contabilidade` — view base

Grão: uma linha por item de título (transação de abastecimento x fatura). Alimenta a aba **Contabilidade**.

Junta as 4 tabelas legadas + `gold_dim_veiculo` e monta, por transação:

- **Estorno/crédito**: se `transacao_estornada` estiver preenchido, a linha é um crédito estornando uma transação original — `valor_item_liquido` vira negativo, `tipo_lancamento = 'ESTORNO (CRÉDITO)'`, e a view resolve tanto "em qual fatura a transação original foi cobrada" (`fatura_origem_referencia`) quanto o inverso — "se essa transação teve um crédito gerado depois, em qual fatura esse crédito caiu" (`fatura_credito_retorno`).
- **`status_fiscal` / `categoria_relatorio`** (regra de prioridade):
  1. Tem NFe vinculada → `1. Com nota fiscal recolhida`
  2. É pedágio (`servico = 'PEDAGIO'`) → `5. Pedágio (isento de nota)` — na prática não aparece dentro de uma fatura de combustível, já que pedágio é outra fatura.
  3. É a própria transação de estorno → `4. Crédito de estorno (desconto)`
  4. Foi referenciada como origem de outro estorno (abastecimento cancelado depois) → `2. Abastecimento cancelado (sem nota)`
  5. Senão → `3. Sem nota fiscal` (pendente)
- **Garagem**: usa o campo da transação; se vazio, cai para `gold_dim_veiculo.filial_operacional`; se nenhum dos dois existir, marca `'VERIFICAR BACKFILL'`.
- **Natureza**: `ARLA` vs `COMBUSTÍVEL` (por nome do combustível conter "ARLA").
- **`chave_nfe_texto`**: concatena uma aspa simples antes da chave da NFe — truque pra Excel/Sheets não converter a chave (44 dígitos) em notação científica. Confirma que a view já é desenhada pra alimentar a planilha diretamente.

### `vw_conciliacao_truckpag_relatorio`

Select direto da `contabilidade`, com um subconjunto de colunas renomeado (`fatura_atual → fatura`, `chave_nfe_texto → chave_nfe`). Sem agregação. Alimenta a aba **Relatorio** (detalhe, uma linha por transação).

### `vw_conciliacao_truckpag_resumo`

Agrega a `contabilidade` por `fatura_atual` e monta uma demonstração em formato de linhas (pivot), no estilo:

```
LEVA 1
  (+) Notas fiscais recolhidas       = soma categoria 1
  (-) Créditos de estorno            = soma categoria 4 (já vem negativo)
  (=) Pagamento no vencimento        = notas_recolhidas + creditos_estorno
LEVA 2
  (+) Abastecimento cancelado        = soma categoria 2
  (+) Sem nota fiscal                = soma categoria 3
  (=) Saldo a pagar                  = cancelado + sem_nota
TOTAL DA FATURA (conferência)        = soma de TODAS as categorias
```

Alimenta a aba **Resumo**.

**Significado confirmado pelo usuário:**
- **Leva 1** = tudo que é pago na data de vencimento da fatura.
- **Leva 2** = saldo a pagar depois de recolher as notas que estavam faltando.

**Processo manual por trás da Leva 2 (gap conhecido):** às vezes chegam notas **não tributáveis "por fora"** — não passam pela integração `nfe_vinculos` — então a view continua classificando o item como "sem nota" mesmo depois de resolvido manualmente. O valor final pago na Leva 2 é ajustado manualmente com base nessas notas recebidas fora do fluxo automatizado.

> Exemplo real: fatura 263144 aparece com R$400 pendente em "sem nota" pela view, mas uma nota recebida fora do lote fecha a recolha em R$1005 — esse valor sobe então para pagamento na Leva 2.

## Gaps / melhorias conhecidas (backlog para a "versão melhorada")

1. **Reconciliação manual da Leva 2** — notas não tributáveis recebidas fora do sistema não entram em `nfe_vinculos`, então a view fica desatualizada até ajuste manual. Melhoria: alguma forma de registrar essas notas "por fora" pra a view refletir a realidade sem intervenção manual.
2. **`VERIFICAR BACKFILL`** — raro; majoritariamente placas fictícias/temporárias usadas para veículos em preparação, que ainda não existem em `gold_dim_veiculo`. Hoje fica só sinalizado, sem resolução — precisa de uma lógica (ex: cadastro provisório dessas placas, ou fallback melhor) pra não ficar pendente.

## Abas Rateio por Garagem e Rateio por Posto (hoje calculadas na planilha)

Essas duas abas **não vêm de view** — são fórmulas Excel em cima da própria aba Contabilidade (confirmado inspecionando o `.xlsx`: `Contabilidade!$B:$B` = coluna `garagem`, `$J:$J` = `nome_posto`, `$M:$M` = `valor_item_liquido`, `$X:$X` = `categoria_relatorio`).

**Rateio por Garagem** — para cada garagem (uma linha por garagem), 4x `SUMIFS` idênticos ao padrão do Resumo, só que agrupando por garagem em vez de por fatura inteira:
```
SUMIFS(Contabilidade!$M:$M, Contabilidade!$B:$B, <garagem>, Contabilidade!$X:$X, "<categoria>")
```
para as 4 categorias (`1. Com nota fiscal recolhida`, `2. Abastecimento cancelado (sem nota)`, `3. Sem nota fiscal`, `4. Crédito de estorno (desconto)`).

**Rateio por Posto** — mesmo padrão, mas agrupando por `nome_posto` (coluna J) em vez de garagem, mais duas coisas a mais:
- busca o CNPJ do posto via `INDEX/MATCH` (redundante numa view, já que `cnpj_posto` já existe direto na `contabilidade`)
- calcula o **percentual de participação** de cada posto sobre um total geral (`valor_posto / total_geral`)

**Conclusão:** dá pra virar view, com a mesma lógica de categorização já usada em `contabilidade`/`resumo`, só trocando o agrupamento. O usuário confirmou que prefere ter isso como view (ou tabela pronta) em vez de fórmula na planilha, pra facilitar pro substituto.

### Proposta de views (rascunho — a rodar/validar pelo usuário)

```sql
CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_rateio_garagem AS
SELECT
    fatura_atual AS fatura,
    garagem,
    sum(CASE WHEN categoria_relatorio = '1. Com nota fiscal recolhida' THEN valor_item_liquido ELSE 0 END) AS notas_recolhidas,
    sum(CASE WHEN categoria_relatorio = '2. Abastecimento cancelado (sem nota)' THEN valor_item_liquido ELSE 0 END) AS cancelado,
    sum(CASE WHEN categoria_relatorio = '3. Sem nota fiscal' THEN valor_item_liquido ELSE 0 END) AS sem_nota,
    sum(CASE WHEN categoria_relatorio = '4. Crédito de estorno (desconto)' THEN valor_item_liquido ELSE 0 END) AS creditos_estorno,
    sum(valor_item_liquido) AS total_garagem
FROM torre.vw_conciliacao_truckpag_contabilidade
GROUP BY fatura_atual, garagem;

CREATE OR REPLACE VIEW torre.vw_conciliacao_truckpag_rateio_posto AS
SELECT
    fatura_atual AS fatura,
    nome_posto,
    cnpj_posto,
    sum(CASE WHEN categoria_relatorio = '1. Com nota fiscal recolhida' THEN valor_item_liquido ELSE 0 END) AS notas_recolhidas,
    sum(CASE WHEN categoria_relatorio = '2. Abastecimento cancelado (sem nota)' THEN valor_item_liquido ELSE 0 END) AS cancelado,
    sum(CASE WHEN categoria_relatorio = '3. Sem nota fiscal' THEN valor_item_liquido ELSE 0 END) AS sem_nota,
    sum(CASE WHEN categoria_relatorio = '4. Crédito de estorno (desconto)' THEN valor_item_liquido ELSE 0 END) AS creditos_estorno,
    sum(valor_item_liquido) AS total_posto,
    -- % de participação do posto sobre o total da fatura (equivalente ao IF(I$208, x/I$208, 0) da planilha)
    sum(valor_item_liquido) / NULLIF(sum(sum(valor_item_liquido)) OVER (PARTITION BY fatura_atual), 0) AS percentual_participacao
FROM torre.vw_conciliacao_truckpag_contabilidade
GROUP BY fatura_atual, nome_posto, cnpj_posto;
```

> Não executei isso no banco — é rascunho pra você revisar/rodar e me devolver se bateu com os números atuais da planilha (comparar contra `Contabilidade - Fatura 269308.xlsx`, abas Rateio por Garagem/Posto).

## Automação do export (n8n)

Ver [`automacao-fechamento.md`](automacao-fechamento.md) — proposta de workflow n8n rodando semanalmente pra substituir o copy-paste manual, incluindo como lidar com a Leva 2 (registro manual mínimo de notas recolhidas "por fora").

## Rotas da API nova mapeadas para o levantamento de ingestão

Ver [`ingestao/README.md`](../ingestao/README.md) para o inventário completo das rotas disponíveis na API nova e o que já foi decidido consumir.
