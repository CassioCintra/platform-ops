# How to use the reusable workflows

Each microservice repository calls the workflows defined here via `workflow_call`.
The pipelines run in the microservice repo's context, but the logic lives centrally in this repo.

---

## Notification secrets — centralized in this repo

Webhook URLs for Discord, Slack, and Teams are stored **once** in this repository
under the `notifications` environment. Microservice repos do **not** need to configure
any notification secrets — they only need to enable the desired channel via input.

### Where to configure

**This repo → Settings → Environments → New environment → name: `notifications`**

Then add the following secrets and variables to that environment:

| Name                  | Type     | Description                      |
|-----------------------|----------|----------------------------------|
| `DISCORD_WEBHOOK_URL` | Variable | Discord channel webhook URL      |
| `SLACK_WEBHOOK_URL`   | Variable | Slack incoming webhook URL       |
| `TEAMS_WEBHOOK_URL`   | Variable | Microsoft Teams webhook URL      |

> All three webhook URLs use **Variables** � they are not authentication credentials and variables are easier to inspect when debugging.

---

## Required secrets (per microservice repo)

| Secret        | Where to set                      | Description                                             |
|---------------|-----------------------------------|---------------------------------------------------------|
| `GHCR_TOKEN`  | Repository → Settings → Secrets  | GitHub token with `packages:write` scope                |
| `SONAR_TOKEN` | Repository → Settings → Secrets  | SonarQube Cloud token (optional — quality skips if absent) |
| `RENOVATE_TOKEN` | This repo → Settings → Secrets | PAT with `repo` scope — required for Renovate PRs      |

---

## Pipeline flow on merge to main

```
merge to main
     │
     ├─▶ quality (reusable-quality.yml)
     │       ├── Dockerfile lint (hadolint)
     │       ├── Unit and integration tests
     │       ├── Coverage threshold check (JaCoCo) <- fails PR if below minimum
     │       └── Static analysis (SonarQube Cloud)
     │
     ├─▶ security — source (reusable-security.yml)
     │       ├── Secret detection (Gitleaks)
     │       ├── Dependency vulnerability scan (Trivy fs)
     │       └── License compliance (Maven)
     │
     ├─▶ db-migration (reusable-db-migration.yml)  <- optional
     │       ├── Apply migrations against ephemeral PostgreSQL
     │       ├── Re-run migrations (idempotency check)
     │       └── Validate migration integrity (flyway:validate)
     │
     ├─▶ cd (reusable-cd.yml)           <- runs only after quality and security pass
     │       ├── Generate semver tag from conventional commits
     │       ├── Update pom.xml version and commit [skip ci]
     │       ├── Build application artifact (Maven)
     │       ├── Build and push Docker image to GHCR (v1.x.x + latest + sha-)
     │       └── Create GitHub Release with changelog
     │
     ├─▶ security — image (reusable-security.yml)  <- runs after cd, scans published image
     │       └── Image vulnerability scan (Trivy image)
     │
     └─▶ notify (reusable-notify.yml)   <- runs after image scan, reports result
             ├── Discord  (webhook from notifications environment — no secret needed in caller)
             ├── Slack    (webhook from notifications environment — no secret needed in caller)
             └── Teams    (webhook from notifications environment — no secret needed in caller)
```

---

## Automatic dependency updates (Renovate)

The `dependency-update.yml` workflow runs every Monday at 08:00 UTC via Renovate.
It opens PRs automatically when newer versions are available for:

| Manager         | What it updates                                        | Auto-merge  |
|-----------------|--------------------------------------------------------|-------------|
| `github-actions`| All `uses:` references in workflow files               | Patch only  |
| `docker-compose`| Image tags in `docker-compose.yml`                     | Never       |
| `maven`         | Dependencies and plugins in `pom.xml`                  | Patch only  |

Security-sensitive actions (`trivy-action`, `gitleaks-action`, `sonarqube-scan-action`)
are never auto-merged — they always require manual review regardless of update type.

---

## Important: image scan must run after cd

The `image-scan` job in `reusable-security.yml` requires the image to already exist in GHCR.
Call the security workflow **twice** in `pipeline.yml`:

- Before cd: source scan only (Gitleaks + Trivy fs + license)
- After cd: pass `image-tag: ${{ needs.cd.outputs.image-tag }}` and `needs: [cd]`

---

## Important: bot push access to main

The cd workflow commits the updated `pom.xml` back to `main` using `github-actions[bot]`.
If branch protection is enabled, you must allow this actor to bypass the restriction:

**Settings -> Branches -> main branch rule -> Allow specified actors to bypass -> add `github-actions[bot]`**

---

## Coverage threshold

The `coverage-minimum` input sets the minimum line coverage percentage (default: `90`).

### Required Maven configuration

```xml
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <version>0.8.11</version>
  <executions>
    <execution>
      <id>prepare-agent</id>
      <goals><goal>prepare-agent</goal></goals>
    </execution>
    <execution>
      <id>report</id>
      <phase>verify</phase>
      <goals><goal>report</goal></goals>
    </execution>
  </executions>
</plugin>
```

---

## License compliance

