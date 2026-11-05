# homebuddy-deployment Specification

## Purpose
Defines the conventions that let independent homeBuddy stacks run together on one host.

## Requirements

### Requirement: Services connect over the homebuddy network
Services that talk to another homeBuddy service SHALL join the external Docker network `homebuddy`. authBuddy SHALL be reachable on it as `auth`, and each product UI as `<service>-ui`. A product API SHALL NOT be reachable from another stack unless a root contract requires it.

#### Scenario: A UI reaches the identity service
- **WHEN** a product UI container resolves `auth` on the `homebuddy` network
- **THEN** it reaches authBuddy

### Requirement: Product UIs share one routing pattern
Every product UI SHALL serve its browser application from one origin, proxy `/api/auth/` to authBuddy before its own `/api/` rule, and proxy other `/api/` requests to its own API.

#### Scenario: Sign in from any product
- **WHEN** a browser posts to `/api/auth/login` on finanzBuddy's or calendarBuddy's origin
- **THEN** authBuddy handles the request

### Requirement: One shared Traefik serves all product domains
The root `docker-compose.yml` SHALL provide the `homebuddy` network and, under the `production` profile, the only Traefik that binds ports 80 and 443 on a host running several homeBuddy services. Product UIs SHALL be routed through Traefik labels naming the `homebuddy` network and a per-service domain variable. A service-local Traefik SHALL be used only for a standalone deployment of that service.

#### Scenario: Two products on one host
- **WHEN** finanzBuddy and calendarBuddy run in production on the same host
- **THEN** the shared Traefik routes each domain to its UI and no other container binds ports 80 or 443

### Requirement: Names and local ports do not collide
Container names SHALL use the `<service>-` prefix. Local host ports SHALL follow the port registry in the root architecture documentation: finanzBuddy 3000, 3001, 5432, 8080, 9000, 9090, 29092; calendarBuddy 3010, 8081, 5433; authBuddy 8090, 5434. A new service SHALL claim unused ports in its umbrella change.

#### Scenario: Run all stacks locally
- **WHEN** a developer starts authBuddy, finanzBuddy, and calendarBuddy on one machine
- **THEN** no container name or host port conflicts occur
