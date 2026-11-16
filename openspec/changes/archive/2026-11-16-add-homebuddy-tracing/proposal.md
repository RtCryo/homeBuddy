# Proposal

## Why

With `add-homebuddy-monitoring` and `add-homebuddy-logging`, homeBuddy has metrics and logs of every service in one Grafana portal, but no way to follow a single request across components. A slow upload passes through finanzBuddy's `api-gateway`, its outbox, Kafka, `parser-service`, and back through a status callback; a sign-in error in a product UI involves authBuddy's token and the product API's JWKS lookup. Today an operator has to guess which component was slow or failed and correlate log lines by timestamp. Grafana Tempo adds distributed traces to the same portal, linked to the logs and metrics that already exist there.

## What Changes

- Add Grafana Tempo to the root `docker-compose.yml` as the single trace store of a host: monolithic mode, local filesystem storage in a named volume, 15-day retention (the same as Prometheus and Loki), unpublished in production and locally, on the root default network only.
- Make the Grafana Alloy collector from `add-homebuddy-logging` the single trace receiver. It accepts OpenTelemetry traces (OTLP over HTTP) from the services, removes attributes that may carry secrets, batches them, and forwards them to Tempo. Alloy joins every `<service>-metrics` network so that product APIs can reach it without joining any other network; only its OTLP receiver port is reachable there. Tempo itself stays unreachable from service stacks.
- Define one tracing convention: OTLP/HTTP to `http://homebuddy-alloy:4318`, W3C Trace Context propagation, `service.name` = `<service>-<component>` (the same value as the scrape job), `service.namespace` = the lowercase service name, a sampling probability of 1.0 by default that operators can lower per component, and no passwords, tokens, cookies, `Authorization` headers, request or response bodies, or e-mail addresses in span attributes.
- Every Spring Boot component (`authbuddy-auth-service`, `finanzbuddy-api-gateway`, `finanzbuddy-parser-service`, `calendarbuddy-calendar-api`) exports traces for incoming HTTP requests, outgoing HTTP calls, and finanzBuddy's Kafka producer and consumer, and writes the trace and span id into every log line written inside a trace. A service keeps working unchanged when the collector is down.
- Enable Tempo's local-blocks processor so that TraceQL metrics queries (request rate, errors, and duration computed from traces) work in Grafana without writing anything to Prometheus.
- Provision Tempo as a third Grafana datasource with links from spans to Loki logs (by trace id), add a trace-id link from Loki log lines to Tempo, and add a `homebuddy-traces` dashboard in the `homeBuddy` folder, linked from the homeBuddy overview.
- Update `docs/ARCHITECTURE.md`, the root `README.md`, and the root compose header.

## Capabilities

### New Capabilities

- `homebuddy-tracing`: Central Tempo, Alloy as the only trace receiver, how services reach it, the tracing convention (protocol, propagation, resource attributes, sampling), privacy rules for span attributes, retention, trace-log correlation, and access to traces only through the Grafana portal.

### Modified Capabilities

- `homebuddy-monitoring` (introduced by the in-flight change `add-homebuddy-monitoring`): the members of each `<service>-metrics` network are the central Prometheus, the central telemetry collector, and that service's application components, which use it both to be scraped and to send traces.
- `homebuddy-deployment`: the isolation rule for product APIs names the telemetry collector as a member of the metrics networks that receives telemetry but never connects to a product API.

## Coordinated per-service changes

| Order | Repository | Change | Delivers |
|---|---|---|---|
| 0 | root | this change | Tempo, Alloy trace pipeline on the metrics networks, Tempo datasource with log links, `homebuddy-traces` dashboard, architecture documentation |
| 1 | authBuddy | [`add-auth-tracing`](../../../authBuddy/openspec/changes/add-auth-tracing/proposal.md) | OpenTelemetry tracing in `auth-service`, OTLP export to the collector, trace ids in logs |
| 1 | calendarBuddy | [`add-calendar-tracing`](../../../calendarBuddy/openspec/changes/add-calendar-tracing/proposal.md) | OpenTelemetry tracing in `calendar-api`, OTLP export, trace ids in logs |
| 1 | finanzBuddy | [`add-finanz-tracing`](../../../finanzBuddy/openspec/changes/add-finanz-tracing/proposal.md) | OpenTelemetry tracing in `api-gateway` and `parser-service`, trace context through the outbox and Kafka, OTLP export, trace ids in logs |

Rollout order: `add-homebuddy-monitoring` and `add-homebuddy-logging` are prerequisites and are rolled out first, because this change extends their Grafana, Prometheus, Alloy, and metrics networks. Step 0 follows on the same hosts. The three step-1 changes are independent of each other and can be deployed in any order; until a service is deployed, its components simply send no traces. Each service stack must already be attached to its metrics network, which `add-homebuddy-monitoring` requires.

## Non-goals

- Browser tracing in the product UIs (Grafana Faro) and tracing through Traefik or the UIs' nginx proxies; traces start at the first Spring Boot component.
- Database query spans (JDBC) and spans inside MinIO or Kafka brokers; client-side HTTP and Kafka spans already show their duration.
- Span metrics and service graphs written to Prometheus (they would require Prometheus's remote-write receiver, which would be writable from every metrics network), tail sampling, exemplars, and trace-based alerting.
- Multi-tenant Tempo, object storage for traces, or retention longer than 15 days.
- Structured (JSON) logging; correlation relies on the trace id written into the existing log line format.

## Impact

- Root: `docker-compose.yml` (service `tempo`, volume `tempo-data`, Alloy on the three metrics networks), new `monitoring/tempo/tempo.yml`, `monitoring/alloy/config.alloy` (OTLP pipeline), Grafana Tempo datasource, Loki datasource derived field, `homebuddy-traces` dashboard and overview link, `README.md`, `docs/ARCHITECTURE.md`, new `openspec/specs/homebuddy-tracing`, `openspec/specs/homebuddy-monitoring`, `openspec/specs/homebuddy-deployment`.
- authBuddy, finanzBuddy, calendarBuddy: one tracing dependency and configuration per Spring Boot component, `OTEL`/management environment in `docker-compose.yml`, finanzBuddy's outbox stores the trace context; specs and docs per service.
- Operators: no new networks, variables, or DNS records. Disk space for 15 days of traces in `tempo-data`. Optional per-component variable to lower the sampling probability.
