# Repository audit — product-catalog-api

Phase 3 (`auditor`), 2026-11-06. HEAD `f6303b29ad9b6b2d1befd5e8297a9451ab1dbfc3` (`master`, clean).
Builds on `projects/info/deps/product-catalog-api.md` (Phase 2, dependency/version/vuln facts — not
re-derived here) plus this phase's own full read of every tracked file. Every claim below cites a
`file:line` or a command; nothing is asserted from the repo name or from memory of similar projects.

## Scope confirmed this phase

- Structure: Laravel 12 app at repo root (not nested), 2 domain entities (`Category`, `Product`), 1
  pivot (`category_product`), standard Laravel scaffolding otherwise. Dual-ecosystem manifests
  (PHP + npm) confirmed by Phase 2; this phase additionally confirms the npm side is **inert** (see
  `docs/ARCHITECTURE.md`'s "npm/Vite layer" section) — not a second live module.
- Env vars: `.env.example` enumerates every variable the app reads (`APP_*`, `LOG_*`, `DB_*`,
  `BROADCAST_DRIVER`, `CACHE_DRIVER`, `FILESYSTEM_DISK`, `QUEUE_CONNECTION`, `SESSION_*`, `MAIL_*`,
  `APP_PORT`). No variable read in code (`grep -rn "env(" app config` — spot-checked against
  `config/*.php`) is missing from `.env.example`.
- API contract: `routes/api.php` (2 `apiResource` routes, read-open/write-gated split) +
  `docs/api.md` (hand-written, matches the real code exactly — spot-checked every example response
  shape against the actual `Resource`/`BaseController` code).
- Integrations: none. No outbound HTTP client is actually called (`guzzlehttp/guzzle` is installed
  but unused, confirmed again this phase — `grep -rn "GuzzleHttp\|Http::"` across `app config routes
  database tests` → no matches). No queue, no broadcast, no external API.
- Database layer: see below.
- Tests: 30 test methods across 3 files, see below.
- CI/CD, Docker: see below.
- Docs: `README.md` + `docs/api.md`, both accurate and unusually candid about known limitations —
  confirmed by cross-checking every claim in both files against the real code.
- Duplication: within-repo, none meaningful — the one recurring concern (pagination bounds) is
  already centralized in `app/Support/PerPage.php`. Cross-repo duplication is Phase 2's domain (already
  checked: zero coupling against all 13 other onboarded repos) — not re-run here.

## Database layer

**Schema** (3 tables own to this app; `users`/`password_resets`/`failed_jobs`/
`personal_access_tokens` are Laravel/Sanctum stock):

| Table | Columns | Constraints / indexes |
|---|---|---|
| `categories` | `id`, `name`, `parent_id` (nullable), timestamps | `parent_id` → `categories.id`, `ON DELETE SET NULL` (`database/migrations/2022_08_13_224524_create_categories_table.php:26-29`). **No index on `parent_id` itself** — Postgres does not auto-index the referencing side of a FK (only the referenced side gets one from the primary key). Self-joins via `Category::subcategory()` (`app/Models/Category.php:37-40`) scan unindexed at scale; immaterial at current catalogue sizes. |
| `products` | `id`, `name`, `priceFrom`/`priceTo` (`decimal(13,4)`), `published` (`enum('Yes','No')`, indexed), timestamps, `deleted_at` | `published` indexed (`...create_products_table.php:27`); decimal(13,4) correctly matches the validation regex (`ProductRequest.php:30-31`, `/^\d{1,13}(\.\d{1,4})?$/`) — money is never stored as float. |
| `category_product` (pivot) | `id`, `product_id`, `category_id` | Both FKs `ON DELETE CASCADE`; `unique(product_id, category_id)` + separate `index(category_id)` (`...create_category_product_table.php:24-31`) — correct indexing for both access directions (`Product::categories()` and `Category::products()`). |

**Relations**: `Product belongsToMany Category` and `Category belongsToMany Product` through
`category_product` (`app/Models/Product.php:29-32`, `app/Models/Category.php:42-44`); `Category
belongsTo/hasMany self` for the parent/subcategory tree (`app/Models/Category.php:25-40`).

