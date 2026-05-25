# Java Architecture — Hexagonal Light

Stack:
- Spring Boot 4
- Java 25
- Maven
- JPA/Hibernate
- Kafka
- Flyway
- PostgreSQL
- Testcontainers
- Lombok
- JUnit 5
- Mockito
- AssertJ

## Dependency Direction

Always respect this dependency flow:

adapter/in/web
→ port/in
→ application/service
→ port/out
→ adapter/out/{persistence,messaging}

domain
← must not depend on any layer above

## Domain Rules

The domain package:
- must not import Spring
- must not import JPA
- must not import Kafka
- may only use JDK and Lombok

Immediately point out violations.

## Ports and Adapters

- Input ports are interfaces in port/in
- Output ports are interfaces in port/out
- Services orchestrate use cases
- Adapters implement infrastructure concerns

Services must never directly reference:
- JPA repositories
- Kafka templates
- infrastructure classes

## Entity Conversion

Entity ↔ Domain conversion belongs inside the Entity itself.

Use:
- from(domain)
- toDomain()

Never place mapping logic:
- in services
- in adapters
- in controllers

## API Layer

Adapters in adapter/in/web:
- must use request/response DTOs
- must never expose domain objects directly

## Commands and Queries

Commands and Queries must be records inside port/in interfaces.

Example:

FeatureFlagUseCase.CreateFlagCommand

Do not create separate command classes.

## Flyway

Migrations:
- located at src/main/resources/db/migration/
- named as V{n}__{description}.sql

Never modify existing migrations.

## Dependency Rules

Before suggesting dependencies:
- verify active maintenance
- verify community adoption
- verify compatible license

Always prefer latest stable versions.
Avoid alpha, beta, rc or canary unless explicitly requested.
