# Guia de Configuração e Template no Looker Studio (Data Studio) — Padrão Gritsch

Este documento traz o passo a passo completo para configurar o **Dashboard Executivo da Diretoria e Reuniões com Filiais** no **Google Looker Studio**, seguindo rigorosamente o **Design System e Manual de Identidade Visual Gritsch v1.0** (extraído dos documentos oficiais).

---

## 1. Fundamentos & Configurações da Página no Looker Studio

* **Dimensões da Tela:** `1920 × 1080 px` (Proporção 16:9 Full HD).
* **Margem de Segurança:** `40 px` em todos os lados (Largura útil de `1840 px`).
* **Tipografia Principal:** `Roboto Condensed` (Nativa do Google / Looker Studio).
* **Tipografia de Letreiro/Marca:** `Roboto Slab`.
* **Sem Sombra:** Todos os cards, tabelas e botões devem estar configurados com **Sombra = Nenhuma**.

### Paleta de Cores Oficial (Hexadecimal)

| Variável | Hexadecimal | RGB | Onde Usar no Looker Studio |
| :--- | :--- | :--- | :--- |
| **Azul Gritsch** | `#213035` | (33, 48, 53) | Títulos principais (H1, H2), KPIs dentro da meta, texto de destaque |
| **Vinho Gritsch** | `#8E2E2F` | (142, 46, 47) | Linha divisória do cabeçalho, faixas de seção, cabeçalhos de tabela |
| **Vermelho Alerta (NOK)** | `#FA1126` | (250, 17, 38) | Números fora da meta, séries críticas, alertas e desvios |
| **Verde Positivo (OK)** | `#13880D` | (19, 136, 13) | Barras de metas batidas, status OK em tabelas (NUNCA em box de KPI) |
| **Âmbar Atenção** | `#E8A33D` | (232, 163, 61) | Faixa intermediária de atenção (90% a 100% da meta) |
| **Cinza Borda** | `#BFBFBF` | (191, 191, 191) | Borda de cards, caixas de KPI e gráficos (espessura `1.6 px` / `1 px`) |
| **Cinza Régua** | `#E2E2E2` | (226, 226, 226) | Réguas verticais divisórias e linhas de grade internas |
| **Cinza Texto** | `#4E4D4D` | (78, 77, 77) | Rótulos de KPIs, legendas, eixos e corpo de tabela |
| **Branco** | `#FFFFFF` | (255, 255, 255) | Fundo dos cards e caixas de KPI |

---

## 2. Conexão de Dados (PostgreSQL Connector)

Conecte o Looker Studio ao banco de dados PostgreSQL do DW Gritsch e aponte para as seguintes views já criadas na pasta `postgres/sql/gold/40_views_bi_diretoria_looker_studio.sql`:

1. **Fonte Principal de KPIs:** `torre.vw_bi_diretoria_kpis_mensal`  
   *(Agregado por Filial e Mês com Custo Total, Km/L, R$/km, Excessos e Preventivas)*
2. **Analítico de Abastecimento:** `torre.vw_bi_diretoria_analitico_combustivel`  
   *(Transações TruckPag com identificação de abastecimentos suspeitos e postos)*
3. **Analítico de Pedágio:** `torre.vw_bi_diretoria_analitico_pedagio`  
   *(Passagens de pedágio por concessionária, filial e valor)*
4. **Analítico de Telemetria:** `torre.vw_bi_diretoria_analitico_telemetria`  
   *(Excessos de velocidade saneados por categoria, gravidade e placa)*
5. **Analítico de Frota e Manutenção:** `torre.vw_bi_diretoria_frota_manutencao`  
   *(Status de preventiva, odômetros e idade da frota)*

---

## 3. Estrutura do Cabeçalho (Header)

* **Zona da Logo (Esquerda - 264px):**
  * Inserir imagem: `https://gritsch.com.br/wp-content/uploads/2022/03/logomarca-1_gritsch-1.png`
  * Altura da marca: `86 px` (respiro de pelo menos `24 px` ao redor).
* **Régua Divisória Vertical:**
  * Linha vertical de espessura `3 px` e cor `#E2E2E2`.
* **Zona de Título (H1):**
  * Fonte: `Roboto Condensed SemiBold`, `32 px`, Cor: `#213035`.
  * Texto: `Painel Executivo de Rodagem e Frotas`
  * Subtítulo: `Roboto Condensed Regular`, `14 px`, Cor: `#4E4D4D` (Visão integrada de Abastecimento, Pedágio, Telemetria e Manutenção).
* **Zona de Contexto & Filtros (Direita):**
  * Controle de Lista Suspensa (Data/Mês): Dimensão `ano_mes`.
  * Controle de Lista Suspensa (Filial): Dimensão `filial_nome`.
  * Controle de Lista Suspensa (Grupo de Veículo): Dimensão `grupo_veiculo`.
