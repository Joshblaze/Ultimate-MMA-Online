-- Separate promotion contract offers from fight-only offers under an existing
-- exclusive promotion contract.

ALTER TABLE public.fight_offers
  ADD COLUMN IF NOT EXISTS offer_kind text NOT NULL DEFAULT 'contract';

ALTER TABLE public.fight_offers
  DROP CONSTRAINT IF EXISTS fight_offers_offer_kind_check;

ALTER TABLE public.fight_offers
  ADD CONSTRAINT fight_offers_offer_kind_check
  CHECK (offer_kind IN ('contract', 'fight'));

UPDATE public.fight_offers fo
SET status = 'declined'
WHERE fo.status = 'pending'
  AND EXISTS (
    SELECT 1
    FROM public.contracts c
    WHERE c.fighter_id = fo.fighter_id
      AND c.status = 'active'
      AND c.promotion_id <> fo.promotion_id
  );

UPDATE public.fight_offers fo
SET offer_kind = 'fight',
    contract_fights = c.fights_remaining
FROM public.contracts c
WHERE c.fighter_id = fo.fighter_id
  AND c.status = 'active'
  AND c.promotion_id = fo.promotion_id
  AND fo.status IN ('pending', 'accepted');

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
  WHERE c.fighter_id = NEW.fighter_id
    AND c.status = 'active'
  ORDER BY c.signed_week DESC, c.id DESC
  LIMIT 1;

  SELECT weight_class, current_skill INTO v_weight_class, v_skill
  FROM public.fighters WHERE id = NEW.fighter_id;

  IF v_contract_promotion IS NULL THEN
    NEW.offer_kind := 'contract';

    IF NOT EXISTS (
      SELECT 1
      FROM public.fighters
      WHERE id = NEW.opponent_fighter_id
        AND promotion_id = NEW.promotion_id
        AND retired = false
        AND weight_class = v_weight_class
    ) THEN
      SELECT id INTO v_replacement_opponent
      FROM public.fighters
      WHERE promotion_id = NEW.promotion_id
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
  END IF;

  NEW.offer_kind := 'fight';
  NEW.promotion_id := v_contract_promotion;
  NEW.contract_fights := v_contract_remaining;

  NEW.purse := v_contract_tier * 5000 + GREATEST(0, (v_skill - 50) * 200);

  IF NOT EXISTS (
    SELECT 1
    FROM public.fighters
    WHERE id = NEW.opponent_fighter_id
      AND promotion_id = v_contract_promotion
      AND retired = false
      AND weight_class = v_weight_class
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
  WHERE fighter_id = v_offer.fighter_id
    AND status = 'active'
  ORDER BY signed_week DESC, id DESC
  LIMIT 1;
  v_has_contract := FOUND;

  IF v_has_contract AND v_contract.promotion_id <> v_offer.promotion_id THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'This fighter is exclusively contracted to another promotion.'
    );
  END IF;

  IF v_offer.offer_kind = 'fight' AND NOT v_has_contract THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'This fight offer requires an active promotion contract.'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.fighters opponent
    WHERE opponent.id = v_offer.opponent_fighter_id
      AND opponent.promotion_id IS DISTINCT FROM v_offer.promotion_id
  ) THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Opponent is not available for this promotion.'
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
    'message',
      CASE
        WHEN v_offer.offer_kind = 'contract' AND NOT v_has_contract THEN
          'Contract accepted and first fight booked on ' || v_event_name ||
          '. Exclusive promotion contract: ' || v_contract_fights || ' fight' ||
          CASE WHEN v_contract_fights = 1 THEN '' ELSE 's' END || '.'
        ELSE
          'Fight booked on ' || v_event_name ||
          ' under the current promotion contract.'
      END,
    'purse', v_offer.purse,
    'event_id', v_event_id
  );
END;
$$;
