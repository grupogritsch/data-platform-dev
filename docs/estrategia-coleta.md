# Estratégia de coleta — proposta para validação

**Diretriz recebida:** consumir do webservice apenas o necessário para o relatório. Não há capacidade de armazenamento para o histórico de posições.

**Resposta curta:** dá para atender o relatório **sem coletar nenhuma posição histórica**, porque a própria 3S já entrega as posições agregadas por dia. A conta sai de **234 GB/ano para 4 GB/ano** — 58× menos — sem perder nada do que o relatório usa.

---

## 1. O que o relatório realmente consome

Auditei o SQL do node `03 - Buscar Alertas Consolidados SQL` em `Torre de Controle - Alertas Telemetria.json`. Ele lê a **array de eventos**, não a posição:

```sql
FROM bronze.nuxeo_posicao_eventos t,
LATERAL jsonb_array_elements(t.eventos_json) AS evt
...
AND (lower(e.nome_evento) LIKE '%excesso%' OR lower(e.nome_evento) LIKE '%velocidade%')
```

Campos usados de ponta a ponta (incluindo os nodes `14 - Agrupar por Filial + KPIs` e `18 - Gerar HTML Email`):

| Campo | Origem |
|---|---|
| `placa`, `velocidade`, `data/hora` | evento |
| `endereco`, `cidade`, `estado` | evento (coluna "Local" do e-mail) |
| `filial_operacional`, `modelo`, `situacao` | `torre.gold_dim_veiculo` (Bluefleet) |

**Nenhum campo vem da posição.** O histórico de posições é 98,5% do volume e 0% do relatório.

---

## 2. ⚠️ CORREÇÃO — a telemetria consolidada está VAZIA nesta conta

> **Testado contra a API em 03/08/2026. A versão anterior deste documento estava errada neste ponto.**

A proposta original se apoiava no bloco `tbVeiculoConsolidado`, que traria por veículo/dia `KMTotal`, `TempoMovimento`, `TempoMarchaLenta`, `VelocidadeMaxima` etc. — os agregados que normalmente se calculariam varrendo as posições.

Duas chamadas mostraram que **esse dado não existe para esta conta**:

| Teste | Resultado |
|---|---|
| `RetornaDados` bootstrap (`idTelemetria = 0`) | `<idTelemetria>0</idTelemetria>` — sem última ocorrência |
| `RetornaDados` com `idTelemetria = 1` (do início) | **0 registros**; o bloco `<tbTelemetria>` some da resposta |

Todos os outros domínios devolveram cursor normalmente (posição `32836079784`, alertas `156301772`). Só a telemetria está zerada — o padrão de um **módulo não habilitado no contrato**, não de uma frota sem dados.

### O que muda

**Não muda o relatório.** Ele consome eventos, e os eventos estão lá (contrato confirmado na seção 4). A estratégia de não coletar posições continua válida e continua entregando o relatório completo.

**Muda o que se perde.** Sem telemetria e sem posições, ficam indisponíveis: KM rodado, tempo em movimento/parado/marcha lenta, velocidade média, hodômetro. KPIs de eficiência e ociosidade a partir da 3S ficam fora de alcance.

### Recomendação

**Perguntar à 3S se a telemetria consolidada pode ser habilitada nesta conta.** É provavelmente um módulo contratável, e o retorno é desproporcional:

| | Linhas/dia | Volume/ano |
|---|---|---|
| Posições (para calcular os mesmos KPIs) | 634.000 | 234 GB |
| Telemetria consolidada | **3.169** | **1,2 GB** |

**200× menos linhas, com a agregação feita pelo fornecedor.** Se habilitarem, vocês ganham os KPIs de eficiência sem tocar no orçamento de armazenamento. Se não habilitarem, esses KPIs só existiriam guardando as posições — que é justamente o que não cabe.

É um e-mail, e pode ser feito junto com a pergunta de retenção.

---

## 3. Proposta: três níveis de coleta

### Nível 1 — Coletar e reter (permanente)

| Domínio | Método | Volume/dia | Por quê |
|---|---|---|---|
| **Eventos** (velocidade, sensor, cerca) | `RetornaDados` | ~6.300 linhas · 7 MB | **É o relatório** |
| **Telemetria diária** | `RetornaDados` | 3.169 linhas · 4 MB | KPIs de eficiência, ociosidade, condução |
| **Cadastro de veículos** | `ListaVeiculos` | 3.169 linhas (upsert) | Dimensão, sem crescimento |

**Total: ~11 MB/dia → 4 GB/ano.**

### Nível 2 — Coletar sem reter histórico (estado atual)

| Domínio | Método | Volume |
|---|---|---|
| **Última posição** | `ListaUltimaPosicaoVeiculos` | **3.169 linhas, fixo** |

