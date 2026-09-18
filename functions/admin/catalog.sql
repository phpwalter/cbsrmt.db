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


CREATE OR REPLACE FUNCTION admin.update_user(p_user_id bigint, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,account,api
AS $$
DECLARE
    v_avatar bytea;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM account.app_user WHERE user_id=p_user_id) THEN
        RETURN NULL;
    END IF;

    IF p_patch ? 'username' AND nullif(btrim(p_patch->>'username'),'') IS NULL THEN
        RAISE EXCEPTION 'username must not be null or empty';
    END IF;
    IF p_patch ? 'first_name' AND p_patch->>'first_name' IS NULL THEN
        RAISE EXCEPTION 'first_name must not be null';
    END IF;
    IF p_patch ? 'last_name' AND p_patch->>'last_name' IS NULL THEN
        RAISE EXCEPTION 'last_name must not be null';
    END IF;

    IF p_patch ? 'avatar' THEN
        IF p_patch->'avatar' IS NULL OR jsonb_typeof(p_patch->'avatar')='null' THEN
            v_avatar := NULL;
        ELSIF p_patch#>>'{avatar,avatar}' IS NULL THEN
            RAISE EXCEPTION 'avatar.avatar is required when avatar is provided';
        ELSE
            v_avatar := decode(p_patch#>>'{avatar,avatar}','base64');
        END IF;
    END IF;

    UPDATE account.app_user
       SET username = CASE WHEN p_patch ? 'username' THEN btrim(p_patch->>'username') ELSE username END,
           first_name = CASE WHEN p_patch ? 'first_name' THEN p_patch->>'first_name' ELSE first_name END,
           last_name = CASE WHEN p_patch ? 'last_name' THEN p_patch->>'last_name' ELSE last_name END,
           avatar = CASE WHEN p_patch ? 'avatar' THEN v_avatar ELSE avatar END,
           updated_at = now()
     WHERE user_id=p_user_id;

    RETURN api.user_json(p_user_id);
END
$$;

CREATE OR REPLACE FUNCTION admin.delete_user(p_user_id bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,account
AS $$
DECLARE
    v_deleted bigint;
BEGIN
    DELETE FROM account.app_user WHERE user_id=p_user_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted=1;
END
$$;
