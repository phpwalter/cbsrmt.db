BEGIN;

ALTER TABLE catalog.episode_cast
    ADD COLUMN IF NOT EXISTS character_name text,
    ADD COLUMN IF NOT EXISTS character_source text,
    ADD COLUMN IF NOT EXISTS character_updated_at timestamptz;

ALTER TABLE catalog.episode_cast
    DROP CONSTRAINT IF EXISTS episode_cast_character_name_ck,
    DROP CONSTRAINT IF EXISTS episode_cast_character_source_ck;

ALTER TABLE catalog.episode_cast
    ADD CONSTRAINT episode_cast_character_name_ck
        CHECK (character_name IS NULL OR btrim(character_name) <> ''),
    ADD CONSTRAINT episode_cast_character_source_ck
        CHECK (character_source IS NULL OR btrim(character_source) <> '');

COMMIT;
