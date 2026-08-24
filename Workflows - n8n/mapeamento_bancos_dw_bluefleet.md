# 🗺️ Mapeamento Definitivo dos Bancos de Dados — DW & Bluefleet

> **Objetivo**: Dicionário e mapa de dados integrado unificando o **PostgreSQL DW** (`torre.*`) e o **SQL Server Bluefleet** (`dbo.*` e `referencia.dbo.*`), detalhando cada tabela, visão e indicador disponível para os relatórios da Torre de Controle.

---

## 🚚 Domínio 1 — Frota & Cadastro de Veículos

| Banco / Schema | Tabela / View | Colunas Chave | Conteúdo & Finalidade | Regra de Uso / Observação |
|---|---|---|---|---|
| **PostgreSQL DW** | `torre.gold_dim_veiculo` | `placa`, `modelo_raw`, `grupo_veiculo`, `filial_operacional`, `situacao_veiculo`, `tanque_litros`, `ano_modelo`, `ano_fabricacao`, `montadora`, `odometro_confirmado` | Cadastro master ativo no DW (21.824 placas). Sincronizado diariamente às 04:00 AM. | Chave primária: `placa` (sem traço ou espaço, maiúscula). `grupo_veiculo` é classificado via regex (`gold_classificar_veiculo()`). |
| **PostgreSQL DW** | `torre.gold_hist_veiculo` | `placa`, `filial_operacional`, `situacao_veiculo`, `valido_de`, `valido_ate`, `atual` | Histórico SCD Tipo 2 de transferências de filial e mudanças de situação do veículo. | Registros vigentes têm `atual = TRUE` e `valido_ate IS NULL`. Permite saber onde o veículo estava em qualquer data passada. |
| **PostgreSQL DW** | `torre.gold_dim_filial` | `garagem`, `filial_nome`, `filial_estado`, `filial_regiao`, `tipo` | Dimensão de filiais (40 garagens). De-para de nomes brutos de garagem para o nome oficial. | Ex: `GRITSCH - CWB (BASE)` $\rightarrow$ `Gritsch Curitiba (Base)`. |
| **PostgreSQL DW** | `torre.gold_dim_placa_excecao` | `placa`, `descricao`, `filial_nome`, `grupo_veiculo`, `tipo` | Placas de exceção que nunca estarão no Bluefleet (veículos particulares, preparação, terceiros, placas fictícias). | `tipo IN ('FUNCIONARIO', 'PREPARACAO', 'TERCEIRO')`. Ex: `TBI2068` (preparação). |
| **SQL Server** | `referencia.dbo.veiculos` | `Placa`, `Modelo`, `FilialOperacional`, `SituacaoVeiculo`, `TanqueLitros`, `AnoModelo`, `AnoFabricacao`, `Montadora` | Tabela de origem no SQL Server (21.830 linhas brutas, sendo 21.823 placas válidas + 7 registros sem placa `NULL`). | Origem da sincronização da `gold_dim_veiculo`. |
| **SQL Server** | `dbo.HistoricoSituacaoVeiculos` | `Placa`, `SituacaoVeiculo`, `UltimaAtualizacao` | Registra datas de mudança de status no SQL Server (ex: data de venda do veículo). | Usado para identificar veículos vendidos. |

---

## ⛽ Domínio 2 — Combustível & Mercado ANP

