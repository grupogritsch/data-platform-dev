# Padrões da estrutura medalhão

Decisões de arquitetura da ingestão e o raciocínio por trás delas.
Companheiro de [`3s-api-contrato.md`](3s-api-contrato.md) (o que a API devolve) — aqui está **como a gente guarda**.

---

## A pergunta que originou este documento

> "Eu deveria salvar todas as informações no banco, certo? Mas alguns métodos precisam de informações adicionais específicas. Como fazer isso?"

Duas respostas, e a segunda é a que a maioria erra.

### 1. Sim — o bronze salva tudo, inclusive o que você não usa hoje

O manual da 3S documenta 7 campos em `ListaVeiculos`. A API devolve **10**. Os três extras são `NumSerie`, `idVeiculo` e `Tipo`.

Se a ingestão tivesse sido escrita para "só o que o relatório precisa", esses três teriam sido descartados — e `idVeiculo` acabou sendo **uma chave que difere de `idEquipamento` em 3.168 dos 3.169 registros**. Um join errado esperando para acontecer.

Regra: **bronze guarda o que veio, não o que você acha que precisa.** Custo de disco é barato; recoletar 3.169 equipamentos a 10 req/min não é.

### 2. Os parâmetros da chamada também são dados

Essa é a parte que responde a segunda metade da pergunta.

A tentação é escrever a informação específica no workflow: uma data no Code node, uma lista de IDs num array. Foi o que aconteceu com o backfill atual — as janelas `01/02/2026` a `31/07/2026` estão **hardcoded dentro do JSON do workflow**. Consequência: não dá para saber o que já foi coletado, retomar de onde parou, nem reprocessar um período sem editar o workflow.

Um sênior trata os parâmetros como **estado no banco**, em coluna `JSONB`. Uma tabela serve os ~70 métodos da API, independente de cada um ter 2 ou 18 parâmetros.

```sql
bronze.tres_s_ingest_job (metodo, params JSONB, status, tentativas, agendado_para, ...)
```

```json
{"idEquipamento": "20260302084805", "DataInicio": "01/07/2026", "DataFim": "31/07/2026"}
```

O workflow deixa de conter conhecimento e passa a **executar** o que a tabela manda.

---

## Os três padrões de ingestão

A API 3S tem três formas distintas de ser chamada, e cada uma puxa parâmetro de um lugar diferente. Está codificado em `bronze.tres_s_metodo.padrao_ingestao`.

| Padrão | Parâmetros | De onde vêm | Métodos |
|---|---|---|---|
| **snapshot** | só credencial | nenhum estado | `ListaVeiculos`, `ListaUltimaPosicaoVeiculos`, `ListaCercaRota`, `RetornaGrupos` |
| **cursor** | 16 IDs | `bronze.tres_s_watermark` | `RetornaDados` |
| **fanout** | `idEquipamento` + janela | `bronze.tres_s_ingest_job` | `HistoricoPosicao*`, `HistoricoOcorrencia*`, `ListaSensores`, `RetornaUtilizacaoVeiculo`, `RetornaStatusComunicacao` |

### Por que isso não é over-engineering aqui

O limite é **10 chamadas por minuto** e a frota tem **3.169 equipamentos**.

```
Backfill ingênuo: 3.169 × 6 janelas = 19.014 chamadas ÷ 10/min ≈ 31,7 HORAS
```

Uma execução de 31 horas **vai** ser interrompida. Sem fila de jobs com status, recomeçar significa refazer tudo. Com ela, retoma de onde parou. O orçamento de chamadas é escasso, e isso torna a resumibilidade requisito, não luxo.

É também o argumento para o `RetornaDados`: com `idEquipamento=0` e cursores, **1 chamada por ciclo** traz posições, sensores, telemetria, alertas e cercas da frota inteira.

---

## Guardar o XML cru é a decisão mais importante do bronze

`bronze.tres_s_raw_response` grava toda chamada HTTP — método, parâmetros, status, duração e o **XML como veio**.

Parece redundante junto das tabelas tipadas. Não é:

**Reprocessar sem rechamar a API.** Se o parser tiver bug — e vai ter, veja o `Chassis` vs `Chassi` — você corrige e reparseia o XML guardado. Sem isso, corrigir um parser custa horas de recoleta contra um teto de 10 req/min.

**Auditoria.** "Por que esse veículo não aparece no relatório?" se resolve seguindo `id_raw_response` até a chamada exata e os parâmetros exatos que a produziram. Toda linha de dado do bronze carrega essa coluna.

**Contrato que muda sem aviso.** Quando a 3S adicionar um campo, ele já está no XML guardado, mesmo antes de existir coluna para ele.

> **Nunca gravar credencial em `params`.** As duas tabelas de controle têm `CHECK` que rejeita chaves `Usuario`/`Senha`/`password`. São tabelas auditáveis e exportáveis — senha ali vaza junto.

---

## Bronze usa tipos permissivos

