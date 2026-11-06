# product-catalog-api
![Views](https://hits.sh/github.com/RasimAghayev/product-catalog-api.svg?label=views&color=0e75b6)


A catalogue API for a company brief: categories with subcategories, and
products that belong to at least one category and carry a price range.

Laravel 12 on PHP 8.4, PostgreSQL 16, and a Docker Compose stack for the
development, the tests and the production build. The API is a JSON API under
`/api`, and the only page is the welcome page of the framework.

## What it does

- **Categories** form a tree: a category has an optional parent, so a
  category is either a top level one or a subcategory.
- **Products** carry a name, a price range (`priceFrom`, `priceTo`), a
  published flag and a soft delete. A product belongs to between two and ten
  categories, through the table `category_product`.
- **The catalogue is read by everyone.** The writes ask for a token of
  Sanctum, so a product can only be created, changed or deleted by an
  authenticated caller.

The contract of every endpoint is in [`docs/api.md`](docs/api.md).

## Running it

A `Makefile` wraps the commands below (`make build`, `make up`, `make
migrate`, `make token EMAIL=you@example.com`, ...; `make help`-style targets
are documented inline in the file itself). `make up` never starts the stack
on a red build or test: it depends on `make verify` (build the images, then
run the test stage) first. Either the raw `docker compose` calls or the
`make` targets work; they call the same stack.

```shell
mkdir -p var
cp .env.example var/.env
docker compose --env-file var/.env build
docker compose --env-file var/.env up -d
```

Then:

```shell
docker compose --env-file var/.env exec app php artisan migrate
docker compose --env-file var/.env exec app php artisan api:token tester@example.com
```

Every command of the stack needs `--env-file var/.env`, because the variables
of the stack live in that file and not in the root of the project. The
passwords of the database have no default value: the stack refuses to start
until they are set.

The command prints a token. Send it in the header
`Authorization: Bearer <token>`.

The application is reachable at `http://localhost:20110` by default — this
program's reserved port block for this repo
(`projects/info/state/ports.md`: `20110-20119`). `APP_PORT` in `var/.env`
moves it to another host port.

Every bind mount of the stack lives under `var/`, so the repository holds no
state of its own: `var/.env` is the local environment file and
`var/postgres` is the data of the database. Named volumes are not used.

The key of the application is read from the environment. When the environment
does not carry one, the container generates a random key for itself and
writes a note about it into the log.

## The endpoints

| Method | Path | Auth | What it does |
|---|---|---|---|
| GET | `/api/category` | – | The categories, a page at a time. |
| GET | `/api/category/{id}` | – | One category. |
| POST | `/api/category` | token | Creates a category. |
| PUT | `/api/category/{id}` | token | Changes a category. |
| DELETE | `/api/category/{id}` | token | Deletes a category that no product uses. |
| GET | `/api/product` | – | The products, a page at a time. |
| GET | `/api/product/{id}` | – | One product. |
| POST | `/api/product` | token | Creates a product. |
| PUT | `/api/product/{id}` | token | Changes a product and its categories. |
| DELETE | `/api/product/{id}` | token | Deletes a product. The row stays, with a date of the deletion. |

A listing takes `per_page` (15 by default, 100 at most) and `page`.

## Tests

Both gates run inside the project's own Docker images. Nothing has to be
installed on the machine.

```shell
docker compose --env-file var/.env --profile test run --rm test                                  # phpunit
docker compose --env-file var/.env --profile test run --rm --entrypoint ./vendor/bin/pint test --test   # the linter
docker compose --env-file var/.env --profile test run --rm --entrypoint composer test audit --no-interaction --abandoned=report
```

The suite runs against an in memory SQLite database, so it needs neither a
database nor a network. It covers the two listings, the two writes, the
validation of the requests, the authentication and the error answers.

The linter is Laravel Pint. The rules are the ones of Laravel, and the
directories of the runtime state are excluded in `pint.json`.

## CI/CD

`.github/workflows/ci.yml` runs the same gates on every push and every pull
request:

| Step | Command | Gate |
|---|---|---|
| Validate the compose file | `docker compose config --quiet` | ✅ |
| Build the test image | `docker compose build test` | ✅ |
| Test suite | `docker compose --profile test run --rm test` | ✅ |
| Linter | `pint --test` | ✅ |
| Dependency audit | `composer audit` | ✅ |
| Build the application image | `docker compose build app` | ✅ |
| Build the database image | `docker compose build postgres` | ✅ |

The runner needs a Docker daemon and nothing else — no PHP toolchain is
installed on it. The workflow reads the repository only, never prints a
secret and never publishes anything, and `actions/checkout` is pinned to a
commit hash so the tag cannot move under the pipeline.

Two permanent branches exist: `master` (the released state) and `test` (the
integration state). A change is delivered as a pull request from a
`feature/*` branch into `test`, and from `test` into `master`.

## The stack

| Part | Choice |
|---|---|
| Language | PHP 8.2 or newer, the image runs 8.4 |
| Framework | Laravel 12 |
| Database | PostgreSQL 16, SQLite for the tests |
| Authentication | Sanctum, a token per caller |
| Web server | Apache with the rewrite module, the process runs as `www-data` on port 8080 |
| Tests | PHPUnit 11, Laravel Pint as the linter |
| Dependency audit | `composer audit` |

The base images are pinned by digest, so a rebuild of the project uses the
same runtime as the last one.

## Known limitations

- **The catalogue has no search.** The listings return the rows in the order
  of their id, and the only parameter is the size of the page.
- **A product is not versioned.** A change of a product overwrites the old
  values, and the date of the change is kept.
- **A category cannot be a child of itself.** The rule is not checked by the
  validation, so a cycle of two categories is possible in the data.
- **The tokens do not expire.** A token is valid until it is removed.
- **No license file.**
