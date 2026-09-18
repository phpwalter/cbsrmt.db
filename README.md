# CBS Radio Mystery Theater PostgreSQL Database

PostgreSQL implementation for the CBS Radio Mystery Theater Episode Guide.

## Design

The database separates canonical episodes from broadcast history.

- `catalog.episode`: exactly one row per canonical CBS RMT episode (1-1399).
- `catalog.broadcast`: one row per calendar/broadcast event: `original`, `repeat`, or `no_broadcast`.
- `catalog.person`: shared person master for actors and writers.
- normalized junction tables for cast, writers, genres, and literary adaptations.
- `catalog.episode_media`: future audio metadata/stream URLs; audio bytes are not served by PostgreSQL.
- thumbnail URLs are derived as `/public/assets/episodes/{episode_number}.png` and are not stored.

## Access boundary

Application roles do not query production tables directly.

- `api.*`: read/query functions for the public API.
- `admin.*`: mutation functions.
- `stage.*` + `import.*`: controlled JSON staging and promotion.

## Fresh installation

A fresh checkout now includes one-command installers for both Windows PowerShell and Unix-like shells.

Prerequisites:

- PostgreSQL client tools, including `psql`
- Python 3 with `venv`
- an existing empty PostgreSQL database
- credentials with permission to create schemas, extensions, and the CBS RMT roles

The installer creates the PostgreSQL schemas, tables, indexes, roles, import/API/admin functions, Python virtual environment, reconciles and imports all JSON data, runs integrity tests, runs API-contract tests, and prints final database counts.

### Windows PowerShell

```powershell
.\install\fresh_install.ps1 `
    -Host localhost `
    -Port 5432 `
    -Database cbsrmt `
    -User postgres
```

### Linux/macOS

```bash
bash install/fresh_install.sh \
    --host localhost \
    --port 5432 \
    --database cbsrmt \
    --user postgres
```

Authentication uses normal PostgreSQL/libpq behavior such as `PGPASSWORD`, `.pgpass`, or an interactive password prompt.

### Rebuild mode

A normal fresh install refuses to overwrite existing CBS RMT schemas.

To intentionally rebuild the CBS RMT application schemas and data:

```powershell
.\install\fresh_install.ps1 -Database cbsrmt -User postgres -Rebuild
```

or:

```bash
bash install/fresh_install.sh --database cbsrmt --user postgres --rebuild
```

Rebuild mode drops only these application schemas:

```text
catalog
api
admin
stage
import
```

It does **not** drop the PostgreSQL database.

## Manual installation

The individual pieces remain runnable for development and debugging:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f install/schema.sql
python -m venv .venv
python -m pip install -r requirements.txt
python tools/load_json.py --dsn "$DATABASE_URL" --data-dir data
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/001_integrity.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/002_api_contract.sql
```

`install/schema.sql` orchestrates all migrations and database functions in the required order.

The loader reconciles the broadcast-history source before staging. Raw JSON files remain unchanged.

## Invariants

- exactly 1,399 canonical episodes.
- default API page size is 5, maximum 100.
- repeat broadcasts reference a canonical episode.
- no-broadcast dates have no episode and no broadcast sequence.
- cast/writer/genre/adaptation relationships are foreign-key enforced.
- `0000-00-00` source dates normalize to SQL `NULL`.
- a successful fresh install must pass both SQL test suites.

See `docs/` for reconciliation and OpenAPI mapping details.
