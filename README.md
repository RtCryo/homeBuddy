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

On a production host, the root `docker-compose.yml` creates this network and runs the shared Traefik, the only container that binds ports 80 and 443:

```bash
docker compose --profile production up -d
```
