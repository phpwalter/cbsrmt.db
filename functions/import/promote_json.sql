CREATE OR REPLACE FUNCTION import.null_date(p_value text)
RETURNS date LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_value IS NULL OR btrim(p_value) IN ('', '0000-00-00') THEN NULL ELSE p_value::date END
$$;

CREATE OR REPLACE FUNCTION import.promote_all()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, catalog, stage, import
AS $$
DECLARE
    v_episodes jsonb;
    v_broadcasts jsonb;
    v_cast jsonb;
    v_writers jsonb;
    v_genres jsonb;
    v_appearance jsonb;
    v_episode_writer jsonb;
    v_episode_genre jsonb;
    v_adaptations jsonb;
    v_episode_adaptation jsonb;
BEGIN
    SELECT payload INTO STRICT v_episodes FROM stage.source_document WHERE source_name='episodes.json';
    SELECT payload INTO STRICT v_broadcasts FROM stage.source_document WHERE source_name='cbsrmt_episode_dataset.json';
    SELECT payload INTO STRICT v_cast FROM stage.source_document WHERE source_name='cast.json';
    SELECT payload INTO STRICT v_writers FROM stage.source_document WHERE source_name='writers.json';
    SELECT payload INTO STRICT v_genres FROM stage.source_document WHERE source_name='genre.json';
    SELECT payload INTO STRICT v_appearance FROM stage.source_document WHERE source_name='appearance.json';
    SELECT payload INTO STRICT v_episode_writer FROM stage.source_document WHERE source_name='episode-writer.json';
    SELECT payload INTO STRICT v_episode_genre FROM stage.source_document WHERE source_name='episode_genre.json';
    SELECT payload INTO STRICT v_adaptations FROM stage.source_document WHERE source_name='adaptations.json';
    SELECT payload INTO STRICT v_episode_adaptation FROM stage.source_document WHERE source_name='episode_adaptation.json';

    TRUNCATE catalog.episode_media, catalog.episode_adaptation, catalog.episode_genre,
             catalog.episode_writer, catalog.episode_cast, catalog.broadcast,
             catalog.adaptation, catalog.genre, catalog.person, catalog.episode RESTART IDENTITY;

    INSERT INTO catalog.episode(episode_number, episode_name, episode_plot, original_air_date)
    SELECT (x->>'episode_id')::integer, btrim(x->>'episode_name'), nullif(x->>'episode_plot',''), (x->>'episode_date')::date
    FROM jsonb_array_elements(v_episodes) x;

    IF (SELECT count(*) FROM catalog.episode) <> 1399 THEN
        RAISE EXCEPTION 'Expected 1399 canonical episodes, got %', (SELECT count(*) FROM catalog.episode);
    END IF;

    INSERT INTO catalog.person(person_id, person_code, first_name, middle_name, last_name, image_url,
                               soundclip_url, bio, born_on, died_on, offsite_url, other_series, credit)
    SELECT DISTINCT ON ((x->>'cast_id')::integer)
           (x->>'cast_id')::integer, nullif(x->>'cast_id_name',''), nullif(x->>'first_name',''),
           nullif(x->>'middle_name',''), nullif(x->>'last_name',''), nullif(x->>'image_url',''),
           nullif(x->>'soundclip_url',''), nullif(x->>'bio',''), import.null_date(x->>'born_on'),
           import.null_date(x->>'died_on'), nullif(x->>'offsite_url',''), nullif(x->>'other_series',''),
           nullif(x->>'credit','')
    FROM (
        SELECT value x, 1 precedence FROM jsonb_array_elements(v_cast)
        UNION ALL
        SELECT value x, 2 precedence FROM jsonb_array_elements(v_writers)
    ) s
    ORDER BY (x->>'cast_id')::integer, precedence;

    INSERT INTO catalog.genre(genre_id, genre_name)
    SELECT (x->>'genre_id')::smallint, x->>'genre_name'
    FROM jsonb_array_elements(v_genres) x;

    INSERT INTO catalog.adaptation(adaptation_id, episode_title, credited_source_note, identified_source_work,
                                   identified_author, confidence, basis)
    SELECT (x->>'record_id')::integer, x->>'episode_title', x->>'credited_source_note',
           x->>'identified_source_work', x->>'identified_author', nullif(x->>'confidence',''), x->>'basis'
    FROM jsonb_array_elements(v_adaptations) x;

    INSERT INTO catalog.broadcast(broadcast_date, broadcast_sequence, episode_number, broadcast_type, source_row_id)
    SELECT (x->>'episode_date')::date,
           nullif(x->>'sequence_number','')::integer,
           CASE WHEN x->>'episode_id' IS NOT NULL THEN (x->>'episode_id')::integer
                WHEN x->>'repeat_of_episode_id' IS NOT NULL THEN (x->>'repeat_of_episode_id')::integer
                ELSE NULL END,
           CASE WHEN x->>'episode_id' IS NOT NULL THEN 'original'
                WHEN x->>'repeat_of_episode_id' IS NOT NULL THEN 'repeat'
                ELSE 'no_broadcast' END,
           nullif(x->>'id','')::integer
    FROM jsonb_array_elements(v_broadcasts) x;

    INSERT INTO catalog.episode_cast(episode_number, person_id)
    SELECT DISTINCT (x->>'episode_id')::integer, (x->>'cast_id')::integer
    FROM jsonb_array_elements(v_appearance) x;

    INSERT INTO catalog.episode_writer(episode_number, person_id)
    SELECT DISTINCT (x->>'episode_id')::integer, (x->>'writer_id')::integer
    FROM jsonb_array_elements(v_episode_writer) x;

    INSERT INTO catalog.episode_genre(episode_number, genre_id)
    SELECT DISTINCT (x->>'episode_id')::integer, (x->>'genre_id')::smallint
    FROM jsonb_array_elements(v_episode_genre) x;

    INSERT INTO catalog.episode_adaptation(episode_number, adaptation_id)
    SELECT DISTINCT (x->>'episode_id')::integer, (x->>'adaptation_id')::integer
    FROM jsonb_array_elements(v_episode_adaptation) x;

    RETURN jsonb_build_object(
        'episodes', (SELECT count(*) FROM catalog.episode),
        'broadcasts', (SELECT count(*) FROM catalog.broadcast),
        'people', (SELECT count(*) FROM catalog.person),
        'genres', (SELECT count(*) FROM catalog.genre),
        'adaptations', (SELECT count(*) FROM catalog.adaptation),
        'episode_cast', (SELECT count(*) FROM catalog.episode_cast),
        'episode_writers', (SELECT count(*) FROM catalog.episode_writer),
        'episode_genres', (SELECT count(*) FROM catalog.episode_genre),
        'episode_adaptations', (SELECT count(*) FROM catalog.episode_adaptation)
    );
END
$$;

REVOKE ALL ON FUNCTION import.promote_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION import.promote_all() TO cbsrmt_import;
