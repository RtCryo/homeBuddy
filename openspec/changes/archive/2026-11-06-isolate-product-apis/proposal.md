# Proposal

## Why

The `homebuddy-deployment` contract says a product API SHALL NOT be reachable from another stack. Both product APIs, finanzBuddy `api-gateway` and calendarBuddy `calendar-api`, still join the shared `homebuddy` network so that they can fetch authBuddy's JWKS. As a result, every container of every stack can call them directly, including finanzBuddy's `/internal/**` endpoints, which only the service API key protects. The review of finanzBuddy PR #100 found this gap, and it applies to every product API.

## What Changes

- Give each product API its own identity network, `<service>-identity`, whose only members are that API and authBuddy. The networks for the current services are `finanzbuddy-identity` and `calendarbuddy-identity`. They are external, internal-only Docker networks. Compose creates only networks that a service in the same file attaches to, and no root service may join an identity network, so the root `docker-compose.yml` cannot create them. Operators create them once on every host, production included, with `docker network create --internal <name>`; the root compose header documents the commands.
- authBuddy's `auth-service` joins every identity network under the alias `auth`, so the JWKS URI `http://auth:8080/.well-known/jwks.json` stays the same for every consumer.
- **BREAKING (deployment)**: product APIs leave the `homebuddy` network. Each API joins only its own stack network and its own identity network. A product API stack no longer starts until its identity network exists.
- Product UIs stay on `homebuddy` unchanged: Traefik reaches them there, and they proxy `/api/auth/` to `auth` there.
- Adding a product service now also means adding its identity network, in the root compose header commands, the documentation, and authBuddy's compose, through that service's umbrella change.
- Update `docs/ARCHITECTURE.md` (topology, naming) and the root compose to match.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `homebuddy-deployment`: The requirement "Services connect over the homebuddy network" now separates the shared `homebuddy` network (Traefik, `auth`, product UIs) from one identity network per product API, and requires a new product service to add its identity network in its umbrella change.

## Coordinated per-service changes

| Order | Repository | Change | Delivers |
|---|---|---|---|
| 0 | root | this change | `finanzbuddy-identity` and `calendarbuddy-identity` network creation commands in the root compose header; architecture documentation |
| 1 | authBuddy | [`join-identity-networks`](../../../../authBuddy/openspec/changes/archive/2026-11-06-join-identity-networks/proposal.md) | `auth-service` joins both identity networks under the alias `auth` |
| 2 | finanzBuddy | [`isolate-api-gateway-network`](../../../../finanzBuddy/openspec/changes/archive/2026-11-06-isolate-api-gateway-network/proposal.md) | `api-gateway` leaves `homebuddy` and joins `finanzbuddy-identity` |
| 2 | calendarBuddy | [`isolate-calendar-api-network`](../../../../calendarBuddy/openspec/changes/archive/2026-11-06-isolate-calendar-api-network/proposal.md) | `calendar-api` leaves `homebuddy` and joins `calendarbuddy-identity` |

The networks must exist before authBuddy joins them, and authBuddy must be reachable on an identity network before a product API leaves `homebuddy`. Otherwise that API can no longer fetch JWKS, and every request returns 401. The two step-2 changes are independent of each other.

## Non-goals

- Changing the token format, the JWKS URI, or how consumers validate tokens.
- Isolating product UIs from each other on `homebuddy`; they hold no secrets and only proxy.
- Replacing the service API key that protects finanzBuddy's `/internal/**`; it stays as a second layer.

## Impact

- Root: `docker-compose.yml`, `docs/ARCHITECTURE.md`, `openspec/specs/homebuddy-deployment`.
- authBuddy: `docker-compose.yml`, deployment documentation and spec.
- finanzBuddy: `docker-compose.yml`, the CI Compose smoke test, README and runbook network setup, the `compose-deployment` spec.
- calendarBuddy: `docker-compose.yml`, README network setup, its deployment spec.
- Operators: one-time `docker network create --internal` for each identity network on every host, production included.
