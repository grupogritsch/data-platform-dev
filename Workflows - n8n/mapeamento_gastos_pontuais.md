# 💰 Mapeamento & Captura de Gastos Pontuais / Fora de Controle

> **Objetivo**: Mapear os custos operacionais da frota que hoje não passam pelos cartões centralizados (TruckPag) e criar a estrutura no DW para capturá-los, consolidando o **Custo Total Operacional Real** (Combustível + Pedágio + Manutenção + Reembolsos + Multas).

---

## 📋 Item 1 do Checklist — Mapeamento das Despesas sem Registro Centralizado

Atualmente, o DW captura de forma automática:
- ⛽ **Combustível** (via TruckPag `gold_truckpag_combustivel`)
- 🛣️ **Pedágio** (via TruckPag `gold_truckpag_pedagio`)

As **5 categorias de despesas pontuais / fora de controle** identificadas na operação de transporte são:

| # | Categoria | Exemplos de Despesas | Origem Atual do Dado | Risco de Vazamento |
|---|---|---|---|---|
| **1** | **Reembolsos Emergenciais de Motorista** | Abastecimento fora da rede credenciada, conserto de pneu (borracharia na estrada), guincho de emergência, pernoite, estacionamento de apoio, sanitização/lavagem de baú | Caixinha da Filial / Nota em papel / Reembolso RH/Financeiro | 🔴 **ALTO** (sem conciliação por placa/KM) |
| **2** | **Manutenção Externa & Peças** | Oficinas mecânicas credenciadas locais, compra emergencial de óleo/lâmpada/correia em viagem, recapagem/troca de pneus fora da garagem | Ordens de Serviço ERP (TOTVS/Sofit/Bluefleet) | 🟡 **MÉDIO** (fragmentado por filial) |
| **3** | **Multas de Trânsito & ANTT** | Excesso de velocidade, evadir balança de pesagem ANTT, restrição de rodízio, estacionamento irregular, taxas de pátio/reboque de trânsito | Sistema de Gestão de Multas / Notificações Detran | 🔴 **ALTO** (geralmente descoberto meses depois) |
| **4** | **Insumos a Granel / Almoxarifado** | Arla 32 comprado a granel para tanque da garagem, óleos lubrificantes em tambor, graxas e aditivos | Notas de Entrada de Compras / Estoque | 🟡 **MÉDIO** (sem rateio exato por placa) |
| **5** | **Sinistros & Avarias de Carga** | Pequenas avarias de carga ou avarias na lataria/sider pagas diretamente pela garagem local para liberação do cliente | Acordos locais / Faturamento direto | 🔴 **ALTO** (não contabilizado na frota) |

---

## 🛠️ Item 2 do Checklist — Regra e Fluxo de Lançamento e Captura no DW

### 🏛️ 1. DDL — Criar Tabela Fato no DW (`torre.gold_fato_despesas_complementares`)

```sql
-- ============================================================
-- DDL: torre.gold_fato_despesas_complementares
-- Captura gastos pontuais, reembolsos, manutenções e multas por placa
-- ============================================================
CREATE TABLE IF NOT EXISTS torre.gold_fato_despesas_complementares (
  id                       SERIAL PRIMARY KEY,
  data_despesa             DATE NOT NULL,
  placa                    VARCHAR(10) NOT NULL,
  filial_nome              VARCHAR(100) NOT NULL,
  garagem                  VARCHAR(100),
  categoria_despesa        VARCHAR(50) NOT NULL, 
  -- Categorias: 'REEMBOLSO_MOTORISTA', 'BORRACHARIA', 'GUINCHO', 'LAVAGEM', 'MANUTENCAO', 'MULTA', 'ARLA_GRANEL', 'AVARIA'
  subcategoria             VARCHAR(100),
  descricao_detalhada      TEXT,
  valor_bruto              NUMERIC(12,2) NOT NULL,
  valor_liquido            NUMERIC(12,2) NOT NULL,
  numero_nota_fiscal       VARCHAR(50),
  cnpj_fornecedor          VARCHAR(20),
  nome_fornecedor          VARCHAR(150),
  aprovador_nome           VARCHAR(100),
  origem_dado              VARCHAR(50) NOT NULL, -- 'ERP_TOTVS', 'FORMULARIO_N8N', 'GOOGLE_SHEETS', 'IMPORTACAO_CSV'
  chave_externa_id         VARCHAR(100), -- ID único na origem para evitar duplicidade
  criado_em                TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT uq_despesa_complementar_ext UNIQUE (origem_dado, chave_externa_id)
);

-- Índices para performance em consultas por filial, data e placa
CREATE INDEX IF NOT EXISTS idx_despesas_comp_placa ON torre.gold_fato_despesas_complementares (placa, data_despesa DESC);
CREATE INDEX IF NOT EXISTS idx_despesas_comp_filial ON torre.gold_fato_despesas_complementares (filial_nome, data_despesa DESC);
CREATE INDEX IF NOT EXISTS idx_despesas_comp_categoria ON torre.gold_fato_despesas_complementares (categoria_despesa);
```

