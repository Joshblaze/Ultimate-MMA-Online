/*
# Fight-count promotion contracts

gym_id represents management. promotion_id represents an exclusive promotion
contract. A fighter can have either, both, or neither.
*/

ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS contracted_fights int,
  ADD COLUMN IF NOT EXISTS fights_remaining int,
  ADD COLUMN IF NOT EXISTS completed_fights int NOT NULL DEFAULT 0;

ALTER TABLE public.fight_offers
  ADD COLUMN IF NOT EXISTS contract_fights int NOT NULL DEFAULT 4
  CHECK (contract_fights BETWEEN 1 AND 12);

UPDATE public.contracts
SET contracted_fights = COALESCE(contracted_fights, 4),
    fights_remaining = COALESCE(fights_remaining, 4),
    expires_week = 2147483647
WHERE status = 'active';

UPDATE public.contracts
SET contracted_fights = COALESCE(contracted_fights, completed_fights),
    fights_remaining = COALESCE(fights_remaining, 0)
WHERE status = 'expired';

ALTER TABLE public.contracts
  ALTER COLUMN contracted_fights SET NOT NULL,
  ALTER COLUMN fights_remaining SET NOT NULL;

ALTER TABLE public.contracts
  ADD CONSTRAINT contracts_fight_counts_check
  CHECK (
    contracted_fights >= 0
    AND completed_fights >= 0
    AND fights_remaining >= 0
    AND completed_fights + fights_remaining <= contracted_fights
  );

WITH duplicate_contracts AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY fighter_id ORDER BY signed_week DESC, id DESC
         ) AS contract_order
  FROM public.contracts
  WHERE status = 'active'
)
UPDATE public.contracts c
SET status = 'expired', fights_remaining = 0
FROM duplicate_contracts d
WHERE c.id = d.id AND d.contract_order > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_contracts_one_active_per_fighter
  ON public.contracts(fighter_id)
  WHERE status = 'active';

CREATE OR REPLACE FUNCTION public.prepare_fight_count_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'active' THEN
    NEW.contracted_fights := COALESCE(NEW.contracted_fights, 4);
    NEW.completed_fights := COALESCE(NEW.completed_fights, 0);
    NEW.fights_remaining := COALESCE(
      NEW.fights_remaining,
      NEW.contracted_fights - NEW.completed_fights
    );
    NEW.expires_week := 2147483647;
  ELSE
    NEW.fights_remaining := 0;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prepare_fight_count_contract ON public.contracts;
CREATE TRIGGER prepare_fight_count_contract
BEFORE INSERT OR UPDATE ON public.contracts
FOR EACH ROW EXECUTE FUNCTION public.prepare_fight_count_contract();

CREATE OR REPLACE FUNCTION public.sync_fighter_promotion_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_active_promotion uuid;
BEGIN
  SELECT promotion_id INTO v_active_promotion
  FROM public.contracts
  WHERE fighter_id = NEW.fighter_id AND status = 'active'
  ORDER BY signed_week DESC
  LIMIT 1;

  UPDATE public.fighters
  SET promotion_id = v_active_promotion
  WHERE id = NEW.fighter_id
    AND promotion_id IS DISTINCT FROM v_active_promotion;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_fighter_promotion_contract ON public.contracts;
CREATE TRIGGER sync_fighter_promotion_contract
AFTER INSERT OR UPDATE OF status, promotion_id ON public.contracts
FOR EACH ROW EXECUTE FUNCTION public.sync_fighter_promotion_contract();

UPDATE public.fighters f
SET promotion_id = c.promotion_id
FROM public.contracts c
WHERE c.fighter_id = f.id
  AND c.status = 'active'
  AND f.promotion_id IS DISTINCT FROM c.promotion_id;

