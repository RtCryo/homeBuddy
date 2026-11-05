# homeBuddy architecture

This is the system map across homeBuddy services. Service internals are documented in each repository's own `docs/ARCHITECTURE.md`. Normative rules live in the root [`openspec/`](../openspec/); while the platform change is active, see [`establish-homebuddy-platform`](../openspec/changes/archive/2026-11-05-establish-homebuddy-platform/design.md).

Status: authBuddy issues shared account tokens. finanzBuddy's identity migration is implemented and pending rollout verification. calendarBuddy's API, UI, and Compose stack are implemented in [`add-calendar-buddy`](../calendarBuddy/openspec/changes/archive/2026-11-05-add-calendar-buddy/proposal.md) and pending rollout verification.

## Services and ownership

| Service | Repository | Owns | Consumes |
|---|---|---|---|
| authBuddy | `authBuddy/` | Accounts, credentials, signing keys, token issuance, JWKS | — |
| finanzBuddy | `finanzBuddy/` | Documents, transactions, categories, tags, rules; local user projection | authBuddy tokens and JWKS |
| calendarBuddy | `calendarBuddy/` | Family members, appointments, recurrence; local account projection | authBuddy tokens and JWKS |

Each service owns its own PostgreSQL database. Services do not read each other's databases; the only runtime dependency between them is token verification against authBuddy.

## Target topology

```
Browser ──HTTPS──► shared Traefik (root compose, production profile)
                     ├─ TRAEFIK_DOMAIN  ──► finanzbuddy-ui   ─┬─ /api/auth/ ──► auth (authBuddy)
                     │                                         └─ /api/      ──► api-gateway
                     └─ CALENDAR_DOMAIN ──► calendarbuddy-ui ─┬─ /api/auth/ ──► auth (authBuddy)
                                                               └─ /api/      ──► calendar-api

api-gateway, calendar-api ──JWKS (cached)──► auth:8080/.well-known/jwks.json
All cross-stack traffic runs on the external Docker network `homebuddy`.
```

## Identity contract (summary)

- Issuer: authBuddy only. RS256 JWT with `kid`; claims `iss=homebuddy-auth`, `sub` = account UUID, `email`, `aud` = service names (`finanzbuddy`, `calendarbuddy`), `iat`, `exp`.
- Consumers verify via JWKS, refresh on unknown `kid`, require issuer and their own audience, and map `sub` to a local projection. No service other than authBuddy issues user tokens.
- One account is one family; everyone signed in with it has full access in every product.

## Port registry (local development)

| Service | Ports |
|---|---|
| finanzBuddy | UI 3000, Grafana 3001, API 8080, Postgres 5432, S3 9000, Prometheus 9090, Kafka 29092 |
| calendarBuddy | UI 3010, API 8081, Postgres 5433 |
| authBuddy | API 8090, Postgres 5434 |

New services claim unused ports in their umbrella change and update this table.

## Naming

- Docker network: `homebuddy` (external). Aliases: `auth`, `finanzbuddy-ui`, `calendarbuddy-ui`.
- Container names: `<service>-<component>` (for example `calendarbuddy-postgres`).
- Domains: finanzBuddy `TRAEFIK_DOMAIN`, calendarBuddy `CALENDAR_DOMAIN`.
