CREATE OR REPLACE FUNCTION admin.upsert_episode(p_episode_number integer,p_episode_name text,p_episode_plot text,p_original_air_date date,p_episode_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,catalog,api AS $$
BEGIN
 INSERT INTO catalog.episode(episode_number,episode_name,episode_plot,episode_note,original_air_date)
 VALUES(p_episode_number,btrim(p_episode_name),p_episode_plot,p_episode_note,p_original_air_date)
 ON CONFLICT(episode_number) DO UPDATE SET episode_name=excluded.episode_name,episode_plot=excluded.episode_plot,
 episode_note=excluded.episode_note,original_air_date=excluded.original_air_date,updated_at=now();
 RETURN api.episode_json(p_episode_number);
END $$;

CREATE OR REPLACE FUNCTION admin.add_episode_cast(p_episode_number integer,p_person_id integer)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,catalog AS $$
 INSERT INTO catalog.episode_cast VALUES(p_episode_number,p_person_id) ON CONFLICT DO NOTHING
$$;
CREATE OR REPLACE FUNCTION admin.remove_episode_cast(p_episode_number integer,p_person_id integer)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,catalog AS $$ DELETE FROM catalog.episode_cast WHERE episode_number=p_episode_number AND person_id=p_person_id $$;
CREATE OR REPLACE FUNCTION admin.add_episode_writer(p_episode_number integer,p_person_id integer)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,catalog AS $$ INSERT INTO catalog.episode_writer VALUES(p_episode_number,p_person_id) ON CONFLICT DO NOTHING $$;
CREATE OR REPLACE FUNCTION admin.remove_episode_writer(p_episode_number integer,p_person_id integer)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,catalog AS $$ DELETE FROM catalog.episode_writer WHERE episode_number=p_episode_number AND person_id=p_person_id $$;
CREATE OR REPLACE FUNCTION admin.add_episode_genre(p_episode_number integer,p_genre_id integer)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,catalog AS $$ INSERT INTO catalog.episode_genre VALUES(p_episode_number,p_genre_id::smallint) ON CONFLICT DO NOTHING $$;
CREATE OR REPLACE FUNCTION admin.remove_episode_genre(p_episode_number integer,p_genre_id integer)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,catalog AS $$ DELETE FROM catalog.episode_genre WHERE episode_number=p_episode_number AND genre_id=p_genre_id $$;
CREATE OR REPLACE FUNCTION admin.set_episode_audio(p_episode_number integer,p_stream_url text,p_duration_seconds integer DEFAULT NULL,p_mime_type text DEFAULT 'audio/mpeg')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,catalog AS $$
DECLARE v_id bigint;
BEGIN
 UPDATE catalog.episode_media SET is_active=false,updated_at=now() WHERE episode_number=p_episode_number AND media_type='audio' AND is_active;
 IF p_stream_url IS NULL OR btrim(p_stream_url)='' THEN RETURN NULL; END IF;
 INSERT INTO catalog.episode_media(episode_number,media_type,stream_url,duration_seconds,mime_type)
 VALUES(p_episode_number,'audio',p_stream_url,p_duration_seconds,p_mime_type) RETURNING media_id INTO v_id;
 RETURN jsonb_build_object('media_id',v_id,'episode_number',p_episode_number,'stream_url',p_stream_url,'duration_seconds',p_duration_seconds,'mime_type',p_mime_type);
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA admin FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA admin TO cbsrmt_admin;