O DDL antigo declarava `placa VARCHAR(20)`, `velocidade NUMERIC(6,2)`, `cep VARCHAR(20)`. Parece cuidadoso. Na prática é frágil: **um valor inesperado derruba a carga inteira**, e você perde os 3.168 registros bons junto com o ruim.

Os dados reais justificam a preocupação. Das 3.169 placas:

| | |
|---|---|
| Mercosul (`ANO 9C61`) | 3.119 |
| Formato antigo | 3 |
| **Contendo o CHASSI de 17 caracteres** | 23 |
| Serial de TAG, não veículo | 1 |
| Outros formatos (`SDQ 4F62 S`) | 23 |

No bronze tudo isso entra. O silver decide o que é placa válida — e sinaliza o resto em vez de descartar em silêncio.

> A validação `^[A-Z0-9]{7}$` que eu tinha proposto no plano original **rejeitaria 47 registros sem avisar**. Virou teste de qualidade que reporta, não filtro que descarta. Foram os dados reais que corrigiram o desenho.

## Bronze não normaliza

Nada de `upper()`, `trim()` ou remoção de hífen na ingestão. As placas vêm com espaço (`ANO 9C61`) e é assim que ficam guardadas.

Normalizar em bronze **apaga a evidência de que a origem está suja**. Depois não dá para responder "a 3S manda com espaço ou fomos nós que tiramos?". A normalização é regra de negócio, e regra de negócio mora no silver.

---

## Idempotência: chave natural em toda tabela

O defeito mais grave do bronze atual: **nenhuma tabela tem chave natural**. Todo rerun duplica tudo.

Toda tabela nova tem `UNIQUE` na chave da origem e carga via `ON CONFLICT`:

```sql
ON CONFLICT (id_equipamento) DO UPDATE SET ...
```

Verificado com dados reais: duas cargas seguidas de 3.169 registros → **3.169 linhas**, não 6.338.

## Carga parametrizada, não concatenação de string

Os Code nodes atuais montam o `INSERT` concatenando string, com `esc()` manual, em blocos de 500 linhas. É frágil e vulnerável a injeção.

O padrão adotado passa **um array JSON como parâmetro** e deixa o SQL expandir:

```sql
SELECT bronze.fn_carrega_veiculos($1::jsonb, $2::bigint);
```

```sql
INSERT INTO bronze.tres_s_veiculos (...)
SELECT r->>'idEquipamento', r->>'idVeiculo', ...
  FROM jsonb_array_elements(p_registros) AS r
ON CONFLICT (id_equipamento) DO UPDATE SET ...;
```

Uma instrução, sem escape manual, sem injeção. No n8n é o campo `options.queryReplacement` do nó Postgres.

## Invariantes moram no banco

O watermark **só anda para frente**. Retroceder reprocessaria dados já ingeridos.

Em vez de confiar que todo Code node lembre disso, a regra vive numa função:

```sql
bronze.fn_avanca_watermark('posicao', 5000)  -- 5000
bronze.fn_avanca_watermark('posicao', 99)    -- 5000 (ignora o retrocesso)
```

Corolário: **o watermark só avança depois do INSERT confirmar.** Avançar antes perde dados em silêncio quando a carga falha no meio — o pior tipo de bug, porque não gera erro.

---

## Estado atual

```
postgres/sql/
  00_schemas.sql                 bronze, silver, torre
  bronze/
    10_3s_controle.sql           metodo · watermark · ingest_job · raw_response · funcoes · view
    11_3s_veiculos.sql           ListaVeiculos (contrato confirmado)
```

Aplicar (idempotente, pode rodar quantas vezes quiser):
```bash
docker compose up -d postgres
for f in postgres/sql/00_schemas.sql postgres/sql/bronze/*.sql; do
  docker exec -i postgres psql -U admin -d dw -v ON_ERROR_STOP=1 < "$f"
done
```

Monitoramento: `SELECT * FROM bronze.vw_3s_ingest_status;`

### Verificado

- [x] Os 3 arquivos aplicam limpo e são idempotentes (rodados 2×)
- [x] 3.169 veículos reais carregados via `fn_carrega_veiculos`
- [x] Segunda carga idêntica → 3.169 linhas, sem duplicar
- [x] `fn_avanca_watermark` recusa retrocesso
- [x] 15 métodos catalogados, 10 domínios de watermark ativos
- [x] Procedência preenchida em 100% das linhas

### Próximas tabelas

Ficam **em branco de propósito**. As colunas de `tres_s_posicoes`, `tres_s_eventos` e `tres_s_telemetria_diaria` saem do contrato real, e o contrato só existe depois dos testes `2.4`, `3.3` e `3.4` no Postman. Inventar colunas antes disso foi exatamente o erro que produziu a coluna `chassi` que nunca foi preenchida.

Enquanto isso, `tres_s_raw_response` já pode receber coleta: **dá para começar a acumular XML cru hoje e modelar as colunas tipadas depois**, reparseando o que foi guardado. Num backfill de 31 horas, começar a coletar cedo vale mais do que começar com o schema perfeito.
