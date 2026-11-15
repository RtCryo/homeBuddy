# Spec Delta

## Purpose

Defines how every homeBuddy repository is checked, versioned, and released, and how production hosts run released images instead of building from source.

## ADDED Requirements

### Requirement: Every service repository runs the CI baseline
Each service repository SHALL run one CI workflow on every pull request to `main` and every push to `main`, and on no other branch trigger. For every component it SHALL check formatting or lint, compile, and run the component's tests. It SHALL build every deployable Docker image of the repository without pushing it, validate the production Compose configuration (`docker compose -f docker-compose.yml config`) and the development configuration (`docker compose config`), and run `openspec validate --all --strict` with a pinned OpenSpec version. Repository-specific checks MAY be added as further jobs of the same workflow. A new service repository SHALL adopt the baseline in its umbrella change.

#### Scenario: A pull request breaks formatting
- **WHEN** a pull request to `main` contains a Java file that violates the repository's formatter rules
- **THEN** the CI workflow fails

#### Scenario: A pull request breaks a Dockerfile
- **WHEN** a pull request changes a component so that its Docker image no longer builds
- **THEN** the CI workflow fails, although every test passes

#### Scenario: A push to a feature branch
- **WHEN** a contributor pushes to a branch other than `main` without opening a pull request
- **THEN** the CI workflow does not run

### Requirement: One gate check reports the CI result
The CI workflow of every repository, root included, SHALL report one status check named `ci` on every pull request and every push to `main`, regardless of which files changed. `ci` SHALL succeed only when every job that the change selected succeeded, and SHALL fail when any selected job failed or was cancelled. Jobs not selected for the changed files SHALL count as passed.

#### Scenario: Documentation-only pull request
- **WHEN** a pull request changes only Markdown files outside every component
- **THEN** the component jobs are skipped and `ci` is reported as successful

#### Scenario: One component fails
- **WHEN** a pull request changes two components and the tests of one fail
- **THEN** `ci` is reported as failed

### Requirement: Main is protected and history follows Conventional Commits
In every repository, `main` SHALL accept changes only through pull requests whose `ci` check and pull-request title check succeeded. Pull requests SHALL be merged by squash, with the pull-request title as the commit subject. The pull-request title check SHALL require a Conventional Commits title with one of the types `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`, or `revert`, and SHALL mark a breaking change with `!`. Automated dependency pull requests SHALL use Conventional Commits titles as well.

#### Scenario: Non-conventional title
- **WHEN** a pull request is titled `Update login page`
- **THEN** the title check fails and the pull request cannot be merged

#### Scenario: Dependency update
- **WHEN** Renovate opens a pull request that updates a dependency
- **THEN** its title starts with `chore(deps):` or `fix(deps):` and the title check passes

### Requirement: Each service repository is versioned and released as one unit
Each service repository SHALL carry one SemVer version for all of its components, recorded in Git tags `vX.Y.Z`. After every push to `main` that adds releasable commits, the repository SHALL maintain one open release pull request that proposes the next version and the `CHANGELOG.md` entries derived from the commits since the last release: a `fix` or `perf` raises the patch version, a `feat` the minor version, and a breaking change the major version. Merging the release pull request SHALL create the tag and a GitHub Release whose notes are the changelog entries. No release SHALL be created any other way.

#### Scenario: A fix is merged
- **WHEN** `fix: reject expired refresh tokens` is merged into authBuddy's `main` and the latest release is `v1.2.0`
- **THEN** the release pull request proposes `v1.2.1` and lists the fix in `CHANGELOG.md`

#### Scenario: A breaking change is merged
- **WHEN** `feat!: drop the legacy login endpoint` is merged and the latest release is `v1.2.1`
- **THEN** the release pull request proposes `v2.0.0`

#### Scenario: Only maintenance commits
- **WHEN** only `docs`, `test`, `ci`, or `chore` commits were merged since the last release
- **THEN** no release pull request proposes a new version

#### Scenario: The release pull request is merged
- **WHEN** a maintainer merges the release pull request for `v1.3.0`
- **THEN** the tag `v1.3.0` and a GitHub Release `v1.3.0` exist, and the release pull request is closed

