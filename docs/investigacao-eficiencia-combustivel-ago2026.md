# Investigação de eficiência de combustível — vilões e exemplares (ago/2026)

Registro da investigação que originou a camada `torre.gold_mv_perfil_operacional_veiculo` e as views `gold_v_benchmark_km_l_por_perfil` / `gold_v_classificacao_eficiencia_veiculo` (ver [`postgres/sql/gold/46_gold_perfil_operacional.sql`](../postgres/sql/gold/46_gold_perfil_operacional.sql)). Serve de referência para montar o Looker Studio e para explicar à diretoria de onde vêm os números — cada achado abaixo tem a query e o resultado real que o gerou.

**Pergunta original da diretoria:** "quais veículos gastam mais e quais gastam menos, comparando categoria com categoria — e queremos replicar os melhores e agir sobre os piores."

**Resposta curta:** dá pra responder, mas a resposta simples ("compara km/L por grupo de veículo") gera falso positivo. Bitruck e Toco "ruins" no km/L são, na maioria, operação urbana pesada legítima. Os vilões reais e acionáveis estão concentrados em Pesado (causa mecânica confirmada) e parcialmente em Médio (causa ainda não identificada).

---

## 1. Metodologia — por que 1 mês não basta

Um mês isolado mistura ruído (viagem atípica, sazonalidade) com padrão real. Toda classificação abaixo usa os **últimos 3 meses fechados** (mai/jun/jul-2026 na investigação original; a view `gold_v_classificacao_eficiencia_veiculo` usa uma janela dinâmica dos últimos 3 meses fechados, não fixa).

Regra de classificação por placa, comparada contra a média do seu próprio `grupo_veiculo`:

| Classificação | Critério |
|---|---|
| `VILAO_CRONICO` | km/L abaixo de 85% da média do grupo em **2 ou mais** dos 3 meses |
| `EXEMPLAR` | km/L acima de 115% da média do grupo em **2 ou mais** dos 3 meses |
| `REGULAR` | nem um nem outro |

Fonte: `torre.gold_mv_eficiencia_placa_mensal`, filtrando `NOT cobertura_parcial AND total_km >= 500 AND km_litro > 0`.

Resultado da primeira passada (mai-jul/2026): dezenas de placas por grupo classificadas, com concentração forte em **Médio** (24 vilão / 33 exemplar) e **Pesado** (38 vilão / 48 exemplar) — os dois grupos que a investigação aprofundou.

---

## 2. Achado 1 — Bitruck e Toco: falso vilão, operação urbana pesada justificada

Cruzando a classificação com o perfil real de viagem (ESL — `silver.esl_manifestos`), Bitruck e Toco mostraram um padrão invertido do esperado: os "vilões" fazem **mais viagens, muito mais curtas, carregando mais peso** que os exemplares do mesmo grupo.

| Grupo | Classificação | Viagens/3m | Km médio/viagem | Peso médio/viagem |
|---|---|---|---|---|
| Bitruck | Exemplar | 42 | 821 km | 1.678 kg |
| Bitruck | Vilão | 100 | 225 km | 3.289 kg |
| Toco | Exemplar | 30,6 | (ver nota metodológica §5) | 862 kg |
| Toco | Vilão | 44 | 60 km | 1.437 kg |

Km/L baixo aqui é **físico** (arranca-e-para urbano, carga cheia), não comportamental. Um Bitruck de Curitiba (`SEF8G22`) que parecia o pior vilão da frota (1,60 km/L) transportou 139,64 toneladas em 41 viagens e gerou **R$ 476.563 de frete no mês** — 0,9% desse valor em combustível.

**Decisão:** Bitruck e Toco não entram no ranking padrão de km/L. A view `gold_v_benchmark_km_l_por_perfil` resolve isso estruturalmente, segmentando o benchmark por `grupo_veiculo x perfil_operacional` em vez de só `grupo_veiculo`.

---

## 3. Achado 2 — Pesado: vilão real, causa mecânica confirmada

Pesado foi o único grupo onde o cruzamento com ESL **não** justificou o km/L ruim: vilões fazem viagens **3,4x mais curtas** (191 km vs 642 km) carregando **peso igual ou menor** (371 kg vs 407 kg) — sem a compensação de carga que explicou Bitruck/Toco.

### 3.1 Concentração por filial (normalizada pelo tamanho da frota)

Fonte: `torre.gold_dim_veiculo` + `torre.gold_dim_filial` (join por `garagem`), só frota `tipo = 'GRITSCH'`.

| Filial | Grupo | Frota ativa | Vilões crônicos/recorrentes | % da frota |
|---|---|---|---|---|
| Campo Grande | Pesado | 15 | 7 | **46,7%** |
| Florianópolis | Pesado | 11 | 4 | **36,4%** |
| Porto Alegre | Pesado | 34 | 9 | 26,5% |
| Curitiba | Pesado | 38 | 7 | 18,4% (proporcional ao tamanho — não é outlier) |

