#!/usr/bin/env python3
"""Validate, stage, and promote cast corrections without rebuilding catalog relationships."""
import argparse
import json
from pathlib import Path

try:
    import psycopg
except ImportError as exc:
    raise SystemExit("psycopg is required: pip install 'psycopg[binary]'") from exc

IDENTITY_FIELDS = ("cast_id_name", "first_name", "middle_name", "last_name")


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"Missing required file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}") from exc


def normalized(value):
    if value is None:
        return None
    value = str(value).strip()
    return value or None


def validate_cast(rows):
    if not isinstance(rows, list):
        raise SystemExit("cast.json must contain a JSON array")

    ids = set()
    codes = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise SystemExit(f"cast.json record {index} is not an object")
        raw_id = str(row.get("cast_id", "")).strip()
        if not raw_id.isdigit() or int(raw_id) < 1:
            raise SystemExit(f"cast.json record {index} has invalid cast_id")
        cast_id = int(raw_id)
        if cast_id in ids:
            raise SystemExit(f"Duplicate cast_id in cast.json: {cast_id}")
        ids.add(cast_id)

        code = normalized(row.get("cast_id_name"))
        if code:
            folded = code.casefold()
            if folded in codes:
                raise SystemExit(f"Duplicate cast_id_name in cast.json: {code}")
            codes.add(folded)

    return ids


def validate_corrections(rows, cast_ids):
    if not isinstance(rows, list):
        raise SystemExit("cast-corrections.json must contain a JSON array")

    keys = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise SystemExit(f"cast-corrections.json record {index} is not an object")

        key = normalized(row.get("correction_key"))
        reason = normalized(row.get("reason"))
        source = normalized(row.get("source_reference"))
        raw_id = str(row.get("cast_id", "")).strip()
        before = row.get("before")
        after = row.get("after")

        if not key:
            raise SystemExit(f"Correction record {index} is missing correction_key")
        if key in keys:
            raise SystemExit(f"Duplicate correction_key: {key}")
        keys.add(key)

        if not raw_id.isdigit() or int(raw_id) < 1:
            raise SystemExit(f"Correction {key} has invalid cast_id")
        if int(raw_id) not in cast_ids:
            raise SystemExit(f"Correction {key} references cast_id {raw_id}, which is absent from cast.json")
        if not reason:
            raise SystemExit(f"Correction {key} is missing reason")
        if not source:
            raise SystemExit(f"Correction {key} is missing source_reference")
        if not isinstance(before, dict) or not isinstance(after, dict):
            raise SystemExit(f"Correction {key} must contain before and after objects")

        for field in IDENTITY_FIELDS:
            if field not in before or field not in after:
                raise SystemExit(f"Correction {key} must include {field} in both before and after")



def validate_deletions(rows, cast_ids):
    if not isinstance(rows, list):
        raise SystemExit("cast-deletions.json must contain a JSON array")

    keys = set()
    deleted_ids = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise SystemExit(f"cast-deletions.json record {index} is not an object")

        key = normalized(row.get("deletion_key"))
        reason = normalized(row.get("reason"))
        source = normalized(row.get("source_reference"))
        raw_id = str(row.get("cast_id", "")).strip()

        if not key:
            raise SystemExit(f"Deletion record {index} is missing deletion_key")
        if key in keys:
            raise SystemExit(f"Duplicate deletion_key: {key}")
        keys.add(key)

        if not raw_id.isdigit() or int(raw_id) < 1:
            raise SystemExit(f"Deletion {key} has invalid cast_id")

        cast_id = int(raw_id)
        if cast_id in cast_ids:
            raise SystemExit(f"Deletion {key} references cast_id {cast_id}, which is still present in cast.json")
        if cast_id in deleted_ids:
            raise SystemExit(f"Duplicate cast_id in cast-deletions.json: {cast_id}")
        deleted_ids.add(cast_id)

        if not normalized(row.get("cast_id_name")):
            raise SystemExit(f"Deletion {key} is missing cast_id_name")
        if not reason:
            raise SystemExit(f"Deletion {key} is missing reason")
        if not source:
            raise SystemExit(f"Deletion {key} is missing source_reference")

    return deleted_ids

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dsn", required=True)
    parser.add_argument("--data-dir", default="data")
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()

    root = Path(args.data_dir)
    cast_rows = load_json(root / "cast.json")
    correction_rows = load_json(root / "cast-corrections.json")
    deletion_rows = load_json(root / "cast-deletions.json")

    cast_ids = validate_cast(cast_rows)
    validate_corrections(correction_rows, cast_ids)
    validate_deletions(deletion_rows, cast_ids)

    print(f"validated cast records: {len(cast_rows)}")
    print(f"validated correction records: {len(correction_rows)}")
    print(f"validated deletion records: {len(deletion_rows)}")

    if args.validate_only:
        return

    with psycopg.connect(args.dsn) as conn:
        with conn.cursor() as cur:
            for name, payload in (
                ("cast.json", cast_rows),
                ("cast-corrections.json", correction_rows),
                ("cast-deletions.json", deletion_rows),
            ):
                cur.execute(
                    """INSERT INTO stage.source_document(source_name,payload,loaded_at)
                       VALUES(%s,%s::jsonb,now())
                       ON CONFLICT(source_name)
                       DO UPDATE SET payload=excluded.payload,loaded_at=now()""",
                    (name, json.dumps(payload, ensure_ascii=False)),
                )
            cur.execute("SELECT import.promote_cast()")
            result = cur.fetchone()[0]
            print(json.dumps(result, indent=2, default=str))
        conn.commit()


if __name__ == "__main__":
    main()