---

### 🔄 2. Fluxo de Ingestão via n8n

```
                               ┌──────────────────────────┐
                               │  ERP TOTVS / Financeiro  │
                               └────────────┬─────────────┘
                                            │ (API / SQL)
                                            ▼
┌─────────────────────────┐    ┌──────────────────────────┐    ┌──────────────────────────────┐
│ Form n8n / Google Sheets│───>│  n8n Workflow de Ingestão│───>│  torre.gold_fato_despesas_   │
│ (Lançamento da Filial)  │    │  & Validação de Placa    │    │  complementares (Postgres DW)│
└─────────────────────────┘    └──────────────────────────┘    └──────────────┬───────────────┘
                                                                              │
                                                                              ▼
                                                               ┌──────────────────────────────┐
                                                               │  View Custo Operacional      │
                                                               │  Consolidada Mensal          │
                                                               └──────────────────────────────┘
```

#### Regras de Validação no n8n antes de Inserir no DW:
1. **Placa**: Normalizar (`UPPER(REPLACE(placa, '-', ''))`) e validar se a placa existe em `torre.gold_dim_veiculo` ou `torre.gold_dim_placa_excecao`.
2. **Duplicidade**: O campo `CONSTRAINT uq_despesa_complementar_ext` impede que o mesmo lançamento do ERP ou planilha seja inserido duas vezes.
3. **Data**: Não permitir lançamentos com data futura ou mais antiga que 180 dias sem justificativa.

---

### 📊 3. Consolidação na View de Custo Operacional (`torre.gold_v_custo_operacional_completo`)

```sql
-- View unificada somando Combustível + Pedágio + Gastos Complementares
CREATE OR REPLACE VIEW torre.gold_v_custo_operacional_completo AS
WITH despesas_agg AS (
  SELECT
    TO_CHAR(data_despesa, 'YYYY-MM') AS ano_mes,
    filial_nome,
    placa,
    SUM(CASE WHEN categoria_despesa = 'MANUTENCAO' THEN valor_liquido ELSE 0 END) AS custo_manutencao,
    SUM(CASE WHEN categoria_despesa IN ('REEMBOLSO_MOTORISTA', 'BORRACHARIA', 'GUINCHO', 'LAVAGEM') THEN valor_liquido ELSE 0 END) AS custo_reembolsos_emergenciais,
    SUM(CASE WHEN categoria_despesa = 'MULTA' THEN valor_liquido ELSE 0 END) AS custo_multas,
    SUM(valor_liquido) AS custo_complementar_total
  FROM torre.gold_fato_despesas_complementares
  GROUP BY TO_CHAR(data_despesa, 'YYYY-MM'), filial_nome, placa
)
SELECT
  COALESCE(c.ano_mes, d.ano_mes) AS ano_mes,
  COALESCE(c.filial_nome, d.filial_nome) AS filial_nome,
  COALESCE(c.placa, d.placa) AS placa,
  COALESCE(c.total_valor_liquido, 0) AS custo_combustivel,
  COALESCE(c.custo_pedagio, 0) AS custo_pedagio,
  COALESCE(d.custo_manutencao, 0) AS custo_manutencao,
  COALESCE(d.custo_reembolsos_emergenciais, 0) AS custo_reembolsos,
  COALESCE(d.custo_multas, 0) AS custo_multas,
  -- CUSTO OPERACIONAL TOTAL REAL
  COALESCE(c.total_valor_liquido, 0) 
    + COALESCE(c.custo_pedagio, 0) 
    + COALESCE(d.custo_complementar_total, 0) AS custo_operacional_total
FROM torre.gold_v_custo_operacional_mensal c
FULL OUTER JOIN despesas_agg d
  ON c.ano_mes = d.ano_mes AND c.filial_nome = d.filial_nome;
```

---

## 📌 Checklist de Implementação Prática

| # | Etapa | Responsável | Status |
|---|---|---|---|
| **1** | Criar tabela `torre.gold_fato_despesas_complementares` no DW | Engenharia de Dados | 🔲 Pendente |
| **2** | Definir método de entrada inicial (Planilha Google Sheets Padronizada por Filial ou Formulário n8n) | Operação / TI | 🔲 Pendente |
| **3** | Criar workflow n8n de ingestão diária da planilha/ERP para o DW | Engenharia de Dados | 🔲 Pendente |
| **4** | Atualizar a View de Custo Operacional Completo no DW | Engenharia de Dados | 🔲 Pendente |
| **5** | Incluir card de "Gastos Complementares" no e-mail semanal da filial | Torre de Controle | 🔲 Pendente |
