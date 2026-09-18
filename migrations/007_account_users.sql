BEGIN;

CREATE TABLE IF NOT EXISTS account.app_user (
    user_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username     text NOT NULL UNIQUE CHECK (btrim(username) <> ''),
    first_name   text NOT NULL,
    last_name    text NOT NULL,
    avatar       bytea,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS app_user_username_trgm_idx
    ON account.app_user USING gin (username gin_trgm_ops);

COMMIT;
