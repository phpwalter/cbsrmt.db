CREATE OR REPLACE FUNCTION api.episode_json(p_episode_number integer)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = pg_catalog, catalog
AS $$
SELECT jsonb_build_object(
    'episode_number', e.episode_number,
    'episode_name', e.episode_name,
    'episode_plot', e.episode_plot,
    'original_air_date', e.original_air_date,
    'thumbnail_url', '/public/assets/episodes/' || e.episode_number || '.png',
    'genres', COALESCE((SELECT jsonb_agg(jsonb_build_object('genre_id',g.genre_id,'genre_name',g.genre_name) ORDER BY g.genre_name)
                       FROM catalog.episode_genre eg JOIN catalog.genre g USING (genre_id)
                       WHERE eg.episode_number=e.episode_number), '[]'::jsonb),
    'cast', COALESCE((SELECT jsonb_agg(jsonb_build_object('person_id',p.person_id,'first_name',p.first_name,'middle_name',p.middle_name,'last_name',p.last_name)
                                      ORDER BY p.last_name,p.first_name,p.person_id)
                     FROM catalog.episode_cast ec JOIN catalog.person p USING (person_id)
                     WHERE ec.episode_number=e.episode_number), '[]'::jsonb),
    'writers', COALESCE((SELECT jsonb_agg(jsonb_build_object('person_id',p.person_id,'first_name',p.first_name,'middle_name',p.middle_name,'last_name',p.last_name)
                                         ORDER BY p.last_name,p.first_name,p.person_id)
                        FROM catalog.episode_writer ew JOIN catalog.person p USING (person_id)
                        WHERE ew.episode_number=e.episode_number), '[]'::jsonb),
    'adaptations', COALESCE((SELECT jsonb_agg(jsonb_build_object('adaptation_id',a.adaptation_id,'source_work',a.identified_source_work,
                                                                 'author',a.identified_author,'credit',a.credited_source_note,
                                                                 'confidence',a.confidence,'basis',a.basis) ORDER BY a.adaptation_id)
                            FROM catalog.episode_adaptation ea JOIN catalog.adaptation a USING (adaptation_id)
                            WHERE ea.episode_number=e.episode_number), '[]'::jsonb),
    'audio', (SELECT jsonb_build_object('available',true,'stream_url',m.stream_url,'duration_seconds',m.duration_seconds,'mime_type',m.mime_type)
              FROM catalog.episode_media m WHERE m.episode_number=e.episode_number AND m.is_active AND m.media_type='audio'
              ORDER BY m.media_id DESC LIMIT 1)
)
FROM catalog.episode e
WHERE e.episode_number=p_episode_number
$$;

