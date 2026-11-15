# Design

## Context

Current state, observed in the repositories on 2026-11-07:

| Repository | Workflows | Gaps against the baseline |
|---|---|---|
| authBuddy | `auth-service.yml`: Spotless, `./mvnw verify`, Compose config (prod and dev), image build, OpenSpec validate (`@fission-ai/openspec@1.13.2`) | Path filters only, so no check can be required; no PR title check; no release |
| finanzBuddy | `api-gateway.yml`, `parser-service.yml` (compile, Spotless, test, JaCoCo, Codecov), `ui.yml` (tsc, lint, build), `docker-compose.yml` (SeaweedFS smoke test), `documentation.yml` | Triggers on stale branches `01-api-gateway`, `02-parser-service`, `03-ui`; no image build, no OpenSpec validation, Compose config only for the dev file; uses `mvn` instead of the wrapper; no release |
| calendarBuddy | `calendar-api.yml` (`./mvnw verify`), `ui.yml` (test, lint, build), `docker-compose.yml` (config) | Runs on every branch push; no Spotless check, no image build, no OpenSpec validation, no `permissions` or `concurrency`; no release |
| root | none | Scripts parity is tested only by hand |

All four GitHub repositories are public, allow both merge commits and squash merges, and have no tags. History on `main` is not Conventional Commits (`Merge pull request #…`, `Update dependency oxlint to v1.92.0`). Every service Compose file builds its own components with `build:`; finanzBuddy and calendarBuddy also keep a service-local Traefik for standalone use. Renovate runs with `config:recommended` in every service. Toolchains are already the same everywhere: Temurin 25 with the Maven wrapper or Maven, Node 26 with npm.

Deployable components per repository: authBuddy `auth-service`; finanzBuddy `api-gateway`, `parser-service`, `ui`; calendarBuddy `calendar-api`, `ui`.

## Goals / Non-Goals

**Goals:**
- One workflow shape that a contributor recognizes in every repository, with one required check.
- Reproducible deployments: a version number identifies exactly which images run.
- Release work reduced to reviewing and merging one pull request.

**Non-Goals:**
- Reusable workflows shared from a central repository. Each repository keeps its workflows self-contained (see Decisions).
- Preview or `edge` images from `main`; only releases publish images.
- Changing the service-local Traefik or any network, port, or routing rule.

## Decisions

### 1. One `ci.yml` per repository with a path-filter job and a `ci` gate

Each repository gets `.github/workflows/ci.yml` with these jobs:

1. `changes`: `dorny/paths-filter` computes one output per component (`auth-service/**`, `ui/**`, …), plus `compose` (`docker-compose*.yml`, `.env.example`) and `openspec` (`openspec/**`). The workflow file itself and the release configuration count as changes to every filter. On push to `main`, every filter is true, so `main` is always fully verified.
2. Component jobs, each guarded by `if: needs.changes.outputs.<component> == 'true'`: Java components run `./mvnw -B spotless:check` and `./mvnw -B verify`; UI components run `npm ci`, lint, type check or test as each UI defines, and `npm run build`.
3. `image`: a matrix over the deployable components that runs `docker/build-push-action` with `push: false` and the GitHub Actions cache.
4. `compose`: `docker compose -f docker-compose.yml config --quiet` and `docker compose config --quiet`, with CI-only values for every required variable, including `<SERVICE>_VERSION=0.0.0-ci`.
5. `openspec`: `npx --yes @fission-ai/openspec@<pinned> validate --all --strict --no-interactive`.
6. Repository-specific jobs: finanzBuddy keeps the documentation integrity check and the SeaweedFS smoke test, and the Codecov upload as a non-failing step of its Java test jobs.
7. `ci`: `if: always()`, `needs:` every other job; it fails when any needed result is `failure` or `cancelled` and passes on `success` or `skipped`.

Branch protection requires `ci` and the title check only. Job names inside the workflow can change without touching repository settings.

