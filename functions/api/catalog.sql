-- Remove pre-OpenAPI-alignment overloads so upgrades do not leave ambiguous calls.
DROP FUNCTION IF EXISTS api.get_genre_episodes(integer,integer,integer);
DROP FUNCTION IF EXISTS api.get_cast_episodes(integer,integer,integer);
DROP FUNCTION IF EXISTS api.get_writer_episodes(integer,integer,integer);
DROP FUNCTION IF EXISTS api.search_catalog(text,integer,integer,text);
DROP FUNCTION IF EXISTS api.get_person(integer);
DROP FUNCTION IF EXISTS api.get_episodes(integer,integer,text,integer,integer,integer,integer,text,text);

CREATE OR REPLACE FUNCTION api.ping()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $$
SELECT jsonb_build_object('status','ok')
$$;

CREATE OR REPLACE FUNCTION api.genre_json(p_genre_id integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, catalog
AS $$
SELECT jsonb_build_object('id',g.genre_id,'name',g.genre_name)
FROM catalog.genre g
WHERE g.genre_id=p_genre_id
  AND g.genre_id >= 1
$$;

CREATE OR REPLACE FUNCTION api.cast_member_json(p_person_id integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, catalog
AS $$
SELECT jsonb_build_object(
    'id', p.person_id,
    'first_name', p.first_name,
    'last_name', p.last_name,
    'display_name', nullif(btrim(concat_ws(' ',p.first_name,p.middle_name,p.last_name)),'')
)
FROM catalog.person p
WHERE p.person_id=p_person_id
$$;

CREATE OR REPLACE FUNCTION api.writer_json(p_person_id integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, catalog
AS $$
SELECT jsonb_build_object(
    'id', p.person_id,
    'first_name', p.first_name,
    'last_name', p.last_name,
    'display_name', nullif(btrim(concat_ws(' ',p.first_name,p.middle_name,p.last_name)),'')
)
FROM catalog.person p
WHERE p.person_id=p_person_id
$$;

CREATE OR REPLACE FUNCTION api.audio_json(p_episode_number integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, catalog
AS $$
SELECT COALESCE(
    (
        SELECT jsonb_build_object(
            'available', true,
            'stream_url', m.stream_url,
            'duration_seconds', m.duration_seconds,
            'media_type', m.mime_type
        )
        FROM catalog.episode_media m
        WHERE m.episode_number=p_episode_number
          AND m.is_active
          AND m.media_type='audio'
        ORDER BY m.media_id DESC
        LIMIT 1
    ),
    jsonb_build_object(
        'available', false,
        'stream_url', NULL,
        'duration_seconds', NULL,
        'media_type', NULL
    )
)
$$;

CREATE OR REPLACE FUNCTION api.episode_summary_json(p_episode_number integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, catalog, api
AS $$
SELECT jsonb_build_object(
    'episode_number', e.episode_number,
    'episode_name', e.episode_name,
    'episode_plot', e.episode_plot,
    'broadcast_date', e.original_air_date,
    'thumbnail', '/assets/episodes/' || lpad(e.episode_number::text,4,'0') || '.png',
    'audio', api.audio_json(e.episode_number)
)
FROM catalog.episode e
WHERE e.episode_number=p_episode_number
$$;

CREATE OR REPLACE FUNCTION api.episode_json(p_episode_number integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, catalog, api
AS $$
SELECT jsonb_build_object(
    'episode_number', e.episode_number,
    'episode_name', e.episode_name,
    'episode_plot', e.episode_plot,
    'broadcast_date', e.original_air_date,
    'thumbnail', '/assets/episodes/' || lpad(e.episode_number::text,4,'0') || '.png',
    'audio', api.audio_json(e.episode_number),
    'genres', COALESCE((
        SELECT jsonb_agg(api.genre_json(g.genre_id) ORDER BY g.genre_name)
        FROM catalog.episode_genre eg
        JOIN catalog.genre g USING (genre_id)
        WHERE eg.episode_number=e.episode_number
          AND g.genre_id >= 1
    ), '[]'::jsonb),
    'cast', COALESCE((
        SELECT jsonb_agg(api.cast_member_json(p.person_id)
                         ORDER BY p.last_name,p.first_name,p.person_id)
        FROM catalog.episode_cast ec
        JOIN catalog.person p USING (person_id)
        WHERE ec.episode_number=e.episode_number
    ), '[]'::jsonb),
    'writers', COALESCE((
        SELECT jsonb_agg(api.writer_json(p.person_id)
                         ORDER BY p.last_name,p.first_name,p.person_id)
        FROM catalog.episode_writer ew
        JOIN catalog.person p USING (person_id)
        WHERE ew.episode_number=e.episode_number
    ), '[]'::jsonb)
)
FROM catalog.episode e
WHERE e.episode_number=p_episode_number
$$;

CREATE OR REPLACE FUNCTION api.get_episode(p_episode_number integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, api
AS $$
SELECT api.episode_json(p_episode_number)
$$;

CREATE OR REPLACE FUNCTION api.get_episode_cast(p_episode_number integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, catalog, api
AS $$
SELECT CASE
    WHEN NOT EXISTS (SELECT 1 FROM catalog.episode e WHERE e.episode_number=p_episode_number) THEN NULL
    ELSE jsonb_build_object(
        'data',
        COALESCE((
            SELECT jsonb_agg(api.cast_member_json(p.person_id)
                             ORDER BY p.last_name,p.first_name,p.person_id)
            FROM catalog.episode_cast ec
            JOIN catalog.person p USING (person_id)
            WHERE ec.episode_number=p_episode_number
        ), '[]'::jsonb)
    )
END
$$;

CREATE OR REPLACE FUNCTION api.get_episode_writers(p_episode_number integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, catalog, api
AS $$
SELECT CASE
    WHEN NOT EXISTS (SELECT 1 FROM catalog.episode e WHERE e.episode_number=p_episode_number) THEN NULL
    ELSE jsonb_build_object(
        'data',
        COALESCE((
            SELECT jsonb_agg(api.writer_json(p.person_id)
                             ORDER BY p.last_name,p.first_name,p.person_id)
            FROM catalog.episode_writer ew
            JOIN catalog.person p USING (person_id)
            WHERE ew.episode_number=p_episode_number
        ), '[]'::jsonb)
    )
END
$$;

CREATE OR REPLACE FUNCTION api.get_episodes(
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5,
    p_search text DEFAULT NULL,
    p_year integer DEFAULT NULL,
    p_genre text DEFAULT NULL,
    p_cast text DEFAULT NULL,
    p_writer text DEFAULT NULL,
    p_sort text DEFAULT 'episode_number',
    p_order text DEFAULT 'asc'
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, catalog, api
AS $$
DECLARE
    v_page integer := greatest(coalesce(p_page,1),1);
    v_limit integer := least(greatest(coalesce(p_limit,5),1),100);
    v_total bigint;
    v_data jsonb;
BEGIN
    IF p_sort NOT IN ('episode_number','episode_name','broadcast_date') THEN
        RAISE EXCEPTION 'Invalid sort field: %', p_sort;
    END IF;
    IF lower(p_order) NOT IN ('asc','desc') THEN
        RAISE EXCEPTION 'Invalid sort direction: %', p_order;
    END IF;

    WITH filtered AS (
        SELECT e.*
        FROM catalog.episode e
        WHERE (p_search IS NULL
               OR e.episode_name ILIKE '%'||p_search||'%'
               OR coalesce(e.episode_plot,'') ILIKE '%'||p_search||'%'
               OR e.original_air_date::text ILIKE '%'||p_search||'%'
               OR to_char(e.original_air_date,'FMMonth DD, YYYY') ILIKE '%'||p_search||'%'
               OR EXISTS (
                    SELECT 1
                    FROM catalog.broadcast b
                    WHERE b.episode_number=e.episode_number
                      AND (
                          b.broadcast_date::text ILIKE '%'||p_search||'%'
                          OR to_char(b.broadcast_date,'FMMonth DD, YYYY') ILIKE '%'||p_search||'%'
                      )
               ))
          AND (p_year IS NULL OR extract(year from e.original_air_date)::integer=p_year)
          AND (p_genre IS NULL OR NOT EXISTS (
                SELECT 1
                FROM unnest(string_to_array(p_genre, ',')) requested_genre(name)
                WHERE btrim(requested_genre.name) <> ''
                  AND NOT EXISTS (
                    SELECT 1
                    FROM catalog.episode_genre eg
                    JOIN catalog.genre g USING (genre_id)
                    WHERE eg.episode_number=e.episode_number
                      AND g.genre_id >= 1
                      AND lower(g.genre_name)=lower(btrim(requested_genre.name))
                  )
              ))
          AND (p_cast IS NULL OR EXISTS (
                SELECT 1
                FROM catalog.episode_cast ec
                JOIN catalog.person p USING (person_id)
                WHERE ec.episode_number=e.episode_number
                  AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_cast||'%'
              ))
          AND (p_writer IS NULL OR EXISTS (
                SELECT 1
                FROM catalog.episode_writer ew
                JOIN catalog.person p USING (person_id)
                WHERE ew.episode_number=e.episode_number
                  AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_writer||'%'
              ))
    )
    SELECT count(*) INTO v_total FROM filtered;

    WITH filtered AS (
        SELECT e.*
        FROM catalog.episode e
        WHERE (p_search IS NULL
               OR e.episode_name ILIKE '%'||p_search||'%'
               OR coalesce(e.episode_plot,'') ILIKE '%'||p_search||'%'
               OR e.original_air_date::text ILIKE '%'||p_search||'%'
               OR to_char(e.original_air_date,'FMMonth DD, YYYY') ILIKE '%'||p_search||'%'
               OR EXISTS (
                    SELECT 1
                    FROM catalog.broadcast b
                    WHERE b.episode_number=e.episode_number
                      AND (
                          b.broadcast_date::text ILIKE '%'||p_search||'%'
                          OR to_char(b.broadcast_date,'FMMonth DD, YYYY') ILIKE '%'||p_search||'%'
                      )
               ))
          AND (p_year IS NULL OR extract(year from e.original_air_date)::integer=p_year)
          AND (p_genre IS NULL OR NOT EXISTS (
                SELECT 1
                FROM unnest(string_to_array(p_genre, ',')) requested_genre(name)
                WHERE btrim(requested_genre.name) <> ''
                  AND NOT EXISTS (
                    SELECT 1
                    FROM catalog.episode_genre eg
                    JOIN catalog.genre g USING (genre_id)
                    WHERE eg.episode_number=e.episode_number
                      AND g.genre_id >= 1
                      AND lower(g.genre_name)=lower(btrim(requested_genre.name))
                  )
              ))
          AND (p_cast IS NULL OR EXISTS (
                SELECT 1
                FROM catalog.episode_cast ec
                JOIN catalog.person p USING (person_id)
                WHERE ec.episode_number=e.episode_number
                  AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_cast||'%'
              ))
          AND (p_writer IS NULL OR EXISTS (
                SELECT 1
                FROM catalog.episode_writer ew
                JOIN catalog.person p USING (person_id)
                WHERE ew.episode_number=e.episode_number
                  AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_writer||'%'
              ))
        ORDER BY
          CASE WHEN p_sort='episode_number' AND lower(p_order)='asc' THEN e.episode_number END ASC,
          CASE WHEN p_sort='episode_number' AND lower(p_order)='desc' THEN e.episode_number END DESC,
          CASE WHEN p_sort='episode_name' AND lower(p_order)='asc' THEN e.episode_name END ASC,
          CASE WHEN p_sort='episode_name' AND lower(p_order)='desc' THEN e.episode_name END DESC,
          CASE WHEN p_sort='broadcast_date' AND lower(p_order)='asc' THEN e.original_air_date END ASC,
          CASE WHEN p_sort='broadcast_date' AND lower(p_order)='desc' THEN e.original_air_date END DESC,
          e.episode_number
        OFFSET (v_page-1)*v_limit
        LIMIT v_limit
    )
    SELECT COALESCE(
        jsonb_agg(
            api.episode_summary_json(episode_number)
            ORDER BY
              CASE WHEN p_sort='episode_number' AND lower(p_order)='asc' THEN episode_number END ASC,
              CASE WHEN p_sort='episode_number' AND lower(p_order)='desc' THEN episode_number END DESC,
              CASE WHEN p_sort='episode_name' AND lower(p_order)='asc' THEN episode_name END ASC,
              CASE WHEN p_sort='episode_name' AND lower(p_order)='desc' THEN episode_name END DESC,
              CASE WHEN p_sort='broadcast_date' AND lower(p_order)='asc' THEN original_air_date END ASC,
              CASE WHEN p_sort='broadcast_date' AND lower(p_order)='desc' THEN original_air_date END DESC,
              episode_number
        ),
        '[]'::jsonb
    )
      INTO v_data
    FROM filtered;

    RETURN jsonb_build_object(
        'data', v_data,
        'pagination', jsonb_build_object(
            'page', v_page,
            'limit', v_limit,
            'total', v_total,
            'pages', CASE WHEN v_total=0 THEN 0 ELSE ceil(v_total::numeric/v_limit)::integer END
        )
    );
END
$$;

CREATE OR REPLACE FUNCTION api.get_people(
    p_role text,
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5,
    p_search text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,catalog,api
AS $$
DECLARE
    v_page integer := greatest(coalesce(p_page,1),1);
    v_limit integer := least(greatest(coalesce(p_limit,5),1),100);
    v_total bigint;
    v_data jsonb;
BEGIN
    IF p_role NOT IN ('cast','writer') THEN
        RAISE EXCEPTION 'Invalid role: %', p_role;
    END IF;

    WITH ids AS (
        SELECT person_id FROM catalog.episode_cast WHERE p_role='cast'
        UNION
        SELECT person_id FROM catalog.episode_writer WHERE p_role='writer'
    ), filtered AS (
        SELECT p.*
        FROM catalog.person p
        JOIN ids USING(person_id)
        WHERE p_search IS NULL
           OR concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_search||'%'
    )
    SELECT count(*) INTO v_total FROM filtered;

    WITH ids AS (
        SELECT person_id FROM catalog.episode_cast WHERE p_role='cast'
        UNION
        SELECT person_id FROM catalog.episode_writer WHERE p_role='writer'
    ), filtered AS (
        SELECT p.*
        FROM catalog.person p
        JOIN ids USING(person_id)
        WHERE p_search IS NULL
           OR concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_search||'%'
        ORDER BY p.last_name,p.first_name,p.person_id
        OFFSET (v_page-1)*v_limit
        LIMIT v_limit
    )
    SELECT COALESCE(
        jsonb_agg(
            CASE WHEN p_role='cast'
                 THEN api.cast_member_json(person_id)
                 ELSE api.writer_json(person_id)
            END
            ORDER BY last_name,first_name,person_id
        ),
        '[]'::jsonb
    )
    INTO v_data
    FROM filtered;

    RETURN jsonb_build_object(
        'data',v_data,
        'pagination',jsonb_build_object(
            'page',v_page,
            'limit',v_limit,
            'total',v_total,
            'pages',CASE WHEN v_total=0 THEN 0 ELSE ceil(v_total::numeric/v_limit)::integer END
        )
    );
END
$$;

CREATE OR REPLACE FUNCTION api.get_cast(
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5,
    p_search text DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,api
AS $$
SELECT api.get_people('cast',p_page,p_limit,p_search)
$$;

CREATE OR REPLACE FUNCTION api.get_writers(
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5,
    p_search text DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,api
AS $$
SELECT api.get_people('writer',p_page,p_limit,p_search)
$$;

CREATE OR REPLACE FUNCTION api.get_cast_member(p_cast_id integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,catalog,api
AS $$
SELECT CASE WHEN EXISTS (
    SELECT 1 FROM catalog.episode_cast ec WHERE ec.person_id=p_cast_id
) THEN api.cast_member_json(p_cast_id) ELSE NULL END
$$;

CREATE OR REPLACE FUNCTION api.get_writer(p_writer_id integer)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,catalog,api
AS $$
SELECT CASE WHEN EXISTS (
    SELECT 1 FROM catalog.episode_writer ew WHERE ew.person_id=p_writer_id
) THEN api.writer_json(p_writer_id) ELSE NULL END
$$;

CREATE OR REPLACE FUNCTION api.get_person_episodes(
    p_role text,
    p_person_id integer,
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5,
    p_sort text DEFAULT 'episode_number',
    p_order text DEFAULT 'asc'
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,catalog,api
AS $$
DECLARE
    v_page integer := greatest(coalesce(p_page,1),1);
    v_limit integer := least(greatest(coalesce(p_limit,5),1),100);
    v_total bigint;
    v_data jsonb;
BEGIN
    IF p_role NOT IN ('cast','writer') THEN RAISE EXCEPTION 'Invalid role'; END IF;
    IF (p_role='cast' AND NOT EXISTS (SELECT 1 FROM catalog.episode_cast WHERE person_id=p_person_id))
       OR (p_role='writer' AND NOT EXISTS (SELECT 1 FROM catalog.episode_writer WHERE person_id=p_person_id)) THEN
        RETURN NULL;
    END IF;
    IF p_sort NOT IN ('episode_number','episode_name','broadcast_date') THEN RAISE EXCEPTION 'Invalid sort field: %',p_sort; END IF;
    IF lower(p_order) NOT IN ('asc','desc') THEN RAISE EXCEPTION 'Invalid sort direction: %',p_order; END IF;

    WITH filtered AS (
        SELECT e.*
        FROM catalog.episode e
        WHERE (p_role='cast' AND EXISTS (
                 SELECT 1 FROM catalog.episode_cast ec
                 WHERE ec.episode_number=e.episode_number AND ec.person_id=p_person_id
              ))
           OR (p_role='writer' AND EXISTS (
                 SELECT 1 FROM catalog.episode_writer ew
                 WHERE ew.episode_number=e.episode_number AND ew.person_id=p_person_id
              ))
    )
    SELECT count(*) INTO v_total FROM filtered;

    WITH filtered AS (
        SELECT e.*
        FROM catalog.episode e
        WHERE (p_role='cast' AND EXISTS (
                 SELECT 1 FROM catalog.episode_cast ec
                 WHERE ec.episode_number=e.episode_number AND ec.person_id=p_person_id
              ))
           OR (p_role='writer' AND EXISTS (
                 SELECT 1 FROM catalog.episode_writer ew
                 WHERE ew.episode_number=e.episode_number AND ew.person_id=p_person_id
              ))
        ORDER BY
          CASE WHEN p_sort='episode_number' AND lower(p_order)='asc' THEN e.episode_number END ASC,
          CASE WHEN p_sort='episode_number' AND lower(p_order)='desc' THEN e.episode_number END DESC,
          CASE WHEN p_sort='episode_name' AND lower(p_order)='asc' THEN e.episode_name END ASC,
          CASE WHEN p_sort='episode_name' AND lower(p_order)='desc' THEN e.episode_name END DESC,
          CASE WHEN p_sort='broadcast_date' AND lower(p_order)='asc' THEN e.original_air_date END ASC,
          CASE WHEN p_sort='broadcast_date' AND lower(p_order)='desc' THEN e.original_air_date END DESC,
          e.episode_number
        OFFSET (v_page-1)*v_limit
        LIMIT v_limit
    )
    SELECT COALESCE(
        jsonb_agg(
            api.episode_summary_json(episode_number)
            ORDER BY
              CASE WHEN p_sort='episode_number' AND lower(p_order)='asc' THEN episode_number END ASC,
              CASE WHEN p_sort='episode_number' AND lower(p_order)='desc' THEN episode_number END DESC,
              CASE WHEN p_sort='episode_name' AND lower(p_order)='asc' THEN episode_name END ASC,
              CASE WHEN p_sort='episode_name' AND lower(p_order)='desc' THEN episode_name END DESC,
              CASE WHEN p_sort='broadcast_date' AND lower(p_order)='asc' THEN original_air_date END ASC,
              CASE WHEN p_sort='broadcast_date' AND lower(p_order)='desc' THEN original_air_date END DESC,
              episode_number
        ),
        '[]'::jsonb
    )
      INTO v_data
    FROM filtered;

    RETURN jsonb_build_object(
        'data',v_data,
        'pagination',jsonb_build_object(
            'page',v_page,
            'limit',v_limit,
            'total',v_total,
            'pages',CASE WHEN v_total=0 THEN 0 ELSE ceil(v_total::numeric/v_limit)::integer END
        )
    );
END
$$;

CREATE OR REPLACE FUNCTION api.get_cast_episodes(
    p_cast_id integer,
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5,
    p_sort text DEFAULT 'episode_number',
    p_order text DEFAULT 'asc'
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,api
AS $$
SELECT api.get_person_episodes('cast',p_cast_id,p_page,p_limit,p_sort,p_order)
$$;

CREATE OR REPLACE FUNCTION api.get_writer_episodes(
    p_writer_id integer,
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5,
    p_sort text DEFAULT 'episode_number',
    p_order text DEFAULT 'asc'
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,api
AS $$
SELECT api.get_person_episodes('writer',p_writer_id,p_page,p_limit,p_sort,p_order)
$$;

CREATE OR REPLACE FUNCTION api.get_genres()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,catalog,api
AS $$
SELECT jsonb_build_object(
    'data',
    COALESCE(
        jsonb_agg(api.genre_json(g.genre_id) ORDER BY g.genre_name)
        FILTER (WHERE g.genre_id >= 1),
        '[]'::jsonb
    )
)
FROM catalog.genre g
$$;

CREATE OR REPLACE FUNCTION api.get_genre_episodes(
    p_genre_id integer,
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5,
    p_sort text DEFAULT 'episode_number',
    p_order text DEFAULT 'asc'
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,catalog,api
AS $$
DECLARE
    v_page integer := greatest(coalesce(p_page,1),1);
    v_limit integer := least(greatest(coalesce(p_limit,5),1),100);
    v_total bigint;
    v_data jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM catalog.genre WHERE genre_id=p_genre_id AND genre_id >= 1) THEN
        RETURN NULL;
    END IF;
    IF p_sort NOT IN ('episode_number','episode_name','broadcast_date') THEN RAISE EXCEPTION 'Invalid sort field: %',p_sort; END IF;
    IF lower(p_order) NOT IN ('asc','desc') THEN RAISE EXCEPTION 'Invalid sort direction: %',p_order; END IF;

    WITH filtered AS (
        SELECT e.*
        FROM catalog.episode e
        WHERE EXISTS (
            SELECT 1 FROM catalog.episode_genre eg
            WHERE eg.episode_number=e.episode_number
              AND eg.genre_id=p_genre_id
        )
    )
    SELECT count(*) INTO v_total FROM filtered;

    WITH filtered AS (
        SELECT e.*
        FROM catalog.episode e
        WHERE EXISTS (
            SELECT 1 FROM catalog.episode_genre eg
            WHERE eg.episode_number=e.episode_number
              AND eg.genre_id=p_genre_id
        )
        ORDER BY
          CASE WHEN p_sort='episode_number' AND lower(p_order)='asc' THEN e.episode_number END ASC,
          CASE WHEN p_sort='episode_number' AND lower(p_order)='desc' THEN e.episode_number END DESC,
          CASE WHEN p_sort='episode_name' AND lower(p_order)='asc' THEN e.episode_name END ASC,
          CASE WHEN p_sort='episode_name' AND lower(p_order)='desc' THEN e.episode_name END DESC,
          CASE WHEN p_sort='broadcast_date' AND lower(p_order)='asc' THEN e.original_air_date END ASC,
          CASE WHEN p_sort='broadcast_date' AND lower(p_order)='desc' THEN e.original_air_date END DESC,
          e.episode_number
        OFFSET (v_page-1)*v_limit
        LIMIT v_limit
    )
    SELECT COALESCE(
        jsonb_agg(
            api.episode_summary_json(episode_number)
            ORDER BY
              CASE WHEN p_sort='episode_number' AND lower(p_order)='asc' THEN episode_number END ASC,
              CASE WHEN p_sort='episode_number' AND lower(p_order)='desc' THEN episode_number END DESC,
              CASE WHEN p_sort='episode_name' AND lower(p_order)='asc' THEN episode_name END ASC,
              CASE WHEN p_sort='episode_name' AND lower(p_order)='desc' THEN episode_name END DESC,
              CASE WHEN p_sort='broadcast_date' AND lower(p_order)='asc' THEN original_air_date END ASC,
              CASE WHEN p_sort='broadcast_date' AND lower(p_order)='desc' THEN original_air_date END DESC,
              episode_number
        ),
        '[]'::jsonb
    )
      INTO v_data
    FROM filtered;

    RETURN jsonb_build_object(
        'data',v_data,
        'pagination',jsonb_build_object(
            'page',v_page,
            'limit',v_limit,
            'total',v_total,
            'pages',CASE WHEN v_total=0 THEN 0 ELSE ceil(v_total::numeric/v_limit)::integer END
        )
    );
END
$$;

CREATE OR REPLACE FUNCTION api.search_catalog(
    p_query text,
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,catalog,api
AS $$
DECLARE
    v_page integer := greatest(coalesce(p_page,1),1);
    v_limit integer := least(greatest(coalesce(p_limit,5),1),100);
    v_total bigint;
    v_data jsonb;
BEGIN
    IF p_query IS NULL OR btrim(p_query)='' THEN
        RAISE EXCEPTION 'Search query is required';
    END IF;

    WITH results AS (
        SELECT 'episode'::text AS type,
               e.episode_name AS sort_title,
               e.episode_number::bigint AS sort_id,
               api.episode_summary_json(e.episode_number) AS payload
        FROM catalog.episode e
        WHERE e.episode_name ILIKE '%'||p_query||'%'
           OR coalesce(e.episode_plot,'') ILIKE '%'||p_query||'%'

        UNION ALL

        SELECT 'cast',
               concat_ws(' ',p.first_name,p.middle_name,p.last_name),
               p.person_id,
               api.cast_member_json(p.person_id)
        FROM catalog.person p
        WHERE EXISTS (SELECT 1 FROM catalog.episode_cast ec WHERE ec.person_id=p.person_id)
          AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_query||'%'

        UNION ALL

        SELECT 'writer',
               concat_ws(' ',p.first_name,p.middle_name,p.last_name),
               p.person_id,
               api.writer_json(p.person_id)
        FROM catalog.person p
        WHERE EXISTS (SELECT 1 FROM catalog.episode_writer ew WHERE ew.person_id=p.person_id)
          AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_query||'%'
    )
    SELECT count(*) INTO v_total FROM results;

    WITH results AS (
        SELECT 'episode'::text AS type,
               e.episode_name AS sort_title,
               e.episode_number::bigint AS sort_id,
               api.episode_summary_json(e.episode_number) AS payload
        FROM catalog.episode e
        WHERE e.episode_name ILIKE '%'||p_query||'%'
           OR coalesce(e.episode_plot,'') ILIKE '%'||p_query||'%'

        UNION ALL

        SELECT 'cast',
               concat_ws(' ',p.first_name,p.middle_name,p.last_name),
               p.person_id,
               api.cast_member_json(p.person_id)
        FROM catalog.person p
        WHERE EXISTS (SELECT 1 FROM catalog.episode_cast ec WHERE ec.person_id=p.person_id)
          AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_query||'%'

        UNION ALL

        SELECT 'writer',
               concat_ws(' ',p.first_name,p.middle_name,p.last_name),
               p.person_id,
               api.writer_json(p.person_id)
        FROM catalog.person p
        WHERE EXISTS (SELECT 1 FROM catalog.episode_writer ew WHERE ew.person_id=p.person_id)
          AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_query||'%'
    ), paged AS (
        SELECT *
        FROM results
        ORDER BY type,sort_title,sort_id
        OFFSET (v_page-1)*v_limit
        LIMIT v_limit
    )
    SELECT jsonb_build_object(
        'episodes', COALESCE(jsonb_agg(payload ORDER BY sort_title,sort_id)
                             FILTER (WHERE type='episode'),'[]'::jsonb),
        'cast', COALESCE(jsonb_agg(payload ORDER BY sort_title,sort_id)
                         FILTER (WHERE type='cast'),'[]'::jsonb),
        'writers', COALESCE(jsonb_agg(payload ORDER BY sort_title,sort_id)
                            FILTER (WHERE type='writer'),'[]'::jsonb)
    )
    INTO v_data
    FROM paged;

    RETURN jsonb_build_object(
        'data',v_data,
        'pagination',jsonb_build_object(
            'page',v_page,
            'limit',v_limit,
            'total',v_total,
            'pages',CASE WHEN v_total=0 THEN 0 ELSE ceil(v_total::numeric/v_limit)::integer END
        )
    );
END
$$;

CREATE OR REPLACE FUNCTION api.get_anniversary_broadcasts(p_target_date date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,catalog,api
AS $$
DECLARE
    v_resolved_date date;
    v_broadcasts jsonb;
BEGIN
    SELECT max(b.broadcast_date)
      INTO v_resolved_date
      FROM catalog.broadcast b
     WHERE b.broadcast_date <= p_target_date
       AND b.broadcast_type IN ('original','repeat')
       AND b.episode_number IS NOT NULL;

    IF v_resolved_date IS NULL THEN
        RETURN jsonb_build_object(
            'requested_date', p_target_date,
            'resolved_broadcast_date', NULL,
            'fallback_used', false,
            'broadcasts', '[]'::jsonb
        );
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'broadcast_type', b.broadcast_type,
                'broadcast_sequence', b.broadcast_sequence,
                'broadcast_date', b.broadcast_date,
                'episode', api.episode_summary_json(b.episode_number)
            )
            ORDER BY b.broadcast_sequence NULLS LAST, b.broadcast_id
        ),
        '[]'::jsonb
    )
      INTO v_broadcasts
      FROM catalog.broadcast b
     WHERE b.broadcast_date = v_resolved_date
       AND b.broadcast_type IN ('original','repeat')
       AND b.episode_number IS NOT NULL;

    RETURN jsonb_build_object(
        'requested_date', p_target_date,
        'resolved_broadcast_date', v_resolved_date,
        'fallback_used', v_resolved_date <> p_target_date,
        'broadcasts', v_broadcasts
    );
END
$$;

CREATE OR REPLACE FUNCTION api.user_json(p_user_id bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,account
AS $$
SELECT jsonb_strip_nulls(jsonb_build_object(
    'id',u.user_id,
    'username',u.username,
    'first_name',u.first_name,
    'last_name',u.last_name,
    'avatar',CASE WHEN u.avatar IS NULL THEN NULL
                  ELSE jsonb_build_object('avatar',replace(encode(u.avatar,'base64'),E'\\n','')) END
))
FROM account.app_user u
WHERE u.user_id=p_user_id
$$;

CREATE OR REPLACE FUNCTION api.get_users(
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,account,api
AS $$
DECLARE
    v_page integer := greatest(coalesce(p_page,1),1);
    v_limit integer := least(greatest(coalesce(p_limit,5),1),100);
    v_total bigint;
    v_data jsonb;
BEGIN
    SELECT count(*) INTO v_total FROM account.app_user;

    SELECT COALESCE(jsonb_agg(api.user_json(user_id) ORDER BY user_id),'[]'::jsonb)
    INTO v_data
    FROM (
        SELECT user_id
        FROM account.app_user
        ORDER BY user_id
        OFFSET (v_page-1)*v_limit
        LIMIT v_limit
    ) s;

    RETURN jsonb_build_object(
        'data',v_data,
        'pagination',jsonb_build_object(
            'page',v_page,
            'limit',v_limit,
            'total',v_total,
            'pages',CASE WHEN v_total=0 THEN 0 ELSE ceil(v_total::numeric/v_limit)::integer END
        )
    );
END
$$;

CREATE OR REPLACE FUNCTION api.get_user(p_user_id bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,api
AS $$
SELECT api.user_json(p_user_id)
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA api FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO cbsrmt_api, cbsrmt_admin;
