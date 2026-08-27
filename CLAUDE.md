# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Local data platform for **Gritsch** (a fleet/logistics operator): PostgreSQL + n8n (ETL/orchestration) + pgAdmin, built around a medallion architecture (bronze → silver → gold/`torre`) that ingests vehicle telemetry (3S, Nuxeo, Omnilink), fuel/toll transactions (TruckPag), freight/cargo data (ESL), and fleet master data (Bluefleet), and serves KPIs to a "Torre de Controle" (Control Tower) BI for the diretoria (executive board), consumed via Looker Studio.

## Commands

**Start/stop the stack:**
```bash
cp .env.example .env          # first-time setup, then fill in credentials
docker compose up -d           # postgres (5433), pgadmin (5050), n8n (5678)
docker compose down            # stop
docker compose down -v         # stop and wipe volumes (destroys all data)
```

**Apply/evolve SQL schema** (NOT auto-applied after first init — `postgres/scripts/` only runs once against an empty volume via `docker-entrypoint-initdb.d`; all schema evolution after that goes through `postgres/sql/`, applied manually):
```bash
docker exec -i postgres psql -U admin -d dw -v ON_ERROR_STOP=1 < postgres/sql/00_schemas.sql
for f in postgres/sql/bronze/*.sql; do
  docker exec -i postgres psql -U admin -d dw -v ON_ERROR_STOP=1 < "$f"
done
# Gold layer (all 4 domains + executive matrix, in dependency order):
docker exec -i postgres psql -U admin -d dw < postgres/sql/gold/00_setup_gold_bi_completo.sql
```
All SQL in `postgres/sql/` is idempotent (`CREATE OR REPLACE`, `CREATE IF NOT EXISTS`, `ON CONFLICT`) — safe to rerun.

**Query the DW directly:**
```bash
PGPASSWORD=admin123 psql -h localhost -p 5433 -U admin -d dw -c "..."
```

**Python ingestion/backfill scripts** (`scripts/`, no virtualenv/requirements.txt — deps installed globally: `psycopg2`, `python-dotenv`, `pandas`, `weasyprint`, `PyMuPDF`/`fitz`):
```bash
python3 scripts/ingest_3s_telemetria.py
python3 scripts/backfill_3s_telemetria.py
```
Scripts load `.env` from the repo root and connect to Postgres at `192.168.0.37:5433/dw` (the host's LAN IP, not `localhost` — these run outside Docker's network, e.g. as cron jobs on the host).

**n8n**: workflows live as exported JSON under `Workflows - n8n/` and `Gestao-rastreadores/` conventions — imported/edited via the n8n UI at `localhost:5678`, not edited as text. Naming is a poor-man's medallion label: `3S -`, `NUXEO -`, `OMNILINK -`, `TRUCKPAG -` = bronze ingestion; `SILVER -` = silver transforms; `GOLD -` = gold dimensional/MV builds; `Torre de Controle -` = alerting/reporting consumers.

## Architecture

### Medallion layers (Postgres schemas)
- **`bronze`** — raw, source-faithful. Permissive types (`TEXT`/`JSONB`), no business rules, ingestion must never fail on unexpected data. Stores the *parameters of the API call* as state (`JSONB`), not hardcoded in workflows — this is what makes long-running backfills resumable. Every load table has idempotency via a natural-key `UNIQUE` constraint + `ON CONFLICT`. Raw XML/JSON API responses are kept in full (`bronze.tres_s_raw_response` etc.) so a parser bug can be fixed by reparsing stored data instead of re-hitting a rate-limited API.
- **`silver`** — typed, deduplicated, unified across sources (3S + Nuxeo). Business-rule normalization (case, trimming, plate formatting) happens here, never in bronze — bronze must preserve evidence of dirty source data. Also holds the **ESL** freight/logistics tables (`esl_manifestos`, `esl_fretes`, `esl_atores`, etc. — trip manifests, cargo weight/volume, freight revenue) and `dim_veiculo`.
- **`torre`** ("tower") — this is the **gold** layer, by historical naming convention (predates the bronze/silver split; n8n `GOLD -` workflows and the `postgres/sql/gold/` SQL both write here). Objects consumed by BI/Looker Studio.

Full rationale for these conventions (bronze permissiveness, raw-response retention, watermark invariants, params-as-state) is written up in `docs/medalhao-padroes.md` — read it before changing ingestion design, not just this file.

### Gold layer (`torre` schema) — 4 domains + executive rollup
Built via `postgres/sql/gold/4{1..5}_gold_*.sql`, run in order by `00_setup_gold_bi_completo.sql`:
1. **Abastecimento** (fuel) — `41_gold_abastecimento.sql`
2. **Pedágio** (toll) — `42_gold_pedagio.sql`
3. **Telemetria/Rastreadores** — `43_gold_telemetria_rastreador.sql`
4. **Manutenção/Frota** — `44_gold_manutencao_frota.sql`
5. **Matriz 360° Diretoria** (`45_gold_diretoria_reuniao_filiais.sql`) — rolls up all 4 domains per filial/month into `torre.vw_bi_diretoria_reuniao_filial_360` for the executive Looker Studio dashboard.