**Transactions**: **none used anywhere.** `ProductController::store()` (lines 31-43) and `::update()`
(62-82) each perform `Product::create()`/`update()` followed by a separate `categories()->sync()`
call, with no `DB::transaction()` wrapping the pair. If the second call fails after the first
succeeds (connection drop, deadlock, etc.), a product is left with zero categories — a direct
violation of the "2 to 10 categories" rule the create/update *request validation* enforces but the
*database* does not (no DB-level check constraint backs it). See Issue P1-1 below.

**N+1**: none in current code (see `docs/ARCHITECTURE.md`); a previously-fixed N+1 is called out in
the code's own comments (`ProductResource.php:31-34`) and is not reproducible today.

**Migrations**: 6 app-specific migrations (3 Laravel stock + `categories`/`products`/
`category_product`), each single-purpose, each with a working `down()`, run in timestamp order with
no squashing or gaps. Migration comments explicitly record two previously-fixed FK type-mismatch bugs
(`categories.parent_id` and both `category_product` columns were originally plain `integer` against a
`bigInteger` key — fixed to `unsignedBigInteger`, see `...create_categories_table.php:19-23` and
`...create_category_product_table.php:18-22`).

**Backup/recovery**: none automated in-repo — Postgres data is a bind mount (`var/postgres`, see
`docker-compose.yml:75`), no backup script/cron/snapshot policy exists. Expected at this scale; not a
defect to fix now, but worth a one-line note in `docs/OPERATIONS.md` when Phase 15 writes it.

## Existing tests — coverage and quality

30 test methods, 3 files, all pass against SQLite in-memory (`phpunit.xml:27-28`), run inside the
Docker `test` stage (`build/php/Dockerfile:44-52`), no coverage percentage measured anywhere in CI or
compose (no `--coverage-*` flag, no Xdebug/PCOV installed in the `base` image).

| File | Tests | What it covers |
|---|---|---|
| `tests/Feature/ProductApiTest.php` | 12 | Listing (count, name field, nested categories), create with/without token, create with 1 category (rejected, min 2), create with a non-existent category id (rejected), create with `priceTo < priceFrom` (rejected), non-numeric price (rejected), 404 on unknown id, update replaces categories, soft-delete keeps the row. |
| `tests/Feature/CategoryApiTest.php` | 13 | Listing (count, pagination, per-page bound), create with/without token, empty name (rejected), non-existent parent (rejected), subcategory creation, 404 on unknown id (show and delete), update, delete, delete-blocked-by-product-usage. |
| `tests/Unit/PerPageTest.php` | 5 | Default, explicit, below-bound, non-numeric, above-bound per-page values. |

**Real gaps, confirmed by reading every test method (not assumed):**

- **No test asserts "without a token" for `update` or `destroy`** on either resource — only `store`
  is tested for the 401 path (`ProductApiTest.php:79-93`, `CategoryApiTest.php:66-72`). An auth
  regression that broke `auth:sanctum` on the update/destroy routes specifically would not be caught
  by this suite today.
- **No test exercises the trashed-product inconsistency** (see `docs/ARCHITECTURE.md`): nothing
  creates a soft-deleted product and asserts what the listing *and* the show/update endpoints actually
  return for it. The single most distinctive, "on purpose" piece of this API's behavior has zero
  regression coverage.
- **No test covers `Category::destroy` with a child category attached** (only the product-usage block
  is tested, `CategoryApiTest.php:148-162`) — the parent-with-children delete path (which succeeds and
  silently nulls the children's `parent_id`) is unverified.
- **No test for the `php artisan api:token` command** (`IssueApiToken.php`) — the only way a caller
  ever obtains a token is untested.
- Tests run only against SQLite; Postgres-specific behavior (the real `enum` type, `decimal(13,4)`
  rounding/overflow at the registered precision, `search_path`) is never exercised by the suite that
  gates CI.

## CI/CD

Single job (`quality-gates`, `.github/workflows/ci.yml:18-53`), fully Docker-driven, triggers on
`push`/`pull_request` to `master`/`test`. Order: checkout → write `var/.env` from `.env.example` →
`docker compose config` → build `test` image → run test suite → run `pint --test` → `composer audit`
→ build `app` image → build `postgres` image. `permissions: contents: read` (line 15); `actions/
checkout` pinned by commit SHA (line 25, labeled `v4.2.2`, 3 majors behind live `v7.0.1` per Phase 2).

**Gaps against this program's CI/CD runner-time standard:**

- Lint (`pint --test`, line 44) and the dependency audit (line 47) run **after** the full test suite
  (line 41), not before — the standard's "cheap checks first, fail fast" ordering is inverted. (They
  could run against the already-built `test` image before the `phpunit` entrypoint step, since `pint`
  and `composer audit` only need the same image, not a passing test run first.)
