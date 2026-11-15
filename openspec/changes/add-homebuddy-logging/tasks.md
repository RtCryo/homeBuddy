# Tasks

## 1. Prerequisite

- [ ] 1.1 Confirm that `add-homebuddy-monitoring` is implemented on the target branch: `homebuddy-grafana` and `homebuddy-prometheus` exist in the root `docker-compose.yml`, and `monitoring/grafana/provisioning/` and `monitoring/grafana/dashboards/homebuddy/homebuddy-overview.json` exist. Verify that `docker compose config` succeeds in the root workspace.

## 2. Root workspace: Loki and Alloy

- [ ] 2.1 Add `monitoring/loki/loki.yml` as described in design.md (single binary, `auth_enabled: false`, filesystem storage under `/loki`, TSDB schema `v13`, compactor retention enabled, `retention_period: 360h`). Pin the latest stable `grafana/loki` 3.x image. Verify with `docker run --rm -v ./monitoring/loki:/etc/loki grafana/loki:<version> -config.file=/etc/loki/loki.yml -verify-config`.
- [ ] 2.2 Add `monitoring/alloy/config.alloy` with `discovery.docker`, `discovery.relabel` (keep only `homebuddy-`, `authbuddy-`, `finanzbuddy-`, `calendarbuddy-` containers; set `service`, `component`, `container`, `stream`), `loki.source.docker`, and `loki.write` to `http://loki:3100/loki/api/v1/push`. Pin the latest stable `grafana/alloy` image. Verify with `docker run --rm -v ./monitoring/alloy:/etc/alloy grafana/alloy:<version> fmt /etc/alloy/config.alloy` and that Alloy starts without component errors in its log.
- [ ] 2.3 Add `loki` (`homebuddy-loki`) and `alloy` (`homebuddy-alloy`) to the root `docker-compose.yml` without a profile, on the default network only, with named volumes `loki-data` and `alloy-data`, the read-only Docker socket and config mounts for Alloy, `depends_on: loki` for Alloy, and `json-file` log rotation (`max-size: 10m`, `max-file: 3`) on all root services. Add the "Logging" note to the compose header. Verify that `docker compose config` and `docker compose -f docker-compose.yml --profile production config` succeed and that neither config publishes a port for `loki` or `alloy`, including with `docker-compose.override.yml`.

## 3. Root workspace: Grafana

- [ ] 3.1 Add the Loki datasource (uid `loki`, URL `http://loki:3100`, not default, not editable) to `monitoring/grafana/provisioning/datasources/`. Verify that Grafana starts locally without provisioning errors and that Explore with the Loki datasource returns lines for `{service="homebuddy"}`.
- [ ] 3.2 Add `monitoring/grafana/dashboards/homebuddy/homebuddy-logs.json` (uid `homebuddy-logs`) with the `service` and `component` variables and the log volume, error lines, and log view panels from design.md, and add a link to it on `homebuddy-overview`. Verify that the dashboard appears in the `homeBuddy` folder, cannot be edited or deleted in the UI, loads without panel errors, and that the overview link opens it.

## 4. Root workspace: documentation

- [ ] 4.1 Update `docs/ARCHITECTURE.md`: topology with Loki and Alloy in the root stack, the log flow (Docker API → Alloy → Loki → Grafana), the label convention, 15-day retention, and the fact that neither publishes a port. Update the root `README.md`: logging starts with the root stack, where to find logs in Grafana, and how to check the `loki-data` volume size. Verify that every documented container name, volume, and port matches `docker compose config`.

## 5. Verification

- [ ] 5.1 Start the root stack and all three service stacks locally. Verify in Grafana that `{service="authbuddy"}`, `{service="finanzbuddy"}`, `{service="calendarbuddy"}`, and `{service="homebuddy"}` each return lines from every running container of that service, with correct `component`, `container`, and `stream` labels, and that a line written by `calendarbuddy-calendar-api` appears within one minute.
- [ ] 5.2 Start a foreign container (`docker run --rm --name logtest alpine echo foreign-line`) and verify that `{container="logtest"}` and a search for `foreign-line` return nothing. Restart one service stack after Alloy and verify that its new containers are collected without restarting Alloy.
- [ ] 5.3 Verify that Loki labels stay bounded: list label names and values with `logcli` or the Loki API and confirm only `service`, `component`, `container`, `stream` (plus Loki-internal labels) exist and that their values correspond to running containers.
- [ ] 5.4 Verify the secrets convention: sign up and sign in to authBuddy, call both product APIs with the issued token, upload a statement in finanzBuddy, and create an appointment in calendarBuddy. Search Loki for the test password, the token (and a `eyJ` prefix), and `Authorization:`. Record any finding; open a follow-up change in the owning service repository, and hold the production rollout if a password or token is found.
- [ ] 5.5 Verify retention configuration: query Loki's `/config` endpoint from inside the root network and confirm `retention_period: 360h` and compactor retention enabled. Recreate `homebuddy-loki` and verify that earlier lines are still searchable.
- [ ] 5.6 Verify production on one host with `docker compose -f docker-compose.yml --profile production up -d`: no container besides Traefik binds a host port, `https://<MONITORING_DOMAIN>` without a session shows no logs, and after sign-in the logs dashboard shows all three services. Verify that `homebuddy-loki` does not resolve from `finanzbuddy-api-gateway`, `calendarbuddy-ui`, or `authbuddy-auth-service`.

## 6. Archive

- [ ] 6.1 Run `openspec validate add-homebuddy-logging --strict` and archive this change after `add-homebuddy-monitoring` has been archived, so `homebuddy-monitoring` exists in `openspec/specs/` when this change is synced.
