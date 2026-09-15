#!/usr/bin/env python3
"""Rebuild CBSRMT normalized data and SQL artifacts.

Transforms the legacy JSON/SQL dump into a normalized relational model:
- merges writers into cast by cast_id
- resolves episode writers to cast IDs
- parses CBSRMT adaptation associations
- migrates legacy origwriter values as fallback adaptation records
- reduces appear to appear_id/episode_id/cast_id
- normalizes episodes and genre data
- writes reconciliation reports and a complete SQL rebuild script
"""

from __future__ import annotations

import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SQL = ROOT / "sql"
REPORTS = ROOT / "reports"
ADAPTATIONS_URL = "https://www.cbsrmt.com/adaptions.html"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def norm(value: str) -> str:
    value = unicodedata.normalize("NFKD", value or "")
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = value.casefold().strip()
    value = value.replace("’", "'")
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def full_name(person: dict[str, Any]) -> str:
    return " ".join(
        part.strip()
        for part in (
            str(person.get("first_name") or ""),
            str(person.get("middle_name") or ""),
            str(person.get("last_name") or ""),
        )
        if part and part.strip()
    )


def merge_writers_into_cast(cast: list[dict[str, Any]], writers: list[dict[str, Any]]):
    by_id = {str(row["cast_id"]): dict(row) for row in cast}
    conflicts: list[dict[str, Any]] = []
    added = 0
    merged = 0

    for writer in writers:
        cid = str(writer["cast_id"])
        if cid not in by_id:
            by_id[cid] = dict(writer)
            added += 1
            continue

        merged += 1
        target = by_id[cid]
        for key, writer_value in writer.items():
            if key == "cast_id":
                continue
            cast_value = target.get(key)
            cast_empty = cast_value is None or str(cast_value).strip() == ""
            writer_empty = writer_value is None or str(writer_value).strip() == ""
            if cast_empty and not writer_empty:
                target[key] = writer_value
            elif not cast_empty and not writer_empty and str(cast_value).strip() != str(writer_value).strip():
                conflicts.append(
                    {
                        "cast_id": cid,
                        "field": key,
                        "cast_value": cast_value,
                        "writer_value": writer_value,
                        "resolution": "cast_value_retained",
                    }
                )

    result = sorted(by_id.values(), key=lambda row: int(row["cast_id"]))
    return result, conflicts, merged, added


def build_person_name_index(cast: list[dict[str, Any]], writers: list[dict[str, Any]]):
    aliases: dict[str, set[str]] = defaultdict(set)

    def add_alias(person: dict[str, Any]):
        cid = str(person["cast_id"])
        names = {full_name(person)}
        first = str(person.get("first_name") or "").strip()
        middle = str(person.get("middle_name") or "").strip()
        last = str(person.get("last_name") or "").strip()
        if first and last:
            names.add(f"{first} {last}")
            if middle:
                names.add(f"{first} {middle[:1]} {last}")
                names.add(f"{first} {middle[:1]}. {last}")
        for name in names:
            key = norm(name)
            if key:
                aliases[key].add(cid)

    for person in cast:
        add_alias(person)
    for person in writers:
        add_alias(person)
    return aliases


def split_writer_text(value: str) -> list[str]:
    value = value.strip()
    if not value:
        return []
    return [
        part.strip()
        for part in re.split(r"\s*(?:;|/|&|\+|\band\b)\s*", value, flags=re.IGNORECASE)
        if part.strip()
    ]


def resolve_episode_writers(episodes: list[dict[str, Any]], aliases: dict[str, set[str]]):
    relationships: set[tuple[int, int]] = set()
    unresolved: list[dict[str, Any]] = []

    for episode in episodes:
        writer_text = str(episode.get("episode_writer") or "").strip()
        if not writer_text:
            continue

        whole = aliases.get(norm(writer_text), set())
        if len(whole) == 1:
            relationships.add((int(episode["episode_id"]), int(next(iter(whole)))))
            continue

        parts = split_writer_text(writer_text)
        resolved_ids: list[int] = []
        unresolved_parts: list[str] = []
        ambiguous_parts: list[dict[str, Any]] = []
        for part in parts:
            candidates = aliases.get(norm(part), set())
            if len(candidates) == 1:
                resolved_ids.append(int(next(iter(candidates))))
            elif len(candidates) == 0:
                unresolved_parts.append(part)
            else:
                ambiguous_parts.append({"writer": part, "cast_ids": sorted(candidates, key=int)})

        if not unresolved_parts and not ambiguous_parts and resolved_ids:
            for cid in resolved_ids:
                relationships.add((int(episode["episode_id"]), cid))
        else:
            unresolved.append(
                {
                    "episode_id": str(episode["episode_id"]),
                    "episode_name": episode.get("episode_name", ""),
                    "episode_writer": writer_text,
                    "unresolved_parts": unresolved_parts,
                    "ambiguous_parts": ambiguous_parts,
                }
            )

    return [
        {"episode_id": str(eid), "cast_id": str(cid)}
        for eid, cid in sorted(relationships)
    ], unresolved