| Banco / Schema | Tabela / View | Colunas Chave | Conteúdo & Finalidade | Regra de Uso / Observação |
|---|---|---|---|---|
| **PostgreSQL DW** | `torre.gold_truckpag_combustivel` (View) | `transacao`, `data`, `placa`, `hodometro`, `valor`, `valor_liquido`, `litragem`, `preco_unitario`, `grupo_combustivel`, `garagem`, `filial_nome`, `grupo_veiculo`, `transacao_estornada` | Visão Gold de abastecimentos do cartão TruckPag com estornos abatidos e dimensões cruzadas. | `servico = 'ABASTECIMENTO'` e `transacao_estornada = false`. |
| **PostgreSQL DW** | `torre.gold_mv_comparativo_anp` (MV) | `placa`, `cnpj_posto`, `semana`, `grupo_combustivel`, `preco_unitario`, `preco_anp_ref`, `nivel_referencia`, `desvio_pct`, `custo_extra_vs_anp`, `status_preco` | Comparativo de preço pago vs mediana ANP em 3 níveis (Município, Vizinho 150km, Estado). | Níveis: `MUNICIPIO`, `VIZINHO`, `ESTADO`. `status_preco`: `MUITO_ACIMA`, `ACIMA`, `NORMAL`, `ABAIXO`. |
| **PostgreSQL DW** | `torre.gold_mv_ranking_postos` (MV) | `cnpj_posto`, `posto_nome`, `cidade_posto`, `uf_posto`, `grupo_combustivel`, `total_litros`, `total_gasto`, `preco_medio`, `desvio_pct_anp`, `custo_extra_total` | Ranking de postos utilizados pela frota com desvio ANP acumulado. | Usado para negociar desconto ou bloquear postos caros. |
| **PostgreSQL DW** | `torre.ref_benchmark_km_l` | `grupo_veiculo`, `grupo_combustivel`, `km_l_ref`, `alerta_85pct`, `alerta_70pct`, `tipo_calculo` | Metas de consumo KM/L por categoria de veículo e combustível. | `alerta_85pct` = Atenção; `alerta_70pct` = Crítico. Cobertura de 100% dos grupos operacionais. |
| **PostgreSQL DW** | `torre.raw_anp_combustiveis` | `cnpj_revenda`, `municipio`, `estado_sigla`, `produto`, `preco_revenda`, `data_coleta` | Pesquisa semanal de preços ANP no Brasil (1.074.000+ registros). | Raspado automaticamente toda segunda-feira às 10:00 AM. |
| **PostgreSQL DW** | `torre.ref_municipios_brasil` | `codigo_ibge`, `nome_municipio`, `uf`, `latitude`, `longitude` | Cadastro IBGE com coordenadas geográficas para cálculo de distância Haversine até postos vizinhos. | Usado no fallback de municípios vizinhos da ANP. |

---

## 🔧 Domínio 3 — Manutenção & Ordens de Serviço

| Banco / Schema | Tabela / View | Colunas Chave | Conteúdo & Finalidade | Regra de Uso / Observação |
|---|---|---|---|---|
| **SQL Server** | `referencia.dbo.torre_vw_FechamentoManutencao` | `IdItemOrdemServico`, `IdNF`, `NumeroNF`, `OrdemServico`, `Placa`, `DescricaoItem`, `TipoItem`, `ValorTotal`, `DataCriacao`, `FILIAL`, `Natureza_Correta` | Visão consolidada de manutenção por Ordem de Serviço e Notas diretas. | Filtra naturezas: `03.03 - MANUTENÇÃO DE VEÍCULOS`, `03.05 - RODAS E PNEUS`, `03.02 - LATARIA E PINTURA`. |
| **SQL Server** | `dbo.NotasFiscais` | `IdNF`, `NumeroNF`, `DataEmissao`, `DataEntrada`, `IdFornecedor`, `TipoNF`, `TipoOrdemCompra` | Cabeçalho das Notas Fiscais de fornecedores e oficinas no ERP. | `DataCriacao` ou `DataEmissao` define a competência da nota. |
| **SQL Server** | `dbo.ItensOrdemServico` | `IdItemOrdemServico`, `IdNF`, `Placa`, `DescricaoItem`, `TipoItem`, `Quantidade`, `ValorUnitario`, `ValorTotal`, `IdGrupoDespesa`, `Fornecedor` | Itens das notas fiscais/OSs (peças, serviços, pneus, lubrificantes). | Ligado a `dbo.GruposDespesa` e `dbo.NaturezasFinanceiras`. |
| **SQL Server** | `dbo.GruposDespesa` | `IdGrupoDespesas`, `CodigoCompleto`, `DescricaoCompleta`, `IdNaturezaFinanceira` | Árvore de classificação de despesas operacionais e administrativas. | Mapeia o item para a Natureza Financeira. |

---

## 🛣️ Domínio 4 — Pedágio & Concessionárias

| Banco / Schema | Tabela / View | Colunas Chave | Conteúdo & Finalidade | Regra de Uso / Observação |
|---|---|---|---|---|
| **PostgreSQL DW** | `torre.gold_truckpag_pedagio` (View) | `transacao`, `data`, `placa`, `valor`, `operadora`, `cidade_posto`, `uf_posto`, `garagem`, `filial_nome`, `grupo_veiculo` | Passagens de pedágio capturadas via tag TruckPag/Sem Parar/Veloe. | `servico = 'PEDAGIO'`. Permite extrair concessionária (`operadora`). |
| **PostgreSQL DW** | `torre.gold_mv_kpis_pedagio_mensal` (MV) | `ano_mes`, `filial_nome`, `grupo_veiculo`, `total_valor`, `qtd_passagens`, `ticket_medio` | Agregado mensal de pedágios por filial e grupo de veículo. | Usado na `gold_v_custo_operacional_mensal`. |

