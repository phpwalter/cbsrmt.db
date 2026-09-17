BEGIN;

CREATE TABLE IF NOT EXISTS catalog.episode_cast (
    episode_number integer NOT NULL REFERENCES catalog.episode(episode_number) ON UPDATE CASCADE ON DELETE CASCADE,
    person_id      integer NOT NULL REFERENCES catalog.person(person_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    PRIMARY KEY (episode_number, person_id)
);

CREATE TABLE IF NOT EXISTS catalog.episode_writer (
    episode_number integer NOT NULL REFERENCES catalog.episode(episode_number) ON UPDATE CASCADE ON DELETE CASCADE,
    person_id      integer NOT NULL REFERENCES catalog.person(person_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    PRIMARY KEY (episode_number, person_id)
);

CREATE TABLE IF NOT EXISTS catalog.episode_genre (
    episode_number integer NOT NULL REFERENCES catalog.episode(episode_number) ON UPDATE CASCADE ON DELETE CASCADE,
    genre_id       smallint NOT NULL REFERENCES catalog.genre(genre_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    PRIMARY KEY (episode_number, genre_id)
);

CREATE TABLE IF NOT EXISTS catalog.episode_adaptation (
    episode_number integer NOT NULL REFERENCES catalog.episode(episode_number) ON UPDATE CASCADE ON DELETE CASCADE,
    adaptation_id  integer NOT NULL REFERENCES catalog.adaptation(adaptation_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    PRIMARY KEY (episode_number, adaptation_id)
);

COMMIT;
