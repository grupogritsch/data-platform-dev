# Torre de Controle — Relatórios por e-mail (telemetria, combustível, pedágio)

> Documento de handoff escrito em 27/08/2026. Cobre os workflows n8n que
> mandam relatório por e-mail pros gestores de filial e pra diretoria —
> telemetria, combustível e pedágio. **Vários desses itens foram construídos
> em múltiplas sessões de IA rodando em paralelo no mesmo dia** (24–27/08).
> Cada seção diz explicitamente o que foi verificado/testado e o que só foi
> encontrado pronto no repositório sem checagem independente — confira antes
> de assumir que algo "simplesmente funciona".

## 1. Arquitetura compartilhada

Todo relatório desta família segue o mesmo esqueleto de nodes no n8n:

```
Trigger (manual + cron)
  → ⚙️ Configurações (Set: modo_producao, email_teste, top_N, datas custom)
  → Calcular Período (Code: calcula janela de datas)
  → Buscar Dados (Postgres: 1 query grande, 1 linha por filial, campos
    agregados em JSON — resumo por tipo, frota, postos/praças, etc.)
  → Gerar HTML por Filial (Code, runOnceForEachItem — 1 e-mail por filial)
  → Consolidar Geral / Diretoria (Code, runOnceForAllItems — 1 e-mail
    agregando a empresa toda)
  → Enviar Email + CSV por Filial (emailSend)
  → Enviar Consolidado (Diretoria) (emailSend)
```

**`modo_producao` (toggle no node "⚙️ Configurações"):**
- `false` (padrão/seguro): todo e-mail vai só pro `email_teste`, CC fica vazio.
  Rodar assim nunca vaza e-mail de teste pra gente real.
- `true`: `toEmail` vira o e-mail real da filial (`torre.email_gritsch_filiais.email_destino`),
  CC vira a lista real combinada.
- **Pegadinha real**: reimportar o workflow no n8n sobrescreve esse valor pelo
  que está salvo no `.json` exportado (hoje sempre `false`, por segurança). Depois de
  reimportar, sempre conferir/reativar o `modo_producao` na mão dentro do n8n.

**Lógica de destinatário/CC** (idêntica nos 3 relatórios):
- `toEmail` (por filial) = `torre.email_gritsch_filiais.email_destino` (join
  por `filial_operacional` = garagem de referência da filial)
- `ccEmail` (por filial) = merge deduplicado de `email_cc` + `cc_regional`
  (mesma tabela) + `cc_global` (`torre.email_gritsch_config`, chave `cc_global`)
- Consolidado: `toEmail`/`ccEmail` vêm de `torre.email_gritsch_config`,
  chaves `consolidado_destinatarios` / `consolidado_cc`
- Todo lookup de config tem fallback hardcoded (`torredecontrole@gritsch.com.br,
  flavio@gritsch.com.br,fabio.pepplow@gritsch.com.br`) caso a chave não
  exista na tabela — ver bug #2 abaixo pra saber por que isso importa.

**Identidade visual**: cabeçalho com a marca do parceiro (TruckPag: verde
`#00B140`, fonte Manrope/IBM Plex Sans) — a logo entra como **anexo inline
via CID** (`<img src="cid:logo_truckpag">`, com o binário anexado em
`options.attachments`), não como URL externa — ver bug #1. Rodapé sempre no
padrão Gritsch (`#213035`, logo branca), igual em todo relatório da família.

## 2. Status por relatório

### Telemetria (rastreadores 3S/Nuxeo)
- **Em produção desde 24/08/2026.**
- Existem **dois arquivos** no repo: `Torre de Controle - Alertas
  Telemetria.json` e `Torre de Controle - Alertas Telemetria SEMANAL v1.json`
  (mesmo timestamp, 24/08 09:07). **Não verificado qual dos dois é o que
  está de fato ativo/importado no n8n** — confira lá antes de mexer.
- Cron diário 07:30 seg-sex (não tem gate de `modo_producao`, roda sempre
  "de verdade" — diferente do padrão dos outros dois relatórios).

### Combustível (dados TruckPag)
- **Semanal**: `Torre de Controle - Alertas Combustivel e Ociosidade
  Semanal.json`. Em produção desde 24/08/2026, cron terça 07:00. Traz KPIs,
  Top 5 maiores gastos, combustível por tipo, custo por grupo de veículo vs.
  referência da frota, postos utilizados (Top 8), CSV em anexo (frota,
  postos, transações).
- **Diário**: `Torre de Controle - Alertas Combustivel Diario.json`. Cron
  seg-sex 08:00. KPIs do dia + toda placa/todo posto que abasteceu (sem
  corte de Top N — volume de 1 dia é pequeno). Sem CSV, sem comparativo por
  grupo de veículo (isso ficou exclusivo do semanal). **Testado com 2 dias
  de dado real em produção em 27/08** — achou e corrigiu 2 bugs reais (ver
  seção 3). Precisa reimportar de novo depois do último fix (janela do LAG).
- Existe também um arquivo antigo `Torre de Controle - Relatorio Semanal
  Combustivel por Filial.json` (10/08/2026) — parece ser uma versão anterior
  /substituída. Não apaguei, mas provavelmente pode ser arquivado.

