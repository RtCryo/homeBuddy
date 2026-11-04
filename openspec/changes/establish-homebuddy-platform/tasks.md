# Tasks

## 1. Root workspace

- [x] 1.1 Add `.gitignore` for service folders, `repos.txt`, and `scripts/repos.sh` / `scripts/repos.ps1` with `clone`, `pull`, and `status`; verify both scripts on present, missing, and unreachable repositories.
- [x] 1.2 Add root `README.md`, `AGENTS.md` (specification placement rule), and `docs/ARCHITECTURE.md` (system map, ownership, contracts); verify links resolve in a fully cloned workspace.
- [x] 1.3 Create remotes for the root, authBuddy, and calendarBuddy repositories and confirm the URLs in `repos.txt`; verify `scripts/repos.sh clone` into an empty workspace.
- [x] 1.4 Add the root `docker-compose.yml` creating the `homebuddy` network and the shared Traefik under the `production` profile; verify `docker compose config` and that a service UI with labels is routed.

## 2. Coordinated rollout

- [ ] 2.1 authBuddy: implement [`add-identity-service`](../../../authBuddy/openspec/changes/add-identity-service/tasks.md) conforming to `homebuddy-identity-contract` and `homebuddy-deployment`.
- [ ] 2.2 finanzBuddy: implement [`adopt-homebuddy-identity`](../../../finanzBuddy/openspec/changes/adopt-homebuddy-identity/tasks.md), including Traefik labels on the shared network.
- [ ] 2.3 calendarBuddy: implement [`add-calendar-buddy`](../../../calendarBuddy/openspec/changes/add-calendar-buddy/tasks.md) conforming to all root capabilities.
- [ ] 2.4 Verify end to end on one host: one account signs in to finanzBuddy and calendarBuddy, an existing finanzBuddy user keeps data and password, and only the shared Traefik owns ports 80/443.

## 3. Archive

- [ ] 3.1 Archive the per-service changes in their repositories, then run `openspec validate establish-homebuddy-platform --strict` and archive this change.