- No secret-scan step (gitleaks or equivalent) anywhere in the pipeline.
- No Docker image/dependency vulnerability scan beyond `composer audit` (no `docker scout`/`trivy`
  against the built `app`/`postgres` images).
- No `concurrency`/`cancel-in-progress` group, no `paths` filter — every push/PR runs the full
  pipeline even for changes that can't affect it (e.g., a `docs/`-only change).
- `timeout-minutes: 30` exists at the job level (line 21) but not per-step.

**What's already right:** Docker-only runner (no PHP toolchain on the runner itself, line 2-5
comment confirms this is deliberate); never prints a secret; never publishes anything; pinned
checkout by SHA, not by a movable tag.

## Docker

Multi-stage `build/php/Dockerfile`: `base` (pgsql/zip extensions, `a2enmod rewrite`, digest-pinned
`php:8.4-apache` + `composer:2` binary copy) → `vendor`/`vendor-prod` (prod-only deps for runtime) →
`test` (phpunit entrypoint, runs as `www-data`) → `runtime` (apache vhost config, non-root, digest-
pinned, `HEALTHCHECK`, `EXPOSE 8080`). `build/postgres/Dockerfile` also digest-pinned. `docker-
compose.yml` defines `app`/`test` (profile `test`)/`postgres`, resource limits on every service, DB
credentials fail-fast with no default (`${DB_DATABASE:?...}` etc.), all state under `var/`.

**Gaps:**

- **No `Makefile` exists anywhere in the repo.** Every documented command is a raw `docker compose
  ...` invocation (`README.md:27-38, 82-86`). This program's Docker standard (`PROMPT.md` §5) expects
  `make build/test/verify/up/run/down` at minimum.
- `docker-compose.yml:1` hardcodes the Compose project name (`name: "task-brief-company"`, the old
  business-brief name — matches the `composer.json` package-name mismatch Phase 2 already flagged).
  This program's per-agent isolation convention needs `COMPOSE_PROJECT_NAME=<repo>-p<phase>`, which a
  static `name:` key in the file itself does not provide room for without an explicit override flag
  every time.
- `docker-compose.yml:45` (`"${APP_PORT:-8080}:8080"`) defaults to port 8080, not this repo's reserved
  block (`20110-20119`, `projects/info/state/ports.md`) — same class of ad-hoc-port gap already
  recorded for other repos in this program's `ports.md` "Known gap" note.
- `HEALTHCHECK` (`build/php/Dockerfile:79-80`) only does a raw TCP connect
  (`fsockopen('127.0.0.1', 8080)`) — it proves the port is open, not that the app answers HTTP 200 or
  that the DB connection works. No `/health/live`/`/health/ready` HTTP endpoint exists at all.
- No image vulnerability scan is run against the built `runtime`/`postgres` images (CI gap, repeated
  above).

**What's already right:** digest-pinned base images, non-root runtime user, dependency layer caching
order (composer files copied before application source), no secrets in any layer, resource limits on
every compose service, DB credentials with no default value.

## Config / security review (redacted)

- `config/cors.php:18-32`: `allowed_origins => ['*']` for `api/*` and `sanctum/csrf-cookie`,
  `supports_credentials => false`. Wildcard origin is broad for a production default, but actual risk
  is low here because this API is pure bearer-token (no cookie session to leak cross-origin) — still
  worth scoping to known frontend origins before any real deployment (see Issue P2-4).
  <br>Confirmed as `file:line`, no value printed — this is a config setting, not a secret.
