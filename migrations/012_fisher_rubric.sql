BEGIN;

ALTER TABLE catalog.episode
    ADD COLUMN IF NOT EXISTS fisher_rubric numeric(5,2);

ALTER TABLE catalog.episode
    DROP CONSTRAINT IF EXISTS episode_fisher_rubric_ck;

ALTER TABLE catalog.episode
    ADD CONSTRAINT episode_fisher_rubric_ck
        CHECK (fisher_rubric IS NULL OR (fisher_rubric >= 0 AND fisher_rubric <= 100));

COMMENT ON COLUMN catalog.episode.fisher_rubric IS
    '100-point episode rating from the Fisher rubric source dataset.';

COMMIT;
