BEGIN;

CREATE TABLE IF NOT EXISTS import.cast_correction_audit (
    correction_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    correction_key      text NOT NULL UNIQUE CHECK (btrim(correction_key) <> ''),
    person_id           integer NOT NULL CHECK (person_id > 0),
    person_code_before  varchar(100),
    person_code_after   varchar(100),
    first_name_before   varchar(100),
    first_name_after    varchar(100),
    middle_name_before  varchar(100),
    middle_name_after   varchar(100),
    last_name_before    varchar(150),
    last_name_after     varchar(150),
    reason              text NOT NULL CHECK (btrim(reason) <> ''),
    source_reference    text,
    applied_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cast_correction_audit_person_idx
    ON import.cast_correction_audit(person_id, applied_at DESC);

COMMENT ON TABLE import.cast_correction_audit IS
    'Append-only audit history of cast identity corrections promoted from authoritative JSON.';

COMMIT;
