# Proposal

## Why

Prometheus and Grafana live inside the finanzBuddy stack, so only finanzBuddy is monitored. authBuddy, which every product depends on for sign-in, and calendarBuddy have no metrics or dashboards at all, and adding a second Grafana per service would split the operational view across several portals with separate logins and ports. homeBuddy needs one monitoring portal that shows every service.

## What Changes

- Add a central monitoring stack to the root `docker-compose.yml`: one Prometheus and one Grafana, with their configuration and all provisioned dashboards tracked in a new root `monitoring/` folder.
- Give every service its own external, internal-only metrics network `<service>-metrics` (`authbuddy-metrics`, `finanzbuddy-metrics`, `calendarbuddy-metrics`). Its only members are the central Prometheus and that service's scrape targets, so the central Prometheus can scrape product APIs without breaking their isolation from other stacks. Operators create the networks once per host, like the identity networks.
- Define one scrape convention: job names `<service>-<component>`, a `service` label on every target, targets addressed by container name.
- Grafana is the single portal: a homeBuddy overview home dashboard with the availability of every service, and one folder per service (`authBuddy`, `finanzBuddy`, `calendarBuddy`) with its dashboards. Datasource and dashboards are provisioned; nothing is set up by hand.
- Grafana is published in production through the shared Traefik on its own domain, `MONITORING_DOMAIN`, over HTTPS, with a required admin password and without anonymous access or sign-up. Prometheus stays unpublished in production. Locally, Grafana stays at `localhost:3001` and Prometheus at `localhost:9090`, now owned by the root stack.
- **BREAKING (deployment)**: finanzBuddy removes its own `prometheus` and `grafana` services, volumes, and `monitoring/` provisioning. Its dashboards move to the root, switched to the new job names. Existing Prometheus history and Grafana user state in finanzBuddy's volumes are not migrated.
- authBuddy and calendarBuddy expose Prometheus metrics: basic service metrics (availability, uptime, HTTP, JVM) and bounded, privacy-preserving business metrics (authBuddy: sign-in and registration outcomes, issued tokens; calendarBuddy: appointment and family-member operations, stored totals, recurrence expansion duration).
- Update `docs/ARCHITECTURE.md` (topology, port registry, naming) and the root compose header.

## Capabilities

### New Capabilities

- `homebuddy-monitoring`: Central Prometheus and Grafana, metrics networks, scrape and label conventions, the metrics every service must expose, the Grafana portal and its access rules, and how a new service joins monitoring.

### Modified Capabilities

- `homebuddy-deployment`: A product API may additionally be reached by the central Prometheus over its metrics network; the shared Traefik also routes the Grafana portal domain; ports 3001 and 9090 move from finanzBuddy to the root monitoring stack in the port registry.

## Coordinated per-service changes

| Order | Repository | Change | Delivers |
|---|---|---|---|
| 0 | root | this change | Metrics network commands in the root compose header, central Prometheus and Grafana, root `monitoring/` with the overview and all service dashboards, architecture documentation |
| 1 | authBuddy | [`expose-auth-metrics`](../../../authBuddy/openspec/changes/archive/2026-11-07-expose-auth-metrics/proposal.md) | `/actuator/prometheus` with basic and business metrics; `auth-service` joins `authbuddy-metrics` |
| 1 | calendarBuddy | [`expose-calendar-metrics`](../../../calendarBuddy/openspec/changes/archive/2026-11-07-expose-calendar-metrics/proposal.md) | Prometheus registry and business metrics in `calendar-api`; it joins `calendarbuddy-metrics` |
| 2 | finanzBuddy | [`move-monitoring-to-homebuddy`](../../../finanzBuddy/openspec/changes/archive/2026-11-07-move-monitoring-to-homebuddy/proposal.md) | Own Prometheus and Grafana removed; `api-gateway`, `parser-service`, and `kafka-exporter` join `finanzbuddy-metrics` |

The metrics networks must exist on a host before any service stack joins them. The two step-1 changes are independent of each other. finanzBuddy goes last: on a development machine its Prometheus and Grafana still hold ports 9090 and 3001, so the root monitoring stack starts locally only once finanzBuddy has dropped them. In production nothing is published on those ports, so the root stack can run from step 0 and shows finanzBuddy's targets as down until step 2.

## Non-goals

- Logs or traces (Loki, Tempo, OpenTelemetry) and alerting rules or notification channels.
- Signing in to Grafana with a homeBuddy account; authBuddy has no OIDC provider. Grafana keeps its own admin login.
- Migrating finanzBuddy's existing Prometheus samples or Grafana user state.
- Monitoring PostgreSQL, the object store, or the UI containers beyond what already exists.

## Impact

- Root: `docker-compose.yml`, a new `docker-compose.override.yml` for the local Grafana and Prometheus ports (production then runs with `-f docker-compose.yml`, like the service stacks), new `monitoring/`, `.env.example` (`GRAFANA_ADMIN_PASSWORD`, `MONITORING_DOMAIN`), `README.md`, `docs/ARCHITECTURE.md`, `openspec/specs/homebuddy-monitoring`, `openspec/specs/homebuddy-deployment`.
- authBuddy: `auth-service` dependencies, actuator configuration, security rules, metrics code; `docker-compose.yml`; deployment spec and docs.
- calendarBuddy: `calendar-api` dependencies, security rules, metrics code; `docker-compose.yml`; deployment spec and docs.
- finanzBuddy: `docker-compose.yml`, `docker-compose.override.yml`, removal of `monitoring/`, CI Compose smoke test if it covers monitoring, README and docs, `application-observability` and `compose-deployment` specs.
- Operators: one-time `docker network create --internal` for each metrics network on every host; set `GRAFANA_ADMIN_PASSWORD` and `MONITORING_DOMAIN` and a DNS record for the Grafana domain in production.
