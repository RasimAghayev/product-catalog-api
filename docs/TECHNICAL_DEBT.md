# Technical debt — product-catalog-api

Phase 3 (`auditor`), 2026-11-06. Debt items are the P1-P3 issues from `docs/REPOSITORY_AUDIT.md`,
re-grouped here by *why it's debt* and *who should pay it down*, plus explicit non-debt calls where a
principle could apply but doesn't earn its place (CLAUDE.md standing decision 7's KISS/YAGNI
tiebreaker). An exception to standing decision 1 ("latest versions, always") needs a written blocker
here — none is claimed; every gap below is a scheduled upgrade, not a declared permanent exception.

## Correctness debt (owner: Phase 6 upgrade / Phase 9 hardener / Phase 11 tester)

| Item | Why it's debt | Fix owner |
|---|---|---|
| No transaction around product create/update + category sync | Partial failure leaves a product with 0 categories, violating the DB's implicit 2-10 invariant | Phase 9 (hardener, correctness-adjacent) — small, no architectural change |
| Trashed-product show/update 404 vs. listing-shows-it | Undocumented inconsistency in a documented, intentional feature | Needs a product decision first (keep/change), then Phase 9 + Phase 11 regression test |
| `Category::destroy` doesn't check for child categories | Silent, undocumented tree-detachment on parent delete (DB-safe, UX-surprising) | Phase 9 (add the check + a clear error, mirroring the existing product-usage guard) |
| No parent-cycle check on `parent_id` | Self-documented in README; a validation gap, not a data-integrity one (FK still resolves) | Phase 9 (add an ancestor-walk validation rule) |

## Dependency / platform debt (owner: Phase 6 upgrader, inventory already done by Phase 2)

All quantified in `projects/info/deps/product-catalog-api.md` — not re-derived here, only routed:

- 4 of 11 direct PHP packages a major behind (`guzzlehttp/guzzle`, `laravel/framework`,
  `laravel/tinker`, `phpunit/phpunit`) — each already has an open, verified-mergeable-looking Renovate
  PR.
- 8 live Composer security advisories (Symfony family) — same-minor patch fixes, no breaking change
  expected.
- `package.json`/`package-lock.json` desync with a live `vite`/`laravel-vite-plugin` peer conflict.
- 3 Docker base images with stale digests within their own tag; `postgres:16-alpine` additionally 2
  majors behind (16→18, skipping 17); `php:8.4-apache` 1 minor line behind (8.4→8.5).
- `actions/checkout` pinned 3 majors behind live (v4.2.2 → v7.0.1), plus one redundant open bot PR.
- `composer.json`'s `"minimum-stability": "dev"` — looser than Composer's default; no current effect
  (every locked package is already the stable tag) but worth tightening to `"stable"` explicitly so a
  future `composer update` can't silently accept an unstable version without an explicit decision
  entry (standing decision 3).

None of these are declared as a permanent exception — all are scheduled for Phase 6 per the
dependency map's upgrade order (runtime/base image → framework → libraries → dev tools → CI actions).

## Dead-code debt (owner: Phase 7 cleaner)

Proven by direct tracing/grep this phase and Phase 2, not guessed:

- `guzzlehttp/guzzle` (direct, prod) — zero usage; also redundant (Laravel's own framework already
  bundles an HTTP client dependency).
- `laravel/sail` (direct, dev) — zero usage; repo has its own hand-written Docker Compose stack.
- The entire npm/Vite asset pipeline (`axios`, `laravel-vite-plugin`, `lodash`, `postcss`, `vite`,
  `vite.config.js`, `resources/js`, `resources/css`) — zero build step anywhere in Docker/CI, zero
  `@vite(...)` call in any view. **Decision needed before Phase 7 can act** — see "Decision point"
  below; this is explicitly not decided by this phase (R1).
- `app/Providers/BroadcastServiceProvider.php` + `routes/channels.php` — the provider is not
  registered in `bootstrap/providers.php`, so the channel file it would load is unreachable code.
  Confirmed by direct trace, not by static-tool guess.

