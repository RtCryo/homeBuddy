# homeBuddy architecture

This is the system map across homeBuddy services. Service internals are documented in each repository's own `docs/ARCHITECTURE.md`. Normative rules live in the root capabilities under [`openspec/specs/`](../openspec/specs/); the design rationale is recorded in the archived [`establish-homebuddy-platform`](../openspec/changes/archive/2026-11-05-establish-homebuddy-platform/design.md) change.

Status: the platform rollout is complete and verified end to end. authBuddy issues the shared account tokens ([`add-identity-service`](../authBuddy/openspec/changes/archive/2026-11-04-add-identity-service/proposal.md)), finanzBuddy accepts them ([`adopt-homebuddy-identity`](../finanzBuddy/openspec/changes/archive/2026-11-05-adopt-homebuddy-identity/proposal.md)), and calendarBuddy is built on them ([`add-calendar-buddy`](../calendarBuddy/openspec/changes/archive/2026-11-05-add-calendar-buddy/proposal.md)).

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

api-gateway ──JWKS (cached)──► auth:8080/.well-known/jwks.json   over finanzbuddy-identity
calendar-api ─JWKS (cached)──► auth:8080/.well-known/jwks.json   over calendarbuddy-identity

Browser ──HTTPS──► shared Traefik ── MONITORING_DOMAIN ──► homebuddy-grafana ──► homebuddy-prometheus
                                                                                  ├─ authbuddy-auth-service           over authbuddy-metrics
                                                                                  ├─ finanzbuddy-api-gateway,
                                                                                  │  -parser-service, -kafka-exporter over finanzbuddy-metrics
                                                                                  └─ calendarbuddy-calendar-api       over calendarbuddy-metrics

homebuddy-grafana ──► homebuddy-loki ◄── homebuddy-alloy ◄── Docker API (read-only socket):
                      (root default network only)            stdout/stderr of every homebuddy-,
                                                              authbuddy-, finanzbuddy-, calendarbuddy- container

homebuddy-grafana ──► homebuddy-tempo ◄─OTLP gRPC─ homebuddy-alloy:4318 ◄─OTLP/HTTP─┬─ authbuddy-auth-service           over authbuddy-metrics
                      (root default network only)                                  ├─ finanzbuddy-api-gateway,
                                                                                   │  -parser-service                over finanzbuddy-metrics
                                                                                   └─ calendarbuddy-calendar-api       over calendarbuddy-metrics
```

Traefik, the product UIs, and authBuddy share the external Docker network `homebuddy`. Product APIs do not join it: each reaches authBuddy only over its own external, internal-only identity network, whose members are that API and authBuddy (alias `auth` on every one). No stack can reach another stack's API, except the central Prometheus over that service's metrics network. The central telemetry collector (`homebuddy-alloy`) joins the metrics networks too, but only receives traces there and never connects to a service. Compose cannot create the identity networks, so operators create them once per host:

```bash
docker network create --internal finanzbuddy-identity
docker network create --internal calendarbuddy-identity
```

## Monitoring

The root compose runs the only Prometheus (`homebuddy-prometheus`) and the only Grafana (`homebuddy-grafana`) of a host, without a Compose profile. Their configuration and every provisioned dashboard live in the root [`monitoring/`](../monitoring/) folder, with one dashboards subfolder per service. Normative rules: root capability `homebuddy-monitoring`.

- **Metrics networks.** Each service has an external, internal-only network `<service>-metrics` shared only by the central Prometheus, the central telemetry collector (`homebuddy-alloy`, see [Tracing](#tracing)), and that service's application components and scrape targets. This keeps product APIs unreachable from other stacks. Prometheus and Alloy join no other network than the root default one and the three metrics networks. Operators create them once per host:

  ```bash
  docker network create --internal authbuddy-metrics
  docker network create --internal finanzbuddy-metrics
  docker network create --internal calendarbuddy-metrics
  ```

- **Scrape convention.** Jobs are named `<service>-<component>`, target a container name, and carry a lowercase `service` label: `authbuddy-auth-service`, `finanzbuddy-api-gateway`, `finanzbuddy-parser-service`, `finanzbuddy-kafka-exporter`, `calendarbuddy-calendar-api`, and `homebuddy-prometheus`. Spring services expose `/actuator/prometheus` on port 8080; it is not reachable through any UI proxy or Traefik route.
- **Grafana portal.** One folder per service (`homeBuddy`, `authBuddy`, `finanzBuddy`, `calendarBuddy`); the home dashboard is the homeBuddy overview with the state of every target. Dashboards and the datasource are provisioned and read-only. Sign-in uses the built-in admin account with `GRAFANA_ADMIN_PASSWORD`; there is no anonymous access or sign-up.
- **Access.** Locally Grafana is at `http://localhost:3001` and Prometheus at `http://localhost:9090`, published on the loopback interface by the root `docker-compose.override.yml`. In production only Grafana is reachable, through the shared Traefik at `MONITORING_DOMAIN`; Prometheus is unpublished. Production therefore starts with `docker compose -f docker-compose.yml --profile production up -d`.
- **Retention.** 15 days of samples in the `prometheus-data` volume.
- **New services.** A new service adds its metrics network, scrape jobs, and dashboards folder here and in `monitoring/` in its umbrella change.

