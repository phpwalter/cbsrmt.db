# Cast Data Corrections

`data/cast.json` is the authoritative cast source. Correct names there first. Do not change an existing `cast_id` when correcting spelling, missing names, punctuation, or `cast_id_name`.

Every identity correction must also be recorded in `data/cast-corrections.json`. The targeted promotion path refuses to change `cast_id_name`, `first_name`, `middle_name`, or `last_name` unless the current database values and corrected JSON values exactly match a correction record.

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

The command validates duplicate IDs and image keys, stages only `cast.json` and `cast-corrections.json`, and calls `import.promote_cast()`.

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
- does not insert, delete, or rewrite `catalog.episode_cast`
- verifies the total episode/cast relationship count is unchanged

The full import/rebuild path stages `cast-corrections.json` and replays its history into `import.cast_correction_audit`, so correction provenance survives a database rebuild.