def parse_sql_values(raw: str) -> list[str]:
    values: list[str] = []
    current: list[str] = []
    in_quote = False
    i = 0
    while i < len(raw):
        ch = raw[i]
        if ch == "'":
            if in_quote and i + 1 < len(raw) and raw[i + 1] == "'":
                current.append("'")
                i += 2
                continue
            in_quote = not in_quote
            i += 1
            continue
        if ch == "," and not in_quote:
            values.append("".join(current).strip())
            current = []
            i += 1
            continue
        current.append(ch)
        i += 1
    values.append("".join(current).strip())
    return values


def extract_appear(sql_text: str, episodes_by_id: dict[str, dict[str, Any]], cast_by_id: dict[str, dict[str, Any]]):
    pattern = re.compile(r"INSERT INTO `appear` VALUES\((.*?)\);", re.DOTALL)
    rows: list[dict[str, str]] = []
    reconciliation: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()

    for match in pattern.finditer(sql_text):
        fields = parse_sql_values(match.group(1))
        if len(fields) != 6:
            reconciliation.append({"issue": "unparseable_row", "raw": match.group(0)})
            continue
        appear_id, episode_id, episode_date, episode_name, cast_id, cast_id_name = fields
        episode_id = str(int(episode_id))
        cast_id = str(int(cast_id))
        key = (episode_id, cast_id)
        if key in seen:
            reconciliation.append(
                {
                    "appear_id": int(appear_id),
                    "episode_id": episode_id,
                    "cast_id": cast_id,
                    "issue": "duplicate_episode_cast",
                    "resolution": "duplicate_dropped",
                }
            )
            continue
        seen.add(key)

        episode = episodes_by_id.get(episode_id)
        person = cast_by_id.get(cast_id)
        if not episode:
            reconciliation.append({"appear_id": int(appear_id), "episode_id": episode_id, "issue": "missing_episode"})
        else:
            if episode_date != str(episode.get("episode_date") or ""):
                reconciliation.append(
                    {
                        "appear_id": int(appear_id),
                        "episode_id": episode_id,
                        "issue": "episode_date_mismatch",
                        "appear_value": episode_date,
                        "episode_value": episode.get("episode_date"),
                    }
                )
            if norm(episode_name) != norm(str(episode.get("episode_name") or "")):
                reconciliation.append(
                    {
                        "appear_id": int(appear_id),
                        "episode_id": episode_id,
                        "issue": "episode_name_mismatch",
                        "appear_value": episode_name,
                        "episode_value": episode.get("episode_name"),
                    }
                )
        if not person:
            reconciliation.append({"appear_id": int(appear_id), "cast_id": cast_id, "issue": "missing_cast"})
        elif norm(cast_id_name) != norm(str(person.get("cast_id_name") or "")):
            reconciliation.append(
                {
                    "appear_id": int(appear_id),
                    "cast_id": cast_id,
                    "issue": "cast_id_name_mismatch",
                    "appear_value": cast_id_name,
                    "cast_value": person.get("cast_id_name"),
                }
            )

        rows.append({"appear_id": str(int(appear_id)), "episode_id": episode_id, "cast_id": cast_id})

    rows.sort(key=lambda row: int(row["appear_id"]))
    return rows, reconciliation


def parse_adaptations_page() -> list[dict[str, str]]:
    response = requests.get(ADAPTATIONS_URL, timeout=45, headers={"User-Agent": "cbsrmt.db data maintenance"})
    response.raise_for_status()
    soup = BeautifulSoup(response.text, "html.parser")
    by_episode: dict[str, dict[str, str]] = {}

    for anchor in soup.find_all("a", href=True):
        href = str(anchor.get("href") or "")
        match = re.search(r"/episode/(\d+)-", href)
        if not match:
            continue
        episode_id = str(int(match.group(1)))
        title = anchor.get_text(" ", strip=True)
        container = anchor.find_parent("li") or anchor.parent
        text = container.get_text(" ", strip=True) if container else ""
        adapted_match = re.search(r"(Adapted\s+from\b.*)$", text, flags=re.IGNORECASE)
        if not adapted_match:
            continue
        adapted = re.sub(r"\s+", " ", adapted_match.group(1)).strip()
        by_episode[episode_id] = {
            "episode_id": episode_id,
            "title": title,
            "adapted": adapted,
            "source_url": requests.compat.urljoin(ADAPTATIONS_URL, href),
        }

    return [by_episode[key] for key in sorted(by_episode, key=int)]