Tabela de *snapshot*, não de histórico: `UPSERT` em `id_equipamento`, cada veículo tem uma linha que é sobrescrita. Responde "onde está cada veículo agora" e "quem parou de comunicar" com **crescimento zero** (~2,4 MB no total, para sempre).

É o que sustenta o `gold_v_frota_sem_sinal` sem custo nenhum.

### Nível 3 — Não coletar

| Domínio | Economia |
|---|---|
| **Histórico de posições** | 134 M linhas · 145 GB no backfill · 234 GB/ano |

Basta enviar `idPosicao = -1` no `RetornaDados`. A economia acontece **na origem**: o dado nem trafega, nem é parseado, nem chega ao banco. É literalmente o que a diretriz pede — consumir só o necessário.

> A estrutura de controle já prevê isso. É um `UPDATE` de uma linha:
> ```sql
> UPDATE bronze.tres_s_watermark SET habilitado = FALSE WHERE dominio = 'posicao';
> ```
> O workflow lê `habilitado` e envia `-1` no envelope. Reverter é o mesmo `UPDATE` com `TRUE`.

---

## 4. Números — revisados com dados reais (03/08/2026)

### 🔑 O cursor do `RetornaDados` anda para trás

Testado: cursor recuado abaixo da última ocorrência **devolve histórico**. Isso elimina o fan-out por veículo no backfill.

O backfill deixa de ser "3.169 veículos × N janelas" e vira **caminhar a sequência de IDs para trás**, com `idEquipamento = 0` (frota toda). O número de chamadas passa a depender só do teto de registros por resposta, não do tamanho da frota.

| Abordagem | Chamadas | Tempo a 10 req/min |
|---|---|---|
| Fan-out por veículo (plano anterior) | 3.169 | 5,3 horas |
| **Caminhar o cursor** | **dezenas** | **minutos** |

> Falta medir o teto de registros por resposta — uma chamada resolve. Mas a ordem de grandeza já mudou.

### Eventos são bem mais raros do que eu estimei

| | Estimativa anterior | Observado |
|---|---|---|
| Alertas de velocidade/dia | 6.338 | **~120** |

Amostra real: janela de ~3.000 IDs da sequência compartilhada (≈24 min) continha **2 alertas de velocidade**. A sequência avança ~125 IDs/min somando todos os tipos de alerta.

> ⚠️ **Amostra de 2 registros, numa segunda de manhã.** É indicação, não medição. Uma coleta de 24 h fecha o número. Mas mesmo errando por 10×, o volume é irrelevante.

### Backfill revisado (01/01/2026 → hoje, 215 dias)

| | Só eventos | Com posições (descartado) |
|---|---|---|
| Chamadas | **dezenas** | 22.183 |
| Tempo | **minutos** | 37 horas |
| Linhas | ~26 mil | 134 M |
| Armazenamento | **~30 MB** | 145 GB |

### Regime diário

| | |
|---|---|
| Chamadas/dia | **145 de 14.400** (1% do orçamento) |
| Armazenamento | **< 1 MB/dia → ~350 MB/ano** |

Detalhe: `RetornaDados` a cada 15 min (96) + `ListaUltimaPosicaoVeiculos` a cada 30 min (48) + `ListaVeiculos` diário (1).

Com telemetria desabilitada e eventos nesse volume, o consumo de disco da 3S é **praticamente nulo**. O custo do projeto migra inteiramente para a Nuxeo, cujas tabelas de posição já acumuladas devem ser o maior item de espaço hoje.

---

## 5. O que se perde — e por que é aceitável

Assumindo a proposta, ficam **impossíveis retroativamente**:

| Perda | Mitigação |
|---|---|
| Reconstruir trajeto de um veículo | Última posição cobre o "agora". Trajeto histórico não é usado por nenhum relatório hoje |
| Recalcular distância percorrida | `KMTotal` vem pronto na telemetria diária |
| Análise retroativa de cerca | As **violações** de cerca são coletadas como evento — só a trajetória entre elas se perde |
| Perícia sobre um incidente específico | Consultar direto no portal da 3S, caso a caso |

> ✅ **Posições:** a 3S mantém ~5 anos. Relatório detalhado de posição sai do portal deles sob demanda. Isso desarma o argumento contra não guardar posições — não é perda, é mudança de onde o dado mora.
>
> 🔴 **Alertas: a retenção é de ~36 DIAS, não 5 anos.** Medido em 03/08/2026 — ver seção 5.1. A regra dos 5 anos **não vale para ocorrências de alerta**.
>
> **Isso inverte a prioridade do projeto.** Não existe backfill de eventos a fazer: o que passar de ~36 dias some do lado da 3S. Nosso bronze passa a ser o **único registro histórico** dos alertas, e cada dia sem ingestão é uma perda permanente. Ligar a coleta diária é urgente; o backfill é irrelevante porque não há o que buscar.

