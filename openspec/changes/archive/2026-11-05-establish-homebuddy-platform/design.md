# Design

## Context

See [proposal](proposal.md). The root folder `D:/repo/homeBuddy` is a Git repository without commits. `finanzBuddy/` is an independent repository (`origin` on GitHub); `authBuddy/` and `calendarBuddy/` are freshly initialized repositories without remotes. finanzBuddy runs its own Traefik under the `production` profile and publishes local ports 3000, 3001, 5432, 8080, 9000, 9090, and 29092.

## Decisions

### Root workspace with ignored service repositories

The root tracks only workspace files. Service folders are listed in `repos.txt` (`name url branch`) and ignored by `.gitignore`. `scripts/repos.sh` and `scripts/repos.ps1` provide the same `clone` (default; clones missing repositories), `pull` (fast-forward clean repositories with an `origin`), and `status` (branch, changed files, ahead/behind) commands; they never commit, push, reset, or overwrite a non-repository folder. Service versions are not pinned by the root: compatibility across services is expressed through the contracts below, and umbrella changes state the required rollout order.

Alternative: Git submodules, which pin versions but add a root commit for every service update. Rejected by the team in favor of independent histories.

### Specification placement

| Belongs in the root `openspec/` | Belongs in a service `openspec/` |
|---|---|
| Contracts between services: token format, network, routing, shared UI rules | Behavior inside one service: endpoints, data, screens |
| Umbrella changes that order several service changes | The per-service change that implements its part |
| Conventions every service must follow | Service-specific exceptions to those conventions, with rationale |

A root requirement states what every service must satisfy; a service spec states how it satisfies it and links back. A root change never contains service implementation tasks, only coordination and verification. When a contract changes, the umbrella change lists every affected service change.

### Identity contract

authBuddy is the only issuer. Tokens are RS256 JWTs with header `kid` and claims `iss=homebuddy-auth`, `sub` (account UUID, stable forever), `email`, `aud` (array of service audience names), `iat`, `exp`. Audience names are the lower-case service names (`finanzbuddy`, `calendarbuddy`). Consumers verify via `http://auth:8080/.well-known/jwks.json`, cache keys, refresh on unknown `kid`, require issuer and their own audience, allow at most 60 s clock skew, and map `sub` to a local projection. They never accept HMAC tokens or issue their own user tokens. A new service gets its audience by adding it to authBuddy's configuration in its own umbrella change.

### Deployment conventions

- One external Docker network `homebuddy`, created once (`docker network create homebuddy`) or by the root compose file.
- Aliases on that network: `auth` (authBuddy), `finanzbuddy-ui`, `calendarbuddy-ui`; APIs stay private to their own stack's default network unless a contract requires otherwise.
- Every product UI serves the browser from one origin and proxies `/api/auth/` to `http://auth:8080/auth/` before its own `/api/` rule.
- The root `docker-compose.yml` runs the shared Traefik (`production` profile) on the `homebuddy` network; service UIs carry Traefik labels with `traefik.docker.network=homebuddy` and their own `*_DOMAIN`. Service-local Traefik definitions remain only for standalone deployments and must not run on a host with the shared one.
- Container names use the `<service>-` prefix; volumes are project-scoped.
- Local port registry:

| Service | Ports |
|---|---|
| finanzBuddy | UI 3000, Grafana 3001, API 8080, Postgres 5432, S3 9000, Prometheus 9090, Kafka 29092 |
| calendarBuddy | UI 3010, API 8081, Postgres 5433 |
| authBuddy | API 8090, Postgres 5434 |

New services take the next free numbers and update this table in their umbrella change.

### UI family

All product UIs follow the finanzBuddy design-system anatomy: typography, spacing, radii, elevation, focus outline, motion, breakpoints, shell, buttons, fields, tables, notices, dialogs, and state patterns, with identical CSS token names. Each product has its own primary palette and brand mark; semantic success, warning, danger, info, and neutral colors are identical everywhere. Palettes: finanzBuddy teal `#167D68`, calendarBuddy indigo `#4F46B8`. A new palette needs WCAG 2.2 AA verification and must be distinguishable from existing ones. Each product keeps its own `ui/DESIGN_SYSTEM.md` that links to finanzBuddy's as the anatomy reference.

## Risks / Trade-offs

- No pinned versions -> an incompatible combination is possible; contracts plus the umbrella rollout order and the `status` script mitigate it.
- Links from the root into service repositories break when a service is not cloned -> `scripts/repos.sh clone` restores them; links in service repositories point to the root only by relative path from a standard workspace.
- Two Traefik instances on one host would fight over ports 80/443 -> the deployment spec forbids running a service-local Traefik alongside the shared one.

## Migration Plan

1. Commit the root workspace files and create remotes for the root, authBuddy, and calendarBuddy (manual step).
2. Implement the per-service changes in the order of the proposal table.
3. Archive the per-service changes in their repositories, then archive this change in the root.