def build_adaptations(episodes: list[dict[str, Any]], external_rows: list[dict[str, str]]):
    episodes_by_id = {str(int(row["episode_id"])): row for row in episodes}
    adaptations: dict[str, str] = {}
    unmatched: list[dict[str, Any]] = []
    fallbacks: list[dict[str, Any]] = []

    for row in external_rows:
        eid = row["episode_id"]
        episode = episodes_by_id.get(eid)
        if not episode:
            unmatched.append({**row, "issue": "episode_id_not_found"})
            continue
        if row.get("title") and norm(row["title"]) != norm(str(episode.get("episode_name") or "")):
            unmatched.append(
                {
                    **row,
                    "issue": "title_mismatch",
                    "database_title": episode.get("episode_name", ""),
                    "resolution": "episode_id_accepted",
                }
            )
        adaptations[eid] = row["adapted"]

    for episode in episodes:
        eid = str(int(episode["episode_id"]))
        origwriter = str(episode.get("origwriter") or "").strip()
        if origwriter and eid not in adaptations:
            adapted = f"Adapted from {origwriter}"
            adaptations[eid] = adapted
            fallbacks.append(
                {
                    "episode_id": eid,
                    "episode_name": episode.get("episode_name", ""),
                    "origwriter": origwriter,
                    "generated_adapted": adapted,
                }
            )

    rows = [
        {"episode_id": eid, "adapted": adaptations[eid]}
        for eid in sorted(adaptations, key=int)
    ]
    return rows, unmatched, fallbacks


