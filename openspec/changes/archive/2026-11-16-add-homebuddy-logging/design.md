# Design

## Context

Every service container already has a `<service>-` container name (`authbuddy-auth-service`, `finanzbuddy-api-gateway`, `calendarbuddy-ui`, ...) and writes its logs to stdout and stderr, which Docker stores with the default `json-file` driver. No service writes log files that matter, and only finanzBuddy's `parser-service` sets log levels in `application.yml`; nothing configures a log format or shipper.

`add-homebuddy-monitoring` (not yet implemented) adds to the root stack: `homebuddy-prometheus` and `homebuddy-grafana` without a profile, `monitoring/` with Grafana provisioning (datasource uid `prometheus`, one file provider per folder `homeBuddy`, `authBuddy`, `finanzBuddy`, `calendarBuddy`), the `homebuddy-overview` home dashboard, Grafana behind Traefik on `MONITORING_DOMAIN` with a required admin password, and a root `docker-compose.override.yml` for local ports. This change builds on those files and must be implemented after it.

Stack isolation (`homebuddy-deployment`) is based on network membership: product APIs are reachable only over their identity and metrics networks.

## Goals / Non-Goals

**Goals:**

- Searchable logs of every homeBuddy container in the existing Grafana portal, behind its sign-in.
- No change to any service repository and no new path between stacks.
- Bounded storage: 15 days, one volume, single-binary deployment.

**Non-Goals:**

- Structured logging, traces, log alerting, log rotation of service stacks (see proposal).

## Decisions

### Loki in single-binary mode with filesystem storage

`loki` runs as `homebuddy-loki` from the `grafana/loki` image, pinned to the latest stable 3.x release at implementation time, with `-target=all`. Configuration in `monitoring/loki/loki.yml`: `auth_enabled: false` (one tenant), `common.storage.filesystem` under `/loki` in the named volume `loki-data`, `replication_factor: 1`, in-memory ring, TSDB index with schema `v13`, and the compactor with `retention_enabled: true` and `limits_config.retention_period: 360h`. Loki joins only the root project's default network, where Grafana and Alloy reach it as `loki:3100`.

- *Alternative: simple scalable or microservices mode with object storage.* Built for horizontal scale; a home server produces a few hundred MB of logs per day at most, so it adds containers and an object store for nothing.
- *Alternative: store Loki chunks in finanzBuddy's MinIO.* Couples the root stack to one service and breaks when finanzBuddy is not deployed.

`auth_enabled: false` is safe only because Loki is reachable on the root default network alone: no service stack joins that network, Traefik does not route Loki, and no host port is published.

### Alloy as the collector, reading the Docker API

`alloy` runs as `homebuddy-alloy` from the `grafana/alloy` image (latest stable at implementation time) with `monitoring/alloy/config.alloy` mounted read-only and `/var/run/docker.sock` mounted read-only, like Traefik. The pipeline:

1. `discovery.docker` lists containers on the host and refreshes every few seconds, so containers started later are picked up.
2. `discovery.relabel` keeps only containers whose name matches `^/(homebuddy|authbuddy|finanzbuddy|calendarbuddy)-.*`, and sets `service` from that prefix, `component` from the `com.docker.compose.service` label, `container` from the name without the leading slash, and `stream` from the log stream.
3. `loki.source.docker` tails the kept containers through the Docker API and forwards to `loki.write` with endpoint `http://loki:3100/loki/api/v1/push`.

Alloy stores its read positions in a small named volume `alloy-data`, so a restart neither drops nor duplicates many lines. Alloy joins only the root default network; its own UI on port 12345 is not published.

- *Alternative: Promtail.* Grafana has deprecated Promtail in favor of Alloy, and it no longer receives feature releases.
- *Alternative: the Docker Loki logging driver.* Every service compose file would have to set `logging.driver: loki`, which needs a plugin installed on every host and changes all service repositories. If Loki is down, the driver can block container output. Alloy needs neither.
- *Alternative: tail `/var/lib/docker/containers/*/*.log` from the host.* Works only on Linux hosts with that layout and loses container metadata; Docker Desktop on the Windows development machines does not expose that path in the same way.