## Logging

The root compose also runs the only log store (`homebuddy-loki`) and the only log collector (`homebuddy-alloy`) of a host, without a Compose profile. Their configuration lives in [`monitoring/loki/`](../monitoring/loki/) and [`monitoring/alloy/`](../monitoring/alloy/). Normative rules: root capability `homebuddy-logging`.

- **Log flow.** Docker API → Alloy → Loki → Grafana. Alloy reads stdout and stderr of every container whose name starts with `homebuddy-`, `authbuddy-`, `finanzbuddy-`, or `calendarbuddy-` through the read-only Docker socket, picks up containers started later, and ignores every other container. Services only log to stdout and stderr; no service stack changes or joins a root network for logging.
- **Labels.** `service` (`authbuddy`, `finanzbuddy`, `calendarbuddy`, `homebuddy`, taken from the container name prefix and equal to the metric `service` label), `component` (Compose service name), `container`, and `stream` (`stdout` or `stderr`). No label comes from log content; Loki detects log levels into structured metadata only.
- **Retention.** 15 days in the `loki-data` volume; Alloy keeps its read positions in `alloy-data`.
- **Loki outages.** Alloy retries a batch without limit (backoff up to one minute), so lines written while Loki is down arrive once it returns. Restarting Alloy during a Loki outage loses the batch it holds in memory; the experimental `loki.write` WAL does not replay it in Alloy v1.22 and is not used.
- **Access.** Loki runs without authentication and is therefore on the root default network only: neither Loki nor Alloy publishes a host port, locally or in production, and Traefik does not route them. Logs are read in Grafana, behind its sign-in: datasource `Loki` and the dashboard `homeBuddy Logs` in the `homeBuddy` folder, linked from the overview.
- **Secrets.** Services never log passwords, tokens, signing keys, session cookies, or full request or response bodies. Loki runs at log level `warn`, because at `info` it logs the text of every query, which would store searched-for values in Loki.
- **Docker log rotation.** Root containers use `json-file` with `max-size: 10m` and `max-file: 3`; service stacks keep their own settings.

## Tracing

The root compose also runs the only trace store (`homebuddy-tempo`) of a host, without a Compose profile; Alloy (`homebuddy-alloy`) is the only trace receiver. Configuration lives in [`monitoring/tempo/`](../monitoring/tempo/) and [`monitoring/alloy/`](../monitoring/alloy/). Normative rules: root capability `homebuddy-tracing`.

