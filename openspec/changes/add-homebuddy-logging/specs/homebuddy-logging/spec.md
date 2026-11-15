# Spec Delta

## Purpose

Defines the single homeBuddy log stack: which container logs are collected centrally, how they are labeled and retained, how operators search them in the Grafana portal, and what every service may and may not write to its log.

## ADDED Requirements

### Requirement: One central log store serves every service
The root `docker-compose.yml` SHALL run the only log store and the only log collector of a homeBuddy host, and their configuration SHALL be tracked in the root repository. A service stack SHALL NOT run its own log store or log collector. The log stack SHALL run without a Compose profile, so it starts both in local development and with the `production` profile. The log store SHALL keep log entries in a named volume, so they survive recreating its container.

#### Scenario: Start logging locally
- **WHEN** a developer runs `docker compose up -d` in the root workspace
- **THEN** the central log store and log collector start together with the monitoring stack

#### Scenario: Recreate the log store
- **WHEN** an operator recreates the log store container
- **THEN** log entries written before remain searchable

### Requirement: Logs of every homeBuddy container are collected
The collector SHALL collect the standard output and standard error of every running container whose name starts with `homebuddy-`, `authbuddy-`, `finanzbuddy-`, or `calendarbuddy-`, including containers started after the collector. It SHALL NOT collect logs of any other container on the host. Services SHALL write their logs to standard output or standard error; logs written only to files inside a container are not collected. Collecting logs SHALL NOT require a service stack to join a network of the root stack or to change its configuration.

#### Scenario: A service container writes a log line
- **WHEN** `calendarbuddy-calendar-api` writes a line to standard output
- **THEN** the line is searchable in the central log store within one minute

#### Scenario: A container starts later
- **WHEN** a service stack is started after the root stack
- **THEN** its containers' logs are collected without restarting the collector

#### Scenario: A foreign container on the same host
- **WHEN** a container whose name has no homeBuddy service prefix writes to standard output
- **THEN** its log lines are not stored

### Requirement: Log entries follow one label convention
Every log entry SHALL carry the labels `service` (the lowercase service name, the same value as the `service` metric label: `authbuddy`, `finanzbuddy`, `calendarbuddy`, or `homebuddy` for the root stack), `component` (the Compose service name), `container` (the container name), and `stream` (`stdout` or `stderr`). Labels SHALL NOT be derived from the content of a log line, so the number of label combinations does not grow with traffic, accounts, or records.

#### Scenario: Filter logs by service
- **WHEN** an operator queries logs with `{service="finanzbuddy"}`
- **THEN** the result contains the logs of every finanzBuddy container and of no other service

#### Scenario: Labels stay bounded
- **WHEN** many accounts sign in and many requests are logged
- **THEN** the set of label combinations stays limited to the running containers and their two streams

### Requirement: Logs are retained for 15 days
The log store SHALL delete log entries older than 15 days. Log entries SHALL NOT be copied to any other store.

#### Scenario: Old entries expire
- **WHEN** a log entry is older than 15 days
- **THEN** it is no longer returned by any query and its storage is reclaimed

### Requirement: Logs are read only through the Grafana portal
The central Grafana defined by `homebuddy-monitoring` SHALL have the log store provisioned as a datasource, without manual setup. The `homeBuddy` folder SHALL contain a provisioned logs dashboard showing the log volume per service, recent error output, and a log view filterable by service and component, and the homeBuddy overview SHALL link to it. The log store and the collector SHALL NOT be published as host ports or routed through Traefik, in production or locally, so that logs are reachable only through Grafana and its sign-in.

#### Scenario: Operator searches logs
- **WHEN** a signed-in operator opens the logs dashboard and selects calendarBuddy
- **THEN** recent log lines of every calendarBuddy container are shown, with the container and stream of each line

#### Scenario: Logs without a sign-in
- **WHEN** someone without a Grafana session tries to read logs through any public domain or host port
- **THEN** no log entry is returned

### Requirement: Services do not log secrets
Every service SHALL NOT write passwords, password hashes, access tokens, refresh tokens, signing keys, session cookies, or full request or response bodies to its log. A service that finds such output in its log SHALL remove it in its own change.

#### Scenario: A user signs in
- **WHEN** a user signs in to authBuddy and then calls a product API with the issued token
- **THEN** no log entry of any service contains the password or the token