Taking `service` from the container name prefix rather than the Compose project label keeps it equal to the metric `service` label even if a stack is started with a different project name.

### Labels stay minimal; level detection stays in Loki

Only `service`, `component`, `container`, and `stream` are labels. Loki 3 detects log levels from line content into structured metadata (`detected_level`) by default, so the dashboard can filter by level without a label and without parsing service-specific formats in Alloy. Without structured logs that detection is best-effort, which is acceptable for an operator's view.

### Grafana integration

`monitoring/grafana/provisioning/datasources/` gets a second datasource: type `loki`, uid `loki`, URL `http://loki:3100`, not default, not editable. `monitoring/grafana/dashboards/homebuddy/homebuddy-logs.json` (uid `homebuddy-logs`) has a `service` and a `component` template variable fed from Loki label values and three panels: log volume per service (`sum by (service) (count_over_time({service=~"$service"}[$__auto]))`), error lines (`{service=~"$service", component=~"$component"} |~ "(?i)\\b(error|exception|fatal)\\b"`), and the log view of the selected streams. The `homebuddy-overview` dashboard gets a link to it. Grafana Explore with the Loki datasource remains available for ad-hoc queries.

### Startup order and compose header

Alloy `depends_on` Loki; Grafana does not, because a missing Loki only empties the log panels and must not stop metrics. Neither service has a profile. The compose header gains a short "Logging" note: Loki and Alloy always run, nothing is published, and logs are read in Grafana. Root containers also get `logging.options` (`max-size: 10m`, `max-file: 3`) so that the root stack's own Docker logs stay bounded; service stacks are unchanged.

### Logging convention verified, not implemented, by the root

The "no secrets in logs" requirement is a root convention. This change checks it once against all running services (sign-in, token use, uploads, appointments) by searching Loki. A finding becomes a follow-up change in the owning service repository; it does not block this change unless it exposes a password or token, in which case the rollout to production waits for the fix.

## Risks / Trade-offs

- [Docker socket access: read-only socket access still allows full Docker API reads, including environment variables of every container] → Same exposure as the existing Traefik; Alloy runs a pinned official image with a read-only config, publishes no port, and joins no network besides the root default network.
- [Logs contain personal data such as e-mail addresses in error messages] → Retention is limited to 15 days, logs are reachable only through Grafana's sign-in, and the secrets convention is verified. Removing personal data from logs is out of scope.
- [Service stacks' own Docker logs grow without rotation] → Unchanged by this change; Loki retention does not affect Docker's local files. Listed as a non-goal; a later convention can add rotation.
- [Loki down or slow] → Alloy buffers and retries without limit (`max_backoff_retries = 0`; the default of 10 drops a batch), so lines written meanwhile are sent when Loki returns. Restarting Alloy during the outage loses the batch held in memory; the experimental `loki.write` WAL does not replay it after a restart in Alloy v1.22, so it is not used. Metrics and services are unaffected.
- [Disk usage of `loki-data`] → Bounded by 15-day retention; the README documents how to check the volume size.
- [Error panel relies on keywords] → Best-effort without structured logs; services can adopt structured logging later without changing this contract.

## Migration Plan

1. Implement and deploy `add-homebuddy-monitoring` first.
2. Merge this change and run `docker compose up -d` (locally) or `docker compose -f docker-compose.yml --profile production up -d` (production) in the root workspace. No new networks, variables, or DNS records are needed.
3. Verify collection and the logs dashboard.

Rollback: stop and remove `loki` and `alloy` and the Loki datasource and dashboard. Services are unaffected. The `loki-data` and `alloy-data` volumes can be removed afterwards.

## Open Questions

- None.
