# Spec Delta

## MODIFIED Requirements

### Requirement: Services connect over the homebuddy network
Product UIs and authBuddy SHALL join the external Docker network `homebuddy`. authBuddy SHALL be reachable on it as `auth`, and each product UI as `<service>-ui`. A product API SHALL NOT join `homebuddy`. Each product API SHALL instead reach authBuddy over its own external, internal-only identity network named `<service>-identity`, whose members are only that API and authBuddy. authBuddy SHALL be reachable as `auth` on every identity network, so the JWKS URI is the same for every consumer. A product API SHALL NOT be reachable from another stack, except by the central Prometheus over that service's metrics network as defined by the root capability `homebuddy-monitoring`. The central telemetry collector also joins the metrics networks, but only to receive telemetry; it SHALL NOT connect to a product API. Operators SHALL create each identity network with `docker network create --internal <name>` on every host, because Compose cannot create a network that only a product API and authBuddy join. A new product service SHALL add its identity network to the root Compose file header, the architecture documentation, and authBuddy in its umbrella change.

#### Scenario: A UI reaches the identity service
- **WHEN** a product UI container resolves `auth` on the `homebuddy` network
- **THEN** it reaches authBuddy

#### Scenario: A product API fetches the signing keys
- **WHEN** a product API requests `http://auth:8080/.well-known/jwks.json`
- **THEN** the request reaches authBuddy over that API's identity network

#### Scenario: Another stack tries to call a product API
- **WHEN** a container of another stack, such as the other product's UI or API, connects to a product API by its service or container name
- **THEN** the name does not resolve, and the connection fails

#### Scenario: The central Prometheus scrapes a product API
- **WHEN** the central Prometheus connects to a product API by its container name
- **THEN** the connection succeeds over that service's metrics network, and no root container other than Prometheus and the telemetry collector can resolve the API

#### Scenario: A product API sends telemetry
- **WHEN** a product API sends traces to the central telemetry collector
- **THEN** the connection succeeds over that service's metrics network, and the collector does not open connections to the API

#### Scenario: Missing identity network
- **WHEN** a product API stack starts on a host where its identity network does not exist
- **THEN** startup fails with a message naming the missing network
