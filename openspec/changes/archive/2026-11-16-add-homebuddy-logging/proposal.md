# Proposal

## Why

homeBuddy has no central place for logs. To understand a failed sign-in, a rejected upload, or a crashing container, an operator has to SSH into the host and run `docker logs` container by container, and the output disappears when a container is recreated. `add-homebuddy-monitoring` gives every service metrics in one Grafana portal but explicitly leaves logs out. Grafana Loki adds the missing half: searchable logs of every service in the same portal, next to the metrics.

## What Changes

- Add Grafana Loki to the root `docker-compose.yml` as the single log store of a host: single-binary mode, filesystem storage in a named volume, 15-day retention (the same as Prometheus), unpublished in production and locally.
- Add Grafana Alloy to the root stack as the single log collector. It reads the stdout and stderr of every homeBuddy container (container names starting with `homebuddy-`, `authbuddy-`, `finanzbuddy-`, `calendarbuddy-`) through the read-only Docker socket and pushes them to Loki. Containers of other projects on the same host are not collected.
- Define one log label convention: `service` (the same values as the `service` metric label), `component`, `container`, and `stream`. No label is derived from log content.
- Provision Loki as a second Grafana datasource and add a `homebuddy-logs` dashboard in the `homeBuddy` folder (log volume per service, error lines, a log browser filtered by service and component), linked from the homeBuddy overview.
- Add a root logging convention: services log to stdout and stderr only, and never write passwords, tokens, signing keys, or full request bodies to the log.
- No service repository changes: services keep their current log format, and no service compose file changes. Configuration lives in a new `monitoring/loki/` and `monitoring/alloy/` next to the monitoring configuration.
- Update `docs/ARCHITECTURE.md`, the root `README.md`, and the root compose header.

## Capabilities

### New Capabilities

- `homebuddy-logging`: Central Loki and Alloy, which containers are collected, the log label convention, retention, access to logs only through the Grafana portal, and the rules every service follows for what it logs.

### Modified Capabilities

- None. The Grafana portal and its access rules are defined by `homebuddy-monitoring` in the in-flight change `add-homebuddy-monitoring`; this change references them instead of modifying them. Loki and Alloy publish no host port, so the port registry in `homebuddy-deployment` is unchanged.

## Coordinated per-service changes

None. All services already write their logs to stdout and stderr, which is everything the collector needs. If the verification of the logging convention (no secrets in logs) finds a violation, the owning service fixes it in its own follow-up change.

Rollout order: `add-homebuddy-monitoring` first, because it creates the central Grafana and the root `monitoring/` folder; this change follows on the same hosts.

## Non-goals

- Structured (JSON) logging, log-level parsing into labels, or trace correlation in the services.
- Traces (Tempo, OpenTelemetry) and log-based alerting.
- Changing the Docker log driver or log rotation of the service stacks.
- Collecting host system logs or logs of containers outside homeBuddy.
- Multi-tenant Loki, object storage for Loki, or retention longer than 15 days.

## Impact

- Root: `docker-compose.yml` (services `loki` and `alloy`, a named volume), new `monitoring/loki/loki.yml`, new `monitoring/alloy/config.alloy`, a Loki datasource and the `homebuddy-logs` dashboard under `monitoring/grafana/`, a link on the `homebuddy-overview` dashboard, `README.md`, `docs/ARCHITECTURE.md`, new `openspec/specs/homebuddy-logging`.
- Service repositories: none.
- Operators: no new variables, networks, or DNS records. Disk space for 15 days of logs in the `loki-data` volume. Alloy gets read-only access to the Docker socket, as Traefik already has.