### 3.2 Manutenção (fonte: SQL Server `referencia.dbo.torre_vw_FechamentoManutencao`, últimos 12 meses)

Este é o achado que fecha a causa raiz. Comparando gasto de manutenção por peça/serviço, por placa, entre as 38 placas vilão e as 48 exemplar:

| Sistema | R$/placa Vilão | R$/placa Exemplar | Razão |
|---|---|---|---|
| **Motor & Injeção Diesel** (bico injetor, virabrequim, válvulas, correia distribuição) | **R$ 2.001** | R$ 190 | **10,5x** |
| **Câmbio/Embreagem** | R$ 558 | R$ 41 | 13,6x |
| **Arrefecimento** | R$ 663 | R$ 141 | 4,7x |
| **Pneu** | R$ 1.245 | R$ 499 | 2,5x |
| **Freio** | R$ 1.253 | R$ 742 | 1,7x |

A maioria dos itens de motor/injeção (bico injetor, virabrequim, tucho de válvula, balancim, guia de válvula, correia de distribuição) aparece com **R$ 0 nos exemplares**. Não é ruído — é a assinatura mecânica de motor desregulado, que ao mesmo tempo consome mais combustível *e* gera mais ordens de serviço. Recência de manutenção é igual entre os grupos (4 dias) — ou seja, não é veículo esquecido sem revisar, é veículo que quebra mais.

> **Ação recomendada:** inspeção de motor/injeção priorizada nas 38 placas, começando pelas de maior gasto acumulado de manutenção nos últimos 12 meses.

---

## 4. Achado 3 — Médio: vilão real, causa ainda não identificada

Ao contrário de Pesado, manutenção **não explica** o padrão em Médio: os 33 exemplares gastam *mais* em manutenção por placa (R$ 10.430) que os 24 vilões (R$ 9.491), ambos com revisão recentíssima (1-5 dias). A causa está em outro lugar — comportamento de condução ou perfil de rota, não peça quebrada.

### 4.1 Sinal geográfico

| Filial | Grupo | Frota ativa | Vilões | % da frota |
|---|---|---|---|---|
| Cuiabá | Médio | 15 | 6 | **40%** |
| Sinop | Médio | 14 | 5 | **35,7%** |

As duas piores filiais de Médio são as duas filiais do **Mato Grosso** — sugere causa regional (terreno, distância entre pontos, estilo de condução), não veículo individual isolado.

**Status: em aberto.** Próximo passo, se a diretoria priorizar, seria telemetria de aceleração/frenagem brusca ou marcha lenta excessiva nessas duas filiais, ou investigação em campo com o gestor local de MT.

---

## 5. Achado metodológico — correção do cálculo "km por viagem" (grupo Toco)

Numa passada intermediária, o grupo Toco "exemplar" mostrou 5.037 km/viagem — número irreal para uma entrega. Investigando os manifestos crus (`silver.esl_manifestos`), a causa foi dupla:

1. **Manifestos "fantasmas":** placas como `BDD3B73` e `RHQ4D40` tinham manifesto aberto no ESL por 30-50 dias sem `manifesto_chegada` preenchida corretamente, com peso ~0 — não é uma viagem real.
2. **Erro de agregação:** a média do grupo foi calculada como média simples da razão `km/viagens` por placa. Uma placa com poucos manifestos capturados (às vezes 1, e esse 1 sendo o fantasma acima) produz uma razão individual absurda que puxa a média do grupo inteiro.

**Correção a aplicar em qualquer cálculo futuro de km/viagem:** excluir manifestos com duração > 720h (30 dias), e agregar por `SUM(km)/SUM(viagens)` por placa/mês — nunca por média simples da razão por placa (foi o erro aqui).

O restante dos dados do Toco é real: `RHQ4D40`, `TAW7H30`, `BDU6J33`, `SEN8A12` têm dezenas de manifestos legítimos de rota interestadual (FLN↔CWB, POA↔CCM, SAO↔ITR↔RVD), com durações de 2-20h e cargas de centenas a milhares de kg — operação de longa distância real, oposta ao padrão urbano do Bitruck.

---

## 6. Achado 4 — Leve: pergunta diferente, não é de eficiência

Vilões de Leve rodam **menos** (6,4 viagens/3m) que exemplares (22,2 viagens/3m), com km/viagem parecido ou até maior. Não é consumo ruim, é subutilização. **Não misturar com a lista de vilões mecânicos** — a pergunta certa para Leve é "esse carro justifica ficar na frota?", não "ele gasta mal combustível".

---

## 7. Camada Gold de perfil operacional — tentada e revertida

