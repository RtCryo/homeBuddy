# Proposal

## Why

Each service repository grew its own GitHub Actions setup, and they no longer agree: calendarBuddy runs CI on every branch without a `main` filter or code-style check, finanzBuddy still triggers on long-gone feature branches and skips Compose and OpenSpec validation, and only authBuddy builds its Docker image in CI. Path-filtered workflows also cannot be used as required checks, so no repository can protect `main`. Nothing is ever released: there are no tags, no changelog, and every production host builds images from whatever source is checked out, so a deployment cannot be reproduced, compared, or rolled back. The root workspace has no CI at all, although its scripts must stay identical across bash and PowerShell.

## What Changes

- Add a root contract `homebuddy-delivery` that every service repository follows:
  - **CI baseline**: one CI workflow per service repository that runs on pull requests to `main` and pushes to `main`, checks format or lint, compiles and tests every component, builds every deployable Docker image without pushing it, validates the production and development Compose configuration, and validates OpenSpec with `--strict`. A single always-reported gate check named `ci` summarizes the result and is the required status check for `main`.
  - **Conventional Commits**: pull requests are squash-merged, and their titles follow Conventional Commits, enforced by a check. Renovate uses semantic commit titles.
  - **Releases**: release-please keeps a release pull request with the next SemVer version and `CHANGELOG.md` per repository. Merging it tags `vX.Y.Z`, creates a GitHub Release, and publishes every deployable image of that repository to GHCR as `ghcr.io/rtcryo/<service>-<component>` with the tags `X.Y.Z` and `X.Y`, OCI labels, and a build provenance attestation. The release notes list the published image references.
  - **Deployment from releases**: production Compose files reference the published images pinned by a per-service version variable (`AUTHBUDDY_VERSION`, `FINANZBUDDY_VERSION`, `CALENDARBUDDY_VERSION`). Local development keeps building from source through `docker-compose.override.yml`. Deployment and rollback stay manual: an operator changes the version and pulls.
- Add root CI for the workspace: OpenSpec validation, a behavior and parity test of `scripts/repos.sh` and `scripts/repos.ps1` (bash, Windows PowerShell 5.1, PowerShell 7), ShellCheck, and validation of the root Compose file.
- Each service repository replaces its existing workflows with the baseline and the release workflow; service-specific extra checks (finanzBuddy's documentation integrity and SeaweedFS smoke test, coverage upload) stay as additional jobs.
- **BREAKING (deployment)**: `docker compose -f docker-compose.yml up -d` in a service repository no longer builds images; it pulls the released version named in `.env`. Starting a production stack without the version variable fails with a message naming it.
- Update `README.md` and `docs/ARCHITECTURE.md` with the delivery flow, image names, and version variables.

## Capabilities

### New Capabilities

- `homebuddy-delivery`: CI baseline and required gate check, Conventional Commits and merge policy, versioning and the release flow, image naming, tagging and provenance, how production consumes released images, and the root workspace CI.

### Modified Capabilities

None. `homebuddy-workspace` already requires each service to keep its own CI, and `homebuddy-deployment` defines networks, routing, and ports, which this change does not alter.

## Coordinated per-service changes

| Order | Repository | Change | Delivers |
|---|---|---|---|
| 0 | root | this change | `homebuddy-delivery` contract, root CI workflow and script tests, documentation |
| 1 | authBuddy | [`adopt-homebuddy-delivery`](../../../authBuddy/openspec/changes/adopt-homebuddy-delivery/proposal.md) | Baseline CI with `ci` gate, PR title check, release-please, GHCR image `authbuddy-auth-service`, Compose on released images |
| 1 | calendarBuddy | [`adopt-homebuddy-delivery`](../../../calendarBuddy/openspec/changes/adopt-homebuddy-delivery/proposal.md) | Baseline CI (adds code style, `main` filters), release-please, images `calendarbuddy-calendar-api` and `calendarbuddy-ui`, Compose on released images |
| 1 | finanzBuddy | [`adopt-homebuddy-delivery`](../../../finanzBuddy/openspec/changes/adopt-homebuddy-delivery/proposal.md) | Baseline CI (drops stale branch triggers, adds Compose, image, and OpenSpec checks), release-please, images `finanzbuddy-api-gateway`, `finanzbuddy-parser-service`, `finanzbuddy-ui`, Compose on released images |
| 2 | all | first release `v1.0.0` per repository | Images published; production switched to them, authBuddy first, then the product services |

The step-1 changes are independent of each other and can land in any order once the root contract exists. Step 2 switches production per service; authBuddy goes first because the product services verify tokens against it, so its released image must run before the products are redeployed. The in-progress root change `add-homebuddy-monitoring` and its finanzBuddy change also edit `docker-compose.yml` files and the root Compose file; whichever change lands second rebases onto the other, and the root CI must then supply the monitoring variables to its Compose validation.

## Non-goals

- Automatic deployment to a host; operators deploy and roll back by hand.
- Releasing the root workspace; it has no deployable artifact.
- Image vulnerability scanning, image signing beyond GitHub build provenance, and multi-architecture images (linux/amd64 only).
- Aligning Maven `pom.xml` and npm `package.json` versions with the release version; the Git tag and image tag are authoritative.

## Impact

- Root: new `.github/workflows/ci.yml`, new `scripts/test/` harness, `README.md`, `docs/ARCHITECTURE.md`, `openspec/specs/homebuddy-delivery`.
- Every service repository: `.github/workflows/` replaced by `ci.yml` and `release.yml`, new `release-please-config.json`, `.release-please-manifest.json`, `CHANGELOG.md`, `renovate.json` (semantic commits), `docker-compose.yml` (`image:` with version variable), `docker-compose.override.yml` (`build:`), `.env.example`, Dockerfiles (OCI labels from build arguments), README and docs, and its `compose-deployment` spec.
- GitHub settings per service repository: squash merge only with the PR title as commit message, branch protection on `main` requiring `ci` and the PR title check, a `RELEASE_PLEASE_TOKEN` secret, and public GHCR packages linked to the repository.
- Operators: set the version variable in each service `.env`, then `docker compose -f docker-compose.yml pull` and `up -d`; no registry login is needed because the packages are public.