- **Trace flow.** Component → OTLP over HTTP to `http://homebuddy-alloy:4318/v1/traces` over its own `<service>-metrics` network → Alloy (removes `http.request.header.authorization`, `http.request.header.cookie`, `http.response.header.set-cookie`, and any attribute whose key contains `password`, `token`, or `secret`; clears span status messages and drops `exception.message` and `exception.stacktrace` from spans and span events, keeping `exception.type`; batches) → OTLP gRPC to `tempo:4317` on the root default network → Grafana. No service joins another root network for tracing.
- **Isolation.** On the metrics networks only Alloy's port 4318 is reachable; its own HTTP server (UI, debug, `/metrics`) listens on `127.0.0.1:12345`. Tempo joins only the root default network, so no service can resolve it or read another service's traces through its query API.
- **Convention.** Resource attributes `service.name` = `<service>-<component>` (the scrape job name: `authbuddy-auth-service`, `finanzbuddy-api-gateway`, `finanzbuddy-parser-service`, `calendarbuddy-calendar-api`) and `service.namespace` = the lowercase service name. W3C Trace Context on every HTTP call and in Kafka record headers; finanzBuddy's outbox stores the upload's context, so an upload is one trace from `api-gateway` through Kafka and `parser-service` back to the status callback. Spring Boot components use the OpenTelemetry starter, with the export endpoint set only in Compose.
- **Sampling.** Every request is sampled by default (probability 1.0). Operators lower it per component with a variable in that service's `.env` (`AUTH_SERVICE_TRACING_SAMPLING_PROBABILITY`, `API_GATEWAY_TRACING_SAMPLING_PROBABILITY`, `PARSER_SERVICE_TRACING_SAMPLING_PROBABILITY`, `CALENDAR_API_TRACING_SAMPLING_PROBABILITY`); downstream components follow the caller's decision.
- **Privacy.** Spans carry no passwords, tokens, cookies, `Authorization` headers, bodies, e-mail addresses, or financial values; span names use route templates. Alloy's scrubbing is a second line of defense. Tempo runs at log level `warn`, so searched-for values are not logged.
- **Retention.** 15 days (`block_retention: 360h`) in the `tempo-data` volume. Tempo's metrics generator runs only the `local-blocks` processor, keeping every span kind (`filter_server_spans: false`), so TraceQL metrics (rate, errors, duration) work without writing to Prometheus and include `parser-service`'s Kafka consumer spans; metric queries may span the whole retention (`query_frontend.metrics.max_duration: 360h`). The `homeBuddy Traces` dashboard counts server and consumer spans. The one-shot `homebuddy-tempo-init` container hands the volume to Tempo's user before Tempo starts.
- **Outages.** Components drop spans they cannot export and only log warnings; requests are unaffected. Alloy keeps no persistent trace queue.
- **Trace-log links.** Spring Boot writes `[<traceId>-<spanId>]` into every log line inside a trace. The `Loki` datasource turns it into a link to the trace (derived field `TraceID`), and the `Tempo` datasource links each span to the Loki lines of its `service` that contain the trace id (±5 minutes).
- **Access.** Neither Tempo nor Alloy publishes a host port, locally or in production, and Traefik does not route them. Traces are read in Grafana, behind its sign-in: datasource `Tempo` and the dashboard `homeBuddy Traces` in the `homeBuddy` folder, linked from the overview.
- **New services.** A new service's umbrella change attaches Alloy to the service's metrics network and includes a per-service change that exports traces following `homebuddy-tracing`.

## Delivery and releases

Normative rules: root capability `homebuddy-delivery`. Every repository runs one CI workflow (`ci.yml`) on pull requests to `main` and pushes to `main`; its `ci` job is the single required check, together with the pull-request title check. Pull requests are squash-merged and titled with Conventional Commits.

Each service repository is versioned as one unit (one SemVer version for all of its components) by release-please. The release pull request proposes the next version and the `CHANGELOG.md` entries; merging it tags `vX.Y.Z`, creates the GitHub Release, and builds and pushes every image of the repository in the same workflow run, each with a build provenance attestation. Tags `X.Y.Z` are never overwritten, and no image is tagged `latest`. The root repository is not released.