**Caveat applied before any of the above is actually deleted in Phase 7**: per CLAUDE.md's dead-code
rule, check reflection/dynamic invocation and framework auto-registration before deleting — already
partially done here (e.g., `spatie/laravel-ignition`'s auto-discovery was checked and is *not* flagged
as dead precisely because auto-discovery could be loading it invisibly to a static grep).

## Decision point this audit surfaces but does not resolve (R1 — out of Phase 3's scope to decide)

**What should happen to the npm/Vite toolchain?** Two honest options, both consistent with CLAUDE.md:

1. **Remove it** (Phase 7, YAGNI/standing-decision-6): nothing in Docker/CI/views ever used it, there
   is no evidence anywhere in the repo of a planned frontend, and it currently carries a live
   version conflict that would only get worse the longer it's upgraded without being exercised.
2. **Fix and keep it** (Phase 6): bump `vite` to `^8.0.0` in `package.json` (resolves the peer
   conflict and the version gap in the same change, per Phase 2's own note), regenerate
   `package-lock.json`, and treat it as a real (if currently unbuilt) part of the stack — appropriate
   only if there is an actual, stated plan to serve a Vite-built asset from this API at some point.

This phase recommends **option 1 (remove)** as the default under YAGNI, absent any evidence of
planned use — but defers the actual decision to whoever owns Phase 6/7 on this repo, since removing a
whole manifest pair is bigger than this phase's "docs only" scope and deserves its own explicit
call, not a default baked silently into an audit document.

## Architecture debt — explicitly NOT treated as debt (KISS/YAGNI tiebreaker)

Per CLAUDE.md standing decision 7, a principle only applies where it solves a *real, present*
problem. This phase explicitly declines to flag the following as debt:

- **No service/repository layer.** Two entities, CRUD plus one pivot sync, no multi-step workflows,
  no external system to swap. Introducing Clean/Hexagonal ports-and-adapters here would add
  indirection with nothing real to abstract — Phase 8 should write the ADR confirming this rather than
  introduce layers.
- **No DDD aggregates / bounded contexts.** There is no real domain complexity or invariant beyond
  "a product needs 2-10 categories" and "a category tree has no cycles" — both are enforceable as
  plain validation/transaction fixes (see Correctness debt above), not evidence of a missing
  aggregate boundary.
- **No event-driven architecture.** Nothing in this repo reacts asynchronously to anything; a direct
  call is simpler and there is no present integration need for domain events.
- **The legacy `RouteServiceProvider` pattern** (flagged as P2 in `docs/REPOSITORY_AUDIT.md`) *is*
  real debt — convention drift against the upgraded framework's own skeleton — but it is a Phase 7
  "re-shape to the upgraded stack's conventions" item, not an architecture-principle question; listed
  here only to distinguish it from the "not debt" items above.

## Documentation / legal debt (owner: Phase 4 git-steward or Phase 15 documenter)

- No root `LICENSE` file despite `composer.json` declaring `"license": "MIT"` — add the actual MIT
  text; no legal risk today (every dependency is permissive), just an inconsistency.
- No `openapi.yaml` machine-readable API contract — `docs/api.md` is accurate but hand-written;
  Phase 9's dual-mode/observability bullet expects a machine-readable spec in the repo.

## Operational debt (owner: Phase 5 container-engineer / Phase 9 hardener / Phase 15 documenter)

- No `Makefile` at all — every documented command is a raw `docker compose ...` call.
- Hardcoded Compose project name (`"task-brief-company"`) and `APP_PORT:-8080` default, not
  reconciled with this program's reserved port block (`20110-20119`) or its per-agent
  `COMPOSE_PROJECT_NAME` isolation convention.
- `HEALTHCHECK` is TCP-connect-only, no real `/health/live`/`/health/ready` HTTP endpoints.
- No backup/recovery policy for the Postgres bind-mount data — acceptable at this scale, worth one
  documented line rather than silence.

## CI/CD debt (owner: Phase 10 ci-engineer)

Lint/audit ordered after the full test run rather than before; no secret-scan step; no image/
dependency vulnerability scan beyond `composer audit`; no `concurrency`/`cancel-in-progress`; no
`paths` filter. None of this makes the pipeline wrong today — it already Docker-only, pinned-by-SHA,
and never leaks a secret — these are runner-time-budget and defense-in-depth improvements, not fixes
to a broken gate.
