# Source Data Findings

The PostgreSQL migration validates relationships before promotion instead of silently dropping bad references.

## Missing writer master rows

`episode-writer.json` references four writer IDs absent from both `cast.json` and the original `writers.json`:

| writer_id | Reconciled name | Evidence in canonical episode data |
|---:|---|---|
| 339 | Bryce Harlow | episode 1320, `The Hanging Sheriff` |
| 340 | Bryce Walton | episodes 1292, 1338, 1360 |
| 341 | Fletcher Markle | episode 631 |
| 345 | Steve Lehrman | episodes 1311 and 1364 |

The branch does not alter raw `data/writers.json`. During staging, `tools/load_json.py` synthesizes minimal writer master records for these four IDs. Unknown biographical dates normalize to SQL NULL.

Episode 1311 spells writer 345 as `Steve Laerman`; episode 1364 spells it `Steve Lehrman`. Because both relationship rows use writer ID 345, the staged master uses `Steve Lehrman` while the episode source text remains unchanged.

After this staging repair, all current episode-cast, episode-writer, episode-genre, and episode-adaptation foreign-key references resolve to a master row.
