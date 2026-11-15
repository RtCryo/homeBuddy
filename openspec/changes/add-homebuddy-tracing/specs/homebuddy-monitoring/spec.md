# Spec Delta

## MODIFIED Requirements

### Requirement: Prometheus reaches each service over its own metrics network
Each service SHALL have an external, internal-only Docker network named `<service>-metrics` (`authbuddy-metrics`, `finanzbuddy-metrics`, `calendarbuddy-metrics`). Its members SHALL be only the central Prometheus, the central telemetry collector defined by `homebuddy-logging`, and that service's application components and scrape targets. The central Prometheus SHALL use it to scrape the service, and the service's components SHALL use it to send traces to the collector as defined by `homebuddy-tracing`. The central Prometheus and the collector SHALL join every metrics network and SHALL NOT join `homebuddy` or any identity network. Operators SHALL create each metrics network once on every host with `docker network create --internal <name>`; the root compose header SHALL list the commands.

#### Scenario: Prometheus scrapes a product API
- **WHEN** the central Prometheus scrapes `calendarbuddy-calendar-api:8080`
- **THEN** the request reaches calendarBuddy's API over `calendarbuddy-metrics`

#### Scenario: A product API sends traces
- **WHEN** `calendarbuddy-calendar-api` sends spans to `homebuddy-alloy`
- **THEN** they reach the collector over `calendarbuddy-metrics`

#### Scenario: Another stack tries to use a metrics network
- **WHEN** a container of finanzBuddy tries to resolve `calendarbuddy-calendar-api`
- **THEN** the name does not resolve, because finanzBuddy's containers are not members of `calendarbuddy-metrics`

#### Scenario: Missing metrics network
- **WHEN** a service stack or the root monitoring stack starts on a host where a metrics network it joins does not exist
- **THEN** startup fails with a message naming the missing network