*Alternatives:* keeping one workflow per component with path filters (status quo) cannot be required, because a skipped workflow never reports; running every job on every pull request without filters is simpler but costs Testcontainers runs on documentation-only changes. Reusable workflows in the root repository (`workflow_call`) would remove duplication, but make every service CI depend on a second repository's `main` and need version pinning across repositories; with three repositories, copying a short, contract-checked file is cheaper. The baseline spec keeps the copies aligned.

### 2. Conventional Commits through squash-merged pull-request titles

Repository settings: squash merge only, default commit message "pull request title". A `pr-title.yml` workflow runs `amannn/action-semantic-pull-request` on `pull_request_target` events `opened`, `edited`, and `synchronize` with the type list from the spec; it checks out no code, so `pull_request_target` is safe. Renovate gets `":semanticCommits"` in `renovate.json`, giving `chore(deps)` for dev dependencies and `fix(deps)` for runtime dependencies, so runtime dependency updates produce patch releases.

*Alternative:* commit-message linting of every commit would force contributors to rewrite branch history; titles are the only thing that reaches `main` after a squash.

### 3. release-please with a manifest per repository, one version per repository

Each service repository adds `release-please-config.json` with one package at `.` (`release-type: simple`, `include-component-in-tag: false`, changelog sections for `feat`, `fix`, `perf`, and `revert`; runtime dependency updates appear under "Bug fixes" as `fix(deps)` because `deps` is a scope, not a commit type), and `.release-please-manifest.json`. `.env.example` carries `<SERVICE>_VERSION=…  # x-release-please-version` and is listed under `extra-files`, so the release pull request also updates the documented version.

Bootstrapping: `bootstrap-sha` is the `main` commit on which the per-service change is merged, so the non-conventional history is ignored, and `release-as: 1.0.0` produces the first release `v1.0.0`. `release-as` is removed in a follow-up `chore` pull request after the first release.

One version per repository matches how the repositories are deployed: one Compose stack, one `.env`, all components shipped together. Per-component versions would need one variable per component and allow combinations that were never tested together.

*Alternatives:* manual tags or a `workflow_dispatch` release with a version input (rejected by the user in favor of release-please); semantic-release, which releases on every merge without a review step.

### 4. Release workflow builds images in the same run, with a dedicated token

`release.yml` runs on push to `main` and on `workflow_dispatch` with an input `tag`:

1. `release-please` job: `googleapis/release-please-action` with `token: ${{ secrets.RELEASE_PLEASE_TOKEN }}`. Outputs `release_created`, `tag_name`, `version`, `major`, `minor`.
2. `publish` job, if a release was created or `workflow_dispatch` named a tag: checks out the tag, then for each deployable component (matrix) skips when `docker manifest inspect ghcr.io/rtcryo/<image>:X.Y.Z` succeeds, otherwise builds with `docker/build-push-action` (`platforms: linux/amd64`, build args `VERSION` and `REVISION`, OCI labels from `docker/metadata-action`), pushes `X.Y.Z` and `X.Y`, and runs `actions/attest-build-provenance` with `push-to-registry: true`.
3. `notes` job: collects the digests and appends an "Images" table to the GitHub Release with `gh release edit`.

Permissions are granted per job: `contents: write` and `pull-requests: write` for release-please; `packages: write`, `id-token: write`, `attestations: write` for publishing; `contents: write` for notes.

The token: pull requests and tags created with the default `GITHUB_TOKEN` do not trigger workflows, so the release pull request would never get a `ci` status and could not be merged under branch protection. `RELEASE_PLEASE_TOKEN` is a fine-grained personal access token limited to the one repository with Contents and Pull requests read/write. Publishing runs in the same workflow run and uses `GITHUB_TOKEN`, so it does not depend on tag-triggered workflows.

The `X.Y` tag moves to the newest patch of that minor version; it exists for operators who want to read which line they are on, not for deployment, which always pins `X.Y.Z`.

*Alternatives:* a separate workflow triggered by `release: published` (would not fire for a release created with `GITHUB_TOKEN`, and splits the run); a GitHub App instead of a personal access token (cleaner ownership, but more setup for a single-maintainer project; can replace the token later without changing the workflow shape).

### 5. Production Compose pulls images; the override builds

