# Design

## Context

All four application components are Spring Boot 4.1.2 on Java 25: `authbuddy-auth-service`, `finanzbuddy-api-gateway`, `finanzbuddy-parser-service`, and `calendarbuddy-calendar-api`. None has tracing today; there is no Micrometer Tracing or OpenTelemetry dependency in any `pom.xml`. Calls between components:

- Product APIs fetch authBuddy's JWKS over their identity network (`http://auth:8080/.well-known/jwks.json`) through Spring Security's resource server; the keys are cached, so the call is rare.
- finanzBuddy's `api-gateway` writes upload events to an outbox table (`OutboxEvent`); `OutboxRelay`, a scheduled job, publishes them to Kafka later, outside the upload request. `parser-service` consumes them and reports status back through `GatewayStatusClient`, a `RestClient` built from an injected `RestClient.Builder`.

The in-flight changes this one builds on, none of them implemented yet:

- `add-homebuddy-monitoring`: `homebuddy-prometheus`, `homebuddy-grafana` (datasource uid `prometheus`, file providers per folder, `homebuddy-overview` home dashboard, Traefik on `MONITORING_DOMAIN`), the external internal-only networks `authbuddy-metrics`, `finanzbuddy-metrics`, `calendarbuddy-metrics`, which every scrape target joins, and the root `docker-compose.override.yml`.
- `add-homebuddy-logging`: `homebuddy-loki`, `homebuddy-alloy` (Docker socket read-only, `monitoring/alloy/config.alloy`, only on the root default network), Loki datasource uid `loki`, labels `service`, `component`, `container`, `stream`, and the `homebuddy-logs` dashboard.

This change must be implemented after both.

## Goals / Non-Goals

**Goals:**

- One trace of a request across components and services, in the existing Grafana portal, linked to its logs.
- No new network, variable, or DNS record for operators; services reach the root stack only over the metrics networks they already join.
- Tracing never affects a service's behavior when the root stack is down.

**Non-Goals:**

- Browser and proxy tracing, JDBC spans, span metrics and service graphs in Prometheus (see proposal).

## Decisions

### Tempo in monolithic mode with local storage

`tempo` runs as `homebuddy-tempo` from the `grafana/tempo` image, pinned to the latest stable 2.x release at implementation time, with `monitoring/tempo/tempo.yml` mounted read-only. Configuration: `server.http_listen_port: 3200`, an OTLP gRPC receiver on `0.0.0.0:4317` only (no Jaeger or Zipkin receivers, no OTLP HTTP), `storage.trace.backend: local` with WAL and blocks under `/var/tempo` in the named volume `tempo-data`, and `compactor.compaction.block_retention: 360h`. The metrics generator runs only the `local-blocks` processor, with `flush_to_storage: true`, so TraceQL metrics queries (`rate()`, `quantile_over_time()`) work over the stored range without remote write. Tempo joins only the root default network, where Alloy reaches `tempo:4317` and Grafana `http://tempo:3200`.

