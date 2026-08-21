# Contrato real da API 3S (`data_export`) — levantamento

> Fonte de verdade: **WSDL ao vivo** + respostas reais da API.
> O manual `ManualConsumoWebService3S_080125.pdf` (v2.8, 08/01/2025) está **desatualizado em vários pontos** — este documento registra os deltas.
>
> Endpoint: `https://3stecnologia.eti.br/data_export/data_export.asmx`
> Namespace: `http://servicos.3stecnologia.com.br/data_export`
> Última atualização: 2026-07-31

---

## 1. Comportamentos gerais

### 1.1 Erro vem com HTTP 200
Toda falha retorna status **200** com a mensagem no corpo:
```xml
<string xmlns="...">Erro: [mensagem]</string>
```
Verificar **antes** de tratar como resposta normal. Mensagens conhecidas (manual §2.4):
`Usuário sem permissão de acesso ao webservice` · `Usuário ou senha inválidos` · `Senha expirada` · `Excesso de chamadas por minuto atingido`

### 1.2 O XML de dados vem escapado
Todas as operações são `xsd:string` no WSDL. Via SOAP a resposta é:
```xml
<soap:Envelope><soap:Body>
  <ListaVeiculosResponse xmlns="http://servicos.3stecnologia.com.br/data_export">
    <ListaVeiculosResult>&lt;Veiculo&gt;&lt;tbVeiculo&gt;...&lt;/tbVeiculo&gt;&lt;/Veiculo&gt;</ListaVeiculosResult>
  </ListaVeiculosResponse>
</soap:Body></soap:Envelope>
```

> ⚠️ **Delta vs. manual:** o manual mostra a resposta como `<string xmlns="...">` na raiz. Isso é o formato da chamada **HTTP GET/POST direta** ao `.asmx`. Via **SOAP** o retorno vem envelopado em `<{Metodo}Response><{Metodo}Result>`. Quem parseia precisa considerar as duas formas.

### 1.3 Namespace
| | |
|---|---|
| WSDL (`targetNamespace` e `soapAction`) | `http://servicos.3stecnologia.com.br/data_export` ✅ |
| Exemplos de resposta do manual | `http://www.3sil.com.br/data_export` ❌ legado |
| Alguns exemplos do manual | `https://ssl691.websiteseguro.com/w3sil/...` ❌ legado |

### 1.4 Rate limit
**10 chamadas/minuto** por padrão (manual §2.3). O usuário precisa de liberação adicional junto à 3S.

---

## 2. Métodos que existem no WSDL mas NÃO no manual v2.8

| Método | Assinatura | Relevância |
|---|---|---|
| `HistoricoPosicaoCompleto` | `Usuario, Senha, idEquipamento, DataInicio, DataFim` | **Alta** — candidato a substituir `HistoricoPosicao` no backfill |
| `RetornaDistanciaVeiculos` | `Usuario, Senha, DataInicio, DataFim` | **Alta** — sem `idEquipamento`, pode trazer a frota toda numa chamada |
| `RetornaUtilizacaoVeiculo` | `Usuario, Senha, idEquipamento, DataInicio, DataFim` | Média |
| `RetornaStatusComunicacao` | `Usuario, Senha, idEquipamento, TipoStatus, QtdeRegistro:int` | Média — base do "veículo sem sinal" |
| `ListaUltimaPosicaoVeiculoPlaca` | `Usuario, Senha, Placa` | Média |
| `RetornaGrupos` | `Usuario, Senha` | Média — pode substituir a filial vinda do Bluefleet |
| `RetornaGruposVeiculos` | `Usuario, Senha, idGrupo:long, idVeiculo:long` | Média |
| `RetornaEnviosDeComandos`, `SincronizaGrupoMacro`, `ListaFormulariosGrupo` | — | Baixa |

### `RetornaDados` — os 16 parâmetros na ordem exata
Todos são **`xsd:long`** (numéricos):
```
idEquipamento, idPosicao, idSensor, idMensagem, idTelemetria,
idAlertaVelocidade, idAlertaSensor, idAlertaTemperatura,
idAlertaTempoOperacaoContinua, idAlertaJornadaDiaria,
idAlertaMovimentacaoindevida, idCercaAlvo, idCercaCheckPoint,
idCercaLogradouro, idCercaPoligonal, idCercaRota
```
> ⚠️ `idAlertaMovimentacaoindevida` tem **`i` minúsculo** em "indevida". SOAP valida a sequência — errar o nome ou a ordem gera erro de schema.

Semântica: `-1` = só estrutura · `0` = devolve o ID da última ocorrência · `<id>` = devolve dados a partir daquele ID.

---

## 3. Resultados dos testes

