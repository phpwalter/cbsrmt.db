-- CBSRMT normalized database integrity checks.
-- Every query below should return zero rows or a zero count.

-- Episodes with missing genres.
SELECT e.episode_id, e.genre_id
FROM episodes e
LEFT JOIN genre g ON g.genre_id = e.genre_id
WHERE g.genre_id IS NULL;

-- Appearance rows with missing parent records.
SELECT a.*
FROM appear a
LEFT JOIN episodes e ON e.episode_id = a.episode_id
LEFT JOIN cast c ON c.cast_id = a.cast_id
WHERE e.episode_id IS NULL OR c.cast_id IS NULL;

-- Duplicate actor appearances.
SELECT episode_id, cast_id, COUNT(*) AS duplicate_count
FROM appear
GROUP BY episode_id, cast_id
HAVING COUNT(*) > 1;

-- Writer rows with missing parent records.
SELECT ew.*
FROM episode_writers ew
LEFT JOIN episodes e ON e.episode_id = ew.episode_id
LEFT JOIN cast c ON c.cast_id = ew.cast_id
WHERE e.episode_id IS NULL OR c.cast_id IS NULL;

-- Duplicate writer relationships.
SELECT episode_id, cast_id, COUNT(*) AS duplicate_count
FROM episode_writers
GROUP BY episode_id, cast_id
HAVING COUNT(*) > 1;

-- Adaptations with missing episodes.
SELECT ea.*
FROM episode_adaptations ea
LEFT JOIN episodes e ON e.episode_id = ea.episode_id
WHERE e.episode_id IS NULL;

-- Duplicate adaptation rows are prevented by the primary key, but retain an explicit audit query.
SELECT episode_id, COUNT(*) AS duplicate_count
FROM episode_adaptations
GROUP BY episode_id
HAVING COUNT(*) > 1;
