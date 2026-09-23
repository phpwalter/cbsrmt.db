# Cast Data Corrections

`data/cast.json` is the authoritative cast source. Correct names there first. Do not change an existing `cast_id` when correcting spelling, missing names, punctuation, or `cast_id_name`.

Every identity correction must also be recorded in `data/cast-corrections.json`. The targeted promotion path refuses to change `cast_id_name`, `first_name`, `middle_name`, or `last_name` unless the current database values and corrected JSON values exactly match a correction record.

Intentional removals are recorded separately in `data/cast-deletions.json`. A deleted `cast_id` is retired permanently; remaining IDs are never renumbered or reused. The database refuses deletion when the person still has an `episode_cast` or `episode_writer` relationship.

## Correction record format

```json
{
  "correction_key": "cast-0123-first-name-20260922",
  "cast_id": "123",
  "reason": "Correct missing first name",
  "source_reference": "Verified against <source name or citation>",
  "before": {
    "cast_id_name": "jsmith",
    "first_name": "",
    "middle_name": "",
    "last_name": "Smith"
  },
  "after": {
    "cast_id_name": "jsmith",
    "first_name": "John",
    "middle_name": "",
    "last_name": "Smith"
  }
}
```

Use a unique, stable `correction_key`. Keep empty source values as empty strings in the JSON. `source_reference` must identify the evidence used to verify the correction.


## Deletion record format

Only remove a record from `cast.json` after confirming its `cast_id` is unused by both acting and writing relationships. Record the removal in `cast-deletions.json`:

```json
{
  "deletion_key": "cast-0126-unused-record",
  "cast_id": "126",
  "cast_id_name": "amadsen",
  "first_name": "A.",
  "middle_name": "",
  "last_name": "Madsen",
  "reason": "No acting appearance or episode-writer relationship exists for this cast_id.",
  "source_reference": "Validated against data/appearance.json and data/episode-writer.json"
}
```

Do not compact or renumber the remaining `cast_id` values. Gaps are intentional and preserve stable identity references.

## Apply corrections on Windows

After editing and committing both JSON files:

```powershell
.\install\apply_cast_corrections.ps1 `
    -Host localhost `
    -Port 5432 `
    -Database cbsrmt `
    -User root
```

Validation without changing PostgreSQL:

```powershell
.\install\apply_cast_corrections.ps1 -Database cbsrmt -User root -ValidateOnly
```

The command validates cast IDs, correction records, and deletion records; stages `cast.json`, `cast-corrections.json`, and `cast-deletions.json`; and calls `import.promote_cast()`.

## Apply corrections on Linux/macOS

```bash
bash install/apply_cast_corrections.sh \
  --host localhost \
  --port 5432 \
  --database cbsrmt \
  --user postgres
```

Add `--validate-only` to validate the files without changing PostgreSQL.

## Database guarantees

`import.promote_cast()`:

- updates existing `catalog.person` rows by stable `cast_id`
- rejects unknown `cast_id` values
- rejects duplicate `cast_id` and duplicate non-empty `cast_id_name` values
- requires an exact audit record for every identity change
- writes the applied correction to `import.cast_correction_audit`
- permits deletion only for IDs explicitly listed in `cast-deletions.json`
- rejects deletion when the person has acting or writer episode relationships
- records successful removals in `import.cast_deletion_audit`
- never renumbers or reuses surviving `cast_id` values
- does not insert, delete, or rewrite `catalog.episode_cast`
- verifies the total episode/cast relationship count is unchanged

The full import/rebuild path stages both audit JSON files and replays their history into `import.cast_correction_audit` and `import.cast_deletion_audit`, so correction and deletion provenance survive a database rebuild.