* **Linha Divisória Inferior:**
  * Retângulo/Linha com largura útil de `1840 px`, altura de `3 px` e cor `#8E2E2F` (Vinho Gritsch).

---

## 4. Boxes de KPI no Topo (Scorecards)

Configurar 5 Scorecards com fundo `#FFFFFF`, borda de `1 px` na cor `#BFBFBF`, raio de canto de `12 px`:

1. **Custo Total de Rodagem:**
   * Métrica: `SUM(custo_total_rodagem)`
   * Formato: Moeda BRL (`R$ #,##0`)
   * Rótulo: `CUSTO TOTAL DE RODAGEM` (`14 px`, Bold, Caixa Alta, `#4E4D4D`)
   * Valor: `28 px`, Bold, `#213035`
   * Comparação: Período anterior (M-1)
2. **Custo Total por KM:**
   * Métrica: `SUM(custo_total_rodagem) / NULLIF(SUM(total_km_rodado), 0)`
   * Formato: Moeda com 2 decimais (`R$ 0,00/km`)
   * Valor: `28 px`, Bold, `#213035`
3. **Eficiência Média (KM/L):**
   * Métrica: `SUM(total_km_rodado) / NULLIF(SUM(total_litros), 0)`
   * Formato: Número com 2 decimais (`0,00 km/L`)
   * Valor: `28 px`, Bold, `#213035`
4. **Excessos de Velocidade (Telemetria):**
   * Métrica: `SUM(qtd_excessos_velocidade)`
   * Formato: Inteiro
   * Valor: `28 px`, Bold, `#FA1126` (Vermelho Alerta por ser infração)
5. **Frota em Operação / Preventivas:**
   * Métrica: `SUM(qtd_veiculos_abastecidos)` / `SUM(total_veiculos_cadastrados)`
   * Subtexto: `Preventivas Vencidas: SUM(preventivas_atrasadas)`

---

## 5. Quadrantes / Abas dos 4 Pilares

### Pilar 1: Abastecimento & Eficiência
* **Faixa de Título:** Retângulo com cantos arredondados (`10 px`), fundo `#8E2E2F`, texto branco em caixa alta: `1. ABASTECIMENTO & EFICIÊNCIA DE COMBUSTÍVEL`.
* **Gráfico de Barras Horizontais:** KM/L médio por `grupo_veiculo` (Bitruck, Truck, Toco, 3/4, Leves) com linha de meta tracejada em `#4E4D4D`.
* **Tabela de Auditoria:**
  * Abastecimentos Regulares vs Suspeitos (Tanque furado / Litros > Capacidade).
  * Colunas: `Qtd Transações`, `Litragem`, `Valor Total (R$)`, `Preço Médio/L`.

### Pilar 2: Gestão de Pedágios
* **Faixa de Título:** Fundo `#8E2E2F`, texto: `2. GESTÃO DE PEDÁGIOS & CONCESSIONÁRIAS`.
* **Tabela Rateio por Filial:**
  * Dimensões: `filial_nome`, `filial_regiao`.
  * Métricas: `qtd_passagens_pedagio`, `total_valor_pedagio`, `custo_pedagio_por_km`.
* **Top Praças de Pedágio:** Gráfico de barras verticais com as concessionárias de maior impacto (Arteris, CCR, EcoRodovias).

### Pilar 3: Telemetria & Segurança
* **Faixa de Título:** Fundo `#8E2E2F`, texto: `3. TELEMETRIA & SEGURANÇA DE FROTAS`.
* **Tabela Ranking de Infratores:**
  * Dimensões: `placa`, `filial_nome`, `modelo`, `grupo_veiculo`.
  * Métricas: `MAX(velocidade_registrada)`, `COUNT(excessos)`.
  * Marcador semáforo: `#FA1126` (Grave - >105 km/h em caminhões) e `#E8A33D` (Moderada).

### Pilar 4: Frotas & Manutenção
* **Faixa de Título:** Fundo `#8E2E2F`, texto: `4. FROTAS & MANUTENÇÃO PREVENTIVA`.
* **Tabela Status Preventivas:**
  * Dimensão: `status_preventiva_tempo` (Em Dia, Vence em 30d, Vencida >180d, Sem Registro).
  * Métricas: `Qtd Veículos`, `% do Total`.
  * Cores do semáforo: Verde `#13880D`, Amarelo `#E8A33D`, Vermelho `#FA1126`, Cinza `#BFBFBF`.

---

## 6. Arquivo de Pré-visualização Interativa

Para visualizar e testar o layout exato antes de montar no Looker Studio, abra no navegador o arquivo:
👉 `relatorios/template_bi_diretoria_gritsch.html`
