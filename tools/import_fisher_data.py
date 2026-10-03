#!/usr/bin/env python3
"""Import Fisher rubric ratings and cast/role data into the CBS RMT catalog.

Rules:
- Episode Number is the key.
- Episode title must match the live database after normalization.
- Title mismatches are skipped and reported.
- Verified episodes have their cast replaced by the supplied cast/role list.
- The first supplied performer is the star; remaining performers are co-stars.
- Unmatched performers are skipped and reported.
- Bracketed uncertainty annotations are removed from stored character names.
- fisher_rubric and recording metadata are updated only for verified episodes.
- recording_quality preserves the explicit source classification.
- commercials and news accept TRUE/FALSE boolean values.
"""

from __future__ import annotations

import argparse
import json
import re
import unicodedata
from pathlib import Path

try:
    import psycopg
except ImportError as exc:
    raise SystemExit("psycopg is required: pip install 'psycopg[binary]'") from exc


TRAILING_ARTICLE = re.compile(r"^(.*?)\s+\[(The|An|A)\]\s*$", re.IGNORECASE)
UNCERTAIN_VALUE = re.compile(r"\[(?:uncertain|unclear)\s*:\s*([^\]]+)\]", re.IGNORECASE)
UNCERTAIN_EMPTY = re.compile(r"\[(?:uncertain|unclear)\]", re.IGNORECASE)


def move_trailing_article(value: str) -> str:
    match = TRAILING_ARTICLE.match(value.strip())
    if not match:
        return value.strip()
    return f"{match.group(2)} {match.group(1)}"


def normalize_title(value: str) -> str:
    value = move_trailing_article(value)
    value = unicodedata.normalize("NFKD", value)
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = value.casefold().replace("&", " and ").replace("’", "'")
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return " ".join(value.split())


