.PHONY: build test verify up run down logs shell migrate token lint format audit clean ensure-env

# Every command of the stack needs var/.env (README's own documented
# convention) — the variables of the stack live there, not in the project
# root. This target creates it from the template the first time only — an
# existence check, not a file-mtime rule, so a later edit to .env.example
# never silently overwrites a developer's already-customized var/.env.
ensure-env:
	@test -f var/.env || { mkdir -p var && cp .env.example var/.env && echo "Created var/.env from .env.example — edit it if you need non-default values."; }

COMPOSE := docker compose --env-file var/.env

## Build the app + postgres images (not the test image — see `test`).
build: ensure-env
	$(COMPOSE) build app postgres

## Run the test stage (phpunit, the only gate the test image's own
## ENTRYPOINT runs). Fails (non-zero exit) if any test fails — this is the
## behavior contract (docs/BASELINE.md).
test: ensure-env
	$(COMPOSE) build test
	$(COMPOSE) --profile test run --rm test

## Build + test. `up` depends on this — nothing starts on a red build.
verify: build test

## Start the app stack in the background. Never starts without a green verify.
up: verify
	$(COMPOSE) up -d
	$(COMPOSE) ps

## Run the app stack in the foreground (Ctrl+C to stop).
run: verify
	$(COMPOSE) up

down: ensure-env
	$(COMPOSE) down

logs: ensure-env
	$(COMPOSE) logs -f

## Open a shell inside the running app container.
shell: ensure-env
	$(COMPOSE) exec app sh

## Apply pending migrations against the running postgres service.
migrate: ensure-env
	$(COMPOSE) exec app php artisan migrate --force

## Issue a Sanctum API token for the given email: make token EMAIL=you@example.com
token: ensure-env
	$(COMPOSE) exec app php artisan api:token $(EMAIL)

## Laravel Pint, run inside the test image (same gate CI runs).
lint: ensure-env
	$(COMPOSE) build test
	$(COMPOSE) --profile test run --rm --entrypoint ./vendor/bin/pint test --test

## Laravel Pint, auto-fix.
format: ensure-env
	$(COMPOSE) build test
	$(COMPOSE) --profile test run --rm --entrypoint ./vendor/bin/pint test

## composer audit (known-vulnerability check), run inside the test image.
## A pre-existing red result here (documented in docs/BASELINE.md) is a
## known Phase 6 finding, not a Phase 5 build gate — see CLAUDE.md standing
## decision 2 vs. the Phase 5 exit criterion.
audit: ensure-env
	$(COMPOSE) build test
	$(COMPOSE) --profile test run --rm --entrypoint composer test audit --no-interaction --abandoned=report

## Never deletes the database volume (var/postgres) without an explicit
## confirmation — CLAUDE.md's Docker standard forbids silent data loss.
## Pass CONFIRM=1 to also delete it.
clean: ensure-env
	$(COMPOSE) down --rmi local
ifeq ($(CONFIRM),1)
	rm -rf var/postgres
	@echo "var/postgres deleted."
else
	@echo "var/postgres kept. Re-run as 'make clean CONFIRM=1' to also delete it."
endif
