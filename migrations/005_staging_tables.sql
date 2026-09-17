BEGIN;

CREATE TABLE IF NOT EXISTS stage.source_document (
    source_name text PRIMARY KEY,
    payload     jsonb NOT NULL,
    loaded_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE stage.source_document IS 'Authoritative JSON documents loaded unchanged before validation/promotion.';

COMMIT;
