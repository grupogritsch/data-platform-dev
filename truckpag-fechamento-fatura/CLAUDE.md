# CLAUDE.md (`truckpag-fechamento-fatura/`)

This file provides guidance to Claude Code (claude.ai/code) when working with code in this subdirectory.

> Movido de uma pasta solta `Truckpag/` pra dentro do repo `data-platform-dev`
> em 27/08/2026 — mesma empresa, mesmo DW, mesmo padrão de automação em n8n
> dos outros sub-projetos daqui (ver `CLAUDE.md` na raiz do repo). Os
> caminhos abaixo (`docs/`, `sql/`, `n8n/`, `referencia/`, `ingestao/`) são
> relativos a esta pasta (`truckpag-fechamento-fatura/`), não à raiz do repo.

## O que é este projeto

Este NÃO é um projeto de código/aplicação — é um projeto de **documentação de saída**. O usuário está saindo da empresa e está usando esta pasta para deixar documentado, para quem assumir depois:

1. Como funciona o processo de **fechamento de fatura** (cobrança/contabilidade).
2. Como funciona a **planilha de fechamento** atual — e, se der tempo, uma versão melhorada dela.
3. Como consumir a **API da Truckpag** (hoje não consumida) e salvar os dados na camada **bronze** do banco de dados.

Não espere aqui os elementos típicos de um CLAUDE.md de código (build/lint/test, arquitetura de app) — eles não existem porque ainda não há aplicação nenhuma neste repo. O valor deste arquivo é de contexto de negócio/ambiente.

## Ambiente da empresa (relevante para a documentação e para a futura ingestão)

- **DW**: Postgres, schema `torre` — é o destino final dos dados (camada bronze/silver/gold; `torre.gold_dim_veiculo` já existe como dimensão gold).
- **SQL Server**: usado pelo ERP **Bluefleet**. **Guardrail permanente**: nunca automatizar o lançamento de fatura no Bluefleet via banco ou API — decisão explícita do usuário, fica manual.
- **n8n** faz só a extração (Postgres → Planilha Google); o envio de e-mail é
  um **Apps Script** preso na planilha, não o n8n — decisão de 27/08/2026 pra
  não depender de mudança no container Docker (ver
  `docs/automacao-fechamento-sheets.md`, que é a versão atual; `docs/automacao-fechamento.md`
  é o desenho anterior, mantido por causa dos bugs de n8n documentados lá).
- **Data Studio / planilhas** são a camada de visualização pro negócio.
- Fatura de **combustível** e de **pedágio** são títulos/numeração diferentes — toda a conciliação abaixo é só de combustível. Fechamento é **semanal**, ~R$500 mil por fatura em média.
- Duas integrações Truckpag no DW: a **API legada** (tabelas `torre.integration_truckpag_*`, 100% funcional, alimenta as views de conciliação) e a **API nova** (doc em `referencia/API - TruckPag - Meios de Pagamentos.html`, 160 rotas em 23 categorias — só "analítico de transações" é consumida hoje, já com bronze+silver).
- Views de conciliação (schema `torre`): `vw_conciliacao_truckpag_contabilidade` (base), `_relatorio`, `_resumo` — lógica completa em `docs/planilha-fechamento.md`. Views aditivas novas (ver `sql/fechamento_fatura/`): `_contabilidade_ajustada`, `_resumo_v2`, `_rateio_garagem`, `_rateio_posto`.

## Estrutura do repositório

```
truckpag-fechamento-fatura/
├── .env                     # credenciais reais — NUNCA imprimir os valores, NUNCA commitar (nao existe aqui hoje; ver .env.example na raiz do repo)
├── referencia/               # materiais originais trazidos pelo usuário, como estão
│   ├── API - TruckPag - Meios de Pagamentos.html (+ _files/)   # export estático da doc da API nova
│   └── Contabilidade - Fatura 269308.xlsx                       # planilha de fechamento (exemplo real)
├── docs/                      # documentação escrita
│   ├── fechamento-fatura.md         # passo a passo do processo de fechamento
│   ├── planilha-fechamento.md       # lógica de cada view/aba + gaps conhecidos (Leva 2, backfill)
│   ├── automacao-fechamento.md      # desenho ANTERIOR (xlsx + e-mail dentro do n8n) -- historico, tem os bugs de n8n documentados
│   └── automacao-fechamento-sheets.md  # desenho ATUAL (n8n so escreve, Apps Script manda o e-mail)
├── sql/fechamento_fatura/      # scripts SQL das views/tabela novas (rodar em ordem numérica no DW)
├── n8n/                         # workflows n8n exportados (.json) para importar
│   ├── fechamento-fatura-combustivel.json          # versao anterior (xlsx), historico
│   ├── fechamento-fatura-combustivel-sheets.json   # versao atual (Google Sheets)
│   └── EnviarFechamentoSemanal.gs                  # Apps Script -- colar em Extensões > Apps Script na planilha
└── ingestao/                    # reservado para os scripts/workflows de API nova -> bronze (ainda vazio)
```

## Variáveis do `.env`

Agora documentadas no `.env.example` da raiz do repo (copiar pro `.env` da
raiz, não criar um `.env` separado aqui dentro). Só os nomes (os valores são
segredos, nunca exibir em chat/commits):

- `SQLSERVER_HOST`, `SQLSERVER_PORT`, `SQLSERVER_USER`, `SQLSERVER_PASSWORD`, `SQLSERVER_DB`
- `DW_HOST`, `DW_PORT`, `DW_NAME`, `DW_USER`, `DW_PASSWORD` (aponta pro mesmo
  Postgres que `POSTGRES_*` no `.env.example` — nomes duplicados por ter
  vindo de outro repo; considerar consolidar)
- `API_TRUCKPAG_PRD`, `API_TRUCKPAG_HML`

## Estado atual / próximos passos

- [x] `docs/fechamento-fatura.md` e `docs/planilha-fechamento.md` preenchidos com o processo e a lógica das views.
- [x] SQL das views novas (`sql/fechamento_fatura/`) — rodado e validado contra a fatura 271797 (ver achados em `docs/automacao-fechamento.md`).
- [x] Primeira versão da automação n8n (xlsx + e-mail direto no n8n) — testada e funcionando, mas exigia mudança de infra no container Docker pra gerar xlsx com várias abas.
- [x] Pivô pra Google Sheets + Apps Script (27/08/2026) — `docs/automacao-fechamento-sheets.md`, `n8n/fechamento-fatura-combustivel-sheets.json`, `n8n/EnviarFechamentoSemanal.gs`. Grafo do workflow validado programaticamente (sem node órfão, sem conexão quebrada), mas **nunca importado/rodado de verdade no n8n** — os parâmetros do node Google Sheets foram escritos batendo com a fonte oficial do n8n, não testados ao vivo.
- [ ] **Próximo passo real**: criar a Planilha Google (6 abas — ver `automacao-fechamento-sheets.md`), importar o workflow novo, configurar credenciais, rodar o plano de teste (fatura 02/09/2026) documentado lá.
- [ ] Definir escopo e priorizar rotas da API nova pra ingestão na bronze (ver `ingestao/README.md`).
- [ ] Eventual versão melhorada/substituição da planilha de fechamento.