def normalize_person_name(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = value.casefold().replace("’", "'")
    value = re.sub(r"[.'\"]", "", value)
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return " ".join(value.split())


def clean_character_name(value: str) -> str | None:
    value = UNCERTAIN_VALUE.sub(lambda m: m.group(1).strip(), value)
    value = UNCERTAIN_EMPTY.sub("", value)
    value = re.sub(r"\s+", " ", value).strip(" ;,/")
    return value or None


def parse_credit(value: str) -> tuple[str, str | None] | None:
    parts = re.split(r"\s+as\s+", value.strip(), maxsplit=1, flags=re.IGNORECASE)
    if len(parts) != 2:
        return None
    actor = parts[0].strip()
    character = clean_character_name(parts[1])
    if not actor:
        return None
    return actor, character


def parse_optional_bool(value, field_name: str) -> bool | None:
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().upper()
        if normalized == "TRUE":
            return True
        if normalized == "FALSE":
            return False
    raise ValueError(f"{field_name} must be TRUE/FALSE or null, got {value!r}")


def normalize_recording_quality(value) -> str | None:
    if value is None or value == "":
        return None
    normalized = str(value).strip().upper()
    if normalized not in {"EXCELLENT", "GOOD", "FAIR", "POOR"}:
        raise ValueError(
            "recording_quality must be EXCELLENT, GOOD, FAIR, POOR, or null"
        )
    return normalized


def load_source(path: Path) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        raise ValueError("Fisher source data must be a JSON array.")
    return payload


def build_person_index(cur) -> tuple[dict[str, int], dict[str, list[int]]]:
    cur.execute(
        """
        SELECT person_id,
               nullif(btrim(concat_ws(' ', first_name, middle_name, last_name)), '')
        FROM catalog.person
        ORDER BY person_id
        """
    )
    unique: dict[str, int] = {}
    ambiguous: dict[str, list[int]] = {}

    for person_id, display_name in cur.fetchall():
        if not display_name:
            continue
        key = normalize_person_name(display_name)
        if key in ambiguous:
            ambiguous[key].append(person_id)
            continue
        if key in unique:
            ambiguous[key] = [unique.pop(key), person_id]
            continue
        unique[key] = person_id

    return unique, ambiguous


def import_fisher_data(conn, source: list[dict], dry_run: bool = False) -> dict:
    report = {
        "source_rows": len(source),
        "verified_episodes": 0,
        "updated_fisher_rubric": 0,
        "updated_recording_metadata": 0,
        "cast_replaced_for_episodes": 0,
        "cast_credits_inserted": 0,
        "title_mismatches": [],
        "missing_episodes": [],
        "unmatched_actors": [],
        "ambiguous_actors": [],
        "malformed_credits": [],
    }

    with conn.cursor() as cur:
        person_index, ambiguous_people = build_person_index(cur)

        for row in source:
            episode_number = int(row["episode_number"])
            source_title = str(row["episode_title"]).strip()
            fisher_rubric = row.get("fisher_rubric")
            recording_quality = normalize_recording_quality(
                row.get("recording_quality", row.get("Recording Quality"))
            )
            commercials = parse_optional_bool(
                row.get("commercials", row.get("Commercials")),
                "commercials",
            )
            news = parse_optional_bool(
                row.get("news", row.get("News")),
                "news",
            )
            cast_roles = str(row.get("cast_roles") or "").strip()

            cur.execute(
                """
                SELECT episode_name
                FROM catalog.episode
                WHERE episode_number = %s
                """,
                (episode_number,),
            )
            result = cur.fetchone()

            if result is None:
                report["missing_episodes"].append(
                    {
                        "episode_number": episode_number,
                        "source_title": source_title,
                    }
                )
                continue

            database_title = result[0]
            if normalize_title(database_title) != normalize_title(source_title):
                report["title_mismatches"].append(
                    {
                        "episode_number": episode_number,
                        "source_title": source_title,
                        "database_title": database_title,
                    }
                )
                continue

            report["verified_episodes"] += 1

            credits: list[dict] = []
            for billing_order, raw_credit in enumerate(
                [item.strip() for item in cast_roles.split(";") if item.strip()],
                start=1,
            ):
                parsed = parse_credit(raw_credit)
                if parsed is None:
                    report["malformed_credits"].append(
                        {
                            "episode_number": episode_number,
                            "credit": raw_credit,
                        }
                    )
                    continue

                actor_name, character_name = parsed
                actor_key = normalize_person_name(actor_name)

                if actor_key in ambiguous_people:
                    report["ambiguous_actors"].append(
                        {
                            "episode_number": episode_number,
                            "actor": actor_name,
                            "person_ids": ambiguous_people[actor_key],
                        }
                    )
                    continue

                person_id = person_index.get(actor_key)
                if person_id is None:
                    report["unmatched_actors"].append(
                        {
                            "episode_number": episode_number,
                            "actor": actor_name,
                            "character_name": character_name,
                        }
                    )
                    continue

                credits.append(
                    {
                        "person_id": person_id,
                        "cast_role": "star" if billing_order == 1 else "co_star",
                        "billing_order": billing_order,
                        "character_name": character_name,
                    }
                )

            if dry_run:
                continue

            cur.execute(
                """
                UPDATE catalog.episode
                   SET fisher_rubric = %s,
                       recording_quality = %s,
                       commercials = %s,
                       news = %s,
                       updated_at = now()
                 WHERE episode_number = %s
                """,
                (
                    fisher_rubric,
                    recording_quality,
                    commercials,
                    news,
                    episode_number,
                ),
            )
            report["updated_fisher_rubric"] += 1
            report["updated_recording_metadata"] += 1

            cur.execute(
                "DELETE FROM catalog.episode_cast WHERE episode_number = %s",
                (episode_number,),
            )

            for credit in credits:
                cur.execute(
                    """
                    INSERT INTO catalog.episode_cast(
                        episode_number,
                        person_id,
                        cast_role,
                        billing_order,
                        character_name,
                        character_source,
                        character_updated_at
                    )
                    VALUES(%s,%s,%s,%s,%s,%s,now())
                    """,
                    (
                        episode_number,
                        credit["person_id"],
                        credit["cast_role"],
                        credit["billing_order"],
                        credit["character_name"],
                        "Fisher rubric dataset",
                    ),
                )
                report["cast_credits_inserted"] += 1

            report["cast_replaced_for_episodes"] += 1

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
        default="data/fisher_episode_updates.json",
        help="Path to Fisher episode dataset JSON.",
    )
    parser.add_argument(
        "--report",
        default="reports/fisher-import-report.json",
        help="Path for import review report.",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    source_path = Path(args.source)
    report_path = Path(args.report)
    source = load_source(source_path)

    with psycopg.connect(args.dsn) as conn:
        report = import_fisher_data(conn, source, dry_run=args.dry_run)

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(json.dumps(report, indent=2, ensure_ascii=False))
    print(f"Report written to: {report_path}")


if __name__ == "__main__":
    main()