Uma primeira tentativa de camada Gold (`gold_mv_perfil_operacional_veiculo` + 2 views, classificando cada veículo em `URBANO`/`RODOVIARIO`/`HIBRIDO`) foi criada, testada e **descartada** (view e MV dropadas, arquivo `.sql` removido do repositório). Registro do porquê, para não repetir o mesmo caminho sem necessidade:

- O critério inicial (km médio por viagem + % de viagens intermunicipais, via extração do código de garagem em `manifesto_filial_origem`/`manifesto_local_descarregamento`) falhou na validação: `SEF8G22` — nosso exemplo de referência de "Bitruck urbano pesado" — saiu classificado como `RODOVIARIO` com ~90-100% de viagens intermunicipais.
- Investigando com o mapa de malha da empresa (`Mapa Estrutural (9).drawio`, fornecido pelo usuário), ficou claro que veículos como `SEF8G22` fazem **transferência interfilial em rota fixa e horário programado** (ex: Curitiba↔Londrina, repetido diariamente) — um terceiro padrão operacional (nem entrega urbana de última milha, nem frete rodoviário avulso ponto-a-ponto) que o critério de 2 categorias não capturava. Faltava um sinal de **repetição do mesmo par origem-destino**, não só "é intermunicipal ou não".
- **Decisão:** não vale o investimento de acertar esse terceiro perfil agora sem um caso de uso puxando (nenhuma pergunta da diretoria depende disso hoje). A solução que já resolve o problema prático — Bitruck e Toco não entrarem no ranking padrão de km/L — continua válida e não precisa de view nova (ver §2). Se a diretoria pedir esse recorte específico no futuro, retomar com o sinal de repetição de rota como terceiro critério.

---

## 8. Fontes de dados usadas (duas bases distintas)

| Fonte | O quê | Observação |
|---|---|---|
| PostgreSQL DW (`torre`, `silver`) | Eficiência (`gold_mv_eficiencia_placa_mensal`), cadastro (`gold_dim_veiculo`, `gold_dim_filial`), viagens/carga (`silver.esl_manifestos`) | Acesso direto via `psql`/DBeaver neste ambiente |
| SQL Server Bluefleet (`referencia.dbo.torre_vw_FechamentoManutencao`) | Ordens de serviço e notas fiscais de manutenção por placa | **Sem conexão configurada neste repositório** — consultado manualmente pelo usuário e colado nas queries desta investigação. Ver mapeamento completo em [`Workflows - n8n/mapeamento_bancos_dw_bluefleet.md`](../Workflows%20-%20n8n/mapeamento_bancos_dw_bluefleet.md) |

`torre.vw_bi_manutencao_frota_master` (criada em `44_gold_manutencao_frota.sql`) **não** foi usada nesta investigação — ela reflete só o campo `ultima_manutencao_preventiva` do cadastro Bluefleet, não o histórico real de ordem de serviço/nota fiscal. Os números de manutenção desta investigação vêm direto de `referencia.dbo.torre_vw_FechamentoManutencao` no SQL Server.

---

## 9. Pendências / próximos passos

- [ ] Investigar causa raiz de Médio em Cuiabá/Sinop (telemetria de condução ou visita em campo) — manutenção já foi descartada como causa.
- [ ] Ranking por placa dentro de Pesado, priorizado por gasto de manutenção acumulado, para a diretoria saber por onde começar a inspeção de motor/injeção.
- [ ] Avaliar se vale conectar o SQL Server Bluefleet direto neste ambiente (hoje é 100% manual, colado pelo usuário) — reduziria fricção pra próximas investigações de manutenção.
- [ ] Reportar ao engenheiro de dados: manifestos ESL ficando abertos 30-50 dias sem `manifesto_chegada` (achado incidental, não é problema de frota); duplicidade de `garagem` para "Referência Curitiba" (com/sem acento) em `gold_dim_filial`.
- [ ] Domínio Leve: decidir com o gestor se subutilização (poucas viagens) deve virar critério de desmobilização de frota — pergunta de negócio, não de dado.
- [ ] Se a diretoria pedir recorte por perfil operacional (urbano/rodoviário/rota fixa interfilial) no Looker Studio: retomar §7, com sinal de repetição de par origem-destino.

---

## 10. Verificado

- [x] Classificação vilão/exemplar por persistência (3 meses) rodada para todos os grupos
- [x] Concentração por filial normalizada pelo tamanho da frota (corrigido bug de join sigla↔nome via `gold_dim_filial`)
- [x] Cruzamento com ESL confirmou Bitruck/Toco como falso positivo (carga/rota justificam)
- [x] Cruzamento com manutenção (SQL Server) confirmou causa mecânica real em Pesado, descartou em Médio
- [x] Anomalia de km/viagem do Toco (5.037 km) investigada e explicada — artefato de dado, não achado de frota
- [x] Camada Gold de perfil operacional prototipada, validada, e conscientemente revertida (não fica objeto não confiável no banco) — ver §7