### ✅ `ValidaLogin` — credencial confirmada

| | |
|---|---|
| Usuário | `referencia.locadora919` (o do `.env.example`) |
| Retorno | `<ValidaLoginResult>0</ValidaLoginResult>` = **válido** |

> **Ponto de decisão #1 resolvido.** O usuário `referencia.lojas`, hardcoded no Code node `01 - Credenciais & XML SOAP 3S` dos workflows 3S, **não** é o que deve ser usado.

### ✅ `ListaVeiculos` — contrato real

| | |
|---|---|
| Registros | **3.169** equipamentos |
| Tamanho | 1,68 MB |
| Tempo | 1,5 s |
| `idCliente` distintos | 1 |
| Placas duplicadas | 0 |

**Campos retornados (10 — presentes em 100% dos registros):**
```
Frota · Placa · Modelo · Chassis · RENAVAM · idEquipamento · idCliente · NumSerie · idVeiculo · Tipo
```

**Deltas vs. manual (que documenta 7 campos):**

| Delta | Detalhe | Impacto |
|---|---|---|
| `Chassi` → **`Chassis`** | O manual escreve `Chassi`; a API devolve `Chassis` | A coluna `chassi` do DDL atual **nunca seria preenchida** por um parser que siga o manual |
| **`NumSerie`** | Não documentado | Serial do rastreador — candidato a chave de junção com a Nuxeo |
| **`idVeiculo`** | Não documentado | **Chave distinta de `idEquipamento`** (ver abaixo) |
| **`Tipo`** | Não documentado | `Passeio` (3153) · `Caminhão` (11) · `Van` (5) |

> 🔴 **`idEquipamento` ≠ `idVeiculo` em 3.168 dos 3.169 registros.** Ambos são únicos, ambos no formato `yyyyMMddHHmmss`. São identificadores **diferentes**: `idEquipamento` é o rastreador, `idVeiculo` é o veículo. `RetornaDados` e `HistoricoPosicao` recebem **`idEquipamento`**. A tabela `bronze.tres_s_veiculos` precisa guardar os dois.

**Qualidade dos dados:**

| Verificação | Resultado |
|---|---|
| `Modelo` preenchido | 3.162 / 3.169 |
| `Chassis` preenchido (≠ `0`) | 2.992 / 3.169 |
| Placa no padrão Mercosul (`ABC1D23`) | 3.119 |
| Placa no padrão antigo (`ABC1234`) | 3 |
| **Placa contendo o CHASSI** (17 caracteres) | **23** ← veículos não emplacados |
| Placa fora de qualquer padrão | 24 |
| Registro que é TAG, não veículo | 1 (`Frota = "TAG - JUNIOR"`, placa `3092516754`) |

> 🔴 **Impacto na modelagem:** o join com `torre.gold_dim_veiculo` é por `placa` (PK). Os 47 registros fora do padrão **não vão casar**. O silver precisa de:
> - regra explícita para placa-que-é-chassi (não normalizar como placa; marcar `placa_valida = false`)
> - flag para ativos não-veículo (TAG)
> - a validação `^[A-Z0-9]{7}$` sugerida no plano **rejeitaria 47 registros silenciosamente** — tem que ser um teste de qualidade que reporta, não um filtro que descarta

### 🔴 Dimensionamento do backfill

```
3.169 equipamentos × 6 janelas mensais = 19.014 chamadas
19.014 ÷ 10 por minuto                 ≈ 31,7 HORAS
```

O backfill por veículo é **inviável**. Isso reforça a decisão de usar `RetornaDados` (1 chamada por ciclo, frota inteira) para a ingestão corrente, e restringir o backfill por veículo apenas à frota que realmente aparece no relatório.

> 💡 Vale testar `RetornaDistanciaVeiculos` e conferir se algum outro método aceita `idEquipamento=0` para histórico — seria a saída para o backfill.

---

## 4. Planilha de levantamento

### A) Inventário por método

| Método | Registro | Campos | Qtde | Tempo | Serve para |
|---|---|---|---|---|---|
| `ListaVeiculos` | `tbVeiculo` | ✅ *(seção 3)* | 3.169 | 1,5 s | `silver.dim_veiculo_rastreador` |
| `ListaUltimaPosicaoVeiculos` | `tbPosicao` | ⬜ | | | `silver.fato_posicao` |
| `HistoricoPosicao` | `tbPosicao` | ⬜ | | | backfill (candidato) |
| **`HistoricoPosicaoCompleto`** | `tbPosicao` | ⬜ | | | **backfill (preferido)** |
| `RetornaDados` / Posicao | `tbPosicao` | ⬜ | | | `silver.fato_posicao` |
| `RetornaDados` / Telemetria | `tbVeiculoConsolidado` | ⬜ | | | `silver.fato_telemetria_diaria` |
| `RetornaDados` / AlertaVelocidade | `tbAlertaVelocidade` | ⬜ | | | `silver.fato_evento` |
| `RetornaDados` / Sensor | `tbEstadoSensor` | ⬜ | | | `silver.fato_evento` |
| `RetornaDados` / Cerca* | `tbCerca*` | ⬜ | | | `silver.fato_evento` |
| `RetornaUtilizacaoVeiculo` | ? | ⬜ | | | `silver.fato_utilizacao` |
| `RetornaStatusComunicacao` | ? | ⬜ | | | `gold_v_frota_sem_sinal` |

