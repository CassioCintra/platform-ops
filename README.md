# order-platform-infra

Central infrastructure repository for the **Order Platform**. Centralizes the shared Docker Compose stack, environment configuration, and CI/CD pipelines used across all microservices.

## Structure

```
order-platform-infra/
├── docker/
│   ├── postgres/
│   │   └── init/                        # SQL scripts run on first startup
│   │       └── 01-databases.sql
│   ├── kafka/                           # Extra Kafka config (if needed)
│   └── keycloak/
│       └── realm/                       # Realm auto-imported on start-dev
│           └── order-platform-realm.json
├── .github/
│   └── workflows/
│       ├── ci-infra.yml                 # Validates docker-compose on every push
│       └── cd-services.yml              # Builds and pushes images (manual trigger)
├── docs/                                # Architecture Decision Records (ADRs)
├── docker-compose.yml                   # Full stack definition
├── .env.example                         # Required variables — copy to .env
└── README.md
```

## Prerequisites

- Docker >= 24
- Docker Compose >= 2.20
- Git

## Getting started

```bash
# 1. Clone the repository
git clone <url> order-platform-infra
cd order-platform-infra

# 2. Set up environment variables
cp .env.example .env
# edit .env with your local passwords

# 3. Start base infra only (postgres, kafka, keycloak)
docker compose up -d postgres kafka keycloak

# 4. Start everything including application services
docker compose --profile services up -d
```

## Services and ports

| Service           | External port | Notes                                       |
|-------------------|---------------|---------------------------------------------|
| PostgreSQL        | 5432          | —                                           |
| Kafka (external)  | 9094          | Host access. Containers communicate on 9092 |
| Keycloak          | 8080          | Admin credentials from .env                 |
| order-service     | 8081          | Requires `--profile services`               |
| dashboard-service | 8082          | Requires `--profile services`               |

## Development users (Keycloak)

| Username    | Password   | Roles                  |
|-------------|------------|------------------------|
| `dev-admin` | `admin123` | admin, beta-user, user |
| `dev-beta`  | `beta123`  | beta-user, user        |
| `dev-user`  | `user123`  | user                   |

## Compose profiles

Profiles separate infrastructure from application services:

- **no profile** — starts only `postgres`, `kafka`, and `keycloak`
- **`--profile services`** — also starts `order-service` and `dashboard-service`

This allows each developer to run application services locally via their IDE while using only the Compose infra.

## CI/CD

| Workflow          | Trigger             | What it does                                    |
|-------------------|---------------------|-------------------------------------------------|
| `ci-infra.yml`    | push / pull_request | Validates syntax and healthchecks docker-compose |
| `cd-services.yml` | manual dispatch     | Builds and pushes images to GitHub Registry     |

## Adding a new service

1. Add the service in `docker-compose.yml` with `profiles: [services]`
2. Add its environment variables to `.env.example`
3. Update this README with the port

## Architecture decisions

See the `docs/` folder for ADRs (Architecture Decision Records).
