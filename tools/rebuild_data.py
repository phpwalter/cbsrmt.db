#!/usr/bin/env python3
"""Rebuild normalized CBSRMT data from the immutable main-branch legacy baseline."""

from __future__ import annotations

import json
import re
import subprocess
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Any

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SQL = ROOT / "sql"
REPORTS = ROOT / "reports"
ADAPTATIONS_URL = "https://www.cbsrmt.com/adaptions.html"
BASE_REF = "origin/main"
SERIES_FORMAT_EQUIVALENT_EPISODES = {
    "1045", "1046", "1047", "1048", "1049",
    "1275", "1276", "1277", "1278", "1279",
}
EPISODE_TITLE_OVERRIDES = {
    "81": "Sunset to Sunrise",
    "344": "Little Old Lady Killer",
}


def source_text(path: str) -> str:
    """Read legacy source from origin/main so reruns cannot consume generated output."""
    try:
        return subprocess.check_output(
            ["git", "show", f"{BASE_REF}:{path}"], cwd=ROOT, text=True, encoding="utf-8"
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return (ROOT / path).read_text(encoding="utf-8", errors="replace")


def source_json(path: str) -> Any:
    return json.loads(source_text(path))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def norm(value: str) -> str:
    value = unicodedata.normalize("NFKD", value or "")
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = value.casefold().replace("’", "'")
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def sortable_title(value: Any) -> str:
    """Normalize leading or trailing The/A articles to [The] or [A] suffixes."""
    name = str(value or "").strip()
    trailing = re.match(r"^(.*)\s+\((The|A)\)$", name, flags=re.IGNORECASE)
    if trailing:
        article = trailing.group(2).title()
        return f"{trailing.group(1).strip()} [{article}]"
    if name.startswith("The "):
        return f"{name[4:]} [The]"
    if name.startswith("A "):
        return f"{name[2:]} [A]"
    return name


def canonical_episode_title(episode_id: Any, value: Any) -> str:
    eid = str(int(episode_id))
    return sortable_title(EPISODE_TITLE_OVERRIDES.get(eid, value))


def full_name(person: dict[str, Any]) -> str:
    return " ".join(
        str(person.get(field) or "").strip()
        for field in ("first_name", "middle_name", "last_name")
        if str(person.get(field) or "").strip()
    )


PERSON_CORRECTIONS: dict[str, dict[str, str]] = {
    "291": {"last_name": "Pennell"},
}

CANONICAL_PEOPLE: dict[str, dict[str, Any]] = {
    "338": {"cast_id":"338","cast_id_name":"bwalton","first_name":"Bryce","middle_name":"","last_name":"Walton","image_url":"","soundclip_url":"","bio":"","born_on":"0000-00-00","died_on":"0000-00-00","offsite_url":"","other_series":"","credit":""},
    "339": {"cast_id":"339","cast_id_name":"slehrman","first_name":"Steve","middle_name":"","last_name":"Lehrman","image_url":"","soundclip_url":"","bio":"","born_on":"0000-00-00","died_on":"0000-00-00","offsite_url":"","other_series":"","credit":""},
    "340": {"cast_id":"340","cast_id_name":"spanitz2","first_name":"Saul","middle_name":"","last_name":"Panitz","image_url":"","soundclip_url":"","bio":"","born_on":"0000-00-00","died_on":"0000-00-00","offsite_url":"","other_series":"","credit":""},
    "341": {"cast_id":"341","cast_id_name":"fmarkle","first_name":"Fletcher","middle_name":"","last_name":"Markle","image_url":"","soundclip_url":"","bio":"","born_on":"0000-00-00","died_on":"0000-00-00","offsite_url":"","other_series":"","credit":""},
}


def merge_writers_into_cast(cast: list[dict[str, Any]], writers: list[dict[str, Any]]):
    by_id = {str(row["cast_id"]): dict(row) for row in cast}
    conflicts: list[dict[str, Any]] = []
    matched = 0
    added = 0
    for writer in writers:
        cid = str(writer["cast_id"])
        if cid not in by_id:
            by_id[cid] = dict(writer); added += 1; continue
        matched += 1; target = by_id[cid]
        for key, writer_value in writer.items():
            if key == "cast_id": continue
            cast_value = target.get(key)
            cast_empty = cast_value is None or str(cast_value).strip() == ""
            writer_empty = writer_value is None or str(writer_value).strip() == ""
            if cast_empty and not writer_empty: target[key] = writer_value
            elif not cast_empty and not writer_empty and str(cast_value).strip() != str(writer_value).strip():
                conflicts.append({"cast_id":cid,"field":key,"cast_value":cast_value,"writer_value":writer_value,"resolution":"cast_value_retained"})
    for cid, person in CANONICAL_PEOPLE.items():
        if cid in by_id: conflicts.append({"cast_id":cid,"issue":"canonical_person_id_collision","resolution":"existing_value_retained"})
        else: by_id[cid] = dict(person); added += 1
    for cid, corrections in PERSON_CORRECTIONS.items():
        if cid in by_id: by_id[cid].update(corrections)
    return sorted(by_id.values(), key=lambda r: int(r["cast_id"])), conflicts, matched, added


def name_index(*collections: list[dict[str, Any]]) -> dict[str, set[str]]:
    aliases: dict[str, set[str]] = defaultdict(set)
    for collection in collections:
        for person in collection:
            cid = str(person["cast_id"]); first = str(person.get("first_name") or "").strip(); middle = str(person.get("middle_name") or "").strip(); last = str(person.get("last_name") or "").strip(); candidates = {full_name(person)}
            if first and last:
                candidates.add(f"{first} {last}")
                if middle: candidates.add(f"{first} {middle[:1]} {last}"); candidates.add(f"{first} {middle[:1]}. {last}")
            for candidate in candidates:
                if norm(candidate): aliases[norm(candidate)].add(cid)
    return aliases


WRITER_ALIASES = {"george lowther":"83","sidney sloan":"88","saul pattis":"284","henry scheschner":"2","henry schlescher":"2","henry slessar":"2","fieldin farrington":"222","elspith eric":"245","g frederick louis":"94","murray bur":"114","gerald kean":"167","gerald keene":"167","karen thorson":"263","roy windsor":"55","roy widnsor":"55","roy windor":"55","elizabeth pinnel":"291","elizabeth pinnell":"291","elizabeth pennel":"291","elizabeth pennell":"291"}
WRITER_TEXT_CORRECTIONS = {"steve laerman":"Steve Lehrman"}
EPISODE_WRITER_TEXT_OVERRIDES: dict[str, str] = {}
EPISODE_WRITER_OVERRIDES: dict[str, list[int]] = {"123":[83],"347":[186,28],"406":[28,186],"433":[340],"442":[28,186],"631":[341],"696":[55],"708":[186,28],"908":[245],"964":[167],"1022":[70],"1072":[70],"1259":[245],"1292":[338],"1311":[339],"1320":[338],"1338":[338],"1360":[338],"1364":[339]}
IGNORED_WRITER_TOKENS = {"f230"}


def split_writer_text(value: str) -> list[str]:
    return [part.strip() for part in re.split(r"\s*(?:;|/|&|\+|\band\b)\s*", value.strip(), flags=re.IGNORECASE) if part.strip()]


def resolve_episode_writers(episodes: list[dict[str, Any]], aliases: dict[str, set[str]]):
    relationships: set[tuple[int, int]] = set(); unresolved: list[dict[str, Any]] = []
    for episode in episodes:
        episode_id = str(episode["episode_id"]); override_ids = EPISODE_WRITER_OVERRIDES.get(episode_id)
        if override_ids is not None:
            for cid in override_ids: relationships.add((int(episode_id), int(cid)))
            continue
        raw = EPISODE_WRITER_TEXT_OVERRIDES.get(episode_id, str(episode.get("episode_writer") or "").strip())
        if not raw: continue
        raw = WRITER_TEXT_CORRECTIONS.get(norm(raw), raw); whole_key = norm(raw); whole = aliases.get(whole_key, set())
        if len(whole) == 1: relationships.add((int(episode["episode_id"]), int(next(iter(whole))))); continue
        if whole_key in WRITER_ALIASES: relationships.add((int(episode["episode_id"]), int(WRITER_ALIASES[whole_key]))); continue
        resolved: list[int] = []; unresolved_parts: list[str] = []; ambiguous_parts: list[dict[str, Any]] = []
        for part in split_writer_text(raw):
            key = norm(part); ids = aliases.get(key, set())
            if key in IGNORED_WRITER_TOKENS: continue
            if len(ids) == 1: resolved.append(int(next(iter(ids))))
            elif key in WRITER_ALIASES: resolved.append(int(WRITER_ALIASES[key]))
            elif len(ids) > 1: ambiguous_parts.append({"writer":part,"cast_ids":sorted(ids,key=int)})
            else: unresolved_parts.append(part)
        if resolved and not unresolved_parts and not ambiguous_parts:
            for cid in resolved: relationships.add((int(episode["episode_id"]), cid))
        else: unresolved.append({"episode_id":str(episode["episode_id"]),"episode_name":episode.get("episode_name",""),"episode_writer":raw,"unresolved_parts":unresolved_parts,"ambiguous_parts":ambiguous_parts})
    return [{"episode_id":str(eid),"cast_id":str(cid)} for eid,cid in sorted(relationships)], unresolved


def parse_sql_values(raw: str) -> list[str]:
    values=[]; current=[]; quoted=False; i=0
    while i < len(raw):
        ch=raw[i]
        if ch=="'":
            if quoted and i+1<len(raw) and raw[i+1]=="'": current.append("'"); i+=2; continue
            quoted=not quoted; i+=1; continue
        if ch=="," and not quoted: values.append("".join(current).strip()); current=[]
        else: current.append(ch)
        i+=1
    values.append("".join(current).strip()); return values


def extract_appear(sql_text: str, episodes_by_id: dict[str, dict[str, Any]], cast_by_id: dict[str, dict[str, Any]]):
    rows=[]; reconciliation=[]; seen=set()
    for match in re.finditer(r"INSERT INTO `appear` VALUES\((.*?)\);", sql_text, flags=re.DOTALL):
        fields=parse_sql_values(match.group(1))
        if len(fields)!=6: reconciliation.append({"issue":"unparseable_row","raw":match.group(0)}); continue
        appear_id,episode_id,episode_date,episode_name,cast_id,cast_id_name=fields; episode_id=str(int(episode_id)); cast_id=str(int(cast_id)); key=(episode_id,cast_id)
        if key in seen: reconciliation.append({"appear_id":int(appear_id),"episode_id":episode_id,"cast_id":cast_id,"issue":"duplicate_episode_cast","resolution":"duplicate_dropped"}); continue
        seen.add(key); episode=episodes_by_id.get(episode_id); person=cast_by_id.get(cast_id)
        if episode is None: reconciliation.append({"appear_id":int(appear_id),"episode_id":episode_id,"issue":"missing_episode"})
        else:
            if episode_date!=str(episode.get("episode_date") or ""): reconciliation.append({"appear_id":int(appear_id),"episode_id":episode_id,"issue":"episode_date_mismatch","appear_value":episode_date,"episode_value":episode.get("episode_date")})
            expected_title=canonical_episode_title(episode_id,episode.get("episode_name"))
            if norm(sortable_title(episode_name))!=norm(expected_title): reconciliation.append({"appear_id":int(appear_id),"episode_id":episode_id,"issue":"episode_name_mismatch","appear_value":episode_name,"episode_value":expected_title})
        if person is None: reconciliation.append({"appear_id":int(appear_id),"cast_id":cast_id,"issue":"missing_cast"})
        elif norm(cast_id_name)!=norm(str(person.get("cast_id_name") or "")): reconciliation.append({"appear_id":int(appear_id),"cast_id":cast_id,"issue":"cast_id_name_mismatch","appear_value":cast_id_name,"cast_value":person.get("cast_id_name")})
        rows.append({"appear_id":str(int(appear_id)),"episode_id":episode_id,"cast_id":cast_id})
    return sorted(rows,key=lambda r:int(r["appear_id"])),reconciliation


def parse_adaptations_page() -> list[dict[str, str]]:
    response=requests.get(ADAPTATIONS_URL,timeout=45,headers={"User-Agent":"cbsrmt.db data maintenance"}); response.raise_for_status(); soup=BeautifulSoup(response.text,"html.parser"); by_episode={}
    for anchor in soup.find_all("a",href=True):
        href=str(anchor.get("href") or ""); match=re.search(r"(?:^|/)episode/(\d+)-",href)
        if not match: continue
        eid=str(int(match.group(1))); container=anchor.find_parent("li") or anchor.parent; text=container.get_text(" ",strip=True) if container else ""; adapted_match=re.search(r"(Adapted\s+from\b.*)$",text,flags=re.IGNORECASE)
        if not adapted_match: continue
        by_episode[eid]={"episode_id":eid,"title":anchor.get_text(" ",strip=True),"adapted":re.sub(r"\s+"," ",adapted_match.group(1)).strip(),"source_url":requests.compat.urljoin(ADAPTATIONS_URL,href)}
    return [by_episode[eid] for eid in sorted(by_episode,key=int)]


def build_adaptations(episodes: list[dict[str, Any]], external_rows: list[dict[str, str]]):
    by_id={str(int(row["episode_id"])):row for row in episodes}; values={}; warnings=[]; fallbacks=[]
    for row in external_rows:
        episode=by_id.get(row["episode_id"])
        if episode is None: warnings.append({**row,"issue":"episode_id_not_found"}); continue
        external_title = sortable_title(row["title"])
        database_title = canonical_episode_title(row["episode_id"], episode.get("episode_name") or "")
        if row["episode_id"] not in SERIES_FORMAT_EQUIVALENT_EPISODES and norm(external_title) != norm(database_title):
            warnings.append({**row,"issue":"title_mismatch","database_title":database_title,"resolution":"episode_id_accepted"})
        values[row["episode_id"]]=row["adapted"]
    for episode in episodes:
        eid=str(int(episode["episode_id"])); origwriter=str(episode.get("origwriter") or "").strip()
        if origwriter and eid not in values:
            adapted=f"Adapted from {origwriter}"; values[eid]=adapted; fallbacks.append({"episode_id":eid,"episode_name":canonical_episode_title(eid,episode.get("episode_name","")),"origwriter":origwriter,"generated_adapted":adapted})
    return [{"episode_id":eid,"adapted":values[eid]} for eid in sorted(values,key=int)],warnings,fallbacks


def normalize_episode_name(value: Any) -> str:
    """Move leading The/A articles to sortable title suffixes."""
    return sortable_title(value)


def normalize_episodes(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    fields=("episode_id","episode_date","episode_name","episode_plot","genre_id"); out=[]
    for row in rows:
        normalized={field:row.get(field,"") for field in fields}; normalized["episode_name"]=canonical_episode_title(row["episode_id"],row.get("episode_name","")); out.append(normalized)
    return out


def normalize_genre(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out=[]
    for row in rows:
        row=dict(row)
        if str(row.get("genre_name") or "").strip()=="Unkown": row["genre_name"]="Unknown"
        out.append(row)
    return sorted(out,key=lambda r:int(r["genre_id"]))


def sql_string(value: Any) -> str:
    if value is None: return "NULL"
    text=str(value).replace("\\","\\\\").replace("'","''").replace("\r","\\r").replace("\n","\\n"); return f"'{text}'"


def sql_date(value: Any) -> str:
    text=str(value or "").strip(); return "NULL" if not text or text=="0000-00-00" else sql_string(text)


def generate_sql(genres,cast,episodes,appear,episode_writers,adaptations) -> str:
    lines=["-- CBS Radio Mystery Theater normalized database rebuild","-- Generated by tools/rebuild_data.py.","","DROP DATABASE IF EXISTS `cbs`;","CREATE DATABASE `cbs` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;","USE `cbs`;","SET FOREIGN_KEY_CHECKS=0;","SET SQL_MODE='NO_AUTO_VALUE_ON_ZERO';","SET time_zone='+00:00';",""]
    lines += ["CREATE TABLE `genre` (","  `genre_id` tinyint unsigned NOT NULL,","  `genre_name` varchar(100) NOT NULL,","  PRIMARY KEY (`genre_id`)",") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;",""]
    lines += ["CREATE TABLE `cast` (","  `cast_id` int unsigned NOT NULL,","  `cast_id_name` varchar(100) NOT NULL DEFAULT '',","  `first_name` varchar(100) DEFAULT NULL,","  `middle_name` varchar(100) DEFAULT NULL,","  `last_name` varchar(100) DEFAULT NULL,","  `image_url` varchar(500) DEFAULT NULL,","  `soundclip_url` varchar(500) DEFAULT NULL,","  `bio` text,","  `born_on` date DEFAULT NULL,","  `died_on` date DEFAULT NULL,","  `offsite_url` varchar(500) DEFAULT NULL,","  `other_series` text,","  `credit` varchar(255) DEFAULT NULL,","  PRIMARY KEY (`cast_id`),","  KEY `idx_cast_id_name` (`cast_id_name`)",") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;",""]
    lines += ["CREATE TABLE `episodes` (","  `episode_id` int unsigned NOT NULL,","  `episode_date` date NOT NULL,","  `episode_name` varchar(150) NOT NULL,","  `episode_plot` text NOT NULL,","  `genre_id` tinyint unsigned NOT NULL,","  PRIMARY KEY (`episode_id`),","  KEY `idx_episodes_date` (`episode_date`),","  KEY `idx_episodes_name` (`episode_name`),","  KEY `idx_episodes_genre` (`genre_id`),","  CONSTRAINT `fk_episodes_genre` FOREIGN KEY (`genre_id`) REFERENCES `genre` (`genre_id`) ON UPDATE CASCADE ON DELETE RESTRICT",") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;",""]
    lines += ["CREATE TABLE `appear` (","  `appear_id` int unsigned NOT NULL AUTO_INCREMENT,","  `episode_id` int unsigned NOT NULL,","  `cast_id` int unsigned NOT NULL,","  PRIMARY KEY (`appear_id`),","  UNIQUE KEY `uq_appear_episode_cast` (`episode_id`,`cast_id`),","  KEY `idx_appear_episode` (`episode_id`),","  KEY `idx_appear_cast` (`cast_id`),","  CONSTRAINT `fk_appear_episode` FOREIGN KEY (`episode_id`) REFERENCES `episodes` (`episode_id`) ON UPDATE CASCADE ON DELETE CASCADE,","  CONSTRAINT `fk_appear_cast` FOREIGN KEY (`cast_id`) REFERENCES `cast` (`cast_id`) ON UPDATE CASCADE ON DELETE RESTRICT",") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;",""]
    lines += ["CREATE TABLE `episode_writers` (","  `episode_writer_id` int unsigned NOT NULL AUTO_INCREMENT,","  `episode_id` int unsigned NOT NULL,","  `cast_id` int unsigned NOT NULL,","  PRIMARY KEY (`episode_writer_id`),","  UNIQUE KEY `uq_episode_writer` (`episode_id`,`cast_id`),","  KEY `idx_episode_writer_episode` (`episode_id`),","  KEY `idx_episode_writer_cast` (`cast_id`),","  CONSTRAINT `fk_episode_writer_episode` FOREIGN KEY (`episode_id`) REFERENCES `episodes` (`episode_id`) ON UPDATE CASCADE ON DELETE CASCADE,","  CONSTRAINT `fk_episode_writer_cast` FOREIGN KEY (`cast_id`) REFERENCES `cast` (`cast_id`) ON UPDATE CASCADE ON DELETE RESTRICT",") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;",""]
    lines += ["CREATE TABLE `episode_adaptations` (","  `episode_id` int unsigned NOT NULL,","  `adapted` text NOT NULL,","  PRIMARY KEY (`episode_id`),","  CONSTRAINT `fk_episode_adaptations_episode` FOREIGN KEY (`episode_id`) REFERENCES `episodes` (`episode_id`) ON UPDATE CASCADE ON DELETE CASCADE",") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;",""]
    for row in genres: lines.append(f"INSERT INTO `genre` (`genre_id`,`genre_name`) VALUES ({int(row['genre_id'])},{sql_string(row['genre_name'])});")
    cast_fields=["cast_id","cast_id_name","first_name","middle_name","last_name","image_url","soundclip_url","bio","born_on","died_on","offsite_url","other_series","credit"]
    for row in cast:
        values=[str(int(row["cast_id"]))]
        for field in cast_fields[1:]:
            value=row.get(field); values.append(sql_date(value) if field in ("born_on","died_on") else sql_string(value if value not in (None,"") else None))
        lines.append("INSERT INTO `cast` (`"+"`,`".join(cast_fields)+"`) VALUES ("+",".join(values)+");")
    for row in episodes: lines.append("INSERT INTO `episodes` (`episode_id`,`episode_date`,`episode_name`,`episode_plot`,`genre_id`) VALUES ("+f"{int(row['episode_id'])},{sql_date(row['episode_date'])},{sql_string(row['episode_name'])},{sql_string(row['episode_plot'])},{int(row['genre_id'])});")
    for row in appear: lines.append(f"INSERT INTO `appear` (`appear_id`,`episode_id`,`cast_id`) VALUES ({int(row['appear_id'])},{int(row['episode_id'])},{int(row['cast_id'])});")
    for idx,row in enumerate(episode_writers,1): lines.append(f"INSERT INTO `episode_writers` (`episode_writer_id`,`episode_id`,`cast_id`) VALUES ({idx},{int(row['episode_id'])},{int(row['cast_id'])});")
    for row in adaptations: lines.append(f"INSERT INTO `episode_adaptations` (`episode_id`,`adapted`) VALUES ({int(row['episode_id'])},{sql_string(row['adapted'])});")
    lines.extend(["","SET FOREIGN_KEY_CHECKS=1;",""]); return "\n".join(lines)


def main() -> None:
    REPORTS.mkdir(parents=True,exist_ok=True)
    cast_legacy=source_json("data/cast.json"); writers=source_json("data/writers.json"); episodes_legacy=source_json("data/episodes.json"); genres_legacy=source_json("data/genre.json"); legacy_sql=source_text("sql/cbs.sql")
    merged_cast,conflicts,matched,added=merge_writers_into_cast(cast_legacy,writers)
    aliases=name_index(merged_cast,writers); episode_writers,unresolved=resolve_episode_writers(episodes_legacy,aliases)
    episodes_by_id={str(int(row["episode_id"])):row for row in episodes_legacy}; cast_by_id={str(int(row["cast_id"])):row for row in merged_cast}; appear,appear_reconciliation=extract_appear(legacy_sql,episodes_by_id,cast_by_id)
    external=parse_adaptations_page(); adaptations,adaptation_warnings,fallbacks=build_adaptations(episodes_legacy,external); episodes=normalize_episodes(episodes_legacy); genres=normalize_genre(genres_legacy)
    write_json(DATA/"cast.json",merged_cast); write_json(DATA/"episodes.json",episodes); write_json(DATA/"appear.json",appear); write_json(DATA/"episode_writers.json",episode_writers); write_json(DATA/"episode_adaptations.json",adaptations); write_json(DATA/"genre.json",genres)
    write_json(REPORTS/"writer-cast-conflicts.json",conflicts); write_json(REPORTS/"writer-unresolved.json",unresolved); write_json(REPORTS/"appear-reconciliation.json",appear_reconciliation); write_json(REPORTS/"adaptation-unmatched.json",adaptation_warnings); write_json(REPORTS/"adaptation-origwriter-fallbacks.json",fallbacks)
    (SQL/"cbs.sql").write_text(generate_sql(genres,merged_cast,episodes,appear,episode_writers,adaptations),encoding="utf-8")
    summary={"episodes":{"input":len(episodes_legacy),"output":len(episodes)},"cast":{"original":len(cast_legacy),"output":len(merged_cast),"writers_matched":matched,"new_people_added":added,"conflicts":len(conflicts)},"appear":{"output":len(appear),"reconciliation_warnings":len(appear_reconciliation),"duplicates_removed":sum(1 for r in appear_reconciliation if r.get("issue")=="duplicate_episode_cast")},"episode_writers":{"created":len(episode_writers),"unresolved":len(unresolved)},"episode_adaptations":{"external_parsed":len(external),"output":len(adaptations),"origwriter_fallbacks":len(fallbacks),"external_reconciliation_warnings":len(adaptation_warnings)},"genre":{"count":len(genres)},"source":{"baseline_ref":BASE_REF,"adaptations_url":ADAPTATIONS_URL}}
    write_json(REPORTS/"migration-summary.json",summary); print(json.dumps(summary,indent=2))


if __name__ == "__main__":
    main()