CREATE OR REPLACE FUNCTION api.get_episode(p_episode_number integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT api.episode_json(p_episode_number) $$;

CREATE OR REPLACE FUNCTION api.get_episodes(
    p_page integer DEFAULT 1,
    p_limit integer DEFAULT 5,
    p_search text DEFAULT NULL,
    p_year integer DEFAULT NULL,
    p_genre_id integer DEFAULT NULL,
    p_cast_id integer DEFAULT NULL,
    p_writer_id integer DEFAULT NULL,
    p_sort text DEFAULT 'episode_number',
    p_order text DEFAULT 'asc'
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, catalog, api
AS $$
DECLARE
    v_page integer := greatest(coalesce(p_page,1),1);
    v_limit integer := least(greatest(coalesce(p_limit,5),1),100);
    v_total bigint;
    v_data jsonb;
BEGIN
    IF p_sort NOT IN ('episode_number','episode_name','original_air_date') THEN RAISE EXCEPTION 'Invalid sort field: %', p_sort; END IF;
    IF lower(p_order) NOT IN ('asc','desc') THEN RAISE EXCEPTION 'Invalid sort direction: %', p_order; END IF;

    WITH filtered AS (
        SELECT DISTINCT e.*
        FROM catalog.episode e
        LEFT JOIN catalog.episode_genre eg ON eg.episode_number=e.episode_number
        LEFT JOIN catalog.episode_cast ec ON ec.episode_number=e.episode_number
        LEFT JOIN catalog.episode_writer ew ON ew.episode_number=e.episode_number
        WHERE (p_search IS NULL OR e.episode_name ILIKE '%'||p_search||'%' OR coalesce(e.episode_plot,'') ILIKE '%'||p_search||'%')
          AND (p_year IS NULL OR extract(year from e.original_air_date)::integer=p_year)
          AND (p_genre_id IS NULL OR eg.genre_id=p_genre_id)
          AND (p_cast_id IS NULL OR ec.person_id=p_cast_id)
          AND (p_writer_id IS NULL OR ew.person_id=p_writer_id)
    )
    SELECT count(*) INTO v_total FROM filtered;

    WITH filtered AS (
        SELECT DISTINCT e.*
        FROM catalog.episode e
        LEFT JOIN catalog.episode_genre eg ON eg.episode_number=e.episode_number
        LEFT JOIN catalog.episode_cast ec ON ec.episode_number=e.episode_number
        LEFT JOIN catalog.episode_writer ew ON ew.episode_number=e.episode_number
        WHERE (p_search IS NULL OR e.episode_name ILIKE '%'||p_search||'%' OR coalesce(e.episode_plot,'') ILIKE '%'||p_search||'%')
          AND (p_year IS NULL OR extract(year from e.original_air_date)::integer=p_year)
          AND (p_genre_id IS NULL OR eg.genre_id=p_genre_id)
          AND (p_cast_id IS NULL OR ec.person_id=p_cast_id)
          AND (p_writer_id IS NULL OR ew.person_id=p_writer_id)
        ORDER BY
          CASE WHEN p_sort='episode_number' AND lower(p_order)='asc' THEN e.episode_number END ASC,
          CASE WHEN p_sort='episode_number' AND lower(p_order)='desc' THEN e.episode_number END DESC,
          CASE WHEN p_sort='episode_name' AND lower(p_order)='asc' THEN e.episode_name END ASC,
          CASE WHEN p_sort='episode_name' AND lower(p_order)='desc' THEN e.episode_name END DESC,
          CASE WHEN p_sort='original_air_date' AND lower(p_order)='asc' THEN e.original_air_date END ASC,
          CASE WHEN p_sort='original_air_date' AND lower(p_order)='desc' THEN e.original_air_date END DESC,
          e.episode_number
        OFFSET (v_page-1)*v_limit LIMIT v_limit
    )
    SELECT coalesce(jsonb_agg(api.episode_json(episode_number)), '[]'::jsonb) INTO v_data FROM filtered;

    RETURN jsonb_build_object('data',v_data,'pagination',jsonb_build_object(
        'page',v_page,'limit',v_limit,'total',v_total,'pages',CASE WHEN v_total=0 THEN 0 ELSE ceil(v_total::numeric/v_limit)::integer END));
END
$$;

CREATE OR REPLACE FUNCTION api.get_episode_broadcasts(p_episode_number integer)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,catalog AS $$
SELECT jsonb_build_object('episode_number',p_episode_number,'broadcasts',coalesce(jsonb_agg(jsonb_build_object(
    'broadcast_date',b.broadcast_date,'broadcast_sequence',b.broadcast_sequence,'broadcast_type',b.broadcast_type)
    ORDER BY b.broadcast_date,b.broadcast_sequence),'[]'::jsonb))
FROM catalog.broadcast b WHERE b.episode_number=p_episode_number
$$;

CREATE OR REPLACE FUNCTION api.get_broadcasts_by_date(p_start_date date, p_end_date date)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,catalog AS $$
SELECT coalesce(jsonb_agg(jsonb_build_object('broadcast_date',b.broadcast_date,'broadcast_sequence',b.broadcast_sequence,
 'broadcast_type',b.broadcast_type,'episode_number',b.episode_number) ORDER BY b.broadcast_date,b.broadcast_sequence NULLS LAST),'[]'::jsonb)
FROM catalog.broadcast b WHERE b.broadcast_date BETWEEN p_start_date AND p_end_date
$$;

CREATE OR REPLACE FUNCTION api.get_genres()
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,catalog AS $$
SELECT coalesce(jsonb_agg(jsonb_build_object('genre_id',g.genre_id,'genre_name',g.genre_name,
 'episode_count',(SELECT count(*) FROM catalog.episode_genre eg WHERE eg.genre_id=g.genre_id)) ORDER BY g.genre_name),'[]'::jsonb)
FROM catalog.genre g
$$;

CREATE OR REPLACE FUNCTION api.get_genre_episodes(p_genre_id integer, p_page integer DEFAULT 1, p_limit integer DEFAULT 5)
RETURNS jsonb LANGUAGE sql STABLE AS $$
SELECT api.get_episodes(p_page,p_limit,NULL,NULL,p_genre_id,NULL,NULL,'episode_number','asc')
$$;

CREATE OR REPLACE FUNCTION api.get_people(p_role text, p_page integer DEFAULT 1, p_limit integer DEFAULT 5, p_search text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog,catalog AS $$
DECLARE v_page int:=greatest(coalesce(p_page,1),1); v_limit int:=least(greatest(coalesce(p_limit,5),1),100); v_total bigint; v_data jsonb;
BEGIN
 IF p_role NOT IN ('cast','writer') THEN RAISE EXCEPTION 'Invalid role'; END IF;
 WITH ids AS (
   SELECT DISTINCT person_id FROM catalog.episode_cast WHERE p_role='cast'
   UNION SELECT DISTINCT person_id FROM catalog.episode_writer WHERE p_role='writer'
 ), f AS (
   SELECT p.* FROM catalog.person p JOIN ids USING(person_id)
   WHERE p_search IS NULL OR concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_search||'%'
 ) SELECT count(*) INTO v_total FROM f;
 WITH ids AS (
   SELECT DISTINCT person_id FROM catalog.episode_cast WHERE p_role='cast'
   UNION SELECT DISTINCT person_id FROM catalog.episode_writer WHERE p_role='writer'
 ), f AS (
   SELECT p.* FROM catalog.person p JOIN ids USING(person_id)
   WHERE p_search IS NULL OR concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_search||'%'
   ORDER BY p.last_name,p.first_name,p.person_id OFFSET (v_page-1)*v_limit LIMIT v_limit
 ) SELECT coalesce(jsonb_agg(jsonb_build_object('person_id',person_id,'first_name',first_name,'middle_name',middle_name,
 'last_name',last_name,'image_url',image_url,'born_on',born_on,'died_on',died_on)),'[]'::jsonb) INTO v_data FROM f;
 RETURN jsonb_build_object('data',v_data,'pagination',jsonb_build_object('page',v_page,'limit',v_limit,'total',v_total,
 'pages',CASE WHEN v_total=0 THEN 0 ELSE ceil(v_total::numeric/v_limit)::int END));
END $$;

CREATE OR REPLACE FUNCTION api.get_cast(p_page integer DEFAULT 1,p_limit integer DEFAULT 5,p_search text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT api.get_people('cast',p_page,p_limit,p_search) $$;
CREATE OR REPLACE FUNCTION api.get_writers(p_page integer DEFAULT 1,p_limit integer DEFAULT 5,p_search text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT api.get_people('writer',p_page,p_limit,p_search) $$;

CREATE OR REPLACE FUNCTION api.get_person(p_person_id integer)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,catalog AS $$
SELECT jsonb_build_object('person_id',p.person_id,'first_name',p.first_name,'middle_name',p.middle_name,'last_name',p.last_name,
'image_url',p.image_url,'soundclip_url',p.soundclip_url,'bio',p.bio,'born_on',p.born_on,'died_on',p.died_on,
'offsite_url',p.offsite_url,'other_series',p.other_series,
'cast_episode_count',(SELECT count(*) FROM catalog.episode_cast ec WHERE ec.person_id=p.person_id),
'writer_episode_count',(SELECT count(*) FROM catalog.episode_writer ew WHERE ew.person_id=p.person_id)) FROM catalog.person p WHERE p.person_id=p_person_id
$$;

CREATE OR REPLACE FUNCTION api.get_cast_episodes(p_person_id integer,p_page integer DEFAULT 1,p_limit integer DEFAULT 5)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT api.get_episodes(p_page,p_limit,NULL,NULL,NULL,p_person_id,NULL,'episode_number','asc') $$;
CREATE OR REPLACE FUNCTION api.get_writer_episodes(p_person_id integer,p_page integer DEFAULT 1,p_limit integer DEFAULT 5)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT api.get_episodes(p_page,p_limit,NULL,NULL,NULL,NULL,p_person_id,'episode_number','asc') $$;

CREATE OR REPLACE FUNCTION api.search_catalog(p_query text,p_page integer DEFAULT 1,p_limit integer DEFAULT 5,p_type text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog,catalog AS $$
DECLARE v_page int:=greatest(coalesce(p_page,1),1); v_limit int:=least(greatest(coalesce(p_limit,5),1),100); v_total bigint; v_data jsonb;
BEGIN
 IF p_query IS NULL OR btrim(p_query)='' THEN RAISE EXCEPTION 'Search query is required'; END IF;
 IF p_type IS NOT NULL AND p_type NOT IN ('episode','cast','writer','adaptation') THEN RAISE EXCEPTION 'Invalid search type'; END IF;
 WITH results AS (
  SELECT 'episode'::text type,e.episode_number::text id,e.episode_name title,left(coalesce(e.episode_plot,''),300) description
  FROM catalog.episode e WHERE (p_type IS NULL OR p_type='episode') AND (e.episode_name ILIKE '%'||p_query||'%' OR coalesce(e.episode_plot,'') ILIKE '%'||p_query||'%')
  UNION ALL
  SELECT 'cast',p.person_id::text,concat_ws(' ',p.first_name,p.middle_name,p.last_name),left(coalesce(p.bio,''),300)
  FROM catalog.person p WHERE (p_type IS NULL OR p_type='cast') AND EXISTS(SELECT 1 FROM catalog.episode_cast ec WHERE ec.person_id=p.person_id)
    AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_query||'%'
  UNION ALL
  SELECT 'writer',p.person_id::text,concat_ws(' ',p.first_name,p.middle_name,p.last_name),left(coalesce(p.bio,''),300)
  FROM catalog.person p WHERE (p_type IS NULL OR p_type='writer') AND EXISTS(SELECT 1 FROM catalog.episode_writer ew WHERE ew.person_id=p.person_id)
    AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_query||'%'
  UNION ALL
  SELECT 'adaptation',a.adaptation_id::text,coalesce(a.identified_source_work,a.episode_title),a.identified_author
  FROM catalog.adaptation a WHERE (p_type IS NULL OR p_type='adaptation') AND (coalesce(a.identified_source_work,'') ILIKE '%'||p_query||'%' OR coalesce(a.identified_author,'') ILIKE '%'||p_query||'%')
 ) SELECT count(*) INTO v_total FROM results;
 WITH results AS (
  SELECT 'episode'::text type,e.episode_number::text id,e.episode_name title,left(coalesce(e.episode_plot,''),300) description
  FROM catalog.episode e WHERE (p_type IS NULL OR p_type='episode') AND (e.episode_name ILIKE '%'||p_query||'%' OR coalesce(e.episode_plot,'') ILIKE '%'||p_query||'%')
  UNION ALL
  SELECT 'cast',p.person_id::text,concat_ws(' ',p.first_name,p.middle_name,p.last_name),left(coalesce(p.bio,''),300)
  FROM catalog.person p WHERE (p_type IS NULL OR p_type='cast') AND EXISTS(SELECT 1 FROM catalog.episode_cast ec WHERE ec.person_id=p.person_id)
    AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_query||'%'
  UNION ALL
  SELECT 'writer',p.person_id::text,concat_ws(' ',p.first_name,p.middle_name,p.last_name),left(coalesce(p.bio,''),300)
  FROM catalog.person p WHERE (p_type IS NULL OR p_type='writer') AND EXISTS(SELECT 1 FROM catalog.episode_writer ew WHERE ew.person_id=p.person_id)
    AND concat_ws(' ',p.first_name,p.middle_name,p.last_name) ILIKE '%'||p_query||'%'
  UNION ALL
  SELECT 'adaptation',a.adaptation_id::text,coalesce(a.identified_source_work,a.episode_title),a.identified_author
  FROM catalog.adaptation a WHERE (p_type IS NULL OR p_type='adaptation') AND (coalesce(a.identified_source_work,'') ILIKE '%'||p_query||'%' OR coalesce(a.identified_author,'') ILIKE '%'||p_query||'%')
 ), paged AS (SELECT * FROM results ORDER BY type,title,id OFFSET (v_page-1)*v_limit LIMIT v_limit)
 SELECT coalesce(jsonb_agg(jsonb_build_object('type',type,'id',id,'title',title,'description',description)),'[]'::jsonb) INTO v_data FROM paged;
 RETURN jsonb_build_object('data',v_data,'pagination',jsonb_build_object('page',v_page,'limit',v_limit,'total',v_total,
  'pages',CASE WHEN v_total=0 THEN 0 ELSE ceil(v_total::numeric/v_limit)::int END));
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA api FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO cbsrmt_api, cbsrmt_admin;
