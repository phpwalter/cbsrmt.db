BEGIN;

-- Authoritative CBSRMT title corrections confirmed during Fisher rubric reconciliation.
UPDATE catalog.episode SET episode_name = 'Death By Whos Hands', updated_at = now()
WHERE episode_number = 63;

UPDATE catalog.episode SET episode_name = 'The Paradise Café', updated_at = now()
WHERE episode_number = 464;

UPDATE catalog.episode SET episode_name = 'Somebody Stop Me!', updated_at = now()
WHERE episode_number = 540;

UPDATE catalog.episode SET episode_name = 'A Casual Affair', updated_at = now()
WHERE episode_number = 593;

UPDATE catalog.episode SET episode_name = 'The Legend of Alexander (1 of 5) - Courage', updated_at = now()
WHERE episode_number = 1145;

UPDATE catalog.episode SET episode_name = 'The Legend of Alexander (2 of 5) - Assassination', updated_at = now()
WHERE episode_number = 1146;

UPDATE catalog.episode SET episode_name = 'The Legend of Alexander (3 of 5) - Divide and Conquer', updated_at = now()
WHERE episode_number = 1147;

UPDATE catalog.episode SET episode_name = 'The Legend of Alexander (4 of 5) - The Oracle', updated_at = now()
WHERE episode_number = 1148;

UPDATE catalog.episode SET episode_name = 'The Legend of Alexander (5 of 5) - The Legend Begins', updated_at = now()
WHERE episode_number = 1149;

COMMIT;
