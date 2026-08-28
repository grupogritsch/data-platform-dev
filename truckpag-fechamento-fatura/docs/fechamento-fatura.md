# Fechamento de Fatura

> Rascunho — passo a passo montado a partir do que foi descrito até agora. Ainda precisa de detalhamento (ver "Perguntas em aberto").

## Objetivo

Descrever, passo a passo, como é feito o fechamento mensal (ou semanal) da fatura de **combustível** hoje, para que outra pessoa consiga reproduzir o processo sem depender de conhecimento tácito. Fatura de **pedágio** é um processo separado (numeração de título diferente) — não coberto aqui ainda.

## Passo a passo (hoje, manual)

1. Rodar as 3 views de conciliação (`vw_conciliacao_truckpag_resumo`, `vw_conciliacao_truckpag_contabilidade`, `vw_conciliacao_truckpag_relatorio`) para a fatura em questão.
2. Copiar o resultado pra planilha (hoje isso quebra formatação — números, encoding — e exige ajuste manual/com IA; ver melhoria proposta em [`automacao-fechamento.md`](automacao-fechamento.md)).
3. Calcular Rateio por Garagem e Rateio por Posto (hoje são fórmulas Excel em cima da aba Contabilidade — ver [`planilha-fechamento.md`](planilha-fechamento.md)).
4. Revisar a Leva 2: conferir se alguma nota "sem nota fiscal" já foi recolhida manualmente fora do sistema (fora da integração `nfe_vinculos`) e ajustar o valor final antes de fechar.
5. Com a planilha fechada, o setor do usuário lança e dá baixa nas notas no **sistema da Truckpag**.
6. Encaminha as informações relevantes (rateio, relatórios) para as áreas relacionadas conforme necessário.
7. Lançamento final da fatura no **ERP Bluefleet** — manual, não automatizável (ver guardrail em `automacao-fechamento.md`).

## Como deve ficar (com a automação n8n proposta)

Passos 1–3 (rodar views, montar planilha corretamente formatada, calcular rateios) passam a ser automáticos, rodando toda quinta-feira e chegando por e-mail pro setor responsável. Os passos 4–7 continuam manuais (revisão da Leva 2 via tabela de notas manuais, lançamento na Truckpag, encaminhamento, lançamento no Bluefleet).

## Fontes de dados

- Views do banco: schema `torre`, views `vw_conciliacao_truckpag_resumo`, `vw_conciliacao_truckpag_contabilidade`, `vw_conciliacao_truckpag_relatorio` (ver [`planilha-fechamento.md`](planilha-fechamento.md) para a lógica completa de cada uma).
- Planilha de referência: [`referencia/Contabilidade - Fatura 269308.xlsx`](../referencia/Contabilidade%20-%20Fatura%20269308.xlsx).

## Pontos de atenção / exceções conhecidas

- **Leva 2 / notas "por fora"**: notas não tributáveis recebidas fora do fluxo automático não entram na `nfe_vinculos`, e o valor real da Leva 2 só fecha depois de ajuste manual. Ver proposta de tabela de registro manual em [`automacao-fechamento.md`](automacao-fechamento.md).
- **`VERIFICAR BACKFILL`**: raro; majoritariamente placas fictícias/temporárias sem cadastro em `gold_dim_veiculo`. Ver [`planilha-fechamento.md`](planilha-fechamento.md).
- **Fatura de combustível ≠ fatura de pedágio**: números de título diferentes, processos separados.
- **Lançamento no ERP Bluefleet nunca deve ser automatizado** — decisão explícita do usuário (nem via banco, nem via API).

## Cadência e volume

- **Fechamento é semanal**, não mensal — toda semana sai uma fatura Truckpag de combustível pra pagamento.
- Valor médio: **~R$500 mil por fatura**.

## Áreas relacionadas (destino do encaminhamento, passo 6)

Contabilidade, Financeiro e Controladoria — o e-mail/informações são encaminhados pras pessoas responsáveis nessas áreas.

## Perguntas em aberto

- (nenhuma pendente por enquanto)