```
pull request (Conventional Commits title) ──► ci ──► squash merge to main
main ──► release-please keeps the release pull request ──► merge ──► tag vX.Y.Z + GitHub Release
                                                                      └─► build, push, and attest every image
operator: set <SERVICE>_VERSION in .env ──► docker compose -f docker-compose.yml pull ──► up -d
```

### Image registry

| Repository | Image (`ghcr.io/rtcryo/…`) | Version variable |
|---|---|---|
| authBuddy | `authbuddy-auth-service` | `AUTHBUDDY_VERSION` |
| finanzBuddy | `finanzbuddy-api-gateway` | `FINANZBUDDY_VERSION` |
| finanzBuddy | `finanzbuddy-parser-service` | `FINANZBUDDY_VERSION` |
| finanzBuddy | `finanzbuddy-ui` | `FINANZBUDDY_VERSION` |
| calendarBuddy | `calendarbuddy-calendar-api` | `CALENDARBUDDY_VERSION` |
| calendarBuddy | `calendarbuddy-ui` | `CALENDARBUDDY_VERSION` |

Images are `linux/amd64`, tagged `X.Y.Z` and `X.Y` (the latter moves to the newest patch of a minor version; deployments pin `X.Y.Z`), and the packages are public. Production Compose files reference them by `image:` with the version variable and do not build; the `docker-compose.override.yml` of each repository builds from source for local development and tags the result `<service>-<component>:dev`. The root stack (Prometheus, Grafana, Loki, Alloy, Tempo, Traefik) uses upstream images and has no version variable. A new service adds its images and variable to this table in its umbrella change.

Rollout order: authBuddy first, because the product services verify tokens against it, then finanzBuddy and calendarBuddy. Rollback is setting the previous released version and recreating the stack.

## Identity contract (summary)

- Issuer: authBuddy only. RS256 JWT with `kid`; claims `iss=homebuddy-auth`, `sub` = account UUID, `email`, `aud` = service names (`finanzbuddy`, `calendarbuddy`), `iat`, `exp`.
- Consumers verify via JWKS, refresh on unknown `kid`, require issuer and their own audience, and map `sub` to a local projection. No service other than authBuddy issues user tokens.
- One account is one family; everyone signed in with it has full access in every product.

## Port registry (local development)

| Service | Ports |
|---|---|
| homeBuddy monitoring | Grafana 3001, Prometheus 9090 (Loki, Alloy, and Tempo publish no port) |
| finanzBuddy | UI 3000, API 8080, Postgres 5432, S3 9000, Kafka 29092 |
| calendarBuddy | UI 3010, API 8081, Postgres 5433 |
| authBuddy | API 8090, Postgres 5434 |

New services claim unused ports in their umbrella change and update this table.

## Naming

- Docker networks: `homebuddy` (external, shared by Traefik, UIs, authBuddy, and Grafana; aliases `auth`, `finanzbuddy-ui`, `calendarbuddy-ui`), one external, internal-only `<service>-identity` per product API (`finanzbuddy-identity`, `calendarbuddy-identity`), and one external, internal-only `<service>-metrics` per service (`authbuddy-metrics`, `finanzbuddy-metrics`, `calendarbuddy-metrics`).
- Container names: `<service>-<component>` (for example `calendarbuddy-postgres`); the root stack uses `homebuddy-` (`homebuddy-traefik`, `homebuddy-prometheus`, `homebuddy-grafana`, `homebuddy-loki`, `homebuddy-alloy`, `homebuddy-tempo`, and the one-shot `homebuddy-tempo-init`).
- Domains: finanzBuddy `TRAEFIK_DOMAIN`, calendarBuddy `CALENDAR_DOMAIN`, monitoring portal `MONITORING_DOMAIN`.
