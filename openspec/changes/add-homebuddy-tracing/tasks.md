# Tasks

## 1. Prerequisites and per-service proposals

- [x] 1.1 Confirm that `add-homebuddy-monitoring` and `add-homebuddy-logging` are implemented on the target branch: `homebuddy-prometheus`, `homebuddy-grafana`, `homebuddy-loki`, and `homebuddy-alloy` exist in the root `docker-compose.yml`, `monitoring/alloy/config.alloy` and the Loki datasource exist, and every service compose file attaches its application components to `<service>-metrics`. Verify that `docker compose config` succeeds in the root workspace.
- [x] 1.2 Propose the per-service changes in their repositories, each on its own branch: authBuddy [`add-auth-tracing`](../../../authBuddy/openspec/changes/add-auth-tracing/proposal.md), calendarBuddy [`add-calendar-tracing`](../../../calendarBuddy/openspec/changes/add-calendar-tracing/proposal.md), and finanzBuddy [`add-finanz-tracing`](../../../finanzBuddy/openspec/changes/add-finanz-tracing/proposal.md). Each references `homebuddy-tracing` instead of restating it and names its `service.name` values, its traced outgoing calls (JWKS fetch for the product APIs; outbox, Kafka, and status callback for finanzBuddy), and how its log pattern keeps the trace id. The finanzBuddy change includes the outbox trace-context column and the switch of `parser-service`'s `RestClientConfig` to the injected builder. Verify that `openspec validate <change> --strict` passes in each repository and that the links in proposal.md resolve.

## 2. Root workspace: Tempo and the trace pipeline

- [x] 2.1 Add `monitoring/tempo/tempo.yml` as described in design.md (HTTP 3200, OTLP gRPC receiver on 4317 only, local storage under `/var/tempo`, `block_retention: 360h`, metrics generator with only the `local-blocks` processor and `flush_to_storage: true`). Pin the latest stable `grafana/tempo` 2.x image. Verify that `homebuddy-tempo` starts and `/ready` returns 200 from inside the root network.
- [x] 2.2 Extend `monitoring/alloy/config.alloy` with `otelcol.receiver.otlp` (HTTP on `0.0.0.0:4318` only), `otelcol.processor.attributes` deleting the credential and cookie keys from design.md, `otelcol.processor.batch`, and `otelcol.exporter.otlp` to `tempo:4317` without TLS. Start Alloy with `--server.http.listen-addr=127.0.0.1:12345`. Verify with `alloy fmt`, that Alloy starts without component errors, and that a test span posted to `http://homebuddy-alloy:4318/v1/traces` with an `http.request.header.authorization` attribute is found in Tempo without that attribute.
- [ ] 2.3 Add `tempo` (`homebuddy-tempo`) to the root `docker-compose.yml` without a profile, on the default network only, with the named volume `tempo-data`, a read-only config mount, the root log rotation, and a `/ready` healthcheck. Attach `alloy` to the external networks `authbuddy-metrics`, `finanzbuddy-metrics`, and `calendarbuddy-metrics` and add `depends_on: tempo`. Add the "Tracing" note to the compose header. Verify that `docker compose config` and `docker compose -f docker-compose.yml --profile production config` succeed, that neither publishes a port for `tempo` or `alloy` (including with `docker-compose.override.yml`), and that `homebuddy-tempo` is on the default network only.

## 3. Root workspace: Grafana

- [x] 3.1 Add the Tempo datasource (uid `tempo`, URL `http://tempo:3200`, not default, not editable, `tracesToLogsV2` to uid `loki` mapping `service.namespace` to `service` with trace-id filtering) to `monitoring/grafana/provisioning/datasources/`, and the `TraceID` derived field with an internal link to uid `tempo` on the Loki datasource. Verify that Grafana starts without provisioning errors and that Explore with the Tempo datasource finds the test span from 2.2.
- [x] 3.2 Add `monitoring/grafana/dashboards/homebuddy/homebuddy-traces.json` (uid `homebuddy-traces`) with the `service` and `component` variables and the rate, error-rate, p95-duration, recent-error-traces, and slowest-traces panels from design.md, and add a link to it on `homebuddy-overview`. Verify that the dashboard appears in the `homeBuddy` folder, cannot be edited or deleted in the UI, loads without panel errors (panels show "no data" while no service sends traces), and that the overview link opens it.

