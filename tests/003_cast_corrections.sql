BEGIN;

DO $cast_correction_test$
DECLARE
    v_person_id integer;
    v_person_code text;
    v_first_name text;
    v_middle_name text;
    v_last_name text;
    v_image_url text;
    v_soundclip_url text;
    v_bio text;
    v_born_on date;
    v_died_on date;
    v_offsite_url text;
    v_other_series text;
    v_credit text;
    v_after_first_name text;
    v_before_appearances bigint;
    v_after_appearances bigint;
    v_result jsonb;
BEGIN
    SELECT p.person_id,p.person_code,p.first_name,p.middle_name,p.last_name,p.image_url,
           p.soundclip_url,p.bio,p.born_on,p.died_on,p.offsite_url,p.other_series,p.credit
      INTO v_person_id,v_person_code,v_first_name,v_middle_name,v_last_name,v_image_url,
           v_soundclip_url,v_bio,v_born_on,v_died_on,v_offsite_url,v_other_series,v_credit
      FROM catalog.person p
     WHERE EXISTS (
        SELECT 1 FROM catalog.episode_cast ec WHERE ec.person_id=p.person_id
     )
     ORDER BY p.person_id
     LIMIT 1;

    IF v_person_id IS NULL THEN
        RAISE EXCEPTION 'No cast member available for cast correction contract test';
    END IF;

    v_after_first_name := left(coalesce(v_first_name,'Correction'),80) || ' Test';

    SELECT count(*) INTO v_before_appearances
      FROM catalog.episode_cast
     WHERE person_id=v_person_id;

    INSERT INTO stage.source_document(source_name,payload,loaded_at)
    VALUES(
        'cast.json',
        jsonb_build_array(jsonb_build_object(
            'cast_id',v_person_id::text,
            'cast_id_name',coalesce(v_person_code,''),
            'first_name',v_after_first_name,
            'middle_name',coalesce(v_middle_name,''),
            'last_name',coalesce(v_last_name,''),
            'image_url',coalesce(v_image_url,''),
            'soundclip_url',coalesce(v_soundclip_url,''),
            'bio',coalesce(v_bio,''),
            'born_on',coalesce(v_born_on::text,'0000-00-00'),
            'died_on',coalesce(v_died_on::text,'0000-00-00'),
            'offsite_url',coalesce(v_offsite_url,''),
            'other_series',coalesce(v_other_series,''),
            'credit',coalesce(v_credit,'')
        )),
        now()
    )
    ON CONFLICT(source_name)
    DO UPDATE SET payload=excluded.payload,loaded_at=now();

    INSERT INTO stage.source_document(source_name,payload,loaded_at)
    VALUES(
        'cast-corrections.json',
        jsonb_build_array(jsonb_build_object(
            'correction_key','__contract_cast_correction__',
            'cast_id',v_person_id::text,
            'reason','Contract test name correction',
            'source_reference','tests/003_cast_corrections.sql',
            'before',jsonb_build_object(
                'cast_id_name',coalesce(v_person_code,''),
                'first_name',coalesce(v_first_name,''),
                'middle_name',coalesce(v_middle_name,''),
                'last_name',coalesce(v_last_name,'')
            ),
            'after',jsonb_build_object(
                'cast_id_name',coalesce(v_person_code,''),
                'first_name',v_after_first_name,
                'middle_name',coalesce(v_middle_name,''),
                'last_name',coalesce(v_last_name,'')
            )
        )),
        now()
    )
    ON CONFLICT(source_name)
    DO UPDATE SET payload=excluded.payload,loaded_at=now();

    v_result := import.promote_cast();

    IF (v_result->>'identity_changes')::integer <> 1 THEN
        RAISE EXCEPTION 'Expected one identity change, got %',v_result->>'identity_changes';
    END IF;

    IF (SELECT first_name FROM catalog.person WHERE person_id=v_person_id) <> v_after_first_name THEN
        RAISE EXCEPTION 'Cast first-name correction was not promoted';
    END IF;

    SELECT count(*) INTO v_after_appearances
      FROM catalog.episode_cast
     WHERE person_id=v_person_id;

    IF v_after_appearances <> v_before_appearances THEN
        RAISE EXCEPTION 'Cast correction changed appearance count: before %, after %',
            v_before_appearances,v_after_appearances;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM import.cast_correction_audit
         WHERE correction_key='__contract_cast_correction__'
           AND person_id=v_person_id
           AND first_name_before IS NOT DISTINCT FROM v_first_name
           AND first_name_after=v_after_first_name
    ) THEN
        RAISE EXCEPTION 'Cast correction audit row was not created';
    END IF;

    RAISE NOTICE 'PASS: targeted cast correction preserves episode relationships';
END
$cast_correction_test$;

ROLLBACK;