Naming convention inside `torre`: `gold_dim_*` (dimensions), `gold_hist_*` (SCD Type 2 history), `gold_mv_*` (materialized views, refreshed by cron via n8n), `gold_v_*` / `vw_bi_*` (plain views). An older set of workflows (`GOLD - 1` through `GOLD - 28` in `Workflows - n8n/`) built the same layer incrementally via n8n before this consolidated into versioned SQL files — the SQL files in `postgres/sql/gold/` are the current source of truth; check `git log` on that directory before trusting the n8n JSON exports as current.

**Data source hierarchy of trust** (important when joining):
- **Bluefleet** (`torre.gold_dim_veiculo`, synced daily via SCD Type 2 into `torre.gold_hist_veiculo`) is the master for vehicle identity: plate, model, branch (`filial_operacional`), status. Always join fuel/toll/telemetry data *to* Bluefleet, not the other way — other systems (TruckPag, trackers) are frequently stale about which branch owns a vehicle.
- **TruckPag** (`torre.integration_truckpag_transacoes`) — fuel and toll transactions. `transacao_estornada` is TEXT not boolean (valid "reversed" = `NOT NULL AND NOT IN ('0','')`); reversals carry negated `valor`/`litragem`.
- **ESL** (`silver.esl_manifestos`, `silver.esl_fretes`) — freight/cargo: trip weight (`manifesto_peso`), volumes, freight revenue (`manifesto_total_fretes`), by `manifesto_veiculo_placa`. Useful for normalizing fuel efficiency against actual cargo load (a "bad" km/L can be fully explained by a heavy load) — join on normalized plate (`UPPER(REPLACE(REPLACE(placa,'-',''),' ',''))`, since plate formatting is inconsistent across source systems).
- **Trackers** (3S / Nuxeo / Omnilink) — telemetry only, least reliable of the three; treat as a secondary signal, not master data.

Vehicle grouping (`grupo_veiculo`, from `torre.gold_classificar_veiculo()`) is an operational taxonomy specific to this fleet, not a spec sheet: `Bitruck` / `Truck` / `Toco` / `3/4` = trucks by axle count; `Pesado` = large vans/furgões (Sprinter, Master, Ducato — NOT heavy trucks despite the name); `Médio` = pickups/mid vans (Strada, Saveiro, S10, Hilux); `Leve` = passenger cars. Don't "fix" this naming — it's the standard the diretoria already uses.

### 3S ingestion patterns (`docs/3s-api-contrato.md`, `docs/estrategia-coleta.md`)
The 3S SOAP API (`data_export.asmx`) has three distinct calling conventions, encoded in `bronze.tres_s_metodo.padrao_ingestao`:
- **snapshot** — credential only, no state (`ListaVeiculos`, `ListaUltimaPosicaoVeiculos`)
- **cursor** — driven by `bronze.tres_s_watermark`, monotonic-only advance (never regresses, even on out-of-order writes) — `RetornaDados`
- **fanout** — per-equipment + time-window jobs queued in `bronze.tres_s_ingest_job`, needed because the API is rate-limited to **10 calls/minute** against ~3,169 pieces of equipment, making resumability a hard requirement, not an optimization.

Postman collections for both the legacy SOAP API (in production) and the newer REST API (blocked pending 3S permissions) are under `postman/` — read `postman/README.md` before touching 3S integration; it documents which endpoints are live.

### Docker network vs host network
Inside `docker-compose.yml`, n8n talks to Postgres as `postgres:5432` (Docker network) using `${POSTGRES_USER}`/`${POSTGRES_PASSWORD}`. From the host (Python scripts, `psql` from a terminal, pgAdmin), it's `localhost:5433` or the LAN IP `192.168.0.37:5433`. The 3S webservice credentials (`TRES_S_USUARIO`/`TRES_S_SENHA`) are **not** read via n8n env vars in production — see the long comment block in `docker-compose.yml` explaining two failed approaches (env var access blocked in prod n8n; native credential injected a header 3S's endpoint rejected) — the working approach is hardcoded literals pasted into each workflow's "Monta XML SOAP" Code node after import, deliberately not versioned in git.

## Working conventions specific to this repo

- **Never write/CREATE/ALTER/DROP against the DW, and never `git commit`/push, unless the user explicitly asks in that message.** This repo is frequently used in a "consult only" mode where the user runs all SQL themselves (via DBeaver/psql) and reports results back — default to producing read-only diagnostic queries and explaining findings rather than executing changes.
- Comments pasted into a query by the user sometimes break on copy/paste into their SQL client — avoid inline `--` comments inside multi-line SQL you hand back for the user to run; keep explanation in prose outside the code block.
- Fuel/toll/telemetry analysis conventions the user has established: always compare "banana com banana" (group-relative, never absolute, e.g. compare a Bitruck's km/L only against other Bitrucks); check ESL cargo weight before calling a vehicle inefficient (heavy loads legitimately lower km/L); prefer "% volume in negotiated/network posto" over raw "number of distinct postos" when auditing fuel purchase dispersion by branch, since some regions (e.g. POA/Rio Grande do Sul) have a single negotiated network (Rede Sim) spanning many CNPJs at one contracted price.