- `.env.example` (8-29): placeholder/local-dev values only (`DB_PASSWORD=app`, `DB_ROOT_PASSWORD=root`,
  `APP_KEY=` empty), each with its own "never commit a real credential" comment at the top of the
  file. No tracked `.env` exists (`git ls-files | grep -i "\.env"` → only `.env.example`).
- `build/php/entrypoint.sh:10-14`: if `APP_KEY` is absent, a random key is generated **per container
  start** and never persisted — documented in the script's own comment and in `README.md:56-58`.
  Harmless today (no encrypted cookies/attributes are used by this stateless bearer-token API), but
  worth stating explicitly so a future feature that *does* rely on `APP_KEY`-based encryption
  (encrypted model casts, encrypted cookies) doesn't silently break across restarts.

## Secret scan (this phase, independent of Phase 2's)

Working tree only (full-history audit is Phase 4/git-steward's job, not re-done here):

```
git status --porcelain                                           → clean, nothing uncommitted
git ls-files -z | xargs -0 grep -InE \
  "AKIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH|PGP|DSA) PRIVATE KEY-----|xox[baprs]-...|
   gh[pousr]_[0-9A-Za-z]{36,}|glpat-...|AIza...|eyJhbGciOi...|(api[_-]?key|secret|password|
   passwd|token)\s*[=:]\s*['\"][^'\"\s]{6,}['\"]" -- .
                                                                   → exit 1 (no match)
git ls-files | grep -i "\.env"                                    → only .env.example
```

**No secret found.** Corroborates Phase 2's narrower scan (which also found zero matches).

## Licence / legal risk

`composer.json:6` declares `"license": "MIT"`. **No root `LICENSE` file exists** (`find . -maxdepth 1
-iname "LICENSE*"` → empty). This is an inconsistency, not a violation: the declared license has no
actual license text backing it in the repository. Per Phase 2, every one of the 117 PHP + 5 npm
dependencies carries a permissive license (MIT/BSD-3-Clause/Apache-2.0; two packages tri-licensed
with a permissive BSD option). **No blocking legal risk** — the only action needed is adding the
actual MIT license text as `LICENSE` at the repo root (Phase 4 or Phase 15, see plan below).

## Issues by severity

### P0 — none found
No unauthenticated write path, no live auth bypass, no secret in the working tree or in config
defaults, no confirmed data-loss path. This repo's baseline is clean at the P0 level — stated
explicitly rather than omitted, per this program's honesty rule.

### P1

1. **No DB transaction around product create/update + category sync** —
   `app/Http/Controllers/API/ProductController.php:37-38` (store) and `:74-78` (update). A failure
   between the two calls leaves a product with 0 categories, violating the 2-10 rule at the DB layer
   even though request validation enforces it. Fix: wrap both pairs in `DB::transaction()`.
2. **Trashed-product show/update inconsistency** — `index()` deliberately includes soft-deleted
   products (documented, by design), but `show()` (`ProductController.php:48-57`) and `update()`
   (`:62-82`) use plain `Product::find($id)`, so a product visible in the listing as `"status":
   "Deleted"` 404s on `GET`/`PUT` by id. Undocumented, untested. Needs a product decision (allow
   `GET`/block `PUT` on trashed, or something else) before Phase 9/11 act on it.
3. **No "without a token" test for `update`/`destroy`** on either resource —
   `ProductApiTest.php`/`CategoryApiTest.php` only test the 401 path for `store`. An auth regression
   on the two highest-risk write verbs would pass CI today.
4. **8 live Composer security advisories** (Symfony family, same-minor fixes available) — quantified
   in `projects/info/deps/product-catalog-api.md`, carried forward, not re-derived here.
5. **Live npm lockfile desync / ERESOLVE conflict** — `laravel-vite-plugin@^3` peer-requires
   `vite@^8`, `package.json` pins `vite@^6`; a bare `npm install` fails today. Quantified in Phase 2,
   carried forward.

### P2

1. **`Category::destroy` doesn't check for child categories** —
   `app/Http/Controllers/API/CategoryController.php:71-90` only blocks deletion when the category is
   used by a product (`category_product` row count). Deleting a parent with subcategories succeeds
   and silently nulls their `parent_id` (DB-safe via `ON DELETE SET NULL`, but undocumented, untested,
   and surprising to a caller who expected a `"Category used other product."`-style guard).
2. **Legacy Laravel ≤10-style `RouteServiceProvider`** still does route/rate-limiter registration
   instead of `bootstrap/app.php`'s `withRouting()` — works, but is the kind of "structure matches the
   upgraded stack's conventions" drift Phase 7 is scoped to fix. See `docs/ARCHITECTURE.md`.
3. **`app/Providers/BroadcastServiceProvider.php` and `routes/channels.php` are both dead** —
   confirmed by tracing: the provider class exists on disk but is **not** listed in
   `bootstrap/providers.php` (which only registers `App`/`Auth`/`Event`/`RouteServiceProvider`), so
   `require base_path('routes/channels.php')` (`BroadcastServiceProvider.php:19`) never executes.
4. **CORS wildcard origin** (`config/cors.php:22`) — see Config review above.
5. **No parent-cycle check on `parent_id`** — already self-documented in `README.md:140-141`
   ("Known limitations"), repeated here with the concrete fix direction (a validation rule that walks
   the ancestor chain, or a recursive CTE check) for `docs/TECHNICAL_DEBT.md`.
6. **Tests run only against SQLite**, production runs Postgres — enum/decimal/Postgres-specific
   behavior is never exercised by the gating suite (`phpunit.xml:27-28`).
7. **No index on `categories.parent_id`** — see Database section above.
8. **No `/health/live`/`/health/ready` HTTP endpoints** — only a raw TCP-connect `HEALTHCHECK`.
9. **No `openapi.yaml`** — only a hand-written `docs/api.md`.
10. **No root `LICENSE` file** despite `composer.json` declaring MIT — see Licence section above.
11. **No `Makefile`** — see Docker section above.
12. **Hardcoded Compose project name + `APP_PORT:-8080` default** — see Docker section above.
13. **CI ordering/gaps** — lint/audit after tests, no secret scan, no image scan, no concurrency
    group — see CI/CD section above.
14. **Unused scaffolding** carried from Phase 2, re-confirmed this phase: `guzzlehttp/guzzle` (prod,
    zero usage), `laravel/sail` (dev, zero usage), the entire npm/Vite asset pipeline (zero build
    step anywhere).
15. **`composer.json:63` `"minimum-stability": "dev"`** — looser than Composer's own default
    `"stable"`; harmless today (every locked package is already stable), carried from Phase 2.
16. **`actions/checkout` 3 majors behind live** (v4.2.2 pinned vs. live v7.0.1) — carried from Phase 2.
17. **2 stale (~2yr) Dependabot branches**, predate a full test-suite rewrite, not safely mergeable
    as-is — carried from Phase 2, Phase 4 triage.

### P3

1. **`ProductResource.price`** (`ProductResource.php:26`) string-concatenates two raw floats
   (`"10.5-20.25"`) with no currency/locale formatting — a display-shape smell, not a bug.
2. **Inconsistent date formatting** between `ProductResource` (`Y-m-d H:i:s`,
   `ProductResource.php:29-30`) and `CategoryResource` (`m/d/Y`, `CategoryResource.php:23-24`) in the
   same API.
3. **No API versioning** (`/api/v1/...`) — a flat `/api/*` today.
4. **`published` modeled as a string enum `Yes`/`No`** rather than boolean — consistent throughout
   (migration, validation, factory, resource) but unconventional REST modeling; a deliberate choice,
   not flagged as wrong.
5. **Tokens never expire** — self-documented in `README.md:142`.
6. **Redundant open bot PR** `#102` (intermediate `actions/checkout` v4.4.0 bump), superseded by
   `#106`'s v7 proposal — carried from Phase 2, Phase 4 triage.

## What's already right (not reopened by later phases without a reason)

See `docs/ARCHITECTURE.md`'s "Strengths" section — the response envelope, the already-fixed N+1/
validation/namespace bugs with their regression tests still in place, the digest-pinned non-root
Docker baseline, and the honestly-documented README/API-doc pair. CLAUDE.md's baseline-preservation
rule applies to all of this: later phases change it only with a stated reason, not by default.