- *Alternative: Jaeger.* Its own UI would be a second portal; Grafana integrates Tempo natively with Loki and TraceQL.
- *Alternative: distributed Tempo with object storage (or finanzBuddy's MinIO).* Same reasoning as Loki: needless at home-server volume, and MinIO would couple the root stack to one service.
- *Alternative: metrics generator with `span-metrics` and `service-graphs` remote-writing to Prometheus.* Prometheus would need `--web.enable-remote-write-receiver`, and because Prometheus is a member of every metrics network, any product API could then write arbitrary series into it. TraceQL metrics on `local-blocks` give the dashboard its rate, errors, and duration without that exposure. The span metrics' `service` label would also clash with the `service` scrape label convention.

### Alloy is the only trace receiver; Tempo stays off the metrics networks

Services need a reachable OTLP endpoint across stacks. Putting Tempo itself on the metrics networks would also expose its query API on port 3200 to every product API, so a compromised `calendar-api` could read finanzBuddy's traces. Instead the existing `homebuddy-alloy` joins the three metrics networks and receives traces:

1. `otelcol.receiver.otlp` with only an HTTP endpoint on `0.0.0.0:4318` (no gRPC, so a single, simple port).
2. `otelcol.processor.attributes` deletes span attributes whose keys match credentials and cookies (`http.request.header.authorization`, `http.request.header.cookie`, `http.response.header.set-cookie`, and any key matching `(?i).*(password|token|secret).*`).
3. `otelcol.processor.batch`, then `otelcol.exporter.otlp` to `tempo:4317` with TLS disabled (traffic stays on the root default network).

Alloy's own HTTP server (UI, debug, and its `/metrics`) is moved from the default `0.0.0.0:12345` to `127.0.0.1:12345` with `--server.http.listen-addr`, so on the metrics networks only 4318 is reachable. Services address the collector by container name, `http://homebuddy-alloy:4318`, which resolves on every network Alloy joins, consistent with Prometheus addressing targets by container name.

- *Alternative: separate `<service>-telemetry` networks.* Cleaner separation from scraping, but three more networks that operators create by hand on every host for the same trust boundary (the root stack ↔ one service). The metrics networks already are that boundary.
- *Alternative: a second, trace-only Alloy without the Docker socket.* Lowers the privileges of the container that product APIs can reach. Rejected for now because only the OTLP port is reachable and Alloy has no API that exposes the socket; recorded as a risk and a cheap follow-up if wanted.
- *Alternative: services export directly to Tempo.* Removes one hop but exposes Tempo's query API and loses the attribute scrubbing.

Alloy keeps no persistent queue for traces: if Tempo is down, its exporter retries with the default in-memory queue and drops spans when it is full. Traces are diagnostic; losing some during an outage of the root stack is acceptable.

### Instrumentation in the services: Spring Boot's OpenTelemetry support

Each per-service change adds Spring Boot 4's OpenTelemetry starter (`spring-boot-starter-opentelemetry`, Micrometer Tracing with the OpenTelemetry bridge and the OTLP exporter) and configures it through environment variables in its `docker-compose.yml`:

- OTLP tracing endpoint `http://homebuddy-alloy:4318/v1/traces` in `MANAGEMENT_OPENTELEMETRY_TRACING_EXPORT_OTLP_ENDPOINT` (Boot 4.1 property `management.opentelemetry.tracing.export.otlp.endpoint`), set only in Compose: Boot creates the span exporter only when the property is present, so tests and host runs export nothing.
- `management.tracing.sampling.probability: 1.0` in `application.yml` (Boot's default is 0.1), overridden through `MANAGEMENT_TRACING_SAMPLING_PROBABILITY`, which each Compose file fills from a per-component `.env` variable (`<COMPONENT>_TRACING_SAMPLING_PROBABILITY`). Micrometer's default sampler is parent-based, so a downstream component follows the caller's decision.
- `management.otlp.metrics.export.enabled: false` and `management.logging.export.otlp.enabled: false`: the starter also brings the OTLP meter registry, which would otherwise push metrics to `localhost:4318`.
- Resource attributes `service.name=<service>-<component>` and `service.namespace=<service>` via `management.opentelemetry.resource-attributes`.
- W3C propagation (`management.tracing.propagation.type=w3c`, the default).

Observed automatically: incoming Spring MVC requests (span name `http <method> <route template>`), Spring Security's filter-chain and authorization steps, Spring Kafka templates and listeners once observation is enabled (`spring.kafka.template.observation-enabled=true`, or `setObservationEnabled(true)` on factories and templates a service builds itself), and `@Scheduled` methods. HTTP clients are observed when they carry the `ObservationRegistry`; in Boot 4 the auto-configured `RestClient.Builder` and `RestTemplateBuilder` come only with a separate REST client module that no component uses, so clients set the registry themselves. Per-service specifics:

- Product APIs give their `NimbusJwtDecoder` a `RestTemplate` with the observation registry, so the JWKS fetch is a client span in the request trace.
- finanzBuddy stores the W3C `traceparent` of the upload request in the outbox row (a new nullable column) and `OutboxRelay` publishes each event inside a span whose parent is that context, so upload → Kafka → parser → status callback is one trace. Rows written before the migration have no context and start new traces.
- `parser-service`'s `RestClientConfig` builds its own `RestClient.Builder`; it sets the observation registry on it, so `GatewayStatusClient` callbacks are client spans.
- Health checks and scrapes of `/actuator/**` and finanzBuddy's `@Scheduled` polls would create a trace every few seconds. A `SpanExportingPredicate` drops those spans before export, and an `ObservationPredicate` skips Spring Security observations inside actuator requests, whose spans would otherwise be exported without their parent. Observations still run, so metrics are unchanged.
- authBuddy wrote no log line per request; it now logs each sign-in outcome (no e-mail or address), so a sign-in can be found from its trace.

The OTLP exporter sends asynchronously with a bounded queue and short timeout, so an unreachable collector only causes dropped spans and periodic warnings in the log.

- *Alternative: the OpenTelemetry Java agent.* No code changes and broader auto-instrumentation (JDBC, Kafka), but a `-javaagent` in every Dockerfile, an agent version separate from Spring Boot's dependency management (and Renovate), slower startup, and a second instrumentation layer next to Micrometer's existing metrics observations. Spring's native support covers HTTP and Kafka, which are the calls that matter here.

### Trace ids in logs and the Grafana links

With tracing on the classpath Spring Boot adds the correlation id to its default console pattern: `[<traceId>-<spanId>]`, 32 and 16 lowercase hex characters, empty outside a trace. Services keep their current log format otherwise. If a service sets its own `logging.pattern.console`, its change must keep `%correlation` (or the equivalent `logging.pattern.correlation`) in it.

Grafana provisioning:

- Datasource `tempo` (uid `tempo`, URL `http://tempo:3200`, not default, not editable) with `tracesToLogsV2` to uid `loki`, mapping the span's `service.namespace` to the Loki label `service`, `filterByTraceID: true`, and a time shift of ±5 minutes; `nodeGraph` disabled because there is no service graph; `search.hide: false`; TraceQL editor default.
- The `loki` datasource from `add-homebuddy-logging` gets a derived field `TraceID` with regex `\[([0-9a-f]{32})-[0-9a-f]{16}\]` and an internal link to uid `tempo` with the query `${__value.raw}`.
- `monitoring/grafana/dashboards/homebuddy/homebuddy-traces.json` (uid `homebuddy-traces`) with `service` and `component` variables (values from Tempo tag `resource.service.namespace` and `resource.service.name`) and panels: request rate per component (`{resource.service.namespace=~"$service" && kind=server} | rate() by (resource.service.name)`), error rate (`{... && kind=server && status=error} | rate() by (resource.service.name)`), p95 duration (`{... && kind=server} | quantile_over_time(duration, .95) by (resource.service.name)`), a table of recent error traces, and a table of the slowest recent traces. The `homebuddy-overview` dashboard gets a link to it, next to the logs link.

### Compose and startup order

`tempo` gets no profile, no published port, the `json-file` log rotation that `add-homebuddy-logging` sets on root services, and a healthcheck on `/ready`. The Tempo image is distroless and runs as uid 10001, while a new named volume is owned by root; a one-shot `tempo-init` container (`busybox`, `network_mode: none`) hands `tempo-data` to uid 10001 before Tempo starts. Alloy gets the three metrics networks as additional external networks and `depends_on: tempo` (started, not healthy, so log collection starts even if Tempo is slow). Grafana does not depend on Tempo. The compose header gains a short "Tracing" note: services send OTLP to `homebuddy-alloy:4318` over their metrics network, nothing is published, traces are read in Grafana.

## Risks / Trade-offs

- [Alloy, which holds the read-only Docker socket, becomes reachable from product APIs] → Only its OTLP HTTP receiver listens on non-loopback addresses; its UI and debug endpoints are bound to localhost; the image is pinned and official. A separate trace-only Alloy without the socket remains an easy follow-up.
- [A service floods the collector with spans] → The batch processor and the exporter queue are bounded; overflowing spans are dropped. Operators can lower that component's sampling probability.
- [Personal data in span attributes, such as identifiers in `url.path` or exception messages containing e-mail addresses] → Span names use route templates, the collector scrubs credential attributes, retention is 15 days, and traces are reachable only behind the Grafana sign-in. The verification searches traces for the test password, token, and e-mail address. Record identifiers in URL paths remain in `url.path`, which is acceptable for an operator view with the same access rules as logs.
- [Trace context lost across the outbox for events written before the migration] → Those events start a new trace in `OutboxRelay`; only the first minutes after deployment are affected.
- [100 % sampling increases CPU and storage] → Home-server traffic is low; storage is bounded by 15-day retention; the README documents how to check `tempo-data` and how to lower sampling.
- [Spring Boot 4 property names for OTLP export differ from Boot 3] → The per-service tasks verify against the 4.1 reference and confirm with a trace arriving in Tempo.
- [Changing `add-homebuddy-monitoring`'s network membership rule after it is merged] → Delivered as a MODIFIED requirement here; this change is archived after monitoring, so the delta applies to the synced spec.

## Migration Plan

1. Implement and deploy `add-homebuddy-monitoring`, then `add-homebuddy-logging`.
2. Root: merge this change and run `docker compose up -d` (locally) or `docker compose -f docker-compose.yml --profile production up -d` (production). The metrics networks already exist; no new variables or DNS records are needed. Alloy is recreated with the additional networks.
3. Services, in any order: deploy `add-auth-tracing`, `add-calendar-tracing`, `add-finanz-tracing` (the finanzBuddy change includes a Liquibase migration adding the nullable outbox column).
4. Verify traces, links, and the dashboard.

Rollback: services can disable export through Spring Boot's tracing export switch in their environment (or by reverting their change) without other effects. In the root, remove `tempo`, the Tempo datasource, the derived field, the dashboard, Alloy's OTLP pipeline, and its metrics network attachments. The `tempo-data` volume can be removed afterwards.
