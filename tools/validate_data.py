#!/usr/bin/env python3
"""Validate normalized CBSRMT data artifacts and relational invariants."""

from __future__ import annotations

import json
import sys
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
    appear = load("appear.json")
    writers = load("episode_writers.json")
    adaptations = load("episode_adaptations.json")

    cast_ids = [str(int(row["cast_id"])) for row in cast]
    episode_ids = [str(int(row["episode_id"])) for row in episodes]
    genre_ids = [str(int(row["genre_id"])) for row in genre]
    cast_set, episode_set, genre_set = set(cast_ids), set(episode_ids), set(genre_ids)

    if len(cast_ids) != len(cast_set):
        fail("cast.cast_id values are not unique", failures)
    if len(episode_ids) != len(episode_set):
        fail("episodes.episode_id values are not unique", failures)
    if len(genre_ids) != len(genre_set):
        fail("genre.genre_id values are not unique", failures)
    if not appear:
        fail("appear.json is empty", failures)
    if not writers:
        fail("episode_writers.json is empty", failures)

    for row in episodes:
        if "episode_writer" in row or "origwriter" in row:
            fail(f"episode {row['episode_id']} retains a legacy writer/origwriter field", failures)
        if str(row.get("episode_name") or "").startswith("The "):
            fail(f"episode {row['episode_id']} still has a leading 'The' article", failures)
        if str(int(row["genre_id"])) not in genre_set:
            fail(f"episode {row['episode_id']} references missing genre {row['genre_id']}", failures)

    appear_ids: list[str] = []
    appear_pairs: list[tuple[str, str]] = []
    for row in appear:
        aid = str(int(row["appear_id"]))
        eid = str(int(row["episode_id"]))
        cid = str(int(row["cast_id"]))
        appear_ids.append(aid)
        appear_pairs.append((eid, cid))
        if eid not in episode_set:
            fail(f"appear {aid} references missing episode {eid}", failures)
        if cid not in cast_set:
            fail(f"appear {aid} references missing cast {cid}", failures)
    if len(appear_ids) != len(set(appear_ids)):
        fail("appear.appear_id values are not unique", failures)
    if len(appear_pairs) != len(set(appear_pairs)):
        fail("appear contains duplicate (episode_id, cast_id) rows", failures)

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
            fail(f"episode_adaptations has blank text for episode {eid}", failures)
    if len(adaptation_ids) != len(set(adaptation_ids)):
        fail("episode_adaptations contains duplicate episode_id rows", failures)

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

    sql = (ROOT / "sql" / "cbs.sql").read_text(encoding="utf-8")
    for fragment in [
        "CREATE TABLE `genre`", "CREATE TABLE `cast`", "CREATE TABLE `episodes`",
        "CREATE TABLE `appear`", "CREATE TABLE `episode_writers`", "CREATE TABLE `episode_adaptations`",
        "FOREIGN KEY (`genre_id`) REFERENCES `genre` (`genre_id`)",
        "FOREIGN KEY (`episode_id`) REFERENCES `episodes` (`episode_id`)",
        "FOREIGN KEY (`cast_id`) REFERENCES `cast` (`cast_id`)", "CHARSET=utf8mb4",
    ]:
        if fragment not in sql:
            fail(f"sql/cbs.sql is missing required fragment: {fragment}", failures)
    if "`episode_writer`" in sql or "`origwriter`" in sql:
        fail("sql/cbs.sql still defines a legacy writer/origwriter column", failures)

    if failures:
        print(f"\n{len(failures)} validation failure(s).")
        return 1

    unresolved = json.loads((REPORTS / "writer-unresolved.json").read_text(encoding="utf-8"))
    print("PASS: normalized data integrity checks")
    print(json.dumps({
        "cast": len(cast), "episodes": len(episodes), "genres": len(genre),
        "appearances": len(appear), "episode_writer_relationships": len(writers),
        "episode_adaptations": len(adaptations), "unresolved_writer_records": len(unresolved),
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