In each service `docker-compose.yml`, every deployable component gets
`image: ghcr.io/rtcryo/<service>-<component>:${<SERVICE>_VERSION:?Set <SERVICE>_VERSION to a released version (see .env.example)}` and loses `build:`. `docker-compose.override.yml` adds `build:` (context and, where used, build arguments) and sets `image: <service>-<component>:dev`, so a local build never shadows a GHCR tag and `docker compose up --build` builds everything from the working tree. Because Compose interpolates the base file even when the override replaces `image`, the version variable is required locally as well; `.env.example` provides it, and developers already copy `.env.example` for the required passwords.

Dockerfiles accept `ARG VERSION` and `ARG REVISION` and set `org.opencontainers.image.version` and `org.opencontainers.image.revision`; `metadata-action` sets the same labels at build time, so local builds stay unlabelled but valid.

*Alternative:* keeping `build:` in production with `pull_policy: build` and checking out the tag on the host; it keeps the host dependent on toolchains and network access to Maven Central and npm, and produces images that differ between hosts.

### 6. Root CI and script tests

Root `.github/workflows/ci.yml` with jobs `openspec`, `compose` (`docker compose config` and `docker compose -f docker-compose.yml --profile production config`, CI values for every required variable), `shellcheck`, `scripts-linux` (bash on `ubuntu-latest`), `scripts-windows` (bash from Git for Windows, `powershell` 5.1 and `pwsh` 7 on `windows-latest`), and the `ci` gate.

The test harness lives in `scripts/test/`. `run-repos-tests.sh` and `run-repos-tests.ps1` build the same fixture: a temporary workspace containing a copy of `scripts/` and a generated `repos.txt` that points at local bare repositories (one normal, one with a local change after clone, one with a non-Git folder in its place, one unreachable URL). They run `clone`, `pull`, and `status` and write the output and exit code of each step to a result directory, with the temporary root replaced by `<root>` and path separators normalized. Expected results are stored in `scripts/test/expected/`, and on Windows the three interpreters' results are also compared with each other. The scripts themselves need no change, because they derive the root from their own location.

## Risks / Trade-offs

- [The personal access token expires or leaks] → Fine-grained, one repository, minimal permissions, expiry of one year noted in each repository's `docs/`; when it expires, release pull requests stop updating and the workflow fails visibly.
- [A database migration makes rollback to an older image unsafe] → Liquibase changesets already carry rollbacks; release notes mark migrations under a breaking or `feat` entry, and the deployment section in each service README states that rolling back across a migration needs the rollback first.
- [Contributors forget Conventional Commits titles] → The title check blocks merging and shows the expected format; squash merge means only the title matters.
- [release-please misreads the first release] → `bootstrap-sha` and `release-as` are set explicitly and removed afterwards; the first release pull request is reviewed before merging.
- [Images are amd64 only] → If a host turns out to be arm64, adding `linux/arm64` to `platforms` and `docker/setup-qemu-action` is a local change to `release.yml`.
- [Copied workflows drift between repositories] → The root spec defines the baseline; each per-service change references it, and root verification compares the three `ci.yml` files against it.
- [Conflict with `add-homebuddy-monitoring`] → Both change service and root Compose files; the later change rebases, and its Compose CI job adds the monitoring variables.

## Migration Plan

1. Root: land the contract, root CI, and documentation. Enable branch protection on the root `main` once `ci` has run green.
2. Per service (any order): land `adopt-homebuddy-delivery`. Then configure the repository: squash merge only, `RELEASE_PLEASE_TOKEN`, branch protection requiring `ci` and the title check.
3. Per service: merge the first release pull request (`v1.0.0`), check the published images and attestations, then make each GHCR package public and linked to its repository.
4. Production, authBuddy first, then finanzBuddy and calendarBuddy: set `<SERVICE>_VERSION=1.0.0` in `.env`, `docker compose -f docker-compose.yml pull`, `up -d`, check sign-in from both products.

Rollback: before step 4, a host can keep running the old `build:`-based Compose file from the previous commit. After step 4, rollback is setting the previous version and recreating the stack. If the release automation itself fails, releases can wait; CI keeps working without it.
