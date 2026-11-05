# homebuddy-workspace Specification

## Purpose
Defines the homeBuddy root workspace and where specifications are written.

## Requirements

### Requirement: The root repository tracks only workspace files
The root repository SHALL track workspace documentation, the service manifest `repos.txt`, the repository scripts, shared infrastructure, and the root `openspec/`. It SHALL ignore every service folder listed in the manifest; each service SHALL remain an independent Git repository with its own history, remote, CI, and `openspec/`.

#### Scenario: Service changes do not appear in the root
- **WHEN** a contributor changes files inside `calendarBuddy/`
- **THEN** the root repository reports no change and the change is committed in the calendarBuddy repository

### Requirement: Service repositories are managed from the manifest
`scripts/repos.sh` and `scripts/repos.ps1` SHALL offer `clone`, `pull`, and `status` with identical behavior. `clone` SHALL clone each missing repository at its manifest branch and SHALL skip present repositories. `pull` SHALL only fast-forward repositories with a clean working tree and an `origin` remote. `status` SHALL show branch, number of changed files, and ahead/behind counts. The scripts SHALL never commit, push, reset, delete, or overwrite a folder that is not a Git repository, and SHALL exit non-zero when any repository fails.

#### Scenario: Set up a new workspace
- **WHEN** a contributor clones the root repository and runs `scripts/repos.sh clone`
- **THEN** every repository in the manifest is cloned into its folder

#### Scenario: Pull with local changes
- **WHEN** a repository has uncommitted changes and the contributor runs `pull`
- **THEN** that repository is skipped and reported, and the others are updated

#### Scenario: Unreachable remote
- **WHEN** a manifest URL cannot be cloned
- **THEN** the script reports that repository, continues with the others, and exits non-zero

### Requirement: Specifications are placed by scope
Contracts between services, conventions every service follows, and umbrella changes that order several service changes SHALL be specified in the root `openspec/`. Behavior inside one service SHALL be specified in that service's `openspec/`, linking to the root capability it satisfies. A root change SHALL list and link every per-service change it coordinates with its rollout order and SHALL NOT contain service implementation tasks.

#### Scenario: A change touches several services
- **WHEN** a feature requires changes in authBuddy and calendarBuddy
- **THEN** an umbrella change in the root defines the contract and order, and each repository has its own change implementing its part

#### Scenario: A change touches one service
- **WHEN** a feature changes only calendarBuddy behavior without affecting a contract
- **THEN** it is specified only in calendarBuddy's `openspec/`
