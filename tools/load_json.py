#!/usr/bin/env python3
"""Load CBS RMT JSON documents, reconcile known source defects, stage them, and promote."""
import argparse, json
from datetime import date, timedelta
from pathlib import Path

try:
    import psycopg
except ImportError as exc:
    raise SystemExit("psycopg is required: pip install 'psycopg[binary]'") from exc

FILES = [
    "episodes.json", "cbsrmt_episode_dataset.json", "cast.json", "cast-corrections.json", "cast-deletions.json", "writers.json", "genre.json",
    "appearance.json", "episode-writer.json", "episode_genre.json", "adaptations.json", "episode_adaptation.json",
]

MISSING_WRITERS = [
    {"cast_id":"339","cast_id_name":"bharlow","first_name":"Bryce","middle_name":"","last_name":"Harlow"},
    {"cast_id":"340","cast_id_name":"bwalton","first_name":"Bryce","middle_name":"","last_name":"Walton"},
    {"cast_id":"341","cast_id_name":"fmarkle","first_name":"Fletcher","middle_name":"","last_name":"Markle"},
    {"cast_id":"345","cast_id_name":"slehrman","first_name":"Steve","middle_name":"","last_name":"Lehrman"},
]

def reconcile_writers(rows):
    rows=[dict(r) for r in rows]
    ids={int(r["cast_id"]) for r in rows}
    for item in MISSING_WRITERS:
        if int(item["cast_id"]) not in ids:
            r=dict(item)
            r.update({"image_url":"","soundclip_url":"","bio":"","born_on":"0000-00-00","died_on":"0000-00-00",
                      "offsite_url":"","other_series":"","credit":"reconciled from episode-writer.json + episodes.json"})
            rows.append(r)
    return sorted(rows,key=lambda r:int(r["cast_id"]))

def reconcile_broadcasts(episodes, rows):
    episode_by_id={int(r["episode_id"]):r for r in episodes}
    rows=[dict(r) for r in rows]
    original_ids={int(r["episode_id"]) for r in rows if r.get("episode_id") is not None}
    for episode_id in sorted(set(episode_by_id)-original_ids):
        canonical=episode_by_id[episode_id]
        candidates=[r for r in rows if r.get("episode_date")==canonical.get("episode_date") and
                    str(r.get("episode_name","")).casefold()==str(canonical.get("episode_name","")).casefold()]
        if len(candidates)!=1:
            raise RuntimeError(f"Cannot uniquely reconcile canonical episode {episode_id}: {len(candidates)} candidates")
        r=candidates[0]
        r["episode_id"]=episode_id
        r["repeat_of_episode_id"]=None
    for r in rows:
        eid=r.get("episode_id") if r.get("episode_id") is not None else r.get("repeat_of_episode_id")
        if eid is not None:
            canonical=episode_by_id[int(eid)]
            r["episode_name"]=canonical.get("episode_name")
            r["episode_plot"]=canonical.get("episode_plot")
    dates={date.fromisoformat(r["episode_date"]) for r in rows}
    start,end=min(dates),max(dates)
    for i in range((end-start).days+1):
        d=start+timedelta(days=i)
        if d not in dates:
            rows.append({"id":None,"sequence_number":None,"episode_id":None,"episode_plot":None,"episode_date":d.isoformat(),
                         "episode_name":"No Episode Tonight","episode_note":None,"repeat_of_episode_id":None})
    def kind(r):
        if r.get("episode_id") is not None: return 0
        if r.get("repeat_of_episode_id") is not None: return 1
        return 2
    rows.sort(key=lambda r:(r["episode_date"],kind(r),r.get("id") or 10**9))
    seq=0
    for idx,r in enumerate(rows,1):
        r["id"]=idx
        if kind(r)<2:
            seq+=1; r["sequence_number"]=seq
        else:
            r["sequence_number"]=None
    ids=[int(r["episode_id"]) for r in rows if r.get("episode_id") is not None]
    if set(ids)!=set(episode_by_id) or len(ids)!=len(set(ids)):
        raise RuntimeError("Reconciled broadcast history does not contain exactly one original row per canonical episode")
    return rows

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--dsn',required=True)
    ap.add_argument('--data-dir',default='data')
    args=ap.parse_args(); root=Path(args.data_dir)
    missing=[name for name in FILES if not (root/name).exists()]
    if missing: raise SystemExit('Missing: '+', '.join(missing))
    docs={name:json.loads((root/name).read_text(encoding='utf-8')) for name in FILES}
    docs['writers.json']=reconcile_writers(docs['writers.json'])
    docs['cbsrmt_episode_dataset.json']=reconcile_broadcasts(docs['episodes.json'],docs['cbsrmt_episode_dataset.json'])
    with psycopg.connect(args.dsn) as conn:
        with conn.cursor() as cur:
            for name in FILES:
                payload=docs[name]
                cur.execute("""INSERT INTO stage.source_document(source_name,payload,loaded_at) VALUES(%s,%s::jsonb,now())
                               ON CONFLICT(source_name) DO UPDATE SET payload=excluded.payload,loaded_at=now()""",
                            (name,json.dumps(payload,ensure_ascii=False)))
                print('staged',name,len(payload) if isinstance(payload,list) else 'object')
            cur.execute('SELECT import.promote_all()')
            print(json.dumps(cur.fetchone()[0],indent=2,default=str))
        conn.commit()

if __name__=='__main__': main()
