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
    v_cast_corrections jsonb;
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
    SELECT payload INTO STRICT v_cast_corrections FROM stage.source_document WHERE source_name='cast-corrections.json';
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

    INSERT INTO import.cast_correction_audit(
        correction_key,person_id,
        person_code_before,person_code_after,
        first_name_before,first_name_after,
        middle_name_before,middle_name_after,
        last_name_before,last_name_after,
        reason,source_reference
    )
    SELECT
        x->>'correction_key',
        (x->>'cast_id')::integer,
        nullif(btrim(x->'before'->>'cast_id_name'),''),
        nullif(btrim(x->'after'->>'cast_id_name'),''),
        nullif(btrim(x->'before'->>'first_name'),''),
        nullif(btrim(x->'after'->>'first_name'),''),
        nullif(btrim(x->'before'->>'middle_name'),''),
        nullif(btrim(x->'after'->>'middle_name'),''),
        nullif(btrim(x->'before'->>'last_name'),''),
        nullif(btrim(x->'after'->>'last_name'),''),
        x->>'reason',
        x->>'source_reference'
    FROM jsonb_array_elements(v_cast_corrections) x
    WHERE nullif(btrim(x->>'correction_key'),'') IS NOT NULL
    ON CONFLICT (correction_key) DO NOTHING;

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


CREATE OR REPLACE FUNCTION import.promote_cast()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, catalog, stage, import
AS $promote_cast$
DECLARE
    v_cast jsonb;
    v_corrections jsonb;
    v_staged_count integer;
    v_identity_changes integer;
    v_rows_updated integer;
    v_audit_rows integer;
    v_episode_cast_before bigint;
    v_episode_cast_after bigint;
