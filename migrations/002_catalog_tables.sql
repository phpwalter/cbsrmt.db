BEGIN;

CREATE TABLE IF NOT EXISTS catalog.episode (
    episode_number      integer PRIMARY KEY CHECK (episode_number > 0),
    episode_name        text NOT NULL CHECK (btrim(episode_name) <> ''),
    episode_plot        text,
    episode_note        text,
    original_air_date   date NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN catalog.episode.episode_number IS 'Canonical public CBS episode identifier.';
COMMENT ON TABLE catalog.episode IS 'One row per canonical episode, independent of later rebroadcasts.';

CREATE TABLE IF NOT EXISTS catalog.broadcast (
    broadcast_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    broadcast_date      date NOT NULL,
    broadcast_sequence  integer CHECK (broadcast_sequence IS NULL OR broadcast_sequence > 0),
    episode_number      integer REFERENCES catalog.episode(episode_number) ON UPDATE CASCADE ON DELETE RESTRICT,
    broadcast_type      text NOT NULL CHECK (broadcast_type IN ('original','repeat','no_broadcast')),
    source_row_id       integer,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT broadcast_semantics_ck CHECK (
        (broadcast_type IN ('original','repeat') AND episode_number IS NOT NULL AND broadcast_sequence IS NOT NULL)
        OR
        (broadcast_type = 'no_broadcast' AND episode_number IS NULL AND broadcast_sequence IS NULL)
    )
);

COMMENT ON COLUMN catalog.broadcast.broadcast_sequence IS 'Ordinal of actual broadcasts only; no-broadcast dates are excluded.';

CREATE TABLE IF NOT EXISTS catalog.person (
    person_id           integer PRIMARY KEY CHECK (person_id > 0),
    person_code         varchar(100),
    first_name          varchar(100),
    middle_name         varchar(100),
    last_name           varchar(150),
    image_url           text,
    soundclip_url       text,
    bio                 text,
    born_on             date,
    died_on             date,
    offsite_url         text,
    other_series        text,
    credit              text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS catalog.genre (
    genre_id            smallint PRIMARY KEY,
    genre_name          varchar(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS catalog.adaptation (
    adaptation_id           integer PRIMARY KEY CHECK (adaptation_id > 0),
    episode_title           text,
    credited_source_note    text,
    identified_source_work  text,
    identified_author       text,
    confidence              varchar(20),
    basis                   text,
    CONSTRAINT adaptation_confidence_ck CHECK (
        confidence IS NULL OR confidence IN ('high','medium','low')
    )
);

CREATE TABLE IF NOT EXISTS catalog.episode_media (
    media_id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    episode_number      integer NOT NULL REFERENCES catalog.episode(episode_number) ON UPDATE CASCADE ON DELETE CASCADE,
    media_type          varchar(30) NOT NULL DEFAULT 'audio' CHECK (media_type IN ('audio')),
    stream_url          text,
    mime_type           varchar(100),
    duration_seconds    integer CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

COMMIT;
