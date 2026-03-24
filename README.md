# Data Platform — Ambiente de Desenvolvimento

Ambiente local com PostgreSQL, pgAdmin e N8N.

## Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

## Setup

```bash
cp .env.example .env
```

Edite o `.env` com as credenciais desejadas e suba os containers:

```bash
docker compose up -d
```

## Serviços

| Serviço   | URL                    |
|-----------|------------------------|
| pgAdmin   | http://localhost:5050  |
| N8N       | http://localhost:5678  |
| PostgreSQL | `localhost:5433`      |

## Parar os containers

```bash
docker compose down
```

Para remover também os volumes (apaga todos os dados):

```bash
docker compose down -v
```
