# Fechamento de Fatura

> Atualizado em 28/08/2026 — a Leva 2 (passo 4) deixou de ser proposta e virou
> mecanismo real, testado em 2 faturas de verdade (263144 e 267384). Ver a
> seção "Como resolver Leva 2 no dia a dia" abaixo — é o que muda o processo
> mais na prática.

## Objetivo

Descrever, passo a passo, como é feito o fechamento mensal (ou semanal) da fatura de **combustível** hoje, para que outra pessoa consiga reproduzir o processo sem depender de conhecimento tácito. Fatura de **pedágio** é um processo separado (numeração de título diferente) — não coberto aqui ainda.

## Passo a passo (hoje, manual)

1. Rodar as 3 views de conciliação (`vw_conciliacao_truckpag_resumo`, `vw_conciliacao_truckpag_contabilidade`, `vw_conciliacao_truckpag_relatorio`) para a fatura em questão.
2. Copiar o resultado pra planilha (hoje isso quebra formatação — números, encoding — e exige ajuste manual/com IA; ver melhoria proposta em [`automacao-fechamento.md`](automacao-fechamento.md)).
3. Calcular Rateio por Garagem e Rateio por Posto (hoje são fórmulas Excel em cima da aba Contabilidade — ver [`planilha-fechamento.md`](planilha-fechamento.md)).
4. Revisar a Leva 2: conferir se alguma nota "sem nota fiscal" já foi recolhida manualmente fora do sistema (fora da integração `nfe_vinculos`) e registrar isso (ver "Como resolver Leva 2 no dia a dia" abaixo — é 1 `INSERT`, as views atualizam sozinhas).
5. Com a planilha fechada, o setor do usuário lança e dá baixa nas notas no **sistema da Truckpag**.
6. Encaminha as informações relevantes (rateio, relatórios) para as áreas relacionadas conforme necessário.
7. Lançamento final da fatura no **ERP Bluefleet** — manual, não automatizável (ver guardrail em `automacao-fechamento.md`).

## Como deve ficar (com a automação n8n proposta)

Passos 1–3 (rodar views, montar planilha corretamente formatada, calcular rateios) passam a ser automáticos, rodando toda quinta-feira e chegando por e-mail pro setor responsável. Os passos 4–7 continuam manuais (revisão da Leva 2 via tabela de notas manuais, lançamento na Truckpag, encaminhamento, lançamento no Bluefleet).

## Como resolver Leva 2 no dia a dia

Quando chega uma nota fiscal "por fora" (não tributável, recebida direto da
Truckpag por e-mail, fora da integração automática `nfe_vinculos`), o único
passo é registrar na tabela de notas manuais — **nada mais**:

```sql
INSERT INTO torre.truckpag_notas_recolhidas_manual (id_transacao, valor, observacao, criado_por)
VALUES ('ID_DA_TRANSACAO', VALOR, 'referência da nota (número/chave de acesso)', 'SEU_NOME');
```

- `id_transacao` é o `id_transacao_atual` da linha em `vw_conciliacao_truckpag_contabilidade` (a nota da Truckpag geralmente já lista os IDs das transações que ela cobre, na "Discriminação do Serviço" do PDF).
- Uma nota pode cobrir várias transações — insere uma linha por transação.
- **Não precisa rodar `CREATE OR REPLACE VIEW` nem mexer em mais nada.** As 5 views (`contabilidade`, `resumo`, `relatorio`, `rateio_garagem`, `rateio_posto`) leem essa tabela ao vivo, em cadeia — a partir do próximo `SELECT`, já vem tudo atualizado.

**Dois pontos que confundem à primeira vista:**

- **"Abastecimento cancelado" ≠ "Sem nota fiscal".** Depois de resolver toda a Leva 2 (todas as notas "por fora" registradas), ainda pode sobrar saldo em "Abastecimento cancelado" no Resumo — isso é **normal e esperado**, é transação que foi estornada depois (crédito gerado), não é pendência de nota. Não tenta "zerar" isso com nota manual, não é o mecanismo certo pra essa categoria.
- **Transação "PENDENTE" na Truckpag**: existe um volume pequeno mas recorrente (na ordem de R$10 mil/mês, poucas dezenas de transação) de transação que a Truckpag ainda não finalizou do lado dela — essas não aparecem na integração principal (`torre.integration_truckpag_transacoes`), só na integração da API nova (`silver.truckpag_analitico_transacao`). A view já busca automaticamente nessa segunda fonte quando a primeira não tem o dado (ver `sql/fechamento_fatura/07_fallback_silver_analitico.sql`) — não precisa fazer nada especial, só não estranhar se aparecer de vez em quando.

## Fontes de dados

- Views do banco: schema `torre`, views `vw_conciliacao_truckpag_resumo`, `vw_conciliacao_truckpag_contabilidade`, `vw_conciliacao_truckpag_relatorio` (ver [`planilha-fechamento.md`](planilha-fechamento.md) para a lógica completa de cada uma).
- Planilha de referência: [`referencia/Contabilidade - Fatura 269308.xlsx`](../referencia/Contabilidade%20-%20Fatura%20269308.xlsx).

## Pontos de atenção / exceções conhecidas

- **Leva 2 / notas "por fora"**: mecanismo real desde 28/08/2026, ver seção acima — `torre.truckpag_notas_recolhidas_manual` + 1 `INSERT`.
- **`VERIFICAR BACKFILL`**: raro; majoritariamente placas fictícias/temporárias sem cadastro em `gold_dim_veiculo`. Ver [`planilha-fechamento.md`](planilha-fechamento.md).
- **Fatura de combustível ≠ fatura de pedágio**: números de título diferentes, processos separados.
- **Lançamento no ERP Bluefleet nunca deve ser automatizado** — decisão explícita do usuário (nem via banco, nem via API).
- **Bugs reais encontrados e corrigidos em 28/08/2026** (`sql/fechamento_fatura/05` a `09`, todos com comentário explicando a causa — vale ler antes de mexer nas views de novo):
  - View base (`vw_conciliacao_truckpag_contabilidade`) usava `JOIN` (inner) em vez de `LEFT JOIN` com a tabela de transações — item de cobrança sem transação correspondente **sumia da view inteira**, não só da categoria. Motivo raiz: a API legada da Truckpag não retorna transação em status `PENDENTE`.
  - Fallback pra `silver.truckpag_analitico_transacao` (API nova) quando a legada não tem a transação — recupera dado que existe, só está em outra tabela.
  - `JOIN` da nota fiscal (`integration_truckpag_nfe_vinculos`) usava a chave errada (`tr.transacao`, que fica `NULL` nos casos acima) — corrigido pra `ti.transacao_id`, que nunca é nulo.
  - `vw_conciliacao_truckpag_relatorio` não expunha a categoria ajustada (coluna nova, view antiga nunca tinha sido atualizada) — corrigido.
  - Consolidação: existiam duas famílias de view (`_contabilidade`/`_resumo` originais + `_ajustada`/`_resumo_v2` aditivas) — unificadas em uma só (`sql/fechamento_fatura/06_consolida_uma_view_por_proposito.sql`), pra não ter duas fontes de verdade.

## Cadência e volume

- **Fechamento é semanal**, não mensal — toda semana sai uma fatura Truckpag de combustível pra pagamento.
- Valor médio: **~R$500 mil por fatura**.

## Áreas relacionadas (destino do encaminhamento, passo 6)

Contabilidade, Financeiro e Controladoria — o e-mail/informações são encaminhados pras pessoas responsáveis nessas áreas.

## Perguntas em aberto

- (nenhuma pendente por enquanto)
