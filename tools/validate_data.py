#!/usr/bin/env python3
"""Validate normalized CBSRMT data artifacts and relational invariants."""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
REPORTS = ROOT / "reports"


def load(name: str):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)
    print(f"FAIL: {message}")


def main() -> int:
    failures: list[str] = []

    cast = load("cast.json")
    episodes = load("episodes.json")
    genre = load("genre.json")
    writers = load("episode_writers.json")
    adaptations = load("episode_adaptations.json")

    cast_ids = [str(int(row["cast_id"])) for row in cast]
    episode_ids = [str(int(row["episode_id"])) for row in episodes]
    genre_ids = [str(int(row["genre_id"])) for row in genre]

    if len(cast_ids) != len(set(cast_ids)):
        fail("cast.cast_id values are not unique", failures)
    if len(episode_ids) != len(set(episode_ids)):
        fail("episodes.episode_id values are not unique", failures)
    if len(genre_ids) != len(set(genre_ids)):
        fail("genre.genre_id values are not unique", failures)

    episode_set = set(episode_ids)
    cast_set = set(cast_ids)
    genre_set = set(genre_ids)

    legacy_fields = {"episode_writer", "origwriter"}
    for row in episodes:
        unexpected = legacy_fields.intersection(row)
        if unexpected:
            fail(f"episode {row['episode_id']} retains legacy fields {sorted(unexpected)}", failures)
        if str(int(row["genre_id"])) not in genre_set:
            fail(f"episode {row['episode_id']} references missing genre {row['genre_id']}", failures)

    writer_pairs: list[tuple[str, str]] = []
    for row in writers:
        eid = str(int(row["episode_id"]))
        cid = str(int(row["cast_id"]))
        writer_pairs.append((eid, cid))
        if eid not in episode_set:
            fail(f"episode_writers references missing episode {eid}", failures)
        if cid not in cast_set:
            fail(f"episode_writers references missing cast {cid}", failures)
    if len(writer_pairs) != len(set(writer_pairs)):
        fail("episode_writers contains duplicate (episode_id, cast_id) rows", failures)

    adaptation_ids: list[str] = []
    for row in adaptations:
        eid = str(int(row["episode_id"]))
        adaptation_ids.append(eid)
        if eid not in episode_set:
            fail(f"episode_adaptations references missing episode {eid}", failures)
        if not str(row.get("adapted") or "").strip():
            fail(f"episode_adaptations has blank adapted text for episode {eid}", failures)
    if len(adaptation_ids) != len(set(adaptation_ids)):
        fail("episode_adaptations contains duplicate episode_id rows", failures)

    # Migration reports are required deliverables and must all be valid JSON.
    required_reports = [
        "writer-cast-conflicts.json",
        "writer-unresolved.json",
        "appear-reconciliation.json",
        "adaptation-unmatched.json",
        "adaptation-origwriter-fallbacks.json",
        "migration-summary.json",
    ]
    for name in required_reports:
        path = REPORTS / name
        if not path.exists():
            fail(f"missing report {name}", failures)
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            fail(f"invalid JSON report {name}: {exc}", failures)

    sql_path = ROOT / "sql" / "cbs.sql"
    sql = sql_path.read_text(encoding="utf-8")
    required_sql_fragments = [
        "CREATE TABLE `genre`",
        "CREATE TABLE `cast`",
        "CREATE TABLE `episodes`",
        "CREATE TABLE `appear`",
        "CREATE TABLE `episode_writers`",
        "CREATE TABLE `episode_adaptations`",
        "FOREIGN KEY (`genre_id`) REFERENCES `genre` (`genre_id`)",
        "FOREIGN KEY (`episode_id`) REFERENCES `episodes` (`episode_id`)",
        "FOREIGN KEY (`cast_id`) REFERENCES `cast` (`cast_id`)",
        "CHARSET=utf8mb4",
    ]
    for fragment in required_sql_fragments:
        if fragment not in sql:
            fail(f"sql/cbs.sql is missing required fragment: {fragment}", failures)

    if "`episode_writer`" in sql or "`origwriter`" in sql:
        fail("sql/cbs.sql still defines a legacy episode writer/origwriter column", failures)

    if failures:
        print(f"\n{len(failures)} validation failure(s).")
        return 1

    unresolved = []
    unresolved_path = REPORTS / "writer-unresolved.json"
    if unresolved_path.exists():
        unresolved = json.loads(unresolved_path.read_text(encoding="utf-8"))

    summary = {
        "cast": len(cast),
        "episodes": len(episodes),
        "genres": len(genre),
        "episode_writer_relationships": len(writers),
        "episode_adaptations": len(adaptations),
        "unresolved_writer_records": len(unresolved),
    }
    print("PASS: normalized data integrity checks")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
