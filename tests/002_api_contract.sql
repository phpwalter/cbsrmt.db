BEGIN;

DO $$
DECLARE
    v jsonb;
    v_user_id bigint;
BEGIN
    v := api.ping();
    IF v->>'status' <> 'ok' THEN RAISE EXCEPTION 'ping contract failed'; END IF;

    v := api.get_anniversary_broadcasts(DATE '1974-01-06');
    IF v->>'requested_date' <> '1974-01-06' THEN RAISE EXCEPTION 'anniversary requested_date failed'; END IF;
    IF v->>'resolved_broadcast_date' <> '1974-01-06' THEN RAISE EXCEPTION 'anniversary exact-date resolution failed'; END IF;
    IF (v->>'fallback_used')::boolean THEN RAISE EXCEPTION 'anniversary exact date incorrectly marked fallback'; END IF;
    IF jsonb_array_length(v->'broadcasts') < 1 THEN RAISE EXCEPTION 'anniversary exact date returned no broadcasts'; END IF;

    v := api.get_anniversary_broadcasts(DATE '1982-01-01');
    IF NOT (v->>'fallback_used')::boolean THEN RAISE EXCEPTION 'anniversary no-broadcast date did not use fallback'; END IF;
    IF (v->>'resolved_broadcast_date')::date >= DATE '1982-01-01' THEN RAISE EXCEPTION 'anniversary fallback did not resolve to prior date'; END IF;
    IF jsonb_array_length(v->'broadcasts') < 1 THEN RAISE EXCEPTION 'anniversary fallback returned no broadcasts'; END IF;

    v := api.get_episode(1);
    IF v->>'episode_number' <> '1' THEN RAISE EXCEPTION 'get_episode(1) failed'; END IF;
    IF NOT (v ? 'broadcast_date') THEN RAISE EXCEPTION 'Episode.broadcast_date missing'; END IF;
    IF v->>'thumbnail' <> '/assets/episodes/0001.png' THEN RAISE EXCEPTION 'Episode.thumbnail convention failed'; END IF;
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

    v := api.get_episodes(1,5,NULL,NULL,'Mystery,Suspense',NULL,NULL,'episode_number','asc');
    IF (v#>>'{pagination,total}')::integer < (api.get_episodes(1,5,NULL,NULL,'Mystery',NULL,NULL,'episode_number','asc')#>>'{pagination,total}')::integer
       OR (v#>>'{pagination,total}')::integer < (api.get_episodes(1,5,NULL,NULL,'Suspense',NULL,NULL,'episode_number','asc')#>>'{pagination,total}')::integer THEN
        RAISE EXCEPTION 'OR genre filtering contract failed';
    END IF;

    v := api.get_episodes(1,5,'January 6, 1974',NULL,NULL,NULL,NULL,'episode_number','asc');
    IF jsonb_array_length(v->'data') < 1 THEN RAISE EXCEPTION 'human-readable broadcast date search failed'; END IF;

    v := api.get_episodes(1,5,'1974-01-06',NULL,NULL,NULL,NULL,'episode_number','asc');
    IF jsonb_array_length(v->'data') < 1 THEN RAISE EXCEPTION 'ISO broadcast date search failed'; END IF;

    IF api.get_episode_cast(999999) IS NOT NULL THEN RAISE EXCEPTION 'missing episode cast must map to 404'; END IF;

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

    IF api.get_cast_member(999999) IS NOT NULL THEN RAISE EXCEPTION 'missing cast member must map to 404'; END IF;
    IF api.get_writer(999999) IS NOT NULL THEN RAISE EXCEPTION 'missing writer must map to 404'; END IF;
    IF api.get_genre_episodes(999999) IS NOT NULL THEN RAISE EXCEPTION 'missing genre must map to 404'; END IF;

    v := api.get_cast();
    IF NOT (v ? 'data') OR NOT (v ? 'pagination') THEN RAISE EXCEPTION 'CastCollection contract failed'; END IF;
    IF jsonb_array_length(v->'data') > 0 AND (
        NOT ((v->'data'->0) ? 'appearance_count')
        OR NOT ((v->'data'->0) ? 'portrait')
        OR NOT ((v->'data'->0) ? 'cast_id_name')
    ) THEN
        RAISE EXCEPTION 'Cast Archive fields missing';
    END IF;

    v := api.get_cast(1,10,NULL,NULL,'appearances','desc');
    IF (v#>>'{pagination,limit}')::integer <> 10 THEN RAISE EXCEPTION 'Cast Archive page size failed'; END IF;

    IF jsonb_array_length(v->'data') > 1 AND
       ((v->'data'->0->>'appearance_count')::integer < (v->'data'->1->>'appearance_count')::integer) THEN
        RAISE EXCEPTION 'Cast appearances descending sort failed';
    END IF;

    v := api.get_cast(1,10,NULL,NULL,'appearances','asc');
    IF jsonb_array_length(v->'data') > 1 AND
       ((v->'data'->0->>'appearance_count')::integer > (v->'data'->1->>'appearance_count')::integer) THEN
        RAISE EXCEPTION 'Cast appearances ascending sort failed';
    END IF;

    v := api.get_cast(1,10,NULL,NULL,'name','asc');
    IF jsonb_array_length(v->'data') > 1 AND
       lower(coalesce(v->'data'->0->>'last_name',v->'data'->0->>'first_name','')) >
       lower(coalesce(v->'data'->1->>'last_name',v->'data'->1->>'first_name','')) THEN
        RAISE EXCEPTION 'Cast name ascending sort failed';
    END IF;

    v := api.get_cast(1,10,NULL,NULL,'name','desc');
    IF jsonb_array_length(v->'data') > 1 AND
       lower(coalesce(v->'data'->0->>'last_name',v->'data'->0->>'first_name','')) <
       lower(coalesce(v->'data'->1->>'last_name',v->'data'->1->>'first_name','')) THEN
        RAISE EXCEPTION 'Cast name descending sort failed';
    END IF;

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
