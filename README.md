# CBS Radio Mystery Theater Database

This repository contains the source data and MySQL rebuild artifacts for the CBS Radio Mystery Theater catalog.

## Normalized model

The database uses the following core relationships:

```text
genre 1 ─────── * episodes

episodes 1 ─────── * appear * ─────── 1 cast

episodes 1 ─────── * episode_writers * ─────── 1 cast

episodes 1 ─────── 0..1 episode_adaptations
```

### Tables

#### `genre`

Reference data for episode genres.

- `genre_id` — primary key
- `genre_name`

#### `cast`

The canonical person table. Actors and writers share the same identity domain.

- `cast_id` — primary key
- `cast_id_name` — stable human-readable identifier
- person/profile fields from the legacy cast and writer datasets

`data/writers.json` is retained as a historical/reference source, but writers are merged into `data/cast.json` by `cast_id` for the canonical database representation.

#### `episodes`

Episode facts only.

- `episode_id` — primary key
- `episode_date`
- `episode_name`
- `episode_plot`
- `genre_id` — foreign key to `genre.genre_id`

Legacy `episode_writer` and `origwriter` fields are removed after their information is migrated into relationship tables.

#### `appear`

Actor-to-episode association table.

- `appear_id` — primary key
- `episode_id` — foreign key to `episodes.episode_id`
- `cast_id` — foreign key to `cast.cast_id`

The former duplicate fields `episode_date`, `episode_name`, and `cast_id_name` are deliberately removed.

#### `episode_writers`

Writer-to-episode association table.

- `episode_writer_id` — primary key
- `episode_id` — foreign key to `episodes.episode_id`
- `cast_id` — foreign key to `cast.cast_id`

The `(episode_id, cast_id)` pair is unique and supports multiple writers per episode.

#### `episode_adaptations`

Optional adaptation metadata for an episode.

- `episode_id` — primary key and foreign key to `episodes.episode_id`
- `adapted` — source adaptation statement

Adaptation data is sourced primarily from `https://www.cbsrmt.com/adaptions.html`. Existing non-empty legacy `origwriter` values are used only as fallbacks when that page has no entry.

## Source files

```text
data/
  cast.json
  episodes.json
  episode_adaptations.json
  episode_writers.json
  genre.json
  writers.json
```

`writers.json` remains in the repository by design even though it is no longer represented as a separate database table.

## Rebuild

Install dependencies:

```bash
python -m pip install -r requirements.txt
```

Rebuild normalized data and SQL:

```bash
python tools/rebuild_data.py
```

Validate the generated artifacts:

```bash
python tools/validate_data.py
```

The rebuild is deterministic for a given repository state and adaptation-page response. It:

1. merges writer records into cast by `cast_id`;
2. resolves episode writer strings to cast IDs without fuzzy guessing;
3. reduces `appear` to its three relational columns;
4. parses the CBSRMT adaptations catalog;
5. preserves legacy `origwriter` values as fallback adaptation records;
6. removes `episode_writer` and `origwriter` from normalized episodes;
7. rebuilds `sql/cbs.sql` using `utf8mb4` and explicit foreign keys;
8. writes reconciliation reports for every unresolved or conflicting legacy value.

## Reconciliation reports

Generated files under `reports/`:

```text
adaptation-origwriter-fallbacks.json
adaptation-unmatched.json
appear-reconciliation.json
migration-summary.json
writer-cast-conflicts.json
writer-unresolved.json
```

These reports are intentional. The migration does not silently guess ambiguous legacy relationships.

## Referential behavior

- `genre -> episodes`: `ON DELETE RESTRICT`
- `episodes -> appear`: `ON DELETE CASCADE`
- `episodes -> episode_writers`: `ON DELETE CASCADE`
- `episodes -> episode_adaptations`: `ON DELETE CASCADE`
- `cast -> appear`: `ON DELETE RESTRICT`
- `cast -> episode_writers`: `ON DELETE RESTRICT`

Historical credits therefore cannot disappear merely because a cast/person record is deleted.

## Workbench model

`sql/cbs.mwb` and `sql/cbs.mwb.bak` are intentionally not modified by this normalization effort.
