## MODIFIED Requirements

### Requirement: Services connect over the homebuddy network
Product UIs and authBuddy SHALL join the external Docker network `homebuddy`. authBuddy SHALL be reachable on it as `auth`, and each product UI as `<service>-ui`. A product API SHALL NOT join `homebuddy`. Each product API SHALL instead reach authBuddy over its own external, internal-only identity network named `<service>-identity`, whose members are only that API and authBuddy. authBuddy SHALL be reachable as `auth` on every identity network, so the JWKS URI is the same for every consumer. A product API SHALL NOT be reachable from another stack unless a root contract requires it. Operators SHALL create each identity network with `docker network create --internal <name>` on every host, because Compose cannot create a network that only a product API and authBuddy join. A new product service SHALL add its identity network to the root Compose file header, the architecture documentation, and authBuddy in its umbrella change.

#### Scenario: A UI reaches the identity service
- **WHEN** a product UI container resolves `auth` on the `homebuddy` network
- **THEN** it reaches authBuddy

#### Scenario: A product API fetches the signing keys
- **WHEN** a product API requests `http://auth:8080/.well-known/jwks.json`
- **THEN** the request reaches authBuddy over that API's identity network

#### Scenario: Another stack tries to call a product API
- **WHEN** a container of another stack, such as the other product's UI or API, connects to a product API by its service or container name
- **THEN** the name does not resolve, and the connection fails

#### Scenario: Missing identity network
- **WHEN** a product API stack starts on a host where its identity network does not exist
- **THEN** startup fails with a message naming the missing network
