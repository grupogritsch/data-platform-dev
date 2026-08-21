# Estimativa de volumetria — backfill 01/01/2026 + regime diário

> Backfill: **01/01/2026 → 31/07/2026 = 212 dias**
> Frota: **3.169 equipamentos** · Limite: **10 chamadas/minuto**

---

## 1. Base de cálculo

### Medido (contra a API, em 31/07/2026)

| | |
|---|---|
| Equipamentos (`ListaVeiculos`) | **3.169** |
| Resposta `ListaVeiculos` | 1,68 MB / 3.169 registros → **530 B por registro XML** |
| Tempo de resposta | 1,5 s |
| Rate limit | 10 req/min = 14.400 chamadas/dia (teto teórico) |

### Premissas (⚠️ NÃO medidas — só os testes `2.5` e `3.3` do Postman resolvem)

| Premissa | Baixo | **Médio** | Alto |
|---|---|---|---|
| Posições por veículo/dia | 80 | **200** | 400 |
| Alertas por veículo/dia | 0,5 | **2** | 5 |
| Telemetria | 1 linha/veículo/dia (granularidade a confirmar no teste `3.4`) |||

> A frota é de uma **locadora** (3.153 de 3.169 são "Passeio"). Veículo alugado alterna entre parado no pátio e em uso, então a média por veículo tende ao cenário baixo/médio. O cenário alto é o de frota rodando 8h+/dia.

---

## 2. Backfill — o custo está nas chamadas, não nos bytes

### 2.1 Tempo, por tamanho de janela

O número de chamadas é `3.169 × (nº de janelas)`. **O tamanho da janela é a variável que decide tudo** — e ela é limitada pelo teto de registros por resposta, que ainda não medimos.

| Janela por chamada | Chamadas | Tempo a 10/min |
|---|---|---|
| **7 meses (uma só)** | 3.169 | **5,3 horas** |
| Mensal | 22.183 | **37 horas** |
| Quinzenal | 47.535 | 3,3 dias |
| Semanal | 98.239 | 6,8 dias |
| Diária | 671.828 | **46,7 dias** ❌ inviável |

No cenário médio, uma janela mensal por veículo devolve ~6.000 posições. **Se a API tiver teto de 1.000 ou 5.000 registros por resposta, a janela mensal não fecha** e você cai para quinzenal ou semanal — de 37 horas para 3 a 7 dias.

> É exatamente isso que o teste **`2.5 - HistoricoPosicaoCompleto janela 30 dias`** mede. Número "redondo" na resposta (1.000, 5.000) = teto implícito.

### 2.2 Linhas geradas

`3.169 equipamentos × 212 dias = 671.828 veículo-dia`

| Domínio | Baixo | **Médio** | Alto |
|---|---|---|---|
| **Posições** | 53,7 M | **134,4 M** | 268,7 M |
| Alertas/eventos | 336 mil | **1,34 M** | 3,36 M |
| Telemetria diária | 672 mil | **672 mil** | 672 mil |

### 2.3 Armazenamento

Linha de posição no bronze: ~18 colunas TEXT (~250 B) + `payload_json` JSONB (~475 B) + overhead ≈ **750 B**. Índices somam ~35%.

| Cenário | Posições (linhas) | Com `payload_json` | Sem `payload_json` |
|---|---|---|---|
| Baixo | 53,7 M | **54 GB** | 20 GB |
| **Médio** | 134,4 M | **136 GB** | **51 GB** |
| Alto | 268,7 M | **272 GB** | 102 GB |

Eventos e telemetria são desprezíveis perto disso: **~2,4 GB somados** no cenário médio.

### 2.4 `tres_s_raw_response` (XML cru)

| | Cenário médio |
|---|---|
| XML por chamada (1 veículo, 1 mês) | ~3,2 MB |
| Total bruto (22.183 chamadas) | **70 GB** |
| Após compressão TOAST (XML comprime ~8:1) | **~9 GB** |

Postgres comprime `TEXT` grande automaticamente via TOAST. XML é altamente compressível, então o custo real é modesto — mas convém confirmar com uma amostra real antes de assumir 8:1.

---

## 3. Regime diário (depois do backfill)

Via `RetornaDados` com watermark, `idEquipamento=0`:

| | Baixo | **Médio** | Alto |
|---|---|---|---|
| Posições/dia | 254 mil | **634 mil** | 1,27 M |
| Chamadas/dia (ciclo de 15 min) | 96 | **96** | 96 |
| % do orçamento de 14.400/dia | **0,7%** | **0,7%** | **0,7%** |
| Posições por chamada | 2.640 | **6.600** | 13.200 |
| Bronze/dia (com `payload_json`) | 257 MB | **642 MB** | 1,28 GB |
| **Bronze/ano** | 94 GB | **234 GB** | 469 GB |

