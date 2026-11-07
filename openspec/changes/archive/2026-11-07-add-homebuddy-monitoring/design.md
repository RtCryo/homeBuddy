# Design

## Context

finanzBuddy's `docker-compose.yml` runs `prometheus` (`prom/prometheus:v3.16.0`, 15-day retention) and `grafana` (`grafana/grafana:13.3.0`) on its default network. Prometheus scrapes `api-gateway:8080/actuator/prometheus`, `parser-service:8080/actuator/prometheus`, and `kafka-exporter:9308` with the job names `api-gateway`, `parser-service`, and `kafka-exporter`. Grafana provisions one Prometheus datasource (uid `prometheus`) and five dashboards from `finanzBuddy/monitoring/grafana/dashboards/` into a `finanzBuddy` folder. Their queries select on those job names, and `finanzbuddy-health.json` is the home dashboard. The local override publishes Grafana on 3001 and Prometheus on 9090; production publishes neither. Grafana still uses the default `admin`/`admin` login.

authBuddy's `auth-service` has the actuator but exposes only `health`; it has no Prometheus registry. calendarBuddy's `calendar-api` lists `prometheus` in its actuator exposure but has no Prometheus registry dependency, and its security rules permit only `/actuator/health`. Neither has business metrics.

Network isolation (`homebuddy-deployment`): product APIs are on their stack network and their `<service>-identity` network only; `auth-service` is on `homebuddy` and every identity network. The root stack is the `homebuddy` Compose project with Traefik under the `production` profile.

## Goals / Non-Goals

**Goals:**

- One Prometheus and one Grafana per host, owned by the root workspace, showing every service.
- No new path between stacks except central Prometheus → scrape targets.
- Grafana usable in production from a browser, protected by a login.
- authBuddy and calendarBuddy gain basic and business metrics; finanzBuddy keeps its existing signals.

**Non-Goals:**

- Logs, traces, alerting, Grafana SSO through authBuddy, and migrating old monitoring data (see proposal).

## Decisions

### Central Prometheus and Grafana in the root compose

Both services move into the root `docker-compose.yml` without a profile, with container names `homebuddy-prometheus` and `homebuddy-grafana`, the same image versions as finanzBuddy today, and named volumes for data. Prometheus and Grafana talk over the root project's default network. Grafana also joins `homebuddy` so that Traefik can route it. Prometheus joins only the default network and the metrics networks.

- *Alternative: a Prometheus per service, with Grafana using several datasources.* It keeps scraping inside each stack, but it runs one Prometheus per service and spreads retention settings and storage across stacks. Cross-service overview panels would need one query per datasource. The user chose the central option.

Without a profile, `docker compose up -d` in the root now starts monitoring locally. The header no longer says that Compose creates nothing without the profile, and it explains that monitoring always runs.

### One internal metrics network per service

Prometheus must reach product APIs, which no other stack may reach. As with identity, the boundary is network membership: `<service>-metrics`, internal and external, shared only by Prometheus and that service's scrape targets. finanzBuddy attaches `api-gateway`, `parser-service`, and `kafka-exporter`; calendarBuddy attaches `calendar-api`; authBuddy attaches `auth-service`. authBuddy also gets a network even though `auth-service` is already on `homebuddy`, so that Prometheus never joins `homebuddy`.

The networks are created by operators with `docker network create --internal`, and every compose file, root included, declares them `external: true`. Unlike the identity networks, the root compose could create them, because Prometheus attaches to them. It still does not: if a developer had already created such a network by hand, Compose would reject it because the Compose labels are missing. External declarations also keep the setup identical to the identity networks and let a service stack start before the root stack.

- *Alternative: one shared `homebuddy-metrics` network.* It is simpler, but every scrape target could reach every other service's API, which breaks the isolation rule.
- *Alternative: Prometheus joins the identity networks.* It would mix two trust boundaries and would not cover finanzBuddy's parser service or Kafka exporter.

### Scrape by container name, label by service

Targets are container names (`finanzbuddy-api-gateway:8080`). Docker registers container names on every network a container joins, and they are already unique across stacks by the naming rule; service names such as `postgres` are not. Jobs are `<service>-<component>`, with a static `service` label. The overview queries `up` and `process_uptime_seconds` by `service` and `job`.

Jobs:

| Job | Target | Path |
|---|---|---|
| `homebuddy-prometheus` | `localhost:9090` | `/metrics` |
| `authbuddy-auth-service` | `authbuddy-auth-service:8080` | `/actuator/prometheus` |
| `finanzbuddy-api-gateway` | `finanzbuddy-api-gateway:8080` | `/actuator/prometheus` |
| `finanzbuddy-parser-service` | `finanzbuddy-parser-service:8080` | `/actuator/prometheus` |
| `finanzbuddy-kafka-exporter` | `finanzbuddy-kafka-exporter:9308` | `/metrics` |
| `calendarbuddy-calendar-api` | `calendarbuddy-calendar-api:8080` | `/actuator/prometheus` |

### Root owns the monitoring configuration and all dashboards

