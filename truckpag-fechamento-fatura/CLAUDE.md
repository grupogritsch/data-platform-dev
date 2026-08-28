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
- **n8n** é usado para orquestração/manipulação de dados — é a ferramenta escolhida pra automação do fechamento (ver `docs/automacao-fechamento.md`).
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
│   └── automacao-fechamento.md      # design da automação n8n (export + e-mail semanal)
├── sql/fechamento_fatura/      # scripts SQL das views/tabela novas (rodar em ordem numérica no DW)
├── n8n/                         # workflows n8n exportados (.json) para importar
│   └── fechamento-fatura-combustivel.json
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
- [x] Design da automação n8n do fechamento semanal (`docs/automacao-fechamento.md`) + SQL das views novas + workflow `.json` de rascunho.
- [ ] Rodar os scripts em `sql/fechamento_fatura/` no DW e validar contra a planilha de referência.
- [ ] Importar/testar o workflow n8n (`n8n/fechamento-fatura-combustivel.json`) usando a fatura com vencimento 02/09/2026 como teste.
- [ ] Definir escopo e priorizar rotas da API nova pra ingestão na bronze (ver `ingestao/README.md`).
- [ ] Eventual versão melhorada/substituição da planilha de fechamento.
