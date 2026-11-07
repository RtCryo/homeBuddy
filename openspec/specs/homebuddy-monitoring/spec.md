# homebuddy-monitoring Specification

## Purpose
Defines the single homeBuddy monitoring stack: how every service exposes metrics, how the central Prometheus reaches them without weakening stack isolation, and how operators reach one Grafana portal for all services.

## Requirements

### Requirement: One central monitoring stack serves every service
The root `docker-compose.yml` SHALL run the only Prometheus and the only Grafana of a homeBuddy host, and their configuration and provisioned dashboards SHALL be tracked in the root repository. A service stack SHALL NOT run its own Prometheus or Grafana. The central stack SHALL run without a Compose profile, so it starts both in local development and with the `production` profile. Prometheus SHALL retain samples for 15 days in a named volume.

#### Scenario: Start monitoring locally
- **WHEN** a developer runs `docker compose up -d` in the root workspace
- **THEN** the central Prometheus and Grafana start, and no service stack starts another Prometheus or Grafana

#### Scenario: Start the production stack
- **WHEN** an operator runs `docker compose -f docker-compose.yml --profile production up -d` in the root workspace
- **THEN** the shared Traefik, the central Prometheus, and the central Grafana are running

### Requirement: Prometheus reaches each service over its own metrics network
Each service SHALL have an external, internal-only Docker network named `<service>-metrics` (`authbuddy-metrics`, `finanzbuddy-metrics`, `calendarbuddy-metrics`). Its members SHALL be only the central Prometheus and that service's scrape targets. The central Prometheus SHALL join every metrics network and SHALL NOT join `homebuddy` or any identity network. Operators SHALL create each metrics network once on every host with `docker network create --internal <name>`; the root compose header SHALL list the commands.

#### Scenario: Prometheus scrapes a product API
- **WHEN** the central Prometheus scrapes `calendarbuddy-calendar-api:8080`
- **THEN** the request reaches calendarBuddy's API over `calendarbuddy-metrics`

#### Scenario: Another stack tries to use a metrics network
- **WHEN** a container of finanzBuddy tries to resolve `calendarbuddy-calendar-api`
- **THEN** the name does not resolve, because finanzBuddy's containers are not members of `calendarbuddy-metrics`

#### Scenario: Missing metrics network
- **WHEN** a service stack or the root monitoring stack starts on a host where a metrics network it joins does not exist
- **THEN** startup fails with a message naming the missing network

### Requirement: Scrape targets follow one naming convention
Every scrape job SHALL be named `<service>-<component>` (for example `finanzbuddy-api-gateway`, `authbuddy-auth-service`), SHALL address its target by container name, and SHALL attach a `service` label whose value is the lowercase service name (`authbuddy`, `finanzbuddy`, `calendarbuddy`; `homebuddy` for the monitoring stack itself). Prometheus SHALL report each target that cannot be scraped as down.

#### Scenario: Query availability per service
- **WHEN** an operator queries `up` grouped by `service` and `job`
- **THEN** every scrape target of every service appears once, with its service and job

#### Scenario: A service is not running
- **WHEN** a service's stack is stopped or not deployed on the host
- **THEN** its targets are reported as down and the other services are unaffected

### Requirement: Every service exposes privacy-preserving Prometheus metrics
Every application component of every service SHALL expose Prometheus metrics, including availability, uptime, HTTP request rate, latency, and errors, and JVM resource usage for JVM services. Each service SHALL also expose metrics for its main business operations, specified in that service's own specification. Metrics SHALL use only bounded label values and SHALL NOT contain account or user identifiers, e-mail addresses, document or appointment identifiers, names, filenames, financial values, or other sensitive data. The metrics endpoint SHALL NOT be reachable through Traefik or through any UI proxy route.

#### Scenario: Scrape an application component
- **WHEN** the central Prometheus scrapes any application component of authBuddy, finanzBuddy, or calendarBuddy
- **THEN** it receives HTTP, uptime, and business metrics in Prometheus format

#### Scenario: Metrics from a browser
- **WHEN** a browser requests the metrics path through any public domain or UI origin
- **THEN** the request does not reach a metrics endpoint

#### Scenario: Labels stay bounded
- **WHEN** many different accounts sign in, upload documents, or create appointments
- **THEN** the number of metric series does not grow with the number of accounts or records, and no series carries personal data

### Requirement: Grafana is the single monitoring portal
Grafana SHALL be provisioned with the central Prometheus as its default datasource and with all dashboards, without manual setup. Its home dashboard SHALL be a homeBuddy overview that shows the availability and uptime of every scrape target grouped by service and links to each service's folder. Each service SHALL have one Grafana folder, named after the service (`authBuddy`, `finanzBuddy`, `calendarBuddy`), containing its dashboards; every service SHALL have at least one dashboard with its HTTP and business signals. Dashboard identifiers SHALL start with the lowercase service name. Provisioned dashboards SHALL NOT be editable or deletable from the Grafana UI. A panel without samples SHALL show that no data is available instead of a misleading zero.

#### Scenario: Operator opens Grafana
- **WHEN** an operator signs in to Grafana
- **THEN** the homeBuddy overview opens and shows authBuddy, finanzBuddy, and calendarBuddy with the state of each target

#### Scenario: Operator opens a service folder
- **WHEN** an operator opens the calendarBuddy folder
- **THEN** it contains calendarBuddy's dashboards with its HTTP and business signals

### Requirement: Grafana and Prometheus access is restricted
Locally, Grafana SHALL be reachable at `http://localhost:3001` and Prometheus at `http://localhost:9090`. In production, Grafana SHALL be reachable only through the shared Traefik over HTTPS on the domain in `MONITORING_DOMAIN`, and Prometheus SHALL NOT be published as a host port or routed through Traefik. Grafana SHALL require a sign-in, SHALL NOT allow anonymous access or self sign-up, and SHALL take its admin password from `GRAFANA_ADMIN_PASSWORD`; the monitoring stack SHALL NOT start without it.

#### Scenario: Open the portal in production
- **WHEN** an operator opens `https://<MONITORING_DOMAIN>` without a session
- **THEN** Grafana shows its sign-in page over a valid TLS certificate, and no dashboard is visible before sign-in

#### Scenario: Prometheus in production
- **WHEN** the production stack is running
- **THEN** Prometheus is reachable only by Grafana inside the root stack, not from the host network or any public domain

#### Scenario: Missing admin password
- **WHEN** the root stack starts without `GRAFANA_ADMIN_PASSWORD`
- **THEN** Compose refuses to start and names the missing variable

### Requirement: New services join monitoring in their umbrella change
A new service's umbrella change SHALL add its metrics network to the root compose header and the architecture documentation, its scrape jobs and dashboards folder to the root monitoring configuration, and a per-service change that exposes its metrics and joins its metrics network.

#### Scenario: Add a fourth service
- **WHEN** a new service is added to the workspace
- **THEN** after its umbrella change it appears on the homeBuddy overview with its own folder and metrics network
