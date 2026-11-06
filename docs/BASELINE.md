# Container baseline — product-catalog-api

Phase 5 (`container-engineer`), 2026-11-06. This is the behavior contract for
everything after this phase (CLAUDE.md: "the Phase 5 baseline is the
contract"). The Dockerfiles and `docker-compose.yml` already existed before
this phase (multi-stage `base -> vendor/vendor-prod -> test/runtime`, both
base images already digest-pinned, per `docs/ARCHITECTURE.md`) — this phase
hardened/completed the existing setup; it did not rebuild it. See "What was
inherited vs. fixed" below for the exact split.

## Evidence (every command run, exit code)

| Command | Exit | Result |
|---|---|---|
| `docker info` | 0 | Docker Desktop already running |
| `make build` | 0 | `app` + `postgres` images built |
| `make test` (= `docker compose build test` + `--profile test run --rm test`) | 0 | PHPUnit 11.5.57, PHP 8.4.26 — **30 tests, 77 assertions, OK** |
| `make verify` (`build` + `test`) | 0 | Green, full clean run |
| `make lint` (Laravel Pint, `--test`) | 0 | PASS, 70 files, 0 style violations |
| `make audit` (`composer audit --abandoned=report`) | 1 (`make`'s own wrapper reports 2) | **8 advisories / 5 packages** — see "Known baseline: Composer advisories" below. Known, expected, not a Phase 5 gate. |
| `make up` (`verify` + `up -d`) | 0 | `app` + `postgres` containers created and started |
| `docker compose ps` (after ~20s) | n/a | `product_catalog_api_app` **healthy**, `product_catalog_api_postgres` **healthy** |
| `docker compose exec app whoami` | 0 | `www-data` (confirms non-root runtime, as designed) |
| `curl http://localhost:20110/api/category` (before migrating) | n/a | HTTP 500 — `SQLSTATE[42P01]: relation "categories" does not exist` (expected: fresh DB, no migrations run yet) |
| `make migrate` (`php artisan migrate --force`) | 0 | 7 migrations applied (users, password_resets, failed_jobs, personal_access_tokens, categories, products, category_product) |
| `curl http://localhost:20110/api/category` (after migrating) | n/a | **HTTP 200**, `{"success":true,...,"data":[],...}` — full stack serves a real request end to end |
| `docker compose down` | 0 | Clean teardown |
| `docker images` | n/a | Sizes recorded below |
| `docker scout cves product-catalog-api-p5-app:latest` | 0 | 160 vulnerabilities / 28 packages: 0C / 7H / 6M / 147L |
| `docker scout cves product-catalog-api-p5-postgres:latest` | 0 | 75 vulnerabilities / 6 packages: 5C / 33H / 30M / 7L |
| `docker scout recommendations product-catalog-api-p5-app:latest` | 0 | Newer digest of the same `8.4-apache` tag available (-2 vulns, no new); `8.5-apache` also available (-2 vulns, no new) |
| `gh run list --repo RasimAghayev/product-catalog-api --limit 5` | 0 | Confirms CI baseline (see "Pre-existing CI state" below) |
| `gh run view 42205831844` (the push run on `master`'s current HEAD, `773b536`, **before any Phase 5 change**) | n/a | Fails at **"Audit the dependencies"** step only — every other step (checkout, compose config, build test image, test suite, linter) green |

## Known baseline: Composer security advisories (Phase 6's job, not Phase 5's)

`composer audit` reports exactly **8 advisories across 5 packages**, all in
the `symfony/*` family, all newly disclosed 2026-10-28 / 2026-11-04 (i.e.
2-9 days before this phase ran, after the Phase 3 audit already recorded "8
live Composer security advisories (Symfony family)" in
`docs/TECHNICAL_DEBT.md`):

| Package | Advisory | CVE | Severity |
|---|---|---|---|
| symfony/http-foundation | PKSA-24ph-xkrh-y79j | CVE-2026-118514 | — |
| symfony/http-foundation | PKSA-pr6q-2w5s-kzzf | NO CVE | — |
| symfony/http-foundation | PKSA-nxjs-s6hn-vb6m | NO CVE | — |
| symfony/http-foundation | PKSA-b2gg-vk1g-6d5q | NO CVE | — |
| symfony/http-kernel | PKSA-3gxv-7xhq-mgmz | NO CVE | — |
| symfony/mime | PKSA-wtxr-p26d-nn42 | CVE-2026-45070 | medium |
| symfony/routing | PKSA-y8c5-1b7f-r1gj | CVE-2026-118516 | — |
| symfony/yaml | PKSA-nktx-f1n1-b4yd | NO CVE | — |

All are same-minor patch fixes (target range `>=8.1.0,<8.1.11` /
`<8.1.10`), no breaking change expected. Per this phase's own brief and
`docs/TECHNICAL_DEBT.md`'s existing routing, **this is Phase 6 (upgrader)
scope** — Phase 5 only records the baseline. `make audit` is a separate
Makefile target, deliberately **not** part of `make verify`/`make test`, so
this known-red result never blocks the Phase 5 build gate.

## Pre-existing CI state (not caused by this phase)

The repository's own `.github/workflows/ci.yml` wires `composer audit` in as
a hard, blocking step ("Audit the dependencies") in the same job as the test
suite and linter — unlike this phase's Makefile, which keeps `audit`
separate from `verify`. Checked the actual GitHub Actions history before
touching anything: the run triggered by `773b536` (the Phase 4 merge commit,
i.e. this phase's own merge-base, pushed before this phase started) **already
fails**, and fails at exactly the same step: "Audit the dependencies", exit
code 1. Every step before it (checkout, env file, compose config validation,
build test image, run test suite, run linter) is green on that same run.
This confirms the audit-gate redness is pre-existing and already present on
`master` before this phase made a single change — consistent with the 8
advisories above being newly disclosed days before Phase 3's audit even ran.
Several Renovate bot branches/PRs targeting the affected dependencies
already exist (out of scope for Phase 5 — Phase 6 upgrader's job to
merge/reconcile them).

Per CLAUDE.md's working procedure ("If CI was already red before the phase,
record that baseline; don't hide it and don't blame the phase for it."),
this phase's own PR is expected to show the same pre-existing red step in
CI. The merge decision for this phase's PR verifies every *other* CI step is
green (nothing this phase touched regressed anything) and treats the
already-documented, already-routed-to-Phase-6 audit failure as the known
baseline, not a new blocker.

## Image sizes

| Image | Size |
|---|---|
| `product-catalog-api-p5-test` | 990 MB |
| `product-catalog-api-p5-app` (runtime) | 860 MB |
| `product-catalog-api-p5-postgres` | 419 MB |

## Vulnerability scan summary (`docker scout cves`)

**`app` (runtime, `php:8.4-apache@sha256:aa8e1308...`):** 160 vulnerabilities
/ 28 packages — 0 critical, 7 high, 6 medium, 147 low. All 7 high findings
are Debian trixie OS packages already present in the base image
(`libxml2`, `expat`, `zlib`, `apt`) — none has a fix published yet
(`docker scout` shows "Fixed version: not fixed" for all 7). `docker scout
recommendations` shows a newer digest of the *same* `8.4-apache` tag is
available today (removes 2 vulnerabilities, introduces none) and a minor
bump to `8.5-apache` is also available (same effect). Both are
`docs/TECHNICAL_DEBT.md`'s already-recorded "3 Docker base images with stale
digests... php:8.4-apache 1 minor line behind" item, explicitly routed to
**Phase 6 (upgrader)** — this phase does not change the pinned digest/tag,
per its own brief ("already digest-pinned... this phase
IMPROVES/HARDENS... does not rebuild from scratch").

**`postgres` (`postgres:16-alpine@sha256:721873c3...`):** 75 vulnerabilities
/ 6 packages — 5 critical, 33 high, 30 medium, 7 low. The criticals are
almost entirely in an embedded Go `stdlib` build (4 CVEs, fixed in
1.24.13/1.25.13/1.26.9) plus one `zlib` CVE. This matches
`docs/TECHNICAL_DEBT.md`'s already-recorded "`postgres:16-alpine`
additionally 2 majors behind (16->18, skipping 17)" item — also explicitly
routed to **Phase 6**, not touched here.

No secret, credential, or PII finding from either scan.

## Non-root / runtime confirmation

- `app` container: `whoami` -> `www-data` (confirmed via `docker compose exec`).
- `app` HEALTHCHECK is a TCP connect on port 8080 (`php -r
  "exit(@fsockopen(...))"`) — reports "healthy" as soon as Apache accepts
  connections, regardless of whether migrations have run or the DB is
  reachable. This is a known, already-documented limitation
  (`docs/TECHNICAL_DEBT.md`'s "Operational debt" section: "HEALTHCHECK is
  TCP-connect-only, no real `/health/live`/`/health/ready` HTTP endpoints"),
  shared ownership between Phase 5/9/15. Adding a real HTTP health route is
  an application-code change (Phase 9 hardener territory, not Docker/Make
  only) — not made in this phase.
- Migrations are **not** auto-applied on container start (confirmed: a
  fresh `make up` returns HTTP 500 on `/api/category` until `make migrate`
  is run separately). This is the existing, intentional design (separate
  `migrate` Makefile target, matches `README.md`'s documented two-step
  "build+up, then migrate" flow) — not changed by this phase.

## What was inherited vs. fixed this pass

This phase resumed a previous agent instance's uncommitted draft (session
boundary, not a crash). Every modified/untracked file was read and verified
line by line before being trusted — nothing was redone or discarded blind.

**Inherited, verified correct, kept as-is:**
- `build/php/Dockerfile`'s composer `--mount=type=cache` additions on the
  `vendor`/`vendor-prod` stages (BuildKit cache mount, never baked into a
  layer, never shared outside the build — correct per CLAUDE.md's Docker
  secrets standard, though this is a build-speed cache, not a secret).
- `.env.example`'s `APP_URL`/`APP_PORT` move from `8080`/generic default to
  `20110` (this repo's reserved block, `projects/info/state/ports.md`:
  `20110-20119`).
- `docker-compose.yml`'s rename from the stale `task-brief-company` /
  `task_brief_company_*` identifiers (a leftover from this repo's
  pre-rename past — see `composer.json`'s own package name for the same
  leftover, not touched here, out of this phase's scope) to
  `product-catalog-api-p5` / `product_catalog_api_*`, matching the
  `<repo>-p<phase>` isolation convention already established by this
  program's other closed Phase 5 repos (`php-query-builder`,
  `ms-laravel-rabbitmq`) and the reserved port default.
- `Makefile` (untracked, new): all 13 targets
  (`build/test/verify/up/run/down/logs/shell/migrate/token/lint/format/audit/clean`)
  read and then actually run — every one behaves as documented. No bug
  found; nothing rewritten.

**Added this pass:**
- `docs/BASELINE.md` (this file) — did not exist yet.
- `README.md`: fixed a stale `http://localhost:8080` reference (the
  default host port is now `20110`, following the `.env.example`/
  `docker-compose.yml` change above) and added a short note that `make`
  targets wrap the same documented `docker compose` commands.
- This phase's own verification run (build, test, verify, lint, audit, up,
  migrate, end-to-end curl, image scan) — none of this existed as recorded
  evidence before this phase.

**Not changed, explicitly out of scope (see brief and reasoning above):**
- The 8 Symfony Composer advisories (Phase 6).
- Base image digests/tags, even though `docker scout` shows a newer digest
  of the same tag is available (Phase 6, per `docs/TECHNICAL_DEBT.md`'s own
  routing).
- The inert npm/Vite layer — not wired into the Docker build (Phase 7
  removes it entirely per the repo's already-approved Gate-10 plan; wiring
  it in here would contradict that approval).
- `HEALTHCHECK`'s TCP-only check and the lack of a real `/health` endpoint
  (Phase 9 — needs application code, not Docker/Make).
- The pre-existing CI audit-gate redness (Phase 6; recorded above as
  baseline, not fixed).

## Phase 6 (`upgrader`), 2026-11-06 — re-verification after the dependency upgrade

Every item in "Known baseline, not fixed" above that was routed to Phase 6
is now closed. Full per-commit evidence in
`projects/info/state/handoff/6/product-catalog-api.md`; summary here per
CLAUDE.md's "the Phase 5 baseline is the contract" — this section records
what changed against it, not a new baseline.

| Item | Phase 5 baseline | Phase 6 result |
|---|---|---|
| `composer audit --locked` | 8 advisories / 5 Symfony packages | **0 advisories** |
| `php` base image | `8.4-apache` (stale digest within tag) | `8.5-apache` (current digest, current supported PHP line) |
| `composer:2` base image | stale digest | current digest |
| `postgres` base image | `16-alpine` (stale digest, 2 majors behind) | `18-alpine` (current digest, current major) |
| `laravel/framework` | v12.70.0 | v13.40.0 |
| `laravel/tinker` | v2.11.1 | v3.0.2 |
| `guzzlehttp/guzzle` | 7.16.1 (unused) | 8.3.1 (still unused — Phase 7's call) |
| `phpunit/phpunit` | 11.5.57 | 13.4.6 |
| `actions/checkout` | `@v4.2.2` (tag) | `@v7.0.1` (commit SHA) |
| CI "Audit the dependencies" step | red (pre-existing, documented) | **green** (re-verified locally: `make audit` exit 0) |

Re-ran the full gate after every bump: `make verify` (build+test,
PHPUnit 13.4.6 on PHP 8.5.12, 30/30 tests, 77 assertions — same counts as
the Phase 5 baseline, no regression); `make lint` (Pint, 70 files, 0
violations, unchanged); `make up` + `make migrate` + a real
`curl /api/category` end-to-end smoke test on the new Postgres 18 image
(public `GET` -> 200 with the same response shape as Phase 5's baseline;
unauthenticated `POST` -> 401 via `auth:sanctum`, confirming the Laravel 13
CSRF middleware rename changed nothing observable).

One new finding this phase, not a regression: Postgres 18's official image
changed its default `PGDATA` location (now a major-version-specific
subdirectory, to support `pg_upgrade --link`); fixed with the image's own
documented backward-compatible `PGDATA=/var/lib/postgresql/data` override
on the `postgres` service rather than restructuring the bind mount. Worth
remembering for the *next* Postgres major bump: if this repo ever needs a
real `pg_upgrade` path (i.e., there is actual data to carry forward), the
mount will need to move to `/var/lib/postgresql` (parent) at that point —
not an issue today since `var/postgres` is a gitignored, disposable
local-dev bind mount with nothing to upgrade in place.

`docker scout cves` re-run on both new images (base images changed, so the
Phase 5 scan no longer applies):

| Image | Phase 5 baseline | Phase 6 (new base images) |
|---|---|---|
| `app` (`php:8.5-apache`) | 160 vulns/28 pkgs — 0C/7H/6M/147L | **158 vulns/27 pkgs — 0C/6H/6M/146L** |
| `postgres` (`postgres:18-alpine`) | 75 vulns/6 pkgs — 5C/33H/30M/7L | **74 vulns/6 pkgs — 5C/32H/30M/7L** |

Slight improvement on both images (newer OS packages), no new criticals, no
regression. Remaining findings are the same category as Phase 5 recorded:
Debian/Alpine OS-level packages with no fix published yet.

Still open, unchanged from Phase 5 (not this phase's scope): `HEALTHCHECK`
TCP-only (Phase 9); the inert npm/Vite layer (Phase 7 removal).
