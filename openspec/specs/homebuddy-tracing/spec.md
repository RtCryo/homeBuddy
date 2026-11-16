# homebuddy-tracing Specification

## Purpose
Defines the single homeBuddy trace stack: how every service component exports distributed traces, how they reach the central trace store without weakening stack isolation, which data spans may carry, and how operators read traces next to logs and metrics in the Grafana portal.

## Requirements

### Requirement: One central trace store serves every service
The root `docker-compose.yml` SHALL run the only trace store of a homeBuddy host, and its configuration SHALL be tracked in the root repository. The central telemetry collector defined by `homebuddy-logging` SHALL be the only receiver of traces from services and SHALL forward them to the trace store. A service stack SHALL NOT run its own trace store or trace collector. The trace stack SHALL run without a Compose profile, so it starts both in local development and with the `production` profile. The trace store SHALL keep traces in a named volume, so they survive recreating its container.

#### Scenario: Start tracing locally
- **WHEN** a developer runs `docker compose up -d` in the root workspace
- **THEN** the trace store starts together with the monitoring and log stack, and the collector accepts traces

#### Scenario: Recreate the trace store
- **WHEN** an operator recreates the trace store container
- **THEN** traces stored before remain searchable

### Requirement: Services send traces to the collector over their metrics network
Every application component SHALL send its spans with OTLP over HTTP to `http://homebuddy-alloy:4318`, reaching the collector over that service's `<service>-metrics` network as defined by `homebuddy-monitoring`. A service SHALL NOT join any other network of the root stack to send traces. Only the collector's trace receiver SHALL be reachable on the metrics networks; the trace store SHALL be reachable only from the root stack's own network. A component SHALL keep serving requests with unchanged behavior and latency when the collector is unavailable, and SHALL drop spans it cannot deliver instead of buffering them without limit.

#### Scenario: A product API exports a span
- **WHEN** `calendarbuddy-calendar-api` finishes handling a request
- **THEN** its spans reach the collector over `calendarbuddy-metrics` and are searchable in the trace store within one minute

#### Scenario: A service tries to reach the trace store directly
- **WHEN** a container of any service stack resolves or connects to the trace store
- **THEN** the name does not resolve, because the trace store joins no network that a service stack joins

#### Scenario: Collector unavailable
- **WHEN** the collector is stopped while a user signs in and calls a product API
- **THEN** sign-in and the API call succeed as before, and the components only log that spans could not be exported

### Requirement: Traces follow one naming and propagation convention
Every span SHALL carry the resource attributes `service.name`, set to `<service>-<component>` (the same value as the component's scrape job, for example `finanzbuddy-api-gateway`), and `service.namespace`, set to the lowercase service name (`authbuddy`, `finanzbuddy`, `calendarbuddy`). Components SHALL propagate trace context with the W3C Trace Context headers on every HTTP call and in the headers of every Kafka message between homeBuddy components, so that one request forms one trace across components and services. A message published asynchronously on behalf of a request, such as through an outbox, SHALL continue the trace of that request.

#### Scenario: Request across two services
- **WHEN** a product API validates a token and fetches authBuddy's signing keys during a request
- **THEN** the product API's request span and its outgoing call to authBuddy belong to the same trace

#### Scenario: Document upload through Kafka
- **WHEN** a user uploads a statement to finanzBuddy and the parser processes it
- **THEN** the upload request, the Kafka publish, the parser's processing, and its status callback appear in one trace with `finanzbuddy-api-gateway` and `finanzbuddy-parser-service` spans

#### Scenario: Search by service
- **WHEN** an operator searches traces with `resource.service.namespace = "calendarbuddy"`
- **THEN** the result contains traces of calendarBuddy's components and of no other service unless they took part in the same trace

### Requirement: Every request is sampled by default
Every component SHALL record and export all traces by default (sampling probability 1.0). Operators SHALL be able to lower the sampling probability of a component through its environment without rebuilding it. A component that receives a request with a sampling decision in its trace context SHALL follow that decision, so traces are never split.

#### Scenario: Default sampling
- **WHEN** a component runs without a sampling override and handles ten requests
- **THEN** ten traces are stored

#### Scenario: Downstream follows the caller
- **WHEN** a caller with a lowered sampling probability decides not to sample a request and calls another component
- **THEN** the called component does not record that request either

### Requirement: Spans do not carry secrets or personal data
Span names and attributes SHALL NOT contain passwords, password hashes, access or refresh tokens, signing keys, cookies, `Authorization` headers, request or response bodies, e-mail addresses, or financial values. Span names SHALL use route templates instead of concrete paths. The collector SHALL remove attributes named for credentials or cookies (such as `http.request.header.authorization` and `http.request.header.cookie`) before storing a span, as a second line of defense. Because exception messages can quote user input or document content, the collector SHALL also remove span status messages and exception messages and stack traces from spans and span events, keeping only the exception type. A service that finds such data in its spans SHALL remove it in its own change.

#### Scenario: A user signs in
- **WHEN** a user signs in to authBuddy and then calls a product API with the issued token
- **THEN** no stored span contains the password, the token, or the e-mail address

#### Scenario: A request fails with an exception
- **WHEN** a component records an exception whose message quotes a value from the request or a document
- **THEN** the stored span keeps its error status and the exception type, but no status message, exception message, or stack trace

#### Scenario: Span names stay bounded
- **WHEN** many different appointments are read by their identifier
- **THEN** the server spans share one name built from the route template, not one name per identifier

### Requirement: Traces are retained for 15 days
The trace store SHALL delete traces older than 15 days. Traces SHALL NOT be copied to any other store.

#### Scenario: Old traces expire
- **WHEN** a trace is older than 15 days
- **THEN** it is no longer returned by any search and its storage is reclaimed

### Requirement: Traces and logs are linked
Every log line that a component writes while handling a traced request SHALL contain the trace id and span id of the current span. The central Grafana SHALL have the trace store provisioned as a datasource, without manual setup, with a link from each span to the log lines of its service that contain its trace id, and the log datasource defined by `homebuddy-logging` SHALL turn the trace id in a log line into a link to that trace.

#### Scenario: From a log line to its trace
- **WHEN** an operator opens an error line of `finanzbuddy-api-gateway` in the logs dashboard
- **THEN** the line shows a link that opens the trace of the request that wrote it

#### Scenario: From a span to its logs
- **WHEN** an operator opens a span of `calendarbuddy-calendar-api` in a trace
- **THEN** a link shows the log lines of calendarBuddy that contain that trace id

### Requirement: Traces are read only through the Grafana portal
The `homeBuddy` Grafana folder SHALL contain a provisioned traces dashboard that shows request rate, error rate, and duration per component computed from traces and lets an operator search recent and failed traces by service and component, and the homeBuddy overview SHALL link to it. The trace store and the collector SHALL NOT be published as host ports or routed through Traefik, in production or locally, so that traces are reachable only through Grafana and its sign-in.

#### Scenario: Operator searches failed requests
- **WHEN** a signed-in operator opens the traces dashboard and selects finanzBuddy
- **THEN** recent traces with an error status of finanzBuddy's components are listed and open in the trace view

#### Scenario: Traces without a sign-in
- **WHEN** someone without a Grafana session tries to read traces through any public domain or host port
- **THEN** no trace is returned

### Requirement: New services join tracing in their umbrella change
A new service's umbrella change SHALL attach the collector to the service's metrics network and include a per-service change in which every application component exports traces following this capability.

#### Scenario: Add a fourth service
- **WHEN** a new service is added to the workspace
- **THEN** after its umbrella change its requests appear as traces in the Grafana portal with its own `service.namespace`
