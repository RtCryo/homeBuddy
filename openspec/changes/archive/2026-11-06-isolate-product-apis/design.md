# Design

## Context

Today every stack joins the single external network `homebuddy` (see proposal.md, Why). On that network:

- authBuddy's `auth-service` has the alias `auth`.
- finanzBuddy's `ui` has the alias `finanzbuddy-ui`, and its `api-gateway` joins without an alias.
- calendarBuddy's `ui` has the alias `calendarbuddy-ui`, and its `calendar-api` joins without an alias.

Docker always registers a container's service name and container name on every network it joins. So an API on `homebuddy` is reachable as `api-gateway` or `finanzbuddy-api-gateway` from every other member, whatever aliases are configured. Aliases alone cannot hide an API; only network membership can.

Both APIs already read `AUTH_JWKS_URI`, which defaults to `http://auth:8080/.well-known/jwks.json`. They fetch the key set lazily and cache it. Each UI reaches its API over its own stack's default network, not over `homebuddy`.

## Goals / Non-Goals

**Goals:**

- A product API can reach exactly one other stack's container: `auth`.
- No configuration change inside the applications: same JWKS URI, same environment variables.
- Each rollout step is safe to deploy on its own, and the order in proposal.md never leaves an API without JWKS.

**Non-Goals:**

- Restricting which ports or paths an API may call on `auth`. Network membership is the boundary; authBuddy's public endpoints stay public.

## Decisions

### One identity network per product API

Each API gets `<service>-identity`, shared only with authBuddy. `auth-service` joins every identity network with the alias `auth`.

- *Alternative: one shared `homebuddy-identity` network for authBuddy and all APIs.* It is simpler, but the APIs would see each other, which still breaks the rule that a product API is not reachable from another stack.
- *Alternative: fetch JWKS through the product's own UI.* It needs no new network, but a compromised UI could then serve a forged key set, and the API would accept tokens that UI mints. The UI would become part of the token trust chain.
- *Alternative: relax the spec.* That would document the gap instead of closing it.

### Identity networks are internal and external

They are created with `--internal`, so a container on them has no route to the outside world through them. They are external to the service stacks, like `homebuddy`, so no single service stack owns them and a service stack can be torn down without removing a network another stack uses.

The root compose cannot create them: Compose drops and never creates a network that no service in the file attaches to, and attaching any root service (Traefik or a helper) would add a member beyond the API and authBuddy. They are therefore created once on every host, production included, with `docker network create --internal <name>`. The root compose header documents the commands.

Both APIs keep their default stack network, which provides their outbound access (Kafka, MinIO, PostgreSQL inside the stack). No API needs internet access through the identity network.

### Keep the alias `auth` on every network

Using the same alias everywhere keeps `AUTH_JWKS_URI` and the identity contract unchanged. Because each identity network contains only one API and authBuddy, the alias does not collide.

### authBuddy lists the identity networks

authBuddy's compose has to name each identity network it joins, so adding a product means one more entry there. The umbrella change of a new service already has to edit authBuddy to add its audience (`homebuddy-identity-contract`), so the network entry goes into that same change. authBuddy's compose and the root compose header and documentation therefore list the same identity networks; the root task list checks that they match.

## Risks / Trade-offs

- [A product API leaves `homebuddy` before authBuddy is on its identity network] → JWKS cannot be fetched, and every token is rejected with 401. Mitigation: the rollout order, plus a verification task that checks JWKS reachability before each API change is deployed.
- [authBuddy fails to start on a host that lacks one of the identity networks] → A standalone authBuddy deployment, or a host running only some products, needs every listed network created. Mitigation: authBuddy's README documents the `docker network create --internal` commands; creating an unused network costs nothing.
- [A developer runs a product stack without the identity network] → Compose fails fast and names the network (see the spec scenario), and the README shows the command.
- [The internal network blocks something an API needed] → Nothing the APIs do today goes through `homebuddy` except the JWKS fetch; the verification task confirms that uploads, parsing, and tokens still work end to end.

## Migration Plan

1. Root: document the identity networks in the `docker-compose.yml` header. On every host, run `docker network create --internal finanzbuddy-identity` and `docker network create --internal calendarbuddy-identity`. This is additive.
2. authBuddy: `auth-service` joins both networks under the alias `auth`, then is redeployed. This is additive: APIs still on `homebuddy` keep working.
3. finanzBuddy and calendarBuddy, in either order: the API swaps `homebuddy` for its identity network and is recreated (`docker compose up -d`).
4. Verify per the root tasks.

Rollback: put the API back on `homebuddy` and recreate it. Steps 1 and 2 can stay in place, because extra networks change no behavior.
