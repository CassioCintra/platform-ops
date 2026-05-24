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
│   ├── renovate.json                    # Renovate config for automated dependency updates
│   └── workflows/
│       ├── ci-infra.yml                 # Validates docker-compose on every push
│       ├── dependency-update.yml        # Runs Renovate every Monday
│       ├── stale.yml                    # Closes stale issues and PRs every Monday
│       ├── reusable-cd.yml              # Reusable: build, tag and push image
│       ├── reusable-quality.yml         # Reusable: lint, tests, coverage, Sonar
│       ├── reusable-security.yml        # Reusable: secrets, vulnerabilities, licenses
│       ├── reusable-db-migration.yml    # Reusable: validate DB migrations
│       └── reusable-notify.yml          # Reusable: Slack and Teams notifications
├── docs/
│   └── how-to-use-reusable-workflows.md # Usage guide and pipeline.yml example
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

> **Warning:** The credentials below are for local development only.
> Never use these users, passwords, or client secrets in staging or production environments.
> In non-local environments, provision users and secrets through a secrets manager.

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

## CI/CD pipelines

| Workflow                    | Trigger             | What it does                                          |
|-----------------------------|---------------------|-------------------------------------------------------|
| `ci-infra.yml`              | push / pull_request | Validates docker-compose syntax and healthchecks      |
| `stale.yml`                 | Every Monday 09h    | Marks and closes stale issues and PRs                 |
| `dependency-update.yml`     | Every Monday 08h    | Opens PRs via Renovate for outdated actions and images |
| `reusable-quality.yml`      | called by services  | Lint, tests, coverage threshold, SonarQube Cloud      |
| `reusable-security.yml`     | called by services  | Gitleaks, Trivy (fs + image), license compliance      |
| `reusable-db-migration.yml` | called by services  | Flyway/Liquibase validation against ephemeral Postgres |
| `reusable-cd.yml`           | called by services  | Semver tag, pom.xml bump, Docker image build and push |
| `reusable-notify.yml`       | called by services  | Slack and/or Teams pipeline result notification        |

See `docs/how-to-use-reusable-workflows.md` for the full usage guide and a `pipeline.yml` example.

## Adding a new service

1. Add the service in `docker-compose.yml` with `profiles: [services]`
2. Add its environment variables to `.env.example`
3. Update this README with the port
4. Create a `pipeline.yml` in the service repo following the guide in `docs/`

## Architecture decisions

See the `docs/` folder for ADRs (Architecture Decision Records).
