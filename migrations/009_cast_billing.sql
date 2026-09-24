BEGIN;

ALTER TABLE catalog.episode_cast
    ADD COLUMN IF NOT EXISTS cast_role varchar(20),
    ADD COLUMN IF NOT EXISTS billing_order integer;

DO $$
DECLARE
    v_appearance jsonb;
BEGIN
    IF EXISTS (SELECT 1 FROM catalog.episode_cast WHERE cast_role IS NULL OR billing_order IS NULL) THEN
        SELECT payload INTO v_appearance
        FROM stage.source_document
        WHERE source_name='appearance.json';

        IF v_appearance IS NULL THEN
            RAISE EXCEPTION 'appearance.json must be staged before cast billing can be backfilled';
        END IF;

        WITH source_rows AS (
            SELECT
                (x->>'episode_id')::integer AS episode_number,
                (x->>'cast_id')::integer AS person_id,
                (x->>'id')::integer AS source_order
            FROM jsonb_array_elements(v_appearance) x
        ), ranked AS (
            SELECT
                episode_number,
                person_id,
                row_number() OVER (
                    PARTITION BY episode_number
                    ORDER BY source_order, person_id
                )::integer AS billing_order
            FROM source_rows
        )
        UPDATE catalog.episode_cast ec
           SET billing_order=r.billing_order,
               cast_role=CASE WHEN r.billing_order=1 THEN 'star' ELSE 'co_star' END
          FROM ranked r
         WHERE ec.episode_number=r.episode_number
           AND ec.person_id=r.person_id;
    END IF;
END
$$;

ALTER TABLE catalog.episode_cast
    ALTER COLUMN cast_role SET NOT NULL,
    ALTER COLUMN billing_order SET NOT NULL;

ALTER TABLE catalog.episode_cast
    DROP CONSTRAINT IF EXISTS episode_cast_role_ck,
    DROP CONSTRAINT IF EXISTS episode_cast_billing_order_ck;

ALTER TABLE catalog.episode_cast
    ADD CONSTRAINT episode_cast_role_ck CHECK (cast_role IN ('star','co_star')),
    ADD CONSTRAINT episode_cast_billing_order_ck CHECK (billing_order > 0);

CREATE UNIQUE INDEX IF NOT EXISTS episode_cast_one_star_uq
    ON catalog.episode_cast(episode_number)
    WHERE cast_role='star';

CREATE UNIQUE INDEX IF NOT EXISTS episode_cast_billing_order_uq
    ON catalog.episode_cast(episode_number,billing_order);

COMMIT;