---

## 💸 Domínio 5 — Financeiro & Gastos Por Fora (Manuais / Sem Cartão)

| Banco / Schema | Tabela / View | Colunas Chave | Conteúdo & Finalidade | Regra de Uso / Observação |
|---|---|---|---|---|
| **SQL Server** | `dbo.LancamentosComNaturezas` | `NumeroLancamento`, `NumeroDocumento`, `PagarReceberDe`, `TipoLancamento`, `ValorNatureza`, `Natureza`, `DataCompetencia`, `Unidade`, `CentroCusto`, `Descricao` | **Tabela mestre de Lançamentos Financeiros do ERP**. Registra 100% das despesas e pagamentos da empresa. | **Filtro Gritsch**: `NOT LIKE '%REFERÊNCIA%' AND NOT LIKE '%LOCAÇÃO%'`. **Filtro Por Fora**: `NumeroDocumento NOT LIKE '%FAT%' AND PagarReceberDe NOT LIKE '%TRUCKPAG%'`. |
| **SQL Server** | `dbo.fundo_fixo` | `placa`, `filial`, `tipo_despesa`, `valor`, `litros`, `data_lancamento`, `status` | Prestação de contas do caixinha/fundo fixo das filiais. | Reembolsos manuais pagos diretamente pela garagem. |
| **PostgreSQL DW** | `torre.auditoria_abastecimentos_fora_rede_gritsch.sql` | Query otimizada extraindo os R\$ 50k-57k/mês de combustível por fora. | Script oficial de conciliação financeira de combustíveis. | Salvo em [`Workflows - n8n/auditoria_abastecimentos_fora_rede_gritsch.sql`](file:///home/gabriel/Projetos/data-platform-dev/Workflows%20-%20n8n/auditoria_abastecimentos_fora_rede_gritsch.sql). |

---

## 📊 Domínio 6 — Indicadores Agregados & Materialized Views (DW)

| Tabela / View | Granularidade | Principais Métricas | Aplicação em Relatórios |
|---|---|---|---|
| `torre.gold_v_custo_operacional_mensal` | Mês $\times$ Filial $\times$ Grupo | `total_valor_liquido` (combustível), `custo_pedagio`, `custo_total`, `pct_pedagio`, `qtd_veiculos` | Dashboard Executivo Mensal |
| `torre.gold_v_projecao_mes_atual` | Mês Atual | `realizado_ate_hoje`, `projecao_restante`, `projecao_fechamento`, `media_dia_util`, `media_dia_fds` | Card de Projeção MTD no Fechamento |
| `torre.gold_mv_eficiencia_placa_mensal` | Mês $\times$ Placa | `total_litros`, `total_gasto`, `km_percorrido`, `km_l_real`, `km_l_ref`, `desvio_pct`, `status_eficiencia` | Ranking de Eficiência por Placa |
| `torre.gold_mv_abastecimentos_suspeitos` | Transação | `placa`, `hodometro`, `litragem`, `score_risco`, `flags_suspeitas` | Painel de Auditoria de Anomalias |
| `torre.gold_fato_fechamento_semanal_combustivel` | Semana $\times$ Filial | `total_litros`, `total_gasto`, `preco_medio_litro`, `qtd_veiculos_ativos`, `total_km_rodado`, `custo_por_km`, `custo_extra_anp_total` | Histórico Semanal Fato (Snapshot Metabase/BI) |

---

## 🎯 Resumo da Estrutura de Fontes por Indicador

```
                   INDICADORES DO RELATÓRIO EXECUTIVO
                                  │
  ┌───────────────────────────────┼───────────────────────────────┐
  │                               │                               │
  ▼                               ▼                               ▼
COMBUSTÍVEL                    MANUTENÇÃO                      PEDÁGIO
├─ TruckPag: DW                └─ Ordem de Serviço / Nota:    └─ Tags: DW
│  `gold_truckpag_combustivel`    SQL Server                      `gold_truckpag_pedagio`
│                                 `torre_vw_FechamentoManutencao`
└─ Por Fora (Notas Diretas):
   SQL Server 
   `LancamentosComNaturezas`
```
