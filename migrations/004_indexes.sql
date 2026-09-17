BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS broadcast_sequence_uq
    ON catalog.broadcast (broadcast_sequence)
    WHERE broadcast_sequence IS NOT NULL;

CREATE INDEX IF NOT EXISTS broadcast_date_idx ON catalog.broadcast (broadcast_date);
CREATE INDEX IF NOT EXISTS broadcast_episode_idx ON catalog.broadcast (episode_number);
CREATE INDEX IF NOT EXISTS episode_air_date_idx ON catalog.episode (original_air_date);
CREATE INDEX IF NOT EXISTS episode_name_trgm_idx ON catalog.episode USING gin (episode_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS episode_plot_fts_idx ON catalog.episode USING gin (to_tsvector('english', coalesce(episode_plot,'')));
CREATE INDEX IF NOT EXISTS person_name_trgm_idx ON catalog.person USING gin ((coalesce(first_name,'') || ' ' || coalesce(middle_name,'') || ' ' || coalesce(last_name,'')) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS adaptation_work_trgm_idx ON catalog.adaptation USING gin (identified_source_work gin_trgm_ops);
CREATE INDEX IF NOT EXISTS adaptation_author_trgm_idx ON catalog.adaptation USING gin (identified_author gin_trgm_ops);
CREATE INDEX IF NOT EXISTS episode_cast_person_idx ON catalog.episode_cast (person_id, episode_number);
CREATE INDEX IF NOT EXISTS episode_writer_person_idx ON catalog.episode_writer (person_id, episode_number);
CREATE INDEX IF NOT EXISTS episode_genre_genre_idx ON catalog.episode_genre (genre_id, episode_number);
CREATE INDEX IF NOT EXISTS episode_adaptation_adaptation_idx ON catalog.episode_adaptation (adaptation_id, episode_number);
CREATE INDEX IF NOT EXISTS episode_media_episode_idx ON catalog.episode_media (episode_number) WHERE is_active;

COMMIT;