def normalize_episodes(episodes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    fields = ("episode_id", "episode_date", "episode_name", "episode_plot", "genre_id")
    return [{field: row.get(field, "") for field in fields} for row in episodes]


def normalize_genre(genres: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    for row in genres:
        new = dict(row)
        if str(new.get("genre_name") or "").strip() == "Unkown":
            new["genre_name"] = "Unknown"
        result.append(new)
    return sorted(result, key=lambda row: int(row["genre_id"]))


def sql_string(value: Any) -> str:
    if value is None:
        return "NULL"
    text = str(value)
    text = text.replace("\\", "\\\\").replace("'", "''").replace("\r", "\\r").replace("\n", "\\n")
    return f"'{text}'"


def sql_date(value: Any) -> str:
    text = str(value or "").strip()
    if not text or text == "0000-00-00":
        return "NULL"
    return sql_string(text)


def generate_sql(
    genres: list[dict[str, Any]],
    cast: list[dict[str, Any]],
    episodes: list[dict[str, Any]],
    appear: list[dict[str, str]],
    episode_writers: list[dict[str, str]],
    adaptations: list[dict[str, str]],
) -> str:
    lines: list[str] = []
    add = lines.append
    add("-- CBS Radio Mystery Theater normalized database rebuild")
    add("-- Generated by tools/rebuild_data.py. Do not edit generated data sections by hand.")
    add("")
    add("DROP DATABASE IF EXISTS `cbs`;")
    add("CREATE DATABASE `cbs` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
    add("USE `cbs`;")
    add("SET FOREIGN_KEY_CHECKS=0;")
    add("SET SQL_MODE='NO_AUTO_VALUE_ON_ZERO';")
    add("SET time_zone='+00:00';")
    add("")
    add("CREATE TABLE `genre` (")
    add("  `genre_id` tinyint unsigned NOT NULL,")
    add("  `genre_name` varchar(100) NOT NULL,")
    add("  PRIMARY KEY (`genre_id`)")
    add(") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;")
    add("")
    add("CREATE TABLE `cast` (")
    add("  `cast_id` int unsigned NOT NULL,")
    add("  `cast_id_name` varchar(100) NOT NULL DEFAULT '',")
    add("  `first_name` varchar(100) DEFAULT NULL,")
    add("  `middle_name` varchar(100) DEFAULT NULL,")
    add("  `last_name` varchar(100) DEFAULT NULL,")
    add("  `image_url` varchar(500) DEFAULT NULL,")
    add("  `soundclip_url` varchar(500) DEFAULT NULL,")
    add("  `bio` text,")
    add("  `born_on` date DEFAULT NULL,")
    add("  `died_on` date DEFAULT NULL,")
    add("  `offsite_url` varchar(500) DEFAULT NULL,")
    add("  `other_series` text,")
    add("  `credit` varchar(255) DEFAULT NULL,")
    add("  PRIMARY KEY (`cast_id`),")
    add("  UNIQUE KEY `uq_cast_id_name` (`cast_id_name`)")
    add(") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;")
    add("")
    add("CREATE TABLE `episodes` (")
    add("  `episode_id` int unsigned NOT NULL,")
    add("  `episode_date` date NOT NULL,")
    add("  `episode_name` varchar(150) NOT NULL,")
    add("  `episode_plot` text NOT NULL,")
    add("  `genre_id` tinyint unsigned NOT NULL,")
    add("  PRIMARY KEY (`episode_id`),")
    add("  KEY `idx_episodes_date` (`episode_date`),")
    add("  KEY `idx_episodes_name` (`episode_name`),")
    add("  KEY `idx_episodes_genre` (`genre_id`),")
    add("  CONSTRAINT `fk_episodes_genre` FOREIGN KEY (`genre_id`) REFERENCES `genre` (`genre_id`) ON UPDATE CASCADE ON DELETE RESTRICT")
    add(") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;")
    add("")
    add("CREATE TABLE `appear` (")
    add("  `appear_id` int unsigned NOT NULL AUTO_INCREMENT,")
    add("  `episode_id` int unsigned NOT NULL,")
    add("  `cast_id` int unsigned NOT NULL,")
    add("  PRIMARY KEY (`appear_id`),")
    add("  UNIQUE KEY `uq_appear_episode_cast` (`episode_id`,`cast_id`),")
    add("  KEY `idx_appear_episode` (`episode_id`),")
    add("  KEY `idx_appear_cast` (`cast_id`),")
    add("  CONSTRAINT `fk_appear_episode` FOREIGN KEY (`episode_id`) REFERENCES `episodes` (`episode_id`) ON UPDATE CASCADE ON DELETE CASCADE,")
    add("  CONSTRAINT `fk_appear_cast` FOREIGN KEY (`cast_id`) REFERENCES `cast` (`cast_id`) ON UPDATE CASCADE ON DELETE RESTRICT")
    add(") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;")
    add("")
    add("CREATE TABLE `episode_writers` (")
    add("  `episode_writer_id` int unsigned NOT NULL AUTO_INCREMENT,")
    add("  `episode_id` int unsigned NOT NULL,")
    add("  `cast_id` int unsigned NOT NULL,")
    add("  PRIMARY KEY (`episode_writer_id`),")
    add("  UNIQUE KEY `uq_episode_writer` (`episode_id`,`cast_id`),")
    add("  KEY `idx_episode_writer_episode` (`episode_id`),")
    add("  KEY `idx_episode_writer_cast` (`cast_id`),")
    add("  CONSTRAINT `fk_episode_writer_episode` FOREIGN KEY (`episode_id`) REFERENCES `episodes` (`episode_id`) ON UPDATE CASCADE ON DELETE CASCADE,")
    add("  CONSTRAINT `fk_episode_writer_cast` FOREIGN KEY (`cast_id`) REFERENCES `cast` (`cast_id`) ON UPDATE CASCADE ON DELETE RESTRICT")
    add(") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;")
    add("")
    add("CREATE TABLE `episode_adaptations` (")
    add("  `episode_id` int unsigned NOT NULL,")
    add("  `adapted` text NOT NULL,")
    add("  PRIMARY KEY (`episode_id`),")
    add("  CONSTRAINT `fk_episode_adaptations_episode` FOREIGN KEY (`episode_id`) REFERENCES `episodes` (`episode_id`) ON UPDATE CASCADE ON DELETE CASCADE")
    add(") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;")
    add("")

    for row in genres:
        add(f"INSERT INTO `genre` (`genre_id`,`genre_name`) VALUES ({int(row['genre_id'])},{sql_string(row.get('genre_name',''))});")
    add("")

    cast_fields = ["cast_id", "cast_id_name", "first_name", "middle_name", "last_name", "image_url", "soundclip_url", "bio", "born_on", "died_on", "offsite_url", "other_series", "credit"]
    for row in cast:
        vals = [str(int(row["cast_id"]))]
        for field in cast_fields[1:]:
            if field in ("born_on", "died_on"):
                vals.append(sql_date(row.get(field)))
            else:
                vals.append(sql_string(row.get(field) if row.get(field) not in (None, "") else None))
        add("INSERT INTO `cast` (`" + "`,`".join(cast_fields) + "`) VALUES (" + ",".join(vals) + ");")
    add("")

    for row in episodes:
        add(
            "INSERT INTO `episodes` (`episode_id`,`episode_date`,`episode_name`,`episode_plot`,`genre_id`) VALUES ("
            f"{int(row['episode_id'])},{sql_date(row.get('episode_date'))},{sql_string(row.get('episode_name',''))},{sql_string(row.get('episode_plot',''))},{int(row['genre_id'])});"
        )
    add("")

    for row in appear:
        add(f"INSERT INTO `appear` (`appear_id`,`episode_id`,`cast_id`) VALUES ({int(row['appear_id'])},{int(row['episode_id'])},{int(row['cast_id'])});")
    add("")

    for idx, row in enumerate(episode_writers, start=1):
        add(f"INSERT INTO `episode_writers` (`episode_writer_id`,`episode_id`,`cast_id`) VALUES ({idx},{int(row['episode_id'])},{int(row['cast_id'])});")
    add("")

    for row in adaptations:
        add(f"INSERT INTO `episode_adaptations` (`episode_id`,`adapted`) VALUES ({int(row['episode_id'])},{sql_string(row['adapted'])});")
    add("")
    add("SET FOREIGN_KEY_CHECKS=1;")
    add("")
    return "\n".join(lines)


def main() -> None:
    REPORTS.mkdir(parents=True, exist_ok=True)

    cast_original = load_json(DATA / "cast.json")
    writers = load_json(DATA / "writers.json")
    episodes_legacy = load_json(DATA / "episodes.json")
    genres_legacy = load_json(DATA / "genre.json")
    old_sql = (SQL / "cbs.sql").read_text(encoding="utf-8", errors="replace")

    merged_cast, conflicts, merged_count, added_count = merge_writers_into_cast(cast_original, writers)
    aliases = build_person_name_index(merged_cast, writers)
    episode_writers, unresolved_writers = resolve_episode_writers(episodes_legacy, aliases)

    episodes_by_id = {str(int(row["episode_id"])): row for row in episodes_legacy}
    cast_by_id = {str(int(row["cast_id"])): row for row in merged_cast}
    appear, appear_reconciliation = extract_appear(old_sql, episodes_by_id, cast_by_id)

    external_adaptations = parse_adaptations_page()
    adaptations, adaptation_unmatched, adaptation_fallbacks = build_adaptations(episodes_legacy, external_adaptations)

    episodes = normalize_episodes(episodes_legacy)
    genres = normalize_genre(genres_legacy)

    write_json(DATA / "cast.json", merged_cast)
    write_json(DATA / "episodes.json", episodes)
    write_json(DATA / "episode_writers.json", episode_writers)
    write_json(DATA / "episode_adaptations.json", adaptations)
    write_json(DATA / "genre.json", genres)

    write_json(REPORTS / "writer-cast-conflicts.json", conflicts)
    write_json(REPORTS / "writer-unresolved.json", unresolved_writers)
    write_json(REPORTS / "appear-reconciliation.json", appear_reconciliation)
    write_json(REPORTS / "adaptation-unmatched.json", adaptation_unmatched)
    write_json(REPORTS / "adaptation-origwriter-fallbacks.json", adaptation_fallbacks)

    sql_text = generate_sql(genres, merged_cast, episodes, appear, episode_writers, adaptations)
    (SQL / "cbs.sql").write_text(sql_text, encoding="utf-8")

    summary = {
        "episodes": {"input": len(episodes_legacy), "output": len(episodes)},
        "cast": {
            "original": len(cast_original),
            "output": len(merged_cast),
            "writers_matched": merged_count,
            "new_people_added": added_count,
            "conflicts": len(conflicts),
        },
        "appear": {
            "output": len(appear),
            "reconciliation_warnings": len(appear_reconciliation),
            "duplicates_removed": sum(1 for row in appear_reconciliation if row.get("issue") == "duplicate_episode_cast"),
        },
        "episode_writers": {"created": len(episode_writers), "unresolved": len(unresolved_writers)},
        "episode_adaptations": {
            "external_parsed": len(external_adaptations),
            "output": len(adaptations),
            "origwriter_fallbacks": len(adaptation_fallbacks),
            "external_reconciliation_warnings": len(adaptation_unmatched),
        },
        "genre": {"count": len(genres)},
        "source": {"adaptations_url": ADAPTATIONS_URL},
    }
    write_json(REPORTS / "migration-summary.json", summary)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