### Pedágio (dados TruckPag)
- **Semanal**: `Torre de Controle - Alertas Pedagio Semanal.json`, construído
  24/08 16:40 (sessão em paralelo, não fui eu). Cron terça 08:00 (1h depois
  do combustível semanal, sem colisão). Estrutura idêntica ao combustível
  semanal, já nasceu com os fixes de CC/options e do CROSS JOIN aplicados.
  **`modo_producao: false`, nunca rodado em produção ainda — não testado com
  dado real.** Antes de confiar nele: rodar uma vez, conferir números e CC,
  só depois virar produção.
- **Diário**: não existe. Era a próxima tarefa natural (mesmo padrão do
  combustível diário).

## 3. Bugs reais encontrados e corrigidos nesta rodada (24–27/08/2026)

Guardar essa lista — são armadilhas do n8n que provavelmente vão se repetir
em qualquer relatório novo que usar esse mesmo padrão de nodes.

1. **`ccEmail` do node emailSend (v2.1) tem que estar dentro de `options`,
   nunca no nível superior de `parameters`.** Fora dali o n8n ignora em
   silêncio — roda sem erro nenhum e simplesmente não manda cópia pra
   ninguém. Isso ficou quebrado no combustível (e possivelmente no
   telemetria também — não confirmado) até ser encontrado em 24/08.
   Confirmado na fonte oficial do n8n (`EmailSend/v2/send.operation.ts`).

2. **`CROSS JOIN` numa subquery de config pode zerar o relatório inteiro.**
   Padrão `CROSS JOIN (SELECT valor FROM torre.email_gritsch_config WHERE
   chave = 'x' LIMIT 1)` — se a chave não existir na tabela, a subquery
   volta zero linhas e o `CROSS JOIN` (não é `LEFT JOIN`) apaga TODAS as
   linhas do resultado, não só o CC. Fix: envolver com `COALESCE` garantindo
   sempre 1 linha, com fallback hardcoded.

3. **`LAG()` pra calcular km rodado precisa enxergar o histórico completo do
   veículo, nunca só a janela do relatório.** O combustível diário original
   filtrava a base já na CTE inicial (`AND c.data >= dia_anterior`) achando
   que aliviava a query — na prática quebrou o `LAG(hodometro)`: ele só acha
   o abastecimento anterior de um veículo se esse abastecimento também
   estiver dentro da janela carregada. Resultado: custo/km em N/D pra
   maioria da frota (só sobrava quem tinha abastecido em 2 dias seguidos).
   Fix: tirar o filtro de data da CTE base — o corte pela janela do
   relatório só entra nos CTEs de agregação final (KPIs/frota/postos), nunca
   antes do `LAG`. Confirmado com dado real de produção (2 dias rodando).

4. **Code node `runOnceForEachItem` precisa `return { json, binary }` como
   objeto solto, nunca `[{ json, binary }]`** — array-wrap nesse modo
   quebra com "A 'json' property isn't an object".

## 4. Pendências / próximos passos

Em ordem de prioridade:

1. **Reimportar o combustível diário** (fix do LAG, feito em 27/08) e
   confirmar que os próximos envios não vêm mais com custo/km em N/D pra
   maioria da frota.
2. **Testar o pedágio semanal com dado real** — nunca rodou em produção.
   Rodar com `modo_producao: false` primeiro (vai pro e-mail de teste),
   conferir números batendo com a fonte, só depois virar `true`.
3. **Construir o pedágio diário**, espelhando a mesma decisão de escopo do
   combustível diário (KPIs + placas/praças do dia, sem CSV, sem
   comparativo por grupo de veículo).
4. **Confirmar qual dos dois arquivos de telemetria é o ativo no n8n** e
   arquivar/remover o outro pra não confundir quem mexer depois.
5. **Conferir se o telemetria tem o mesmo bug #1 (`ccEmail` fora de
   `options`)** — não foi corrigido nele nesta rodada, só no combustível e
   pedágio.
6. Cron atual (evitar colisão):
   - Telemetria diário: 07:30 seg-sex
   - Combustível diário: 08:00 seg-sex
   - Combustível semanal: terça 07:00
   - Pedágio semanal: terça 08:00
   - Pedágio diário (a construir): sugestão 08:30 seg-sex

## 5. Onde estão as coisas

- Workflows exportados: `Workflows - n8n/*.json` — são exports manuais, o
  estado real vive no volume Docker do n8n. Não existe sync automático:
  editar o `.json` no repo não muda o n8n sozinho, precisa reimportar; e
  mudar algo direto no n8n (como o `modo_producao`) não volta pro `.json`
  sozinho — por isso o `.json` no repo sempre mostra `modo_producao: false`.
- Tabelas de config: `torre.email_gritsch_filiais` (destino/CC por filial),
  `torre.email_gritsch_config` (chaves `cc_global`, `consolidado_destinatarios`,
  `consolidado_cc`).
- Fonte dos dados: TruckPag → `torre.gold_truckpag_combustivel` (combustível
  e pedágio), Bluefleet → `torre.gold_dim_veiculo`/`gold_dim_filial` (mestre
  de veículo/filial — sempre a fonte de verdade pra filial, nunca a TruckPag).
- Preço de referência ANP: `torre.raw_anp_combustiveis`, só posto bandeirado,
  mesma semana da coleta.
- Fontes das queries/templates JS dos relatórios (para edição futura, fora
  do próprio `.json` exportado): `Workflows - n8n/_source/` — ver README
  ali dentro.
