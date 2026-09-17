DO $$
DECLARE v bigint;
BEGIN
 SELECT count(*) INTO v FROM catalog.episode;
 IF v <> 1399 THEN RAISE EXCEPTION 'episode count: expected 1399, got %',v; END IF;
 IF EXISTS(SELECT episode_number FROM catalog.episode GROUP BY episode_number HAVING count(*)>1) THEN RAISE EXCEPTION 'duplicate episode_number'; END IF;
 IF EXISTS(SELECT 1 FROM catalog.broadcast b LEFT JOIN catalog.episode e USING(episode_number) WHERE b.episode_number IS NOT NULL AND e.episode_number IS NULL) THEN RAISE EXCEPTION 'orphan broadcast episode'; END IF;
 IF EXISTS(SELECT 1 FROM catalog.episode_cast ec LEFT JOIN catalog.person p USING(person_id) WHERE p.person_id IS NULL) THEN RAISE EXCEPTION 'orphan cast person'; END IF;
 IF EXISTS(SELECT 1 FROM catalog.episode_writer ew LEFT JOIN catalog.person p USING(person_id) WHERE p.person_id IS NULL) THEN RAISE EXCEPTION 'orphan writer person'; END IF;
 IF EXISTS(SELECT 1 FROM catalog.episode_genre eg LEFT JOIN catalog.genre g USING(genre_id) WHERE g.genre_id IS NULL) THEN RAISE EXCEPTION 'orphan genre'; END IF;
 IF EXISTS(SELECT 1 FROM catalog.episode_adaptation ea LEFT JOIN catalog.adaptation a USING(adaptation_id) WHERE a.adaptation_id IS NULL) THEN RAISE EXCEPTION 'orphan adaptation'; END IF;
 SELECT count(*) INTO v FROM catalog.broadcast;
 IF v <> 3259 THEN RAISE EXCEPTION 'broadcast row count: expected 3259, got %',v; END IF;
 SELECT count(*) INTO v FROM catalog.broadcast WHERE broadcast_sequence IS NOT NULL;
 IF v <> 2836 THEN RAISE EXCEPTION 'actual broadcast count: expected 2836, got %',v; END IF;
 IF EXISTS(SELECT broadcast_sequence FROM catalog.broadcast WHERE broadcast_sequence IS NOT NULL GROUP BY broadcast_sequence HAVING count(*)>1) THEN RAISE EXCEPTION 'duplicate broadcast_sequence'; END IF;
 IF EXISTS(SELECT 1 FROM catalog.broadcast WHERE broadcast_type='no_broadcast' AND (episode_number IS NOT NULL OR broadcast_sequence IS NOT NULL)) THEN RAISE EXCEPTION 'invalid no_broadcast semantics'; END IF;
 RAISE NOTICE 'PASS: catalog integrity';
END $$;
