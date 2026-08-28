# Ingestão API Truckpag -> Bronze

> Pasta reservada para os scripts/workflows que vão consumir a API **nova** da Truckpag (ver [`referencia/API - TruckPag - Meios de Pagamentos.html`](../referencia/API%20-%20TruckPag%20-%20Meios%20de%20Pagamentos.html)) e salvar os dados brutos na camada bronze do DW (Postgres). Ainda vazio — nenhum script/workflow criado.

## Já consumido hoje

- `POST api/integracao/clientes/relatorios/analitico/transacao` — já tem bronze e silver montados. Não faz parte deste levantamento.

## Decisões em aberto

- Consumo via n8n (workflow) ou via script (Python/Node) chamado pelo n8n?
- Nome/schema da camada bronze no Postgres.
- Frequência de execução.

## Inventário de rotas disponíveis (levantado do doc da API, 160 endpoints em 23 categorias)

Legenda de status: 🟢 quero consumir · 🔴 não quero · ⚪ a decidir

| Categoria | Qtd | O que parece ser (a confirmar) | Status |
|---|---|---|---|
| `roteirizador` | 4 | **Pedágio**: praças de pedágio, praças ANTT, preços, roteirizador | ⚪ |
| `veiculo` | 21 | **Cadastro de veículo**: veículo, cor, modelo, marca, tipo, frota (CRUD completo) | ⚪ |
| `veiculo-crud` | 1 | Consulta de veículo pelo lado parceiro | ⚪ |
| `cnpj-nfe` | 17 | Cadastro/configuração de CNPJ emissor de NFe por empresa | ⚪ |
| `mapa-e-gerenciadora-de-riscos` | 20 | Rede credenciada, preços negociados, mapa de rotas, clientes | ⚪ |
| `endpoints` | 30 | Ordem de serviço de manutenção (oficina/balcão) | ⚪ |
| `manutencao` | 14 | Chamados, ordens de serviço, cancelamento de NF | ⚪ |
| `integracao-clientes` | 9 | Motorista (CRUD), relatórios analíticos, liberação por litragem, nota fiscal XML | ⚪ |
| `tags` | 8 | Tag RFID (veículo, contestação de transação) | ⚪ |
| `pos` | 6 | Maquininha POS (transações, motorista, parâmetros) | ⚪ |
| `integracao-ordem-servico` | 4 | Ordem de serviço de manutenção (oficina, lote, com nota fiscal) | ⚪ |
| `integracao-de-posto` | 4 | Integração com posto (autorização, NFe, transações sem NFe) | ⚪ |
| `vale-combustivel` | 4 | Vale-combustível (gerar, listar, cancelar, consultar) | ⚪ |
| `viagem` | 4 | Viagem do veículo (CRUD) | ⚪ |
| `transacao-liberacao` | 3 | Liberação/consulta/exclusão de regra de liberação de transação | ⚪ |
| `autorizacao-abastecimento` | 2 | Autorização de abastecimento na bomba | ⚪ |
| `credito` | 2 | Disponibilização de crédito (histórico e crédito eventual) | ⚪ |
| `daf` | 2 | Preços e programa de frotas | ⚪ |
| `bitrix` | 1 | Integração com CRM Bitrix (lead) | ⚪ |
| `dominios` | 1 | Bloqueio de e-mail (domínio) | ⚪ |
| `empresas` | 1 | Consulta de estabelecimentos por empresa | ⚪ |
| `negociacao-de-precos` | 1 | Preço de combustível negociado | ⚪ |
| `tpag` | 1 | TPag fiscal (posto) | ⚪ |

### Detalhe — `roteirizador` (pedágio)

```
GET  api/integracao/parceiros/pracas-pedagio
GET  api/integracao/parceiros/pracas-pedagio/pracas-antt
GET  api/integracao/parceiros/pracas-pedagio/precos
POST api/integracao/parceiros/pracas-pedagio/roteirizador
```

### Detalhe — `veiculo` + `veiculo-crud` (cadastro)

```
GET/POST  api/integracao/clientes/veiculo
GET/PUT   api/integracao/clientes/veiculo/{VEH_ID}
GET/POST  api/integracao/clientes/veiculo/cor
GET/PUT   api/integracao/clientes/veiculo/cor/{COR_ID}
GET/POST  api/integracao/clientes/veiculo/modelo
GET/PUT   api/integracao/clientes/veiculo/modelo/{MOD_ID}
GET       api/integracao/clientes/veiculo/frota
GET/POST  api/integracao/clientes/veiculo/marca
GET/PUT   api/integracao/clientes/veiculo/marca/{MAR_ID}
GET/POST  api/integracao/clientes/veiculo/tipo
GET/PUT   api/integracao/clientes/veiculo/tipo/{id}
GET       api/integracao/parceiros/veiculo   (veiculo-crud)
```

**Observação:** essa rota de cadastro de veículo é candidata natural pra resolver o gap do `'VERIFICAR BACKFILL'` documentado em [`docs/planilha-fechamento.md`](../docs/planilha-fechamento.md) — placas fictícias/temporárias que não existem em `gold_dim_veiculo` poderiam, em tese, ser encontradas/cadastradas por aqui.

## Próximo passo

Usuário vai revisando esta tabela e marcando quais categorias/rotas quer (🟢) ou não quer (🔴) consumir, pra fechar o escopo antes de desenhar o pipeline.
