# Changelog

All notable changes to this project are documented in this file.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## Phase 6 — Dependency upgrade (2026-11-06)

Every runtime, framework, library, dev-tool, base image, and CI action
upgraded to its live latest-stable release (CLAUDE.md standing decision 1).
Full command-by-command evidence: `projects/info/state/handoff/6/product-catalog-api.md`
in the modernization program's own tracking repo.

### Base images
- `php:8.4-apache` -> `php:8.5-apache` (current supported PHP line; 8.6 not yet released).
- `composer:2` digest refreshed (same tag, newer build).
- `postgres:16-alpine` -> `postgres:18-alpine` (latest stable major, skips 17).

### Breaking changes migrated
- **Postgres 18's image moved its default `PGDATA`** to a major-version-specific
  subdirectory of `/var/lib/postgresql` (`docker-library/postgres#1259`, enables
  `pg_upgrade --link`) and refuses to start against the old bind-mount layout.
  Fixed with the image's own documented backward-compatible override
  (`PGDATA=/var/lib/postgresql/data` on the `postgres` service) rather than
  restructuring the mount — no existing on-disk database to migrate.
- **Laravel 13's CSRF middleware rename**: `Illuminate\Foundation\Http\Middleware\VerifyCsrfToken`
  is renamed to `PreventRequestForgery` (the old name remains a deprecated
  alias). This repo's own `App\Http\Middleware\VerifyCsrfToken` now extends
  the real class directly. No runtime behavior change — this app's Sanctum
  config never enables the stateful/CSRF-aware SPA flow (bearer-token auth
  only).

### Dependencies (PHP / Composer)
| Package | Before | After |
|---|---|---|
| `laravel/framework` | v12.70.0 | v13.40.0 |
| `laravel/tinker` | v2.11.1 | v3.0.2 |
| `guzzlehttp/guzzle` | 7.16.1 | 8.3.1 |
| `guzzlehttp/promises` (transitive) | 2.6.0 | 3.1.0 |
| `guzzlehttp/psr7` (transitive) | 2.13.2 | 3.2.0 |
| `phpunit/phpunit` | 11.5.57 | 13.4.6 |
| `symfony/http-foundation` (transitive) | v7.4.21 | v8.1.11 |
| `symfony/http-kernel` (transitive) | v7.4.21 | v8.1.11 |
| `symfony/mime` (transitive) | v7.4.19 | v8.1.10 |
| `symfony/routing` (transitive) | v7.4.21 | v8.1.11 |
| `symfony/yaml` (dev, transitive) | v8.1.9 | v8.1.11 |
| `filp/whoops` (dev, transitive) | 2.18.7 | 2.19.2 |
| `spatie/flare-client-php` (dev, transitive) | 1.11.1 | 1.11.2 |
| `spatie/laravel-ignition` (dev) | 2.12.1 | 2.13.0 |
| `ralouphie/getallheaders` (transitive) | 3.0.3 | removed (no longer needed by `guzzlehttp/psr7` 3.x) |

`php` floor raised `^8.2` -> `^8.4` (matches `laravel/framework` 13's own
floor `^8.3` and `phpunit/phpunit` 13's floor `>=8.4.1`; the Docker image was
already on 8.4+ before this phase).

`composer.json`'s `minimum-stability` tightened `dev` -> `stable` (every
locked package was already stable; closes the gap so a future
`composer update` can't silently accept an unstable version without an
explicit decision entry).

### Security
`composer audit --locked`: **8 advisories (5 Symfony packages) -> 0**. Seven
were resolved as a side effect of the `laravel/framework` 13 bump (its own
required Symfony floor already sits above every patched version); the
eighth (`symfony/yaml`, dev-only via `laravel/sail`) was bumped directly.

### CI
- `actions/checkout` pinned by commit SHA (`v4.2.2` -> `v7.0.1`,
  `3d3c42e5aac5ba805825da76410c181273ba90b1`).
- Added `renovate.json` (repo root) formalizing the already-active Renovate
  bot's policy; npm manager explicitly disabled (dead scaffolding scheduled
  for removal in Phase 7).

### Not changed / out of scope
See `docs/TECHNICAL_DEBT.md` and the Phase 6 handoff's "Out-of-scope
findings" for items noticed but routed to a later phase (npm/Vite removal,
health-endpoint, correctness debt, CI pipeline redesign, etc.).
