# Postman — API 3S Tecnologia

Dois kits neste diretório, para duas APIs diferentes da 3S:

| Kit | API | Status |
|---|---|---|
| `3S-data_export.*` | SOAP (`data_export.asmx`) | **Em uso em produção** — é o que os workflows `3S - 10` a `13` consomem hoje |
| `3S-REST-*` | REST nova (`dataexportapi`, [swagger](https://3stecnologia.eti.br/dataexportapi/swagger/index.html)) | **Bloqueado** — a credencial `referencia.locadora919` ainda não tem permissão liberada pela 3S para esta API (testado em 04/08/2026: `3S.1041 - Usuário sem permissão de acesso ao webservice`). Assim que a 3S liberar, use este kit para confirmar o contrato antes de qualquer mudança nos workflows — ver seção própria mais abaixo. |

O restante deste documento (até a seção "Kit REST") é sobre o SOAP, que é o que está ativo agora.

---

## SOAP (`data_export.asmx`) — em uso em produção

Kit de levantamento da API 3S para a estrutura medalhão de telemetria.
As assinaturas foram extraídas do **WSDL ao vivo**, não do manual v2.8 (que está desatualizado — veja [`../docs/3s-api-contrato.md`](../docs/3s-api-contrato.md)).

```
3S-data_export.postman_collection.json   29 requests em 7 pastas
3S-dev.postman_environment.json          variáveis (SEM a senha)
```

## Como usar

**1. Importar.** No Postman: botão **Import** (canto superior esquerdo) → arraste os **dois** arquivos `.json` de uma vez.

**2. Selecionar o environment.** No dropdown do canto superior direito, escolha **`3S - Dev`**.
> É um environment separado de propósito. O seu `Token Login` (Bluefleet + Nuxeo) continua intacto — no Postman só um environment fica ativo por vez, e assim os nomes de variável ficam limpos (`{{base_url}}` em vez de `base_url_3stec`).

**3. Colar a senha.** Menu lateral → **Environments** → `3S - Dev` → linha `senha` → cole o valor na coluna **Current value** (não na Initial value).
> **Initial value** é o que viaja quando você exporta ou compartilha. **Current value** fica só na sua máquina. Por isso a senha vai só no Current — assim este arquivo pode ficar no git sem segredo.

**4. Abrir o Console.** `Ctrl+Alt+C` (ou View → Show Postman Console).
> **É aqui que sai o resultado do levantamento.** Cada request imprime os campos reais que a API devolveu, a quantidade de registros, o tempo e uma amostra. A aba "Body" mostra o XML cru; o Console mostra o contrato já mastigado.

**5. Rodar na ordem `00 → 06`,** aguardando **~7 segundos entre chamadas**.

## Por que esperar 7 segundos

O limite documentado é **10 chamadas por minuto**. Estourar devolve `Erro: Excesso de chamadas por minuto atingido` — **com HTTP 200**, escondido no corpo. A pasta `06` mede exatamente esse comportamento.

## Ordem de execução

| Pasta | O que faz | Pré-requisito |
|---|---|---|
| `00 - Conectividade & Credencial` | Valida rede e credencial | — |
| `01 - Cadastro` | **Rode a `1.1` primeiro** — ela preenche `id_equip_teste` e `placa_teste`, usados por quase todas as outras | 00 |
| `02 - Posições` | A `2.4` decide qual método o backfill vai usar | 1.1 |
| `03 - RetornaDados` | **Rode `3.1` antes da `3.3`** — a 3.1 preenche os cursores `wm_*` | 1.1 |
| `04 - Eventos & Cercas` | Alertas de velocidade, sensores, cercas | 1.1, 1.4 |
| `05 - Utilização & Saúde` | Três métodos sem documentação nenhuma | 1.1 |
| `06 - Limites & Erros` | Rate limit e casos de erro | — |

Requests com **"negativo"** no nome **devem falhar** — é o comportamento esperado, elas documentam as mensagens de erro. O guard da collection já sabe disso.

## Os três pontos de decisão

| # | Pergunta | Onde | Status |
|---|---|---|---|
| 1 | Qual credencial é a válida? | `0.2` | ✅ **Resolvido** — `referencia.locadora919` retorna `0` (válido) |
| 2 | `HistoricoPosicaoCompleto` traz `idPosicao`/`Placa`/`idEquipamento`? | `2.4` | ⬜ Pendente |
| 3 | O cursor do `RetornaDados` é confiável para watermark? | `3.3` (rodar 2× com o mesmo cursor) | ⬜ Pendente |

## O que fazer com os resultados

Vá preenchendo [`../docs/3s-api-contrato.md`](../docs/3s-api-contrato.md) conforme o Console for imprimindo. **É esse documento que destrava a modelagem silver/gold** — sem ele, definir as colunas do silver é chute.

## Duas coisas não óbvias da API

**Erro vem com HTTP 200.** A resposta de erro é `<string>Erro: [mensagem]</string>` com status 200. Um teste que só cheque `pm.response.to.have.status(200)` passa em cima de um erro. O script no nível da collection já valida isso em toda request.

**O XML de dados vem escapado.** Toda operação é declarada como `xsd:string` no WSDL, então o payload chega assim:
```xml
<ListaVeiculosResult>&lt;Veiculo&gt;&lt;tbVeiculo&gt;...</ListaVeiculosResult>
```
O guard desescapa e publica em `{{xml}}`, que é o que os testes de cada request consomem. Se for inspecionar na mão, lembre que a aba Body mostra a forma escapada.

## Rodar por linha de comando (opcional)

```bash
npm install -g newman

newman run 3S-data_export.postman_collection.json \
  -e 3S-dev.postman_environment.json \
  --env-var "senha=SUA_SENHA" \
  --delay-request 7000 \
  -r cli,json --reporter-json-export out/run.json
```
`--delay-request 7000` respeita o limite de 10/min.

---

## Kit REST (`dataexportapi`) — aguardando liberação da 3S

```
3S-REST-dataexportapi.postman_collection.json   15 requests em 6 pastas
3S-REST-dev.postman_environment.json            variáveis (SEM a senha)
```

Gerado a partir do `swagger.json` oficial (baixado em 04/08/2026 de `https://3stecnologia.eti.br/dataexportapi/swagger/v1/swagger.json`), não do manual — mesma disciplina do kit SOAP.

### O que muda desta API para a SOAP antiga

- **Tudo em JSON**, sem escape de XML.
- **Autenticação JWT**: `POST /ValidaLogin {usuario, senha}` → `{token, expiration}`. As demais chamadas usam `Authorization: Bearer <token>`. Na collection, isso é automático — o teste da `0.1` grava `{{token}}` e o Bearer Auth no nível da collection já aponta pra lá.
- **Erro confirmado por teste real** (não é o que o `swagger.json` documenta como schema): corpo em **texto puro** `"3S.xxxx - mensagem"`, `Content-Type: text/plain`, independente do endpoint. O guard da collection já usa esse formato.

### Como usar (quando a 3S liberar)

1. Importar os dois arquivos.
2. Selecionar o environment **`3S REST - Dev`**.
3. Colar a senha no **Current value** da variável `senha`.
4. Rodar **`0.1 - ValidaLogin` primeiro** — preenche `{{token}}`, usado por todo o resto.
5. Rodar as pastas `01 → 05` na ordem.

### As duas perguntas de contrato que travam o desenho dos workflows

| # | Pergunta | Onde testar | Por que importa |
|---|---|---|---|
| 1 | `idVeiculo=0` ainda significa "frota toda" (como `idEquipamento=0` significava no SOAP)? | `2.2` e `3.2` | Se não, a ingestão de posições/eventos vira **uma chamada por veículo** (~3.169) em vez de uma só — muda rate limit, tempo de execução e o desenho inteiro do `3S - 12`/`13`. |
| 2 | Qual o rate limit real desta API? | `5.3` (Collection Runner, delay 0) | O SOAP documentava 10/min; não há garantia de que valha aqui. |

Só depois dessas duas respondidas (mais duração do token e formato de data aceito em `dataInicio`/`dataFim`, também sinalizados nas notas das requests) faz sentido redesenhar `gen_n8n_3s.py` para esta API.
