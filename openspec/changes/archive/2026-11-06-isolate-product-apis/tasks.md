# Tasks

## 1. Root workspace

- [x] 1.1 Document the `finanzbuddy-identity` and `calendarbuddy-identity` networks in the root `docker-compose.yml` header comment, with the `docker network create --internal` commands for every host (Compose cannot create them, see design.md). Verify that `docker compose config` and `docker compose --profile production config` still succeed and that the header names both networks.
- [x] 1.2 Update `docs/ARCHITECTURE.md`: show the APIs reaching `auth` over their identity networks in the topology, replace "All cross-stack traffic runs on `homebuddy`", and list the identity networks under Naming. Update the root `README.md` network setup if it names networks. Verify that every documented network name matches the root compose.
- [x] 1.3 Propose the per-service changes in their repositories, each on its own branch: authBuddy [`join-identity-networks`](../../../../authBuddy/openspec/changes/archive/2026-11-06-join-identity-networks/proposal.md), finanzBuddy [`isolate-api-gateway-network`](../../../../finanzBuddy/openspec/changes/archive/2026-11-06-isolate-api-gateway-network/proposal.md), and calendarBuddy [`isolate-calendar-api-network`](../../../../calendarBuddy/openspec/changes/archive/2026-11-06-isolate-calendar-api-network/proposal.md). Each must reference `homebuddy-deployment` instead of restating it. Verify that `openspec validate <change> --strict` passes in each repository and that the links in proposal.md resolve.

## 2. Coordinated rollout

- [x] 2.1 authBuddy: implement `join-identity-networks`, so that `auth-service` joins both identity networks under the alias `auth` while staying on `homebuddy`. Verify that `curl http://auth:8080/.well-known/jwks.json` succeeds from a throwaway container on each identity network, and that `homebuddy` still resolves `auth`.
- [x] 2.2 Check that the identity networks listed in authBuddy's compose and in the root compose are the same set. Verify by comparing the networks in authBuddy's `docker compose config` output with the root compose header and `docs/ARCHITECTURE.md`.
- [x] 2.3 finanzBuddy: implement `isolate-api-gateway-network` only after 2.1 is deployed. Verify that the gateway accepts a fresh homeBuddy token through `http://localhost:3000/api/documents`, which means JWKS was fetched over `finanzbuddy-identity`.
- [x] 2.4 calendarBuddy: implement `isolate-calendar-api-network` only after 2.1 is deployed. Verify that `calendar-api` accepts a fresh homeBuddy token through the calendarBuddy UI.

## 3. Verification

- [x] 3.1 Verify isolation on one host with all stacks running. From `calendarbuddy-ui`, `calendarbuddy-calendar-api`, and a throwaway container on `homebuddy`, the names `api-gateway` and `finanzbuddy-api-gateway` must not resolve. The same must hold the other way round for `calendar-api` and `calendarbuddy-calendar-api`. Both UIs must still reach `auth`.
- [x] 3.2 Verify end to end: one account signs in to both products, uploads and parses a finanzBuddy statement, and creates a calendarBuddy appointment. Both UIs remain routed through the shared Traefik under the `production` profile.
- [x] 3.3 Verify that starting a product stack without its identity network fails with a message naming the network.

## 4. Archive

- [x] 4.1 Archive the per-service changes in their repositories, then run `openspec validate isolate-product-apis --strict` and archive this change.