```xml
<plugin>
  <groupId>com.mycila</groupId>
  <artifactId>license-maven-plugin</artifactId>
  <version>4.3</version>
  <configuration>
    <licenseSets>
      <licenseSet>
        <header>com/mycila/maven/plugin/license/templates/APACHE-2.txt</header>
      </licenseSet>
    </licenseSets>
  </configuration>
</plugin>
```

---

## Conventional commits -> version bump

| Commit prefix                  | Version bump | Example                              |
|--------------------------------|--------------|--------------------------------------|
| `fix:`                         | patch        | `fix: correct order status mapping`  |
| `feat:`                        | minor        | `feat: add rollout by user role`     |
| `feat!:` or `BREAKING CHANGE:` | major        | `feat!: redesign order schema`       |

---

## Autonomous workflows (this repo only)

| Workflow                 | Schedule          | Description                                                    |
|--------------------------|-------------------|----------------------------------------------------------------|
| `stale.yml`              | Every Monday 09h  | Marks and closes stale issues and PRs                          |
| `dependency-update.yml`  | Every Monday 08h  | Opens PRs via Renovate for outdated actions, images, Maven deps |
| `ci-infra.yml`           | push / PR to main | Validates docker-compose syntax and healthchecks               |

---

## Example: `.github/workflows/pipeline.yml` in a microservice repo

```yaml
name: Pipeline

on:
  push:
    branches: [main]

jobs:
  quality:
    name: Quality
    uses: <your-org>/order-platform-infra/.github/workflows/reusable-quality.yml@main
    with:
      java-version: '21'
      enable-tests: true
      coverage-minimum: 90
      enable-sonar: true  # set to false if SONAR_TOKEN is not configured
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}

  security-source:
    name: Security — source
    uses: <your-org>/order-platform-infra/.github/workflows/reusable-security.yml@main
    with:
      service-name: order-service
      fail-on-severity: HIGH
    secrets:
      GHCR_TOKEN: ${{ secrets.GHCR_TOKEN }}

  db-migration:
    name: DB migration
    uses: <your-org>/order-platform-infra/.github/workflows/reusable-db-migration.yml@main
    with:
      migration-tool: flyway
      postgres-version: '16'

  cd:
    name: Build and publish
    needs: [quality, security-source, db-migration]
    uses: <your-org>/order-platform-infra/.github/workflows/reusable-cd.yml@main
    with:
      service-name: order-service
      java-version: '21'
    secrets:
      GHCR_TOKEN: ${{ secrets.GHCR_TOKEN }}

  security-image:
    name: Security — image
    needs: [cd]
    uses: <your-org>/order-platform-infra/.github/workflows/reusable-security.yml@main
    with:
      service-name: order-service
      image-tag: ${{ needs.cd.outputs.image-tag }}
      fail-on-severity: HIGH
    secrets:
      GHCR_TOKEN: ${{ secrets.GHCR_TOKEN }}

  notify:
    name: Notify
    needs: [quality, security-source, db-migration, cd, security-image]
    if: always()
    uses: <your-org>/order-platform-infra/.github/workflows/reusable-notify.yml@main
    with:
      service-name: order-service
      image-tag: ${{ needs.cd.outputs.image-tag }}
      overall-status: ${{ needs.cd.result }}
      tests-result: ${{ needs.quality.result }}
      security-result: ${{ needs.security-source.result }}
      migration-result: ${{ needs.db-migration.result }}
      cd-result: ${{ needs.cd.result }}
      notify-discord: true
      # notify-slack: true
      # notify-teams: true
      # No secrets needed — webhooks come from the notifications environment in order-platform-infra
```

> Replace `<your-org>` with your GitHub username.

---

## Severity levels (security)

The `fail-on-severity` input accepts: `UNKNOWN`, `LOW`, `MEDIUM`, `HIGH`, `CRITICAL`.
The pipeline always blocks on `CRITICAL` regardless of this setting.
Default is `HIGH`.

---

## Action versions reference

| Action                              | Version used |
|-------------------------------------|--------------|
| `actions/checkout`                  | `v6`         |
| `actions/setup-java`                | `v5`         |
| `actions/upload-artifact`           | `v5`         |
| `actions/stale`                     | `v9`         |
| `docker/setup-buildx-action`        | `v4`         |
| `docker/login-action`               | `v4`         |
| `docker/metadata-action`            | `v5`         |
| `docker/build-push-action`          | `v7`         |
| `aquasecurity/trivy-action`         | `v0.36.0`    |
| `SonarSource/sonarqube-scan-action` | `v4`         |
| `softprops/action-gh-release`       | `v3`         |
| `slackapi/slack-github-action`      | `v3.0.1`     |
| `stefanzweifel/git-auto-commit-action` | `v7`      |
| `renovatebot/github-action`         | `v46`        |
| `mathieudutour/github-tag-action`   | `v6.2`       |
| `gitleaks/gitleaks-action`          | `v2`         |
| `hadolint/hadolint-action`          | `v3.1.0`     |
| `mikepenz/action-junit-report`      | `v4`         |
| `madrapps/jacoco-report`            | `v1.6.1`     |
| `nick-fields/retry`                 | `v3`         |
| `github/codeql-action/upload-sarif` | `v3`         |

Versions are kept current automatically by the `dependency-update.yml` Renovate workflow.



