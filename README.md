# homeBuddy

homeBuddy is a family of household services that share one family account. This root repository is the workspace: it holds cross-service specifications, shared infrastructure, and scripts. Each service is its own Git repository, cloned into a folder next to these files and ignored by this repository.

| Service | Purpose | Folder |
|---|---|---|
| authBuddy | Shared homeBuddy accounts, sign-in, token issuance | `authBuddy/` |
| finanzBuddy | Bank statements, transactions, tags | `finanzBuddy/` |
| calendarBuddy | Family calendar with members and appointments | `calendarBuddy/` |

The list of repositories, their URLs, and branches lives in [`repos.txt`](repos.txt).

## Getting started

```bash
git clone <homeBuddy root URL> homeBuddy
cd homeBuddy
scripts/repos.sh clone
```

There are two equivalent scripts with the same commands and behavior; use whichever fits your shell:

| Script | Run it from | Example |
|---|---|---|
| [`scripts/repos.sh`](scripts/repos.sh) | bash: Linux, macOS, Git Bash, CI | `scripts/repos.sh status` |
| [`scripts/repos.ps1`](scripts/repos.ps1) | Windows PowerShell 5.1 or PowerShell 7 | `./scripts/repos.ps1 status` |

From PowerShell you can also run the bash version with `bash scripts/repos.sh status`. Commands:

| Command | Effect |
|---|---|
| `clone` (default) | Clone every missing repository from `repos.txt`; present ones are left alone |
| `pull` | Fast-forward every repository that has no local changes and an `origin` remote |
| `status` | Show branch, changed files, and ahead/behind for every repository |

The scripts never commit, push, or reset. Commit and push inside each service folder as usual.

On Windows, keep the workspace in a short path (for example `D:/repo/homeBuddy`) or enable `git config --global core.longpaths true`; some service files have deep paths that exceed the 260-character limit under long parent folders.

## Where things are specified

- **Root [`openspec/`](openspec/)**: contracts between services (identity token, network and routing, shared UI rules) and umbrella changes that coordinate several services.
- **`<service>/openspec/`**: behavior inside that service.

See [`AGENTS.md`](AGENTS.md) for the full rule and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the system map and port registry.

## Running locally

Each service has its own `docker-compose.yml` and `.env.example`; start authBuddy first, because the product services verify tokens against it. All stacks share the external Docker network `homebuddy`:

```bash
docker network create homebuddy
```

Each product API reaches authBuddy over its own internal-only identity network instead of `homebuddy`. Create these once on every host, production included, because Compose cannot create them:

```bash
docker network create --internal finanzbuddy-identity
docker network create --internal calendarbuddy-identity
```

Monitoring uses one more internal-only network per service, shared only by that service's metrics endpoints and the central Prometheus. Create these once on every host, too:

```bash
docker network create --internal authbuddy-metrics
docker network create --internal finanzbuddy-metrics
docker network create --internal calendarbuddy-metrics
```

The root `docker-compose.yml` runs the central monitoring stack: one Prometheus and one Grafana for all services. Copy [`.env.example`](.env.example) to `.env`, set `GRAFANA_ADMIN_PASSWORD`, and start it:

```bash
cp .env.example .env
docker compose up -d
```

Grafana is then at <http://localhost:3001> and Prometheus at <http://localhost:9090>. Sign in to Grafana as `admin` with `GRAFANA_ADMIN_PASSWORD`; the homeBuddy overview opens first and each service has its own folder. Services whose stacks are not running show as down. Ports 3001 and 9090 must be free: stop finanzBuddy's own Prometheus and Grafana first if your finanzBuddy checkout still starts them.

On a production host, the same file also runs the shared Traefik, the only container that binds ports 80 and 443, and publishes Grafana on `MONITORING_DOMAIN` over HTTPS (create a DNS record for it first). Set `GRAFANA_ADMIN_PASSWORD`, `MONITORING_DOMAIN`, `GRAFANA_COOKIE_SECURE=true`, and `TRAEFIK_ACME_EMAIL` in `.env`. Start it without the local override, which would publish Grafana and Prometheus on host ports:

```bash
docker compose -f docker-compose.yml --profile production up -d
```

## Delivery and releases

Every repository, this one included, is checked by one GitHub Actions workflow (`ci.yml`) on pull requests to `main` and pushes to `main`. Its last job, `ci`, is the only check that branch protection requires; it reports on every change and passes when every job the change selected passed. Specified in the root capability [`homebuddy-delivery`](openspec/specs/homebuddy-delivery/spec.md).

- **Conventional Commits titles.** Pull requests are squash-merged and the pull-request title becomes the commit on `main`, so the title must read `type(scope): summary` with one of `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`, or `revert`; `!` marks a breaking change (`feat!: drop the legacy login endpoint`). A check blocks other titles.
- **Release pull requests.** In each service repository, release-please keeps one open pull request that proposes the next version (`fix` and `perf` raise the patch version, `feat` the minor, `!` the major) and its `CHANGELOG.md` entries. Merging it creates the tag `vX.Y.Z` and a GitHub Release, and publishes every deployable image of that repository to `ghcr.io/rtcryo/<service>-<component>` with the tags `X.Y.Z` and `X.Y`. The release notes list each image with its digest. The root repository has no releases.
- **Deploying a version.** Production Compose files use the released images, pinned by a version variable per service: `AUTHBUDDY_VERSION`, `FINANZBUDDY_VERSION`, `CALENDARBUDDY_VERSION`. Set it in the service's `.env` (`.env.example` names the latest release), then pull and recreate; no registry login is needed because the packages are public:

  ```bash
  docker compose -f docker-compose.yml pull
  docker compose -f docker-compose.yml up -d
  ```

  Starting the production file without the variable fails and names it. Deploy authBuddy first, because the product services verify tokens against it.
- **Rolling back.** Set the variable to the previous released version and run the same two commands. If a release added a database migration, roll the migration back first (see the service README).
- **Local development.** `docker compose up --build` in a service repository builds every component from the working tree and tags the images `<service>-<component>:dev`; the version variable from `.env.example` is still required but never pulls an image for those components.
- **Verifying an image.** `gh attestation verify oci://ghcr.io/rtcryo/<service>-<component>:X.Y.Z --owner RtCryo` proves which workflow and commit built it.

Run the script tests locally with `scripts/test/run-repos-tests.sh` (bash) or `./scripts/test/run-repos-tests.ps1` (Windows PowerShell 5.1 or PowerShell 7). They run `clone`, `pull`, and `status` of `repos.sh` or `repos.ps1` against local fixture repositories and compare the output and exit code with `scripts/test/expected/`, so the two scripts cannot drift apart.