## 4. Root workspace: documentation

- [x] 4.1 Update `docs/ARCHITECTURE.md`: topology with Tempo in the root stack and Alloy on the metrics networks, the trace flow (component → OTLP/HTTP `homebuddy-alloy:4318` over `<service>-metrics` → Alloy → Tempo → Grafana), the resource attribute and propagation convention, 15-day retention, the trace-log links, and that nothing is published. Update the root `README.md`: tracing starts with the root stack, where to find traces in Grafana, how to lower a component's sampling probability, and how to check the `tempo-data` volume size. Verify that every documented container name, network, volume, port, and variable matches `docker compose config`.

## 5. Coordinated rollout

- [x] 5.1 authBuddy: implement `add-auth-tracing`. Verify that a sign-in produces a trace with `service.name = "authbuddy-auth-service"` and that the matching log line in Loki contains its trace id.
- [x] 5.2 calendarBuddy: implement `add-calendar-tracing`. Verify that creating an appointment produces a trace with `service.name = "calendarbuddy-calendar-api"`, a span name built from the route template, and, after a restart of `calendar-api`, a JWKS client span to authBuddy in the first authenticated request's trace.
- [x] 5.3 finanzBuddy: implement `add-finanz-tracing`. Verify that one statement upload produces one trace containing the `api-gateway` upload request, the outbox publish, the `parser-service` consumer span, and the status callback.
- [x] 5.4 Check that the metrics networks Alloy joins in the root compose match the set in every service compose file and in `docs/ARCHITECTURE.md`, by comparing the `docker compose config` output of each stack.

## 6. Verification

- [x] 6.1 Verify isolation with all stacks running: `homebuddy-tempo` does not resolve from `authbuddy-auth-service`, `finanzbuddy-api-gateway`, `finanzbuddy-parser-service`, `calendarbuddy-calendar-api`, or any UI; from `calendarbuddy-calendar-api`, `homebuddy-alloy:4318` is reachable but `homebuddy-alloy:12345` is not; the names `finanzbuddy-api-gateway` and `calendarbuddy-calendar-api` still do not resolve from the other service's containers.
- [x] 6.2 Verify resilience: stop `homebuddy-alloy`, then sign in, create an appointment, and upload a statement. All succeed with normal response times, and the services only log export warnings. Start Alloy again and verify that new requests are traced without restarting any service.
- [x] 6.3 Verify the privacy rules: after the flows in 5.1–5.3 with a known test password and e-mail address, search Tempo with TraceQL for the password, the token (and an `eyJ` prefix), the e-mail address, and any `http.request.header.*` attribute. Record any finding; open a follow-up change in the owning service repository, and hold the production rollout if a password or token is found.
- [ ] 6.4 Verify the Grafana links: from an error line of `finanzbuddy-api-gateway` in `homebuddy-logs` the TraceID link opens its trace, and from a span of `calendarbuddy-calendar-api` the logs link shows that request's calendarBuddy log lines.
- [x] 6.5 Verify sampling: set `MANAGEMENT_TRACING_SAMPLING_PROBABILITY=0` on `calendar-api`, recreate it, and confirm that its requests produce no traces while other components still do; restore the default.
- [x] 6.6 Verify retention and persistence: query Tempo's `/status/config` from inside the root network and confirm `block_retention: 360h`; recreate `homebuddy-tempo` and confirm that earlier traces are still found.
- [x] 6.7 Verify production on one host with `docker compose -f docker-compose.yml --profile production up -d`: no container besides Traefik binds a host port, `https://<MONITORING_DOMAIN>` without a session shows no traces, and after sign-in the traces dashboard shows all three services.

## 7. Archive

- [ ] 7.1 Archive the per-service changes in their repositories. Then run `openspec validate add-homebuddy-tracing --strict` and archive this change after `add-homebuddy-monitoring` and `add-homebuddy-logging` have been archived, so that `homebuddy-monitoring` and `homebuddy-logging` exist in `openspec/specs/` when this change is synced.