The root repository gets `monitoring/prometheus/prometheus.yml` and `monitoring/grafana/{provisioning,dashboards}`, with one dashboards subfolder per service and one for the homeBuddy overview, and one file provider per folder that maps to a Grafana folder. finanzBuddy's five dashboards move there unchanged except for their job selectors. Dashboard uids get the service prefix; finanzBuddy's already start with `finanzbuddy-`.

- *Alternative: each service keeps its dashboards and scrape fragment, and the root compose bind-mounts `./<service>/monitoring`.* Ownership would sit next to the metrics, but a bind mount of a service folder that is not cloned makes Docker create that folder. Afterwards `scripts/repos.sh clone` skips it as present and not a Git repository. A root stack on a host that runs only some services would also need every repository. Root-owned files avoid both problems. The cost is that a service change that renames a metric has to update the root dashboard too, in an umbrella change. Metric names are part of what the service promises to monitoring, so that cost is acceptable.

### Grafana published through the shared Traefik

Grafana carries Traefik labels like the product UIs: `traefik.docker.network=homebuddy`, router `homebuddy-grafana` on ``Host(`${MONITORING_DOMAIN}`)``, `websecure`, `letsencrypt`, and service port 3000. `GF_SERVER_ROOT_URL` is `https://${MONITORING_DOMAIN}` when the domain is set. Security settings: `GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:?...}`, `GF_AUTH_ANONYMOUS_ENABLED=false`, `GF_USERS_ALLOW_SIGN_UP=false`, and cookies marked secure in production. Grafana's built-in brute-force login protection stays on. The local override publishes `3001:3000` and `9090:9090`. The root has no override file today, so this change adds `docker-compose.override.yml` to the root, and production runs with `-f docker-compose.yml`, as in the service stacks.

- *Alternative: keep Grafana unpublished and use an SSH tunnel.* It is safer, but the user wants a portal reachable on its own domain.
- *Alternative: protect Grafana with Traefik basic auth in front of the Grafana login.* That adds a second password with no real gain, because Grafana already enforces a login with brute-force protection. It can be added later without changing the contract.

### Metrics endpoints stay off public routes

The UIs proxy only `/api/auth/` → `auth:8080/auth/` and `/api/` → the API's `/api/` paths, so actuator paths are not reachable from browsers. Traefik routes only UI and Grafana domains. authBuddy keeps metrics on port 8080: other members of `homebuddy` (UIs, Grafana) could technically read them, but the metrics carry only bounded aggregate counters. A separate management port would not change network reachability. Each per-service change permits `/actuator/prometheus` in its security rules and verifies that the UI origin does not serve it.

### Business metrics (named in the service specs)

- authBuddy: sign-in attempts by outcome (success, invalid credentials, rate limited), registrations by outcome (success, rejected, disabled), and tokens issued.
- calendarBuddy: appointment and family-member operations by operation (create, update, delete) and outcome, current totals of appointments and family members across all accounts, and recurrence expansion duration.
- finanzBuddy: unchanged (`application-observability`).

Labels are limited to fixed outcome and operation sets. The root spec forbids account identifiers and e-mail addresses.

## Risks / Trade-offs

- [Port clash on a development machine while finanzBuddy still runs its own Grafana and Prometheus] → The rollout starts the root stack locally only after finanzBuddy's change; the README notes it.
- [Grafana exposed to the internet] → HTTPS only, required strong admin password, no anonymous access or sign-up, brute-force protection; Prometheus remains unpublished.
- [Losing finanzBuddy's 15-day metric history and Grafana preferences] → Accepted, because dashboards are provisioned and history is short-lived. The old volumes stay until an operator removes them after verification.
- [A standalone finanzBuddy deployment without the root stack has no monitoring] → Documented. Standalone deployments already depend on root contracts for networks and identity.
- [A host that does not run some service shows its targets as down on the overview] → Intended: the overview reflects what is missing. Operators who deliberately run a subset can read the down state as expected.
- [Root dashboards drift from service metric names] → Per-service specs name their business metrics. A rename requires an umbrella change touching the root dashboard. The verification tasks check every panel for data.

## Migration Plan

1. Root: on every host, create `authbuddy-metrics`, `finanzbuddy-metrics`, and `calendarbuddy-metrics` with `docker network create --internal`. Merge the root monitoring stack. In production set `GRAFANA_ADMIN_PASSWORD` and `MONITORING_DOMAIN`, add the DNS record, and start the stack with `docker compose -f docker-compose.yml --profile production up -d`. Locally, wait for step 3.
2. authBuddy and calendarBuddy, in either order: deploy the metrics changes; their targets turn up.
3. finanzBuddy: deploy the change that removes its Prometheus and Grafana and attaches its targets to `finanzbuddy-metrics`. Start the root stack locally if needed. Remove the old `finanzbuddy_prometheus-data` and `finanzbuddy_grafana-data` volumes after verification.

Rollback: redeploy finanzBuddy's previous compose to restore its own monitoring, and stop the root `prometheus` and `grafana` services. Metrics networks and exposed endpoints can stay in place; they change no product behavior.

## Open Questions

- None.