BEGIN
    SELECT payload INTO STRICT v_cast
      FROM stage.source_document
     WHERE source_name='cast.json';

    SELECT payload INTO STRICT v_corrections
      FROM stage.source_document
     WHERE source_name='cast-corrections.json';

    IF jsonb_typeof(v_cast) <> 'array' THEN
        RAISE EXCEPTION 'cast.json must contain a JSON array';
    END IF;
    IF jsonb_typeof(v_corrections) <> 'array' THEN
        RAISE EXCEPTION 'cast-corrections.json must contain a JSON array';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_cast) x
        WHERE coalesce(x->>'cast_id','') !~ '^[1-9][0-9]*
    ) THEN
        RAISE EXCEPTION 'cast.json contains an invalid cast_id';
    END IF;

    IF EXISTS (
        SELECT (x->>'cast_id')::integer
        FROM jsonb_array_elements(v_cast) x
        GROUP BY (x->>'cast_id')::integer
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'cast.json contains duplicate cast_id values';
    END IF;

    IF EXISTS (
        SELECT lower(btrim(x->>'cast_id_name'))
        FROM jsonb_array_elements(v_cast) x
        WHERE nullif(btrim(x->>'cast_id_name'),'') IS NOT NULL
        GROUP BY lower(btrim(x->>'cast_id_name'))
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'cast.json contains duplicate cast_id_name values';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_cast) x
        LEFT JOIN catalog.person p ON p.person_id=(x->>'cast_id')::integer
        WHERE p.person_id IS NULL
    ) THEN
        RAISE EXCEPTION 'cast.json contains a cast_id that is not present in catalog.person';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_corrections) x
        WHERE nullif(btrim(x->>'correction_key'),'') IS NULL
           OR coalesce(x->>'cast_id','') !~ '^[1-9][0-9]*
           OR nullif(btrim(x->>'reason'),'') IS NULL
           OR nullif(btrim(x->>'source_reference'),'') IS NULL
           OR jsonb_typeof(x->'before') <> 'object'
           OR jsonb_typeof(x->'after') <> 'object'
    ) THEN
        RAISE EXCEPTION 'cast-corrections.json contains an invalid correction record';
    END IF;

    IF EXISTS (
        SELECT x->>'correction_key'
        FROM jsonb_array_elements(v_corrections) x
        GROUP BY x->>'correction_key'
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'cast-corrections.json contains duplicate correction_key values';
    END IF;

    SELECT count(*) INTO v_staged_count FROM jsonb_array_elements(v_cast);
    SELECT count(*) INTO v_episode_cast_before FROM catalog.episode_cast;

    WITH staged AS (
        SELECT
            (x->>'cast_id')::integer AS person_id,
            nullif(btrim(x->>'cast_id_name'),'') AS person_code,
            nullif(btrim(x->>'first_name'),'') AS first_name,
            nullif(btrim(x->>'middle_name'),'') AS middle_name,
            nullif(btrim(x->>'last_name'),'') AS last_name
        FROM jsonb_array_elements(v_cast) x
    ), changes AS (
        SELECT p.person_id
        FROM catalog.person p
        JOIN staged s USING(person_id)
        WHERE ROW(p.person_code,p.first_name,p.middle_name,p.last_name)
              IS DISTINCT FROM
              ROW(s.person_code,s.first_name,s.middle_name,s.last_name)
    )
    SELECT count(*) INTO v_identity_changes FROM changes;

    IF EXISTS (
        WITH staged AS (
            SELECT
                (x->>'cast_id')::integer AS person_id,
                nullif(btrim(x->>'cast_id_name'),'') AS person_code,
                nullif(btrim(x->>'first_name'),'') AS first_name,
                nullif(btrim(x->>'middle_name'),'') AS middle_name,
                nullif(btrim(x->>'last_name'),'') AS last_name
            FROM jsonb_array_elements(v_cast) x
        ), changes AS (
            SELECT
                p.person_id,
                p.person_code AS before_person_code,
                p.first_name AS before_first_name,
                p.middle_name AS before_middle_name,
                p.last_name AS before_last_name,
                s.person_code AS after_person_code,
                s.first_name AS after_first_name,
                s.middle_name AS after_middle_name,
                s.last_name AS after_last_name
            FROM catalog.person p
            JOIN staged s USING(person_id)
            WHERE ROW(p.person_code,p.first_name,p.middle_name,p.last_name)
                  IS DISTINCT FROM
                  ROW(s.person_code,s.first_name,s.middle_name,s.last_name)
        ), corrections AS (
            SELECT
                (x->>'cast_id')::integer AS person_id,
                nullif(btrim(x->'before'->>'cast_id_name'),'') AS before_person_code,
                nullif(btrim(x->'before'->>'first_name'),'') AS before_first_name,
                nullif(btrim(x->'before'->>'middle_name'),'') AS before_middle_name,
                nullif(btrim(x->'before'->>'last_name'),'') AS before_last_name,
                nullif(btrim(x->'after'->>'cast_id_name'),'') AS after_person_code,
                nullif(btrim(x->'after'->>'first_name'),'') AS after_first_name,
                nullif(btrim(x->'after'->>'middle_name'),'') AS after_middle_name,
                nullif(btrim(x->'after'->>'last_name'),'') AS after_last_name
            FROM jsonb_array_elements(v_corrections) x
        )
        SELECT 1
        FROM changes ch
        WHERE NOT EXISTS (
            SELECT 1
            FROM corrections c
            WHERE c.person_id=ch.person_id
              AND ROW(c.before_person_code,c.before_first_name,c.before_middle_name,c.before_last_name)
                  IS NOT DISTINCT FROM
                  ROW(ch.before_person_code,ch.before_first_name,ch.before_middle_name,ch.before_last_name)
              AND ROW(c.after_person_code,c.after_first_name,c.after_middle_name,c.after_last_name)
                  IS NOT DISTINCT FROM
                  ROW(ch.after_person_code,ch.after_first_name,ch.after_middle_name,ch.after_last_name)
        )
    ) THEN
        RAISE EXCEPTION 'Every cast identity change requires an exact matching cast-corrections.json audit record';
    END IF;

    WITH staged AS (
        SELECT
            (x->>'cast_id')::integer AS person_id,
            nullif(btrim(x->>'cast_id_name'),'') AS person_code,
            nullif(btrim(x->>'first_name'),'') AS first_name,
            nullif(btrim(x->>'middle_name'),'') AS middle_name,
            nullif(btrim(x->>'last_name'),'') AS last_name
        FROM jsonb_array_elements(v_cast) x
    ), changes AS (
        SELECT
            p.person_id,
            p.person_code AS before_person_code,
            p.first_name AS before_first_name,
            p.middle_name AS before_middle_name,
            p.last_name AS before_last_name,
            s.person_code AS after_person_code,
            s.first_name AS after_first_name,
            s.middle_name AS after_middle_name,
            s.last_name AS after_last_name
        FROM catalog.person p
        JOIN staged s USING(person_id)
        WHERE ROW(p.person_code,p.first_name,p.middle_name,p.last_name)
              IS DISTINCT FROM
              ROW(s.person_code,s.first_name,s.middle_name,s.last_name)
    ), corrections AS (
        SELECT
            x->>'correction_key' AS correction_key,
            (x->>'cast_id')::integer AS person_id,
            nullif(btrim(x->>'reason'),'') AS reason,
            nullif(btrim(x->>'source_reference'),'') AS source_reference,
            nullif(btrim(x->'before'->>'cast_id_name'),'') AS before_person_code,
            nullif(btrim(x->'before'->>'first_name'),'') AS before_first_name,
            nullif(btrim(x->'before'->>'middle_name'),'') AS before_middle_name,
            nullif(btrim(x->'before'->>'last_name'),'') AS before_last_name,
            nullif(btrim(x->'after'->>'cast_id_name'),'') AS after_person_code,
            nullif(btrim(x->'after'->>'first_name'),'') AS after_first_name,
            nullif(btrim(x->'after'->>'middle_name'),'') AS after_middle_name,
            nullif(btrim(x->'after'->>'last_name'),'') AS after_last_name
        FROM jsonb_array_elements(v_corrections) x
    )
    INSERT INTO import.cast_correction_audit(
        correction_key,person_id,
        person_code_before,person_code_after,
        first_name_before,first_name_after,
        middle_name_before,middle_name_after,
        last_name_before,last_name_after,
        reason,source_reference
    )
    SELECT
        c.correction_key,ch.person_id,
        ch.before_person_code,ch.after_person_code,
        ch.before_first_name,ch.after_first_name,
        ch.before_middle_name,ch.after_middle_name,
        ch.before_last_name,ch.after_last_name,
        c.reason,c.source_reference
    FROM changes ch
    JOIN corrections c
      ON c.person_id=ch.person_id
     AND ROW(c.before_person_code,c.before_first_name,c.before_middle_name,c.before_last_name)
         IS NOT DISTINCT FROM
         ROW(ch.before_person_code,ch.before_first_name,ch.before_middle_name,ch.before_last_name)
     AND ROW(c.after_person_code,c.after_first_name,c.after_middle_name,c.after_last_name)
         IS NOT DISTINCT FROM
         ROW(ch.after_person_code,ch.after_first_name,ch.after_middle_name,ch.after_last_name)
    ON CONFLICT (correction_key) DO NOTHING;

    GET DIAGNOSTICS v_audit_rows = ROW_COUNT;

    WITH staged AS (
        SELECT
            (x->>'cast_id')::integer AS person_id,
            nullif(btrim(x->>'cast_id_name'),'') AS person_code,
            nullif(btrim(x->>'first_name'),'') AS first_name,
            nullif(btrim(x->>'middle_name'),'') AS middle_name,
            nullif(btrim(x->>'last_name'),'') AS last_name,
            nullif(x->>'image_url','') AS image_url,
            nullif(x->>'soundclip_url','') AS soundclip_url,
            nullif(x->>'bio','') AS bio,
            import.null_date(x->>'born_on') AS born_on,
            import.null_date(x->>'died_on') AS died_on,
            nullif(x->>'offsite_url','') AS offsite_url,
            nullif(x->>'other_series','') AS other_series,
            nullif(x->>'credit','') AS credit
        FROM jsonb_array_elements(v_cast) x
    )
    UPDATE catalog.person p
       SET person_code=s.person_code,
           first_name=s.first_name,
           middle_name=s.middle_name,
           last_name=s.last_name,
           image_url=s.image_url,
           soundclip_url=s.soundclip_url,
           bio=s.bio,
           born_on=s.born_on,
           died_on=s.died_on,
           offsite_url=s.offsite_url,
           other_series=s.other_series,
           credit=s.credit,
           updated_at=now()
      FROM staged s
     WHERE p.person_id=s.person_id
       AND ROW(p.person_code,p.first_name,p.middle_name,p.last_name,p.image_url,p.soundclip_url,p.bio,
               p.born_on,p.died_on,p.offsite_url,p.other_series,p.credit)
           IS DISTINCT FROM
           ROW(s.person_code,s.first_name,s.middle_name,s.last_name,s.image_url,s.soundclip_url,s.bio,
               s.born_on,s.died_on,s.offsite_url,s.other_series,s.credit);

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

    SELECT count(*) INTO v_episode_cast_after FROM catalog.episode_cast;
    IF v_episode_cast_after <> v_episode_cast_before THEN
        RAISE EXCEPTION 'Cast correction changed episode_cast relationship count';
    END IF;

    RETURN jsonb_build_object(
        'staged_cast_records',v_staged_count,
        'identity_changes',v_identity_changes,
        'rows_updated',v_rows_updated,
        'audit_rows_inserted',v_audit_rows,
        'episode_cast_relationships',v_episode_cast_after
    );
END
$promote_cast$;

REVOKE ALL ON FUNCTION import.promote_cast() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION import.promote_cast() TO cbsrmt_import;

REVOKE ALL ON FUNCTION import.promote_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION import.promote_all() TO cbsrmt_import;
