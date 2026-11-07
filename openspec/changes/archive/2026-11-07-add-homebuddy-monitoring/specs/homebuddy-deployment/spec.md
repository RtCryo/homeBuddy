# Spec Delta

## MODIFIED Requirements

### Requirement: Services connect over the homebuddy network
Product UIs and authBuddy SHALL join the external Docker network `homebuddy`. authBuddy SHALL be reachable on it as `auth`, and each product UI as `<service>-ui`. A product API SHALL NOT join `homebuddy`. Each product API SHALL instead reach authBuddy over its own external, internal-only identity network named `<service>-identity`, whose members are only that API and authBuddy. authBuddy SHALL be reachable as `auth` on every identity network, so the JWKS URI is the same for every consumer. A product API SHALL NOT be reachable from another stack, except by the central Prometheus over that service's metrics network as defined by the root capability `homebuddy-monitoring`. Operators SHALL create each identity network with `docker network create --internal <name>` on every host, because Compose cannot create a network that only a product API and authBuddy join. A new product service SHALL add its identity network to the root Compose file header, the architecture documentation, and authBuddy in its umbrella change.

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
- **THEN** the connection succeeds over that service's metrics network, and no other root container can make it

#### Scenario: Missing identity network
- **WHEN** a product API stack starts on a host where its identity network does not exist
- **THEN** startup fails with a message naming the missing network

### Requirement: One shared Traefik serves all product domains
The root `docker-compose.yml` SHALL provide the `homebuddy` network and, under the `production` profile, the only Traefik that binds ports 80 and 443 on a host running several homeBuddy services. Product UIs SHALL be routed through Traefik labels naming the `homebuddy` network and a per-service domain variable. The central Grafana SHALL be routed the same way on the domain in `MONITORING_DOMAIN`. A service-local Traefik SHALL be used only for a standalone deployment of that service.

#### Scenario: Two products on one host
- **WHEN** finanzBuddy and calendarBuddy run in production on the same host
- **THEN** the shared Traefik routes each domain to its UI and no other container binds ports 80 or 443

#### Scenario: Monitoring portal on the shared entry point
- **WHEN** the root stack runs in production with `MONITORING_DOMAIN` set
- **THEN** the shared Traefik routes that domain to the central Grafana over HTTPS

### Requirement: Names and local ports do not collide
Container names SHALL use the `<service>-` prefix; containers of the root stack SHALL use the `homebuddy-` prefix. Local host ports SHALL follow the port registry in the root architecture documentation: homeBuddy monitoring 3001 (Grafana), 9090 (Prometheus); finanzBuddy 3000, 5432, 8080, 9000, 29092; calendarBuddy 3010, 8081, 5433; authBuddy 8090, 5434. A new service SHALL claim unused ports in its umbrella change.

#### Scenario: Run all stacks locally
- **WHEN** a developer starts the root stack, authBuddy, finanzBuddy, and calendarBuddy on one machine
- **THEN** no container name or host port conflicts occur