### Requirement: A release publishes every deployable image
When a release is created, every deployable component of the repository SHALL be built from the tagged commit and pushed to `ghcr.io/rtcryo/<service>-<component>`, where `<service>` is the lowercase repository name, with the tags `X.Y.Z` and `X.Y`. Each image SHALL carry the OCI labels for version, source repository, and revision, and SHALL have a GitHub build provenance attestation. The packages SHALL be public and linked to their repository. The GitHub Release notes SHALL list every published image reference with its digest. An image tag `X.Y.Z` SHALL never be overwritten once pushed; re-running the publication for a version SHALL push only images whose `X.Y.Z` tag is missing. No image SHALL be tagged `latest`.

#### Scenario: calendarBuddy releases a version
- **WHEN** calendarBuddy releases `v1.4.0`
- **THEN** `ghcr.io/rtcryo/calendarbuddy-calendar-api:1.4.0` and `ghcr.io/rtcryo/calendarbuddy-ui:1.4.0` exist, `1.4` points to the same digests, and the GitHub Release lists both references with digests

#### Scenario: Publication fails halfway
- **WHEN** finanzBuddy's release `v2.1.0` pushed `finanzbuddy-api-gateway:2.1.0` but failed before pushing the other images, and a maintainer re-runs the publication
- **THEN** the missing images are pushed, `finanzbuddy-api-gateway:2.1.0` keeps its original digest, and the release notes list all three images

#### Scenario: Verify an image's origin
- **WHEN** an operator runs `gh attestation verify oci://ghcr.io/rtcryo/authbuddy-auth-service:1.0.0 --owner RtCryo`
- **THEN** the verification succeeds and names the authBuddy release workflow and the tagged commit

### Requirement: Production runs released images
The production Compose file (`docker-compose.yml`) of every service repository SHALL reference each deployable component by its published image, pinned to the version variable `<SERVICE>_VERSION` (`AUTHBUDDY_VERSION`, `FINANZBUDDY_VERSION`, `CALENDARBUDDY_VERSION`) and SHALL NOT build images. Starting it without that variable SHALL fail with a message naming the variable. Local development (`docker compose` with `docker-compose.override.yml`) SHALL build every component from the working tree instead. `.env.example` SHALL name the latest released version. Deploying and rolling back SHALL consist of setting the variable to a released version, pulling, and recreating the stack.

#### Scenario: Deploy a release
- **WHEN** an operator sets `CALENDARBUDDY_VERSION=1.4.0` and runs `docker compose -f docker-compose.yml pull` and `up -d`
- **THEN** the calendarBuddy containers run the `1.4.0` images without building and without a registry login

#### Scenario: Version variable missing
- **WHEN** an operator runs `docker compose -f docker-compose.yml up -d` in authBuddy without `AUTHBUDDY_VERSION`
- **THEN** Compose fails with a message naming `AUTHBUDDY_VERSION`

#### Scenario: Local development
- **WHEN** a developer runs `docker compose up --build` in finanzBuddy
- **THEN** every finanzBuddy component image is built from the working tree and no image is pulled from GHCR for them

### Requirement: The root workspace has CI
The root repository SHALL run a CI workflow on every pull request to `main` and every push to `main` that validates the root OpenSpec with `--strict`, validates the root Compose file with and without the `production` profile, lints `scripts/repos.sh` with ShellCheck, and tests `scripts/repos.sh` under bash and `scripts/repos.ps1` under Windows PowerShell 5.1 and PowerShell 7 against the same fixture repositories. The test SHALL fail when the two scripts differ in output or exit code for any of `clone`, `pull`, and `status`. The root repository SHALL NOT be released.

#### Scenario: The scripts drift apart
- **WHEN** a pull request changes the message `repos.sh` prints for a skipped repository without changing `repos.ps1`
- **THEN** the parity test fails and `ci` fails

#### Scenario: A clone fails
- **WHEN** the fixture manifest contains an unreachable repository
- **THEN** the test expects both scripts to report it, continue with the others, and exit non-zero
