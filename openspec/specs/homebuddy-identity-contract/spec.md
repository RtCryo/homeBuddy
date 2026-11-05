# homebuddy-identity-contract Specification

## Purpose
Defines the single homeBuddy account token that every homeBuddy service issues or accepts.

## Requirements

### Requirement: authBuddy is the only issuer of homeBuddy account tokens
Only authBuddy SHALL issue user tokens. A token SHALL be an RS256 JWT with a `kid` header and the claims `iss` = `homebuddy-auth`, `sub` = the account UUID, `email`, `aud` = an array of service audience names, `iat`, and `exp`. The subject SHALL never change for an account. Audience names SHALL be the lower-case service names. Other services SHALL NOT issue user tokens or accept tokens signed with a shared secret.

#### Scenario: Token issued for a family
- **WHEN** a family signs in
- **THEN** the token contains its account UUID as subject and the audiences of every product service it may use

#### Scenario: A service tries to issue its own token
- **WHEN** a product service would need to authenticate users itself
- **THEN** it delegates to authBuddy instead, because only authBuddy issues user tokens

### Requirement: Services validate tokens the same way
Every consuming service SHALL verify the signature with a key from authBuddy's JWKS selected by `kid`, cache the keys and refresh them on an unknown `kid`, require the issuer `homebuddy-auth` and its own audience, reject expired tokens with at most 60 seconds of clock skew, and identify the account only by `sub`. It SHALL keep at most a local projection of the account (id, email, service-specific settings) and SHALL update the stored email when the claim changes.

#### Scenario: Token for another audience
- **WHEN** a token whose audience does not include `calendarbuddy` reaches calendarBuddy
- **THEN** calendarBuddy rejects it with 401

#### Scenario: Key rotation
- **WHEN** authBuddy starts signing with a new key published in its JWKS
- **THEN** every consuming service accepts the new tokens without a restart

#### Scenario: Email change
- **WHEN** an account's email changes in authBuddy and a new token is presented
- **THEN** the consuming service keeps the same local account and updates its stored email

### Requirement: New services join the contract explicitly
A new homeBuddy service SHALL receive its audience name through an umbrella change that adds it to authBuddy's issued audiences and documents the service as a consumer.

#### Scenario: Add a new product service
- **WHEN** a third product service is introduced
- **THEN** its umbrella change adds its audience to authBuddy and the service validates tokens according to this contract
