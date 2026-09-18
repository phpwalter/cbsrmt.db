BEGIN;

DO $$
DECLARE
    v jsonb;
    v_user_id bigint;
BEGIN
    v := api.ping();
    IF v->>'status' <> 'ok' THEN RAISE EXCEPTION 'ping contract failed'; END IF;

    v := api.get_episode(1);
    IF v->>'episode_number' <> '1' THEN RAISE EXCEPTION 'get_episode(1) failed'; END IF;
    IF NOT (v ? 'broadcast_date') THEN RAISE EXCEPTION 'Episode.broadcast_date missing'; END IF;
    IF v->>'thumbnail' <> '/public/assets/episodes/1.png' THEN RAISE EXCEPTION 'Episode.thumbnail convention failed'; END IF;
    IF NOT (v ? 'audio') OR NOT ((v->'audio') ? 'available') THEN RAISE EXCEPTION 'Episode.audio contract failed'; END IF;
    IF v ? 'original_air_date' OR v ? 'thumbnail_url' THEN RAISE EXCEPTION 'legacy Episode field leaked'; END IF;

    v := api.get_episodes();
    IF jsonb_array_length(v->'data') <> 5 THEN RAISE EXCEPTION 'default page size must be 5'; END IF;
    IF (v#>>'{pagination,total}')::integer <> 1399 THEN RAISE EXCEPTION 'pagination total must be 1399'; END IF;
    IF NOT ((v->'data'->0) ? 'broadcast_date') OR NOT ((v->'data'->0) ? 'thumbnail') THEN
        RAISE EXCEPTION 'EpisodeSummary contract failed';
    END IF;

    v := api.get_episodes(1,5,NULL,NULL,'Mystery',NULL,NULL,'broadcast_date','asc');
    IF NOT (v ? 'data') OR NOT (v ? 'pagination') THEN RAISE EXCEPTION 'name-filtered episodes contract failed'; END IF;

    v := api.get_episode_cast(1);
    IF NOT (v ? 'data') THEN RAISE EXCEPTION 'episode cast envelope failed'; END IF;
    IF jsonb_array_length(v->'data') > 0 AND NOT ((v->'data'->0) ? 'id') THEN
        RAISE EXCEPTION 'CastMember.id missing';
    END IF;

    v := api.get_episode_writers(1);
    IF NOT (v ? 'data') THEN RAISE EXCEPTION 'episode writer envelope failed'; END IF;
    IF jsonb_array_length(v->'data') > 0 AND NOT ((v->'data'->0) ? 'id') THEN
        RAISE EXCEPTION 'Writer.id missing';
    END IF;

    v := api.get_cast();
    IF NOT (v ? 'data') OR NOT (v ? 'pagination') THEN RAISE EXCEPTION 'CastCollection contract failed'; END IF;

    v := api.get_writers();
    IF NOT (v ? 'data') OR NOT (v ? 'pagination') THEN RAISE EXCEPTION 'WriterCollection contract failed'; END IF;

    v := api.get_genres();
    IF NOT (v ? 'data') THEN RAISE EXCEPTION 'genres envelope failed'; END IF;
    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v->'data') x
        WHERE (x->>'id')::integer < 1 OR NOT (x ? 'name')
    ) THEN
        RAISE EXCEPTION 'Genre contract failed';
    END IF;

    v := api.search_catalog('ghost',1,5);
    IF NOT (v ? 'data') OR NOT (v ? 'pagination') THEN RAISE EXCEPTION 'SearchResults envelope failed'; END IF;
    IF NOT ((v->'data') ? 'episodes') OR NOT ((v->'data') ? 'cast') OR NOT ((v->'data') ? 'writers') THEN
        RAISE EXCEPTION 'SearchResults grouped data contract failed';
    END IF;

    INSERT INTO account.app_user(username,first_name,last_name)
    VALUES('__contract_test__','Contract','Test')
    RETURNING user_id INTO v_user_id;

    v := api.get_user(v_user_id);
    IF v->>'username' <> '__contract_test__' OR NOT (v ? 'id') THEN RAISE EXCEPTION 'User contract failed'; END IF;

    v := admin.update_user(v_user_id,'{"first_name":"Updated"}'::jsonb);
    IF v->>'first_name' <> 'Updated' THEN RAISE EXCEPTION 'UserUpdate contract failed'; END IF;

    IF NOT admin.delete_user(v_user_id) THEN RAISE EXCEPTION 'deleteUser contract failed'; END IF;
    IF api.get_user(v_user_id) IS NOT NULL THEN RAISE EXCEPTION 'deleted user still retrievable'; END IF;

    RAISE NOTICE 'PASS: OpenAPI database contract tests';
END $$;

ROLLBACK;
