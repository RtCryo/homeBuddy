# homeBuddy workspace instructions

These instructions apply to the root workspace. Each service repository (`authBuddy/`, `finanzBuddy/`, `calendarBuddy/`) has its own `AGENTS.md`, which applies to work inside that folder in addition to this file.

## Language

All commit messages, pull request texts, code comments, specifications, documentation, scripts, and other generated text are written in English, regardless of the conversation language.

## Repository boundaries

- The root repository tracks only workspace files: `README.md`, `AGENTS.md`, `repos.txt`, `scripts/`, `docs/`, `openspec/`, and shared infrastructure such as the root `docker-compose.yml`.
- Service folders are independent Git repositories listed in `repos.txt` and ignored by the root `.gitignore`. Commit service changes in the service repository, never in the root.
- Adding, renaming, or removing a service means updating `repos.txt`, `.gitignore`, `README.md`, and `docs/ARCHITECTURE.md` together.

## Where to write specifications

| Write in the root `openspec/` | Write in `<service>/openspec/` |
|---|---|
| Contracts between services: identity token, network, routing, shared UI rules | Behavior inside one service: APIs, data, screens |
| Conventions every service must follow | How that service satisfies a root contract, with a link to it |
| Umbrella changes ordering several service changes | The per-service change implementing its part |

- Before work that touches authentication, cross-service calls, Docker networking, routing, ports, or shared UI foundations, read the relevant root capability under `openspec/specs/` or the active root change under `openspec/changes/`.
- A change that affects more than one service needs a root umbrella change that links every per-service change and states the rollout order. Root changes contain coordination and verification tasks only, never service implementation tasks.
- Do not restate a root contract in a service spec; reference it and specify only service-specific behavior.
- Validate with `openspec validate <change> --strict` from the folder that owns the change.

## Architecture documentation

- Keep [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) aligned with the services' deployment configuration and the root capabilities. When a change alters service ownership, cross-service contracts, network aliases, routing, or the port registry, update it in the same change.
- Service-internal architecture belongs in each service's own `docs/ARCHITECTURE.md`.
