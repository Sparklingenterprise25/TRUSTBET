-- Assign permanent, monotonic TRUSTBET UIDs. Supabase Auth UUIDs remain unchanged.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.profiles WHERE role = 'admin') <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one existing TRUSTBET admin before assigning UID 1000.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='profiles' AND column_name='trustbet_uid'
  ) THEN
    RAISE EXCEPTION 'profiles.trustbet_uid already exists; inspect existing assignments before applying this migration.';
  END IF;
END $$;

ALTER TABLE public.profiles ADD COLUMN trustbet_uid bigint;

WITH numbered_users AS (
  SELECT id, row_number() OVER (ORDER BY created_at, id) AS position
  FROM public.profiles
  WHERE role <> 'admin'
)
UPDATE public.profiles AS p
SET trustbet_uid = 1000 + numbered_users.position
FROM numbered_users
WHERE p.id = numbered_users.id;

UPDATE public.profiles
SET trustbet_uid = 1000
WHERE role = 'admin';

ALTER TABLE public.profiles
  ALTER COLUMN trustbet_uid SET NOT NULL;

CREATE UNIQUE INDEX profiles_trustbet_uid_key
  ON public.profiles (trustbet_uid);

CREATE SEQUENCE public.trustbet_uid_seq
  AS bigint
  INCREMENT BY 1
  MINVALUE 1000
  START WITH 1004
  NO CYCLE;

SELECT setval(
  'public.trustbet_uid_seq',
  GREATEST(1003, COALESCE((SELECT max(trustbet_uid) FROM public.profiles), 1003)),
  true
);

CREATE OR REPLACE FUNCTION public.assign_trustbet_uid()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.id = '461892b7-f24b-4ba8-99d7-fa9bb44d1a33'::uuid THEN
      NEW.trustbet_uid := 1000;
    ELSE
      NEW.trustbet_uid := nextval('public.trustbet_uid_seq');
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.trustbet_uid IS DISTINCT FROM OLD.trustbet_uid THEN
    RAISE EXCEPTION 'TRUSTBET UID is permanent and cannot be changed.';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_trustbet_uid() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.trustbet_uid_seq FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_assign_trustbet_uid
BEFORE INSERT OR UPDATE OF trustbet_uid ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.assign_trustbet_uid();
