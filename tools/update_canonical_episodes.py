#!/usr/bin/env python3
"""Update canonical episode titles and original air dates from the authoritative dataset.

Rules:
- Episode Number is the key.
- Only episode_name and original_air_date may be updated.
- Only rows whose stored values differ are updated.
- All other episode metadata remains untouched.
- Source titles are already canonicalized in data/canonical_episodes.json.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    import psycopg
except ImportError as exc:
    raise SystemExit("psycopg is required: pip install 'psycopg[binary]'") from exc


def load_source(path: Path) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        raise ValueError("Canonical episode source must be a JSON array.")
    return payload


def update_episodes(conn, source: list[dict], dry_run: bool = False) -> dict:
    report = {
        "source_rows": len(source),
        "database_rows_checked": 0,
        "unchanged_rows": 0,
        "updated_rows": 0,
        "missing_episode_numbers": [],
        "changes": [],
    }

    with conn.cursor() as cur:
        for row in source:
            episode_number = int(row["episode_number"])
            episode_name = str(row["episode_name"])
            original_air_date = str(row["original_air_date"])

            cur.execute(
                """
                SELECT episode_name, original_air_date
                  FROM catalog.episode
                 WHERE episode_number = %s
                """,
                (episode_number,),
            )
            current = cur.fetchone()

            if current is None:
                report["missing_episode_numbers"].append(episode_number)
                continue

            report["database_rows_checked"] += 1

            current_name = current[0]
            current_date = current[1].isoformat()

            name_changed = current_name != episode_name
            date_changed = current_date != original_air_date

            if not name_changed and not date_changed:
                report["unchanged_rows"] += 1
                continue

            change = {
                "episode_number": episode_number,
                "old_episode_name": current_name,
                "new_episode_name": episode_name,
                "old_original_air_date": current_date,
                "new_original_air_date": original_air_date,
                "title_changed": name_changed,
                "date_changed": date_changed,
            }
            report["changes"].append(change)

            if not dry_run:
                cur.execute(
                    """
                    UPDATE catalog.episode
                       SET episode_name = %s,
                           original_air_date = %s::date,
                           updated_at = now()
                     WHERE episode_number = %s
                    """,
                    (episode_name, original_air_date, episode_number),
                )

            report["updated_rows"] += 1

    if dry_run:
        conn.rollback()
    else:
        conn.commit()

    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dsn", required=True)
    parser.add_argument(
        "--source",
        default="data/canonical_episodes.json",
        help="Canonical episode title/date JSON file.",
    )
    parser.add_argument(
        "--report",
        default="reports/canonical-episode-update-report.json",
        help="Output JSON report path.",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    source = load_source(Path(args.source))

    with psycopg.connect(args.dsn) as conn:
        report = update_episodes(conn, source, dry_run=args.dry_run)

    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(json.dumps(report, indent=2, ensure_ascii=False))
    print(f"Report written to: {report_path}")


if __name__ == "__main__":
    main()
