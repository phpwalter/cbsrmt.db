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

## Installation

Run the files in `migrations/` in lexical order, then load the functions in `functions/`.

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_extensions_and_schemas.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/002_catalog_tables.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/003_relationship_tables.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/004_indexes.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/005_staging_tables.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/006_roles_and_grants.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f functions/import/promote_json.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f functions/api/catalog.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f functions/admin/catalog.sql
python tools/load_json.py --dsn "$DATABASE_URL" --data-dir data
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/001_integrity.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/002_api_contract.sql
```

The loader reconciles the broadcast-history source before staging. Raw JSON files remain unchanged.

## Invariants

- exactly 1,399 canonical episodes.
- default API page size is 5, maximum 100.
- repeat broadcasts reference a canonical episode.
- no-broadcast dates have no episode and no broadcast sequence.
- cast/writer/genre/adaptation relationships are foreign-key enforced.
- `0000-00-00` source dates normalize to SQL `NULL`.

See `docs/` for reconciliation and OpenAPI mapping details.