CREATE OR REPLACE FUNCTION public.consume_promotion_contract_fight()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_promotion_id uuid;
BEGIN
  IF NEW.status <> 'completed' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'completed' THEN
    RETURN NEW;
  END IF;

  SELECT promotion_id INTO v_promotion_id
  FROM public.events WHERE id = NEW.event_id;

  UPDATE public.contracts
  SET completed_fights = completed_fights + 1,
      fights_remaining = GREATEST(0, fights_remaining - 1),
      status = CASE WHEN fights_remaining <= 1 THEN 'expired' ELSE 'active' END
  WHERE status = 'active'
    AND promotion_id = v_promotion_id
    AND fighter_id IN (NEW.fighter_a_id, NEW.fighter_b_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS consume_promotion_contract_fight ON public.fights;
CREATE TRIGGER consume_promotion_contract_fight
AFTER INSERT OR UPDATE OF status ON public.fights
FOR EACH ROW EXECUTE FUNCTION public.consume_promotion_contract_fight();

CREATE OR REPLACE FUNCTION public.enforce_offer_promotion_exclusivity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_contract_promotion uuid;
  v_contract_tier int;
  v_contract_remaining int;
  v_weight_class text;
  v_skill int;
  v_replacement_opponent uuid;
BEGIN
  SELECT c.promotion_id, p.tier, c.fights_remaining
  INTO v_contract_promotion, v_contract_tier, v_contract_remaining
  FROM public.contracts c
  JOIN public.promotions p ON p.id = c.promotion_id
  WHERE c.fighter_id = NEW.fighter_id AND c.status = 'active'
  LIMIT 1;

  IF v_contract_promotion IS NULL THEN
    RETURN NEW;
  END IF;

  NEW.promotion_id := v_contract_promotion;
  NEW.contract_fights := v_contract_remaining;
  SELECT weight_class, current_skill INTO v_weight_class, v_skill
  FROM public.fighters WHERE id = NEW.fighter_id;
  NEW.purse := v_contract_tier * 5000 + GREATEST(0, (v_skill - 50) * 200);

  IF NOT EXISTS (
    SELECT 1 FROM public.fighters
    WHERE id = NEW.opponent_fighter_id
      AND promotion_id = v_contract_promotion
      AND retired = false
  ) THEN
    SELECT id INTO v_replacement_opponent
    FROM public.fighters
    WHERE promotion_id = v_contract_promotion
      AND gym_id IS NULL
      AND retired = false
      AND weight_class = v_weight_class
      AND id <> NEW.fighter_id
      AND ABS(current_skill - v_skill) <= 15
    ORDER BY random()
    LIMIT 1;

    IF v_replacement_opponent IS NULL THEN
      RETURN NULL;
    END IF;
    NEW.opponent_fighter_id := v_replacement_opponent;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_offer_promotion_exclusivity ON public.fight_offers;
CREATE TRIGGER enforce_offer_promotion_exclusivity
BEFORE INSERT ON public.fight_offers
FOR EACH ROW EXECUTE FUNCTION public.enforce_offer_promotion_exclusivity();

-- Accepted upcoming bookings created before this migration receive a matching
-- promotion contract so their exclusivity and remaining fights are explicit.
INSERT INTO public.contracts (
  fighter_id, promotion_id, signed_week, expires_week,
  purse_per_fight, status, contracted_fights, fights_remaining
)
SELECT DISTINCT ON (fo.fighter_id)
  fo.fighter_id, fo.promotion_id, fo.offered_at_week, 2147483647,
  fo.purse, 'active', 4, 4
FROM public.fight_offers fo
WHERE fo.status = 'accepted'
  AND NOT EXISTS (
    SELECT 1 FROM public.contracts c
    WHERE c.fighter_id = fo.fighter_id AND c.status = 'active'
  )
ORDER BY fo.fighter_id, fo.offered_at_week DESC;

CREATE OR REPLACE FUNCTION public.sign_fighter(p_fighter_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_gym RECORD;
  v_fighter RECORD;
  v_cost bigint;
  v_active_count int;
BEGIN
  SELECT * INTO v_gym FROM public.gyms WHERE owner_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'You do not own a gym.');
  END IF;

  SELECT * INTO v_fighter
  FROM public.fighters WHERE id = p_fighter_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fighter not found.');
  END IF;
  IF v_fighter.retired THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Cannot sign a retired fighter.');
  END IF;
  IF v_fighter.gym_id IS NOT NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fighter is already managed by a gym.');
  END IF;

  SELECT count(*) INTO v_active_count
  FROM public.fighters WHERE gym_id = v_gym.id AND retired = false;
  IF v_active_count >= v_gym.capacity THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Gym is at capacity. Upgrade capacity first.');
  END IF;

  v_cost := GREATEST(2000, (v_fighter.current_skill - 40) * 1500);
  IF v_gym.cash < v_cost THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Insufficient cash to sign this fighter.', 'cost', v_cost);
  END IF;

  UPDATE public.gyms SET cash = cash - v_cost WHERE id = v_gym.id;
  UPDATE public.fighters SET gym_id = v_gym.id WHERE id = v_fighter.id;

  INSERT INTO public.news_items (week, type, title, body, fighter_id, gym_id)
  VALUES (
    public.get_current_week(), 'signing',
    v_gym.name || ' signs ' || v_fighter.name,
    v_gym.name || ' has signed ' || v_fighter.name ||
      ' to its management roster. Any active promotion contract remains in force.',
    v_fighter.id, v_gym.id
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'message', 'Signed ' || v_fighter.name ||
      CASE WHEN v_fighter.promotion_id IS NOT NULL
        THEN '. Their existing promotion contract remains active.'
        ELSE '.' END,
    'cost', v_cost
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_offer(p_offer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_gym RECORD;
  v_event_id uuid;
  v_event_name text;
  v_contract RECORD;
  v_contract_fights int;
  v_has_contract boolean := false;
BEGIN
  SELECT * INTO v_offer
  FROM public.fight_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Offer not found.');
  END IF;

  SELECT * INTO v_gym
  FROM public.gyms
  WHERE id = v_offer.gym_id AND owner_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Offer does not belong to your gym.');
  END IF;
  IF v_offer.status <> 'pending' THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Offer is no longer pending.');
  END IF;

  SELECT * INTO v_contract
  FROM public.contracts
  WHERE fighter_id = v_offer.fighter_id AND status = 'active'
  LIMIT 1;
  v_has_contract := FOUND;

  IF v_has_contract AND v_contract.promotion_id <> v_offer.promotion_id THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'This fighter is exclusively contracted to another promotion.'
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.fights f
    JOIN public.events e ON e.id = f.event_id
    WHERE f.status = 'pending' AND e.status = 'scheduled'
      AND (
        v_offer.fighter_id IN (f.fighter_a_id, f.fighter_b_id)
        OR v_offer.opponent_fighter_id IN (f.fighter_a_id, f.fighter_b_id)
      )
  ) THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'One of these fighters is already booked for an upcoming fight.'
    );
  END IF;

  IF NOT v_has_contract THEN
    v_contract_fights := v_offer.contract_fights;
    INSERT INTO public.contracts (
      fighter_id, promotion_id, signed_week, expires_week,
      purse_per_fight, status, contracted_fights, fights_remaining
    ) VALUES (
      v_offer.fighter_id, v_offer.promotion_id, public.get_current_week(),
      2147483647, v_offer.purse, 'active', v_contract_fights, v_contract_fights
    );
  ELSE
    v_contract_fights := v_contract.fights_remaining;
  END IF;

  SELECT e.id, e.name INTO v_event_id, v_event_name
  FROM public.events e
  WHERE e.promotion_id = v_offer.promotion_id
    AND e.scheduled_week = v_offer.scheduled_week
    AND e.status = 'scheduled'
  ORDER BY e.id LIMIT 1;

  IF v_event_id IS NULL THEN
    SELECT p.name || ' #' || v_offer.scheduled_week INTO v_event_name
    FROM public.promotions p WHERE p.id = v_offer.promotion_id;
    INSERT INTO public.events (promotion_id, name, scheduled_week, status)
    VALUES (v_offer.promotion_id, v_event_name, v_offer.scheduled_week, 'scheduled')
    RETURNING id INTO v_event_id;
  END IF;

  INSERT INTO public.fights
    (event_id, fighter_a_id, fighter_b_id, weight_class, status)
  SELECT v_event_id, v_offer.fighter_id, v_offer.opponent_fighter_id,
         f.weight_class, 'pending'
  FROM public.fighters f WHERE f.id = v_offer.fighter_id;

  UPDATE public.fight_offers
  SET status = 'accepted', event_id = v_event_id
  WHERE id = v_offer.id;

  UPDATE public.fight_offers
  SET status = 'declined'
  WHERE fighter_id = v_offer.fighter_id
    AND status = 'pending'
    AND id <> v_offer.id;

  UPDATE public.gyms
  SET cash = cash + v_offer.purse, reputation = reputation + 1
  WHERE id = v_gym.id;

  RETURN jsonb_build_object(
    'status', 'ok',
    'message', 'Fight booked on ' || v_event_name ||
      '. Exclusive promotion contract: ' || v_contract_fights || ' fight' ||
      CASE WHEN v_contract_fights = 1 THEN '' ELSE 's' END || ' remaining.',
    'purse', v_offer.purse,
    'event_id', v_event_id
  );
END;
$$;