### 5.1 Retenção de alertas — medição

Testado com `HistoricoOcorrenciaVelocidade` no veículo `TBO 0C67` (equip. `20250626165563`):

| Janela | Registros |
|---|---|
| 01/07/2026 – 03/08/2026 | **274** ✅ |
| 01/06/2026 – 30/06/2026 | 21 (só a partir de 29/06) |
| 01/04/2026 – 30/04/2026 | **0** |
| 01/01/2026 – 31/03/2026 | **0** |

E via `RetornaDados` com cursor recuado ao máximo: **1.166 eventos, de 28/06/2026 a 03/08/2026 — 36 dias**, e nada antes.

**Não é limitação de configuração.** Os `idAlerta` presentes nos dados decodificam para datas de criação em **fevereiro e março de 2026** (`20260220151643`, `20260310174359`) — as regras de alerta existem desde fevereiro, mas as **ocorrências** anteriores a 28/06 não estão mais disponíveis.

Conclusão: é retenção do lado da 3S, na casa de **~36 dias para ocorrências de alerta**.

> Vale confirmar o número oficial com a 3S — e perguntar se há plano/contrato com retenção maior.

### Válvula de escape de 7 dias — não necessária

A ideia de reter posições recentes por 7 dias (~4,5 GB fixos) existia para cobrir investigação de incidente. **Com 5 anos de retenção no fornecedor, ela perde a razão de ser.** Fica registrada caso apareça uma necessidade de consulta frequente o bastante para não valer abrir o portal.

---

## 6. A mesma lógica vale para a Nuxeo — ✅ aprovado

Hoje o `NUXEO - 3` usa `lastPositionAndEvent`, que traz os eventos **embutidos dentro dos registros de posição** — ou seja, pagamos pelas posições para chegar nos eventos, e gravamos as duas coisas em `bronze.nuxeo_posicao_eventos`.

Plano, espelhando a 3S:

| Workflow | Hoje | Passa a ser |
|---|---|---|
| `NUXEO - 4 - Ingestão Eventos por Placa` | `active = false` | **Ativar** — vira a fonte de eventos |
| `NUXEO - 3 - lastPositionAndEvent` | horário, grava posição + evento | Desativar depois que o `NUXEO - 4` estiver validado |
| `NUXEO - 2 - positionByPlate` | horário, só posições | Desativar |
| `NUXEO - 1 - targetAndPosition` | 30 min | **Manter** — vira o snapshot de última posição |

Antes de desligar o `NUXEO - 3`, rodar os dois em paralelo por alguns dias e conferir que a contagem de eventos bate. É o mesmo cuidado do corte do relatório.

> As tabelas `bronze.nuxeo_posicoes_detalhadas` e `bronze.nuxeo_posicao_eventos` acumulam posições hoje. Vale medir o tamanho atual delas e definir se o histórico já coletado é descartado ou mantido — provavelmente o maior ganho imediato de espaço do projeto.

---

## 7. Pontos para sua validação

| # | Ponto | Status |
|---|---|---|
| 1 | Retenção no fornecedor | ✅ **~5 anos na 3S** — risco desarmado |
| 2 | Mesma lógica na Nuxeo | ✅ **Aprovado** |
| 3 | Válvula de 7 dias | ✅ Dispensada (item 1 resolve) |
| 4 | Manter última posição em snapshot (Nível 2) | ⬜ Recomendo sim — custo ~zero, habilita frota sem sinal |
| 5 | Backfill de eventos desde 01/01/2026 | ⬜ Confirmar o período |
| 6 | `kpis-torre-de-controle` usa posição? | ⬜ **Verificar** — o FastAPI/frontend lê este mesmo DW; se alguma tela usa posição, muda o desenho |
| 7 | Pedir à 3S a habilitação da telemetria consolidada | ⬜ Ver seção 2 — 200× mais barato que posições para os mesmos KPIs |

---

## 8. Nota de arquitetura

Vale registrar a distinção, porque as duas coisas costumam ser confundidas:

- **Reduzir o escopo da coleta** (não pedir posições à API) — decisão de produto, legítima, reversível para frente, e é o que está sendo proposto.
- **Filtrar linhas dentro de um domínio que já foi coletado** (baixar posições e guardar só as "interessantes") — isso sim quebra o princípio do bronze, porque descarta a evidência e não dá para reprocessar.

A proposta faz o primeiro, não o segundo. Dentro de cada domínio que continuarmos coletando, o bronze segue fiel à origem: nada de filtro, nada de normalização, XML cru preservado em `tres_s_raw_response`.
