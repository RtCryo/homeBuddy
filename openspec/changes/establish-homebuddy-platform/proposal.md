# Proposal

## Why

homeBuddy grows from one product (finanzBuddy) to three independent repositories: authBuddy, finanzBuddy, and calendarBuddy. They share a family account, a Docker network, a public entry point, and a visual language, but each repository can only specify its own behavior. Without one place for these contracts, every service restates them slightly differently and cross-service changes have no common rollout plan.

## What Changes

- Establish the `homeBuddy` root repository as a workspace: it tracks `repos.txt`, `scripts/repos.sh` / `scripts/repos.ps1`, root documentation, shared infrastructure, and this `openspec/`, and ignores the service folders, which stay independent Git repositories.
- Define where specifications live: cross-service contracts and umbrella changes in the root, service behavior in each service's `openspec/`.
- Specify the **homeBuddy identity contract** (issuer, audiences, claims, signing, JWKS, consumer validation) once, owned by authBuddy and consumed by every service.
- Specify **homeBuddy deployment** conventions: the external `homebuddy` network, service aliases, one shared Traefik entry point, the `/api/auth` proxy rule, container and port naming.
- Specify the **homeBuddy UI family**: shared component anatomy, per-service palettes, and semantic colors that stay identical.
- Coordinate the rollout of the shared account and calendarBuddy across the three per-service changes.

## Capabilities

### New Capabilities

- `homebuddy-workspace`: Root repository scope, service manifest and scripts, and the specification placement rule.
- `homebuddy-identity-contract`: Token format and validation rules for all homeBuddy services.
- `homebuddy-deployment`: Network, routing, naming, and port conventions across service stacks.
- `homebuddy-ui-family`: Shared UI anatomy and per-service identity rules.

### Modified Capabilities

- None (first root change).

## Coordinated per-service changes

| Order | Repository | Change | Delivers |
|---|---|---|---|
| 1 | authBuddy | [`add-identity-service`](../../../authBuddy/openspec/changes/archive/2026-11-04-add-identity-service/proposal.md) | Accounts, token issuance, JWKS, legacy import |
| 2 | finanzBuddy | [`adopt-homebuddy-identity`](../../../finanzBuddy/openspec/changes/adopt-homebuddy-identity/proposal.md) | Gateway accepts homeBuddy tokens; local users linked |
| 3 | calendarBuddy | [`add-calendar-buddy`](../../../calendarBuddy/openspec/changes/archive/2026-11-05-add-calendar-buddy/proposal.md) | Family calendar on the shared account |

## Non-goals

- Moving service code or service specifications into the root repository, or Git submodules.
- A shared UI package or shared Java library; each service copies the documented conventions.

## Impact

- Root repository: `.gitignore`, `repos.txt`, `scripts/`, `README.md`, `AGENTS.md`, `docs/ARCHITECTURE.md`, `openspec/`, and a root `docker-compose.yml` for the shared network and Traefik.
- Service repositories: their changes reference these root capabilities instead of restating the contracts.