### B) Perguntas fechadas

- [x] Qual credencial é válida? → **`referencia.locadora919`**
- [x] Tamanho da frota 3S → **3.169 equipamentos**
- [x] `idEquipamento` e `idVeiculo` são a mesma coisa? → **Não, diferem em 3.168/3.169**
- [ ] `HistoricoPosicaoCompleto` traz `idPosicao`, `Placa`, `idEquipamento`?
- [ ] `RetornaDados` com `idEquipamento=0` traz mesmo a frota toda?
- [ ] Cursor do `RetornaDados` é exclusivo (`> id`) ou inclusivo (`>= id`)?
- [ ] Existe teto de registros por chamada? Qual?
- [ ] Volume por ciclo de 15 min (define a frequência do schedule)
- [ ] Telemetria é 1 linha por veículo/dia?
- [ ] Mensagem literal do rate limit + tempo até liberar
- [ ] Valores aceitos em `TipoStatus`
- [ ] Formato de data aceito: `dd/MM/yyyy` ou `dd/MM/yyyy HH:mm:ss`?
- [ ] Quantos veículos sem última posição (regra do "sem sinal")
- [ ] `RetornaGrupos` tem agrupamento equivalente à filial?

### C) Mapa de unificação 3S ↔ Nuxeo

> Preencher a coluna Nuxeo com os nomes reais. **É a especificação literal do silver.**

| Silver (alvo) | Campo 3S | Campo Nuxeo | Transformação |
|---|---|---|---|
| `placa` | `Placa` | `plate` | `upper(trim())`, remover espaço/hífen — **tratar os 47 fora do padrão** |
| `id_equipamento` | `idEquipamento` | — | rastreador |
| `id_veiculo` | `idVeiculo` | — | veículo (chave distinta!) |
| `num_serie` | `NumSerie` | `serial`? | candidato a junção entre as duas fontes |
| `tipo_ativo` | `Tipo` | — | `Passeio`/`Caminhão`/`Van` |
| `chassi` | **`Chassis`** | — | ⚠️ não `Chassi` |
| `data_gps` | `Data` | `date` | `to_timestamp(…,'DD/MM/YYYY HH24:MI:SS')` |
| `velocidade` | `Velocidade` | `speed` | vírgula → ponto, `numeric` |
| `latitude`/`longitude` | `Latitude`/`Longitude` | `latitude`/`longitude` | vírgula → ponto |
| `tipo_evento` | ⬜ | `event` | mapear para taxonomia canônica |
| `fonte` | `'3S'` | `'NUXEO'` | literal |

**Taxonomia canônica de evento** — levantar os valores distintos dos dois lados:
```sql
-- Nuxeo (exige subir o Postgres)
SELECT DISTINCT evt->>'event' AS evento, count(*)
FROM bronze.nuxeo_posicao_eventos t, LATERAL jsonb_array_elements(t.eventos_json) evt
GROUP BY 1 ORDER BY 2 DESC;
```
Lado 3S: sai dos testes `4.3` (campo `Sensor`) e `4.4` (campo `Violacao`).

Hoje o relatório filtra `lower(nome_evento) LIKE '%excesso%' OR LIKE '%velocidade%'` — casamento de string sobre o rótulo da Nuxeo. Substituir por valores fixos: `EXCESSO_VELOCIDADE`, `CERCA_ENTRADA`, `CERCA_SAIDA`, `SENSOR_PANICO`, `SENSOR_IGNICAO`, …

---

## 5. Correções necessárias no DDL atual

`postgres/scripts/3s_raw_tables.sql`, tabela `bronze.tres_s_veiculos`:

| Problema | Correção |
|---|---|
| Falta `id_veiculo` | Adicionar — é chave distinta de `id_equipamento` |
| Falta `num_serie` | Adicionar |
| Falta `tipo` | Adicionar |
| `chassi` nunca preenchido | A API devolve `Chassis`, não `Chassi` |
| Sem chave natural | `UNIQUE (id_equipamento)` — hoje todo rerun duplica |
