# Improvement roadmap — product-catalog-api

Phase 3 (`auditor`), 2026-11-06. This maps `docs/TECHNICAL_DEBT.md`'s items onto this program's own
phase sequence (`PROMPT.md` Phases 4-11, then the ecosystem phases). It is the execution order this
repo's plan in `projects/info/analysis/product-catalog-api.md` commits to — not a second, competing
plan. Each later phase agent still runs its own full checklist; this file exists so the ordering and
dependencies between fixes are explicit before any of them start.

## Immediate (Phase 4 — git hygiene, no code change)

1. Full-history `gitleaks` audit (this phase only checked the working tree).
2. Triage the 2 stale (~2yr) Dependabot branches (#76/#77) — close as superseded, they predate a full
   test-suite rewrite.
3. Close the redundant `actions/checkout` bot PR `#102` (superseded by `#106`).
4. Decide and execute the `master` → `main` rename (**Gate 4**) — update the CI trigger
   (`.github/workflows/ci.yml:8-10`) in the same change so the pipeline doesn't desync.
5. Add the actual MIT `LICENSE` file at repo root (cheap, no dependency on anything else).

## Near-term (Phase 5 — container baseline, then Phase 6 — upgrade)

6. Phase 5: add a `Makefile` (`build`/`test`/`verify`/`up`/`run`/`down` at minimum); parameterize the
   Compose project name and `APP_PORT` default against this repo's reserved block (`20110-20119`);
   record `docs/BASELINE.md` from the current, already-passing 30-test suite.
7. Phase 6, in dependency-map order: resolve the npm/Vite decision point first (see
   `docs/TECHNICAL_DEBT.md`'s "Decision point" — remove or fix-and-keep), then Symfony patch
   advisories (low-risk, do early), then `php:8.4→8.5`, `postgres:16→18` (budget real verification
   time for this 2-major jump), `composer:2` digest refresh, `laravel/framework 12→13`,
   `laravel/tinker 2→3`, `phpunit/phpunit 11→13` (skips 12 — check test syntax compat),
   `actions/checkout v4→v7`. Tighten `minimum-stability` to `"stable"` while here. Skip bumping
   `guzzlehttp/guzzle` to v8 — it has zero usage; let Phase 7 remove it instead of upgrading dead
   weight.

## Mid-term (Phase 7 — dead code & restructure)

8. Remove confirmed-dead code: `guzzlehttp/guzzle`, `laravel/sail`, `BroadcastServiceProvider.php` +
   `routes/channels.php`, and the npm/Vite toolchain **if** Phase 6 decided to remove rather than fix
   it.
9. Migrate route/rate-limiter registration from the legacy `RouteServiceProvider` pattern into
   `bootstrap/app.php`'s `withRouting()`/middleware config, matching Laravel 12's own skeleton
   convention; drop the now-empty provider class.

## Mid-term (Phase 8 — architecture)

10. Write the ADR confirming the deliberate **non**-adoption of a service/repository layer, DDD
    aggregates, and event-driven patterns for this repo (see `docs/TECHNICAL_DEBT.md`'s "explicitly
    not treated as debt" section) — a documented decision, not a structural change.

## Mid-term (Phase 9 — hardening)

11. Wrap product create/update + category sync in `DB::transaction()`.
12. Resolve the trashed-product show/update inconsistency (needs a product decision first: should
    `GET`/`PUT /api/product/{id}` work on a soft-deleted row or not — then implement and document
    whichever is chosen).
13. Add a child-category check to `Category::destroy` (mirroring the existing product-usage guard).
14. Add a parent-cycle validation rule for `categories.parent_id`.
15. Scope `config/cors.php`'s `allowed_origins` away from `['*']` before any real deployment.
16. Add `/health/live` + `/health/ready` HTTP endpoints (the current Docker `HEALTHCHECK` only
    proves the TCP port is open).
17. Add `openapi.yaml` as the machine-readable API contract (`docs/api.md` stays as the human-
    readable companion).

## Mid-term (Phase 10 — CI/CD)

18. Reorder lint/`composer audit` ahead of the full test run; add a secret-scan step; add an image/
    dependency vulnerability scan beyond `composer audit`; add `concurrency`/`cancel-in-progress` and
    a `paths` filter; measure and record real job duration in `docs/TEST_REPORT.md`.

## Mid-term (Phase 11 — tests)

19. Add regression tests for: "without a token" on `update`/`destroy` (both resources); the
    trashed-product show/update behavior (whatever Phase 9 decides); `Category::destroy` with a
    child category attached; the `php artisan api:token` command.
20. Add Postgres-specific test coverage (or document why SQLite-only remains acceptable) once Phase 6
    has upgraded Postgres.

## Long-term / opportunistic (no phase forces these; pick up only if touching the area anyway)

- API versioning (`/api/v1/...`) before any breaking contract change is ever needed.
- Consistent date formatting between `ProductResource` and `CategoryResource`.
- A friendlier `ProductResource.price` shape (currently a raw `"from-to"` string).
- Document the Postgres backup/recovery policy (even a one-line "none; data loss acceptable at this
  scale" is better than silence) in Phase 15's `docs/OPERATIONS.md`.

## Explicitly out of scope for this roadmap

- Phase 12 (merger), Phase 13 (lib-extractor), Phase 14 (renamer), Phase 16 (platform-engineer) — see
  the `n/a` calls and reasons in `projects/info/analysis/product-catalog-api.md`'s per-repo plan.
