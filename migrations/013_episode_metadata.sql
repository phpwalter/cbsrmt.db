BEGIN;

ALTER TABLE catalog.episode
    ADD COLUMN IF NOT EXISTS recording_quality text,
    ADD COLUMN IF NOT EXISTS commercials boolean,
    ADD COLUMN IF NOT EXISTS news boolean;

ALTER TABLE catalog.episode
    DROP CONSTRAINT IF EXISTS episode_recording_quality_ck;

ALTER TABLE catalog.episode
    ADD CONSTRAINT episode_recording_quality_ck
        CHECK (
            recording_quality IS NULL
            OR recording_quality IN ('EXCELLENT', 'GOOD', 'FAIR', 'POOR')
        );

COMMENT ON COLUMN catalog.episode.recording_quality IS
    'Source recording quality classification: EXCELLENT, GOOD, FAIR, or POOR.';
COMMENT ON COLUMN catalog.episode.commercials IS
    'TRUE when the source recording contains commercials; FALSE when it does not; NULL when unknown.';
COMMENT ON COLUMN catalog.episode.news IS
    'TRUE when the source recording contains news; FALSE when it does not; NULL when unknown.';

COMMIT;
