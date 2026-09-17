DO $$
DECLARE v jsonb;
BEGIN
 v := api.get_episode(1);
 IF v->>'episode_number' <> '1' THEN RAISE EXCEPTION 'get_episode(1) failed'; END IF;
 IF v->>'thumbnail_url' <> '/public/assets/episodes/1.png' THEN RAISE EXCEPTION 'thumbnail convention failed'; END IF;
 v := api.get_episodes();
 IF jsonb_array_length(v->'data') <> 5 THEN RAISE EXCEPTION 'default page size must be 5'; END IF;
 IF (v#>>'{pagination,total}')::integer <> 1399 THEN RAISE EXCEPTION 'pagination total must be 1399'; END IF;
 v := api.get_episode_broadcasts(1);
 IF v->>'episode_number' <> '1' THEN RAISE EXCEPTION 'broadcast lookup failed'; END IF;
 RAISE NOTICE 'PASS: API contract smoke tests';
END $$;