Eventos: ~6,3 mil linhas/dia (5 MB). Telemetria: 3.169 linhas/dia (3,2 MB). Irrelevantes.

> **O regime diário é confortável em chamadas** — 96 de 14.400 disponíveis, 0,7% do orçamento. Sobra folga enorme para retry e backfill em paralelo. O gargalo é disco, não rate limit.
>
> ⚠️ **Risco a validar:** 6.600 posições por chamada no cenário médio. Se houver teto de resposta, o ciclo de 15 min não drena o acúmulo e o watermark **fica para trás progressivamente**. O teste `3.3` mede isso. Mitigação: reduzir o ciclo para 5 min (288 chamadas/dia, ainda só 2% do orçamento).

---

## 4. Onde está o custo

**Posições são 99% de tudo.** No cenário médio:

| Domínio | Linhas | % |
|---|---|---|
| Posições | 134,4 M | **98,5%** |
| Eventos | 1,34 M | 1,0% |
| Telemetria | 672 mil | 0,5% |

Isso leva a uma pergunta que vale responder antes de gastar 37 horas de coleta:

**O relatório de telemetria precisa de posições históricas?**

O `Torre de Controle - Alertas Telemetria` reporta **excesso de velocidade por filial**. Isso vem de `fato_evento`, não de `fato_posicao`. Posição histórica só é necessária para trajetória, distância percorrida e cerca retroativa.

Backfill só de eventos + telemetria:

| | |
|---|---|
| Chamadas | 3.169 (janela única de 7 meses — cabe, porque eventos são ~100× mais raros) |
| Tempo | **~5,3 horas** |
| Armazenamento | **~2,4 GB** |

Contra 37 horas e 136 GB com posições. **Mesmo resultado no relatório, 15% do tempo e 2% do disco.**

---

## 5. Recomendações

**1. Fatiar o backfill por prioridade.** Eventos + telemetria primeiro (5 h, 2,4 GB) — já entrega o relatório completo. Posições depois, só se aparecer um caso de uso concreto.

**2. Testar se `RetornaDados` faz backfill.** A semântica do cursor é "dados **a partir** daquele ID". Se aceitar um ID artificialmente baixo, ele pode puxar histórico sem fan-out por veículo — o que colapsaria 37 horas em algumas horas. **É a incógnita de maior alavancagem que sobrou** e não está coberta pela collection atual; vale adicionar uma request.

**3. Telemetria histórica pode não existir.** Nenhum método do WSDL com `DataInicio`/`DataFim` devolve `tbVeiculoConsolidado` — só o `RetornaDados`, que é cursor. Se o cursor não voltar no tempo, **não há como fazer backfill de telemetria**: ela só acumula a partir do dia em que a ingestão ligar. Argumento forte para ligar a coleta corrente cedo, mesmo antes do backfill.

**4. Particionar `tres_s_posicoes` por mês** se as posições forem coletadas. A 134 M linhas, `DELETE` de retenção sem partição trava a tabela; com partição vira `DROP PARTITION`.

**5. Considerar dispensar `payload_json` nas posições.** Com `raw_response` guardando o XML completo, o `payload_json` por linha é redundante — e economiza **60% do disco** (136 GB → 51 GB no cenário médio). Nas tabelas de baixo volume (veículos, telemetria, eventos) vale manter.

**6. Dimensionar o disco.** O ambiente hoje é Docker com volume local. 136 GB de posições + 9 GB de XML no cenário médio, mais 234 GB/ano de crescimento, exige decisão de infra antes de começar.

---

## 6. Resumo executivo

| | Backfill (212 dias) | Diário | Anual |
|---|---|---|---|
| **Cenário médio, tudo** | 37 h · 136 M linhas · **145 GB** | 642 MB | 234 GB |
| **Só eventos + telemetria** | 5,3 h · 2 M linhas · **2,4 GB** | 8 MB | 3 GB |
| Chamadas/dia em regime | — | 96 de 14.400 (**0,7%**) | — |

> Margem de erro: as premissas de posições/veículo/dia não foram medidas. **O intervalo entre o cenário baixo e o alto é de 5×.** Os testes `2.5` e `3.3` no Postman fecham isso em duas chamadas — vale rodá-los antes de qualquer decisão de infra.
