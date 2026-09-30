BEGIN;

CREATE OR REPLACE FUNCTION catalog.uri_encode_path_segment(p_value text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
DECLARE
    v_bytes bytea := convert_to(p_value, 'UTF8');
    v_result text := '';
    v_index integer;
    v_byte integer;
BEGIN
    IF length(v_bytes) = 0 THEN
        RETURN '';
    END IF;

    FOR v_index IN 0 .. length(v_bytes) - 1 LOOP
        v_byte := get_byte(v_bytes, v_index);

        IF (v_byte BETWEEN 48 AND 57)
           OR (v_byte BETWEEN 65 AND 90)
           OR (v_byte BETWEEN 97 AND 122)
           OR v_byte IN (45, 46, 95, 126) THEN
            v_result := v_result || chr(v_byte);
        ELSE
            v_result := v_result || '%' || upper(lpad(to_hex(v_byte), 2, '0'));
        END IF;
    END LOOP;

    RETURN v_result;
END
$$;

CREATE OR REPLACE FUNCTION catalog.episode_stream_title(p_episode_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
SELECT CASE
    WHEN right(p_episode_name, 6) = ' [The]'
        THEN 'The ' || left(p_episode_name, length(p_episode_name) - 6)
    WHEN right(p_episode_name, 5) = ' [An]'
        THEN 'An ' || left(p_episode_name, length(p_episode_name) - 5)
    WHEN right(p_episode_name, 4) = ' [A]'
        THEN 'A ' || left(p_episode_name, length(p_episode_name) - 4)
    ELSE p_episode_name
END
$$;

CREATE OR REPLACE FUNCTION catalog.derive_episode_audio_uri(
    p_episode_number integer,
    p_original_air_date date,
    p_episode_name text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
SELECT
    'https://stream.cbsrmt.com/' ||
    catalog.uri_encode_path_segment(
        'CBSRMT.com ' ||
        to_char(p_original_air_date, 'YY-MM-DD') ||
        ' e' || lpad(p_episode_number::text, 4, '0') ||
        ' ' || catalog.episode_stream_title(p_episode_name) ||
        '.mp3'
    )
$$;

ALTER TABLE catalog.episode
    ADD COLUMN IF NOT EXISTS audio_uri text;

UPDATE catalog.episode
SET audio_uri = catalog.derive_episode_audio_uri(
    episode_number,
    original_air_date,
    episode_name
);

CREATE OR REPLACE FUNCTION catalog.set_episode_audio_uri()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.audio_uri := catalog.derive_episode_audio_uri(
        NEW.episode_number,
        NEW.original_air_date,
        NEW.episode_name
    );

    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS episode_audio_uri_trg ON catalog.episode;

CREATE TRIGGER episode_audio_uri_trg
BEFORE INSERT OR UPDATE OF episode_number, original_air_date, episode_name
ON catalog.episode
FOR EACH ROW
EXECUTE FUNCTION catalog.set_episode_audio_uri();

COMMENT ON COLUMN catalog.episode.audio_uri IS
    'Derived CBSRMT stream URI using the canonical original air date, four-digit episode number, and normalized episode title.';

COMMIT;
