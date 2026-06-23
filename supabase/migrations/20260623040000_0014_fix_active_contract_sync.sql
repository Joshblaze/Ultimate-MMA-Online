-- Keep promotion contracts exclusive without letting stale fighter.promotion_id
-- values or legacy week-based contracts break advance_week().

UPDATE public.contracts
SET status = 'expired',
    fights_remaining = 0
WHERE status = 'active'
  AND (
    fights_remaining <= 0
    OR (
      expires_week < 2147483647
      AND expires_week <= public.get_current_week()
    )
  );

WITH active_contract AS (
  SELECT DISTINCT ON (fighter_id)
    fighter_id,
    promotion_id
  FROM public.contracts
  WHERE status = 'active'
  ORDER BY fighter_id, signed_week DESC, id DESC
)
UPDATE public.fighters f
SET promotion_id = active_contract.promotion_id
FROM active_contract
WHERE f.id = active_contract.fighter_id
  AND f.promotion_id IS DISTINCT FROM active_contract.promotion_id;

UPDATE public.fighters f
SET promotion_id = NULL
WHERE f.promotion_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.contracts c
    WHERE c.fighter_id = f.id
      AND c.status = 'active'
  );

CREATE OR REPLACE FUNCTION public.sync_fighter_promotion_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fighter_id uuid;
  v_promotion_id uuid;
BEGIN
  v_fighter_id := COALESCE(NEW.fighter_id, OLD.fighter_id);

  SELECT c.promotion_id INTO v_promotion_id
  FROM public.contracts c
  WHERE c.fighter_id = v_fighter_id
    AND c.status = 'active'
  ORDER BY c.signed_week DESC, c.id DESC
  LIMIT 1;

  UPDATE public.fighters
  SET promotion_id = v_promotion_id
  WHERE id = v_fighter_id
    AND promotion_id IS DISTINCT FROM v_promotion_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_fighter_promotion_contract ON public.contracts;
DROP TRIGGER IF EXISTS sync_fighter_promotion_contract_delete ON public.contracts;
CREATE TRIGGER sync_fighter_promotion_contract
AFTER INSERT OR UPDATE OF status, promotion_id ON public.contracts
FOR EACH ROW EXECUTE FUNCTION public.sync_fighter_promotion_contract();
CREATE TRIGGER sync_fighter_promotion_contract_delete
AFTER DELETE ON public.contracts
FOR EACH ROW EXECUTE FUNCTION public.sync_fighter_promotion_contract();

CREATE OR REPLACE FUNCTION public.skip_duplicate_active_contract_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_existing_promotion_id uuid;
BEGIN
  IF NEW.status <> 'active' THEN
    RETURN NEW;
  END IF;

  SELECT c.promotion_id INTO v_existing_promotion_id
  FROM public.contracts c
  WHERE c.fighter_id = NEW.fighter_id
    AND c.status = 'active'
  ORDER BY c.signed_week DESC, c.id DESC
  LIMIT 1;

  IF v_existing_promotion_id IS NOT NULL THEN
    UPDATE public.fighters
    SET promotion_id = v_existing_promotion_id
    WHERE id = NEW.fighter_id
      AND promotion_id IS DISTINCT FROM v_existing_promotion_id;

    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS skip_duplicate_active_contract_insert ON public.contracts;
CREATE TRIGGER skip_duplicate_active_contract_insert
BEFORE INSERT ON public.contracts
FOR EACH ROW EXECUTE FUNCTION public.skip_duplicate_active_contract_insert();
