/*
# Player vs player fight booking

When both fighters belong to player gyms, create paired fight offers linked by
booking_group_id. The bout is only added to the card after both gyms accept.
Declining or expiring either offer cancels the whole booking group.
*/

ALTER TABLE public.fight_offers
  ADD COLUMN IF NOT EXISTS booking_group_id uuid;

CREATE INDEX IF NOT EXISTS fight_offers_booking_group_id_idx
  ON public.fight_offers (booking_group_id)
  WHERE booking_group_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fighter_has_open_booking(
  p_fighter_id uuid,
  p_exclude_offer_id uuid DEFAULT NULL,
  p_exclude_booking_group_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.fights f
    JOIN public.events e ON e.id = f.event_id
    WHERE f.status = 'pending'
      AND e.status = 'scheduled'
      AND p_fighter_id IN (f.fighter_a_id, f.fighter_b_id)
  )
  OR EXISTS (
    SELECT 1
    FROM public.fight_offers fo
    WHERE fo.status IN ('pending', 'accepted')
      AND fo.opponent_fighter_id IS NOT NULL
      AND p_fighter_id IN (fo.fighter_id, fo.opponent_fighter_id)
      AND fo.id IS DISTINCT FROM p_exclude_offer_id
      AND (
        p_exclude_booking_group_id IS NULL
        OR fo.booking_group_id IS DISTINCT FROM p_exclude_booking_group_id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.fights f
        WHERE f.event_id = fo.event_id
          AND f.status = 'pending'
          AND fo.fighter_id IN (f.fighter_a_id, f.fighter_b_id)
          AND fo.opponent_fighter_id IN (f.fighter_a_id, f.fighter_b_id)
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.cancel_booking_group(p_booking_group_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_booking_group_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.fight_offers
  SET status = 'declined'
  WHERE booking_group_id = p_booking_group_id
    AND status IN ('pending', 'accepted');
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_pvp_booking_group(p_booking_group_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_offer_a RECORD;
  v_offer_b RECORD;
  v_event_id uuid;
  v_event_name text;
  v_championship_id uuid;
  v_is_title_fight boolean := false;
  v_fight_id uuid;
BEGIN
  SELECT * INTO v_offer_a
  FROM public.fight_offers
  WHERE booking_group_id = p_booking_group_id
  ORDER BY id
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Booking group not found.');
  END IF;

  SELECT * INTO v_offer_b
  FROM public.fight_offers
  WHERE booking_group_id = p_booking_group_id
    AND id <> v_offer_a.id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Linked booking offer not found.');
  END IF;

  IF v_offer_a.status <> 'accepted' OR v_offer_b.status <> 'accepted' THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Both gyms must accept before the fight can be booked.');
  END IF;

  v_event_id := v_offer_a.event_id;
  SELECT name INTO v_event_name FROM public.events WHERE id = v_event_id;

  IF EXISTS (
    SELECT 1
    FROM public.fights f
    WHERE f.event_id = v_event_id
      AND f.status = 'pending'
      AND v_offer_a.fighter_id IN (f.fighter_a_id, f.fighter_b_id)
      AND v_offer_a.opponent_fighter_id IN (f.fighter_a_id, f.fighter_b_id)
  ) THEN
    UPDATE public.fight_offers
    SET event_id = v_event_id
    WHERE booking_group_id = p_booking_group_id;

    RETURN jsonb_build_object(
      'status', 'ok',
      'message', 'Fight already booked on ' || COALESCE(v_event_name, 'the event') || '.',
      'event_id', v_event_id
    );
  END IF;

  IF v_offer_a.offer_kind = 'title_shot' THEN
    SELECT c.id INTO v_championship_id
    FROM public.championships c
    JOIN public.fighters f ON f.id = v_offer_a.fighter_id
    WHERE c.promotion_id = v_offer_a.promotion_id
      AND c.weight_class = f.weight_class
    LIMIT 1;
    v_is_title_fight := v_championship_id IS NOT NULL;
  ELSE
    SELECT c.id INTO v_championship_id
    FROM public.championships c
    JOIN public.fighters f ON f.id = v_offer_a.fighter_id
    WHERE c.promotion_id = v_offer_a.promotion_id
      AND c.weight_class = f.weight_class
      AND c.current_champion_fighter_id IS NOT NULL
      AND (
        c.current_champion_fighter_id = v_offer_a.fighter_id
        OR c.current_champion_fighter_id = v_offer_a.opponent_fighter_id
      )
    LIMIT 1;
    v_is_title_fight := v_championship_id IS NOT NULL;
  END IF;

  INSERT INTO public.fights (
    event_id, fighter_a_id, fighter_b_id, weight_class, is_title_fight, championship_id, status
  )
  SELECT
    v_event_id,
    v_offer_a.fighter_id,
    v_offer_a.opponent_fighter_id,
    f.weight_class,
    v_is_title_fight,
    v_championship_id,
    'pending'
  FROM public.fighters f
  WHERE f.id = v_offer_a.fighter_id
  RETURNING id INTO v_fight_id;

  UPDATE public.fight_offers
  SET event_id = v_event_id
  WHERE booking_group_id = p_booking_group_id;

  RETURN jsonb_build_object(
    'status', 'ok',
    'message',
      CASE
        WHEN v_is_title_fight THEN 'Title fight booked on ' || COALESCE(v_event_name, 'the event') || '.'
        ELSE 'Fight booked on ' || COALESCE(v_event_name, 'the event') || '.'
      END,
    'fight_id', v_fight_id,
    'event_id', v_event_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_offer_for_booked_fighter()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.opponent_fighter_id IS NOT NULL
     AND public.fighter_has_open_booking(NEW.fighter_id) THEN
    RETURN NULL;
  END IF;

  IF NEW.opponent_fighter_id IS NOT NULL
     AND public.fighter_has_open_booking(NEW.opponent_fighter_id) THEN
    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- add_event_fight: allow two player-managed fighters via paired offers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.add_event_fight(
  p_event_id uuid,
  p_fighter_a_id uuid,
  p_fighter_b_id uuid,
  p_is_title_fight boolean DEFAULT false,
  p_purse bigint DEFAULT 5000
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_tick int;
  v_event RECORD;
  v_fa RECORD;
  v_fb RECORD;
  v_championship_id uuid;
  v_offer_id uuid;
  v_fight_id uuid;
  v_player_count int;
  v_contract_fights int;
  v_offer_kind text;
  v_booking_group_id uuid;
  v_offer_a_id uuid;
  v_offer_b_id uuid;
BEGIN
  v_tick := public.get_current_week();

  SELECT e.*, p.id AS promo_id
  INTO v_event
  FROM public.events e
  JOIN public.promotions p ON p.id = e.promotion_id
  WHERE e.id = p_event_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Event not found.');
  END IF;

  IF NOT public.promotion_owner_check(v_event.promo_id) THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'You do not own this promotion.');
  END IF;

  IF v_event.status <> 'scheduled' THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Event is not open for booking.');
  END IF;

  IF v_event.scheduled_week < v_tick + 4 THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fights must be booked at least 4 weeks (1 month) before the event.');
  END IF;

  IF p_fighter_a_id = p_fighter_b_id THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'A fighter cannot fight themselves.');
  END IF;

  SELECT * INTO v_fa FROM public.fighters WHERE id = p_fighter_a_id AND retired = false;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fighter A not found.');
  END IF;

  SELECT * INTO v_fb FROM public.fighters WHERE id = p_fighter_b_id AND retired = false;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fighter B not found.');
  END IF;

  IF v_fa.weight_class <> v_fb.weight_class THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fighters must be in the same weight class.');
  END IF;

  v_player_count := (CASE WHEN v_fa.gym_id IS NOT NULL THEN 1 ELSE 0 END)
                  + (CASE WHEN v_fb.gym_id IS NOT NULL THEN 1 ELSE 0 END);

  IF public.fighter_has_open_booking(p_fighter_a_id)
     OR public.fighter_has_open_booking(p_fighter_b_id) THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'One of these fighters is already booked for an upcoming fight.');
  END IF;

  IF p_is_title_fight THEN
    SELECT c.id INTO v_championship_id
    FROM public.championships c
    WHERE c.promotion_id = v_event.promo_id
      AND c.weight_class = v_fa.weight_class;
  END IF;

  v_offer_kind := CASE WHEN p_is_title_fight THEN 'title_shot' ELSE 'fight' END;

  IF v_player_count = 0 THEN
    INSERT INTO public.fights (
      event_id, fighter_a_id, fighter_b_id, weight_class, is_title_fight, championship_id, status
    ) VALUES (
      p_event_id, p_fighter_a_id, p_fighter_b_id, v_fa.weight_class, p_is_title_fight, v_championship_id, 'pending'
    )
    RETURNING id INTO v_fight_id;

    RETURN jsonb_build_object(
      'status', 'ok',
      'message', 'Fight booked on the card.',
      'fight_id', v_fight_id,
      'auto_accepted', true
    );
  END IF;

  IF v_player_count = 2 THEN
    SELECT c.fights_remaining INTO v_contract_fights
    FROM public.contracts c
    WHERE c.fighter_id = v_fa.id
      AND c.promotion_id = v_event.promo_id
      AND c.status = 'active'
    ORDER BY c.signed_week DESC, c.id DESC
    LIMIT 1;

    IF NOT FOUND OR v_contract_fights IS NULL THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'Fighter A must have an active promotion contract before fight offers.');
    END IF;

    SELECT c.fights_remaining INTO v_contract_fights
    FROM public.contracts c
    WHERE c.fighter_id = v_fb.id
      AND c.promotion_id = v_event.promo_id
      AND c.status = 'active'
    ORDER BY c.signed_week DESC, c.id DESC
    LIMIT 1;

    IF NOT FOUND OR v_contract_fights IS NULL THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'Fighter B must have an active promotion contract before fight offers.');
    END IF;

    v_booking_group_id := gen_random_uuid();

    INSERT INTO public.fight_offers (
      gym_id, fighter_id, opponent_fighter_id, promotion_id, event_id,
      purse, scheduled_week, status, offered_at_week, response_deadline_week,
      offer_kind, contract_fights, booking_group_id
    )
    SELECT
      v_fa.gym_id, v_fa.id, v_fb.id, v_event.promo_id, p_event_id,
      p_purse, v_event.scheduled_week, 'pending', v_tick, v_tick + 2,
      v_offer_kind, GREATEST(1, c.fights_remaining), v_booking_group_id
    FROM public.contracts c
    WHERE c.fighter_id = v_fa.id
      AND c.promotion_id = v_event.promo_id
      AND c.status = 'active'
    ORDER BY c.signed_week DESC, c.id DESC
    LIMIT 1
    RETURNING id INTO v_offer_a_id;

    INSERT INTO public.fight_offers (
      gym_id, fighter_id, opponent_fighter_id, promotion_id, event_id,
      purse, scheduled_week, status, offered_at_week, response_deadline_week,
      offer_kind, contract_fights, booking_group_id
    )
    SELECT
      v_fb.gym_id, v_fb.id, v_fa.id, v_event.promo_id, p_event_id,
      p_purse, v_event.scheduled_week, 'pending', v_tick, v_tick + 2,
      v_offer_kind, GREATEST(1, c.fights_remaining), v_booking_group_id
    FROM public.contracts c
    WHERE c.fighter_id = v_fb.id
      AND c.promotion_id = v_event.promo_id
      AND c.status = 'active'
    ORDER BY c.signed_week DESC, c.id DESC
    LIMIT 1
    RETURNING id INTO v_offer_b_id;

    IF v_offer_a_id IS NULL OR v_offer_b_id IS NULL THEN
      PERFORM public.cancel_booking_group(v_booking_group_id);
      RETURN jsonb_build_object('status', 'error', 'message', 'Fight offers could not be created.');
    END IF;

    RETURN jsonb_build_object(
      'status', 'ok',
      'message', 'Fight offers sent to both gyms. Each has 2 weeks to accept before the bout is booked.',
      'offer_id', v_offer_a_id,
      'booking_group_id', v_booking_group_id,
      'auto_accepted', false
    );
  END IF;

  IF v_fa.gym_id IS NOT NULL THEN
    SELECT c.fights_remaining INTO v_contract_fights
    FROM public.contracts c
    WHERE c.fighter_id = v_fa.id
      AND c.promotion_id = v_event.promo_id
      AND c.status = 'active'
    ORDER BY c.signed_week DESC, c.id DESC
    LIMIT 1;

    IF NOT FOUND OR v_contract_fights IS NULL THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'Player fighter must have an active promotion contract before fight offers.');
    END IF;

    INSERT INTO public.fight_offers (
      gym_id, fighter_id, opponent_fighter_id, promotion_id, event_id,
      purse, scheduled_week, status, offered_at_week, response_deadline_week, offer_kind, contract_fights
    ) VALUES (
      v_fa.gym_id, v_fa.id, v_fb.id, v_event.promo_id, p_event_id,
      p_purse, v_event.scheduled_week, 'pending', v_tick, v_tick + 2,
      v_offer_kind, GREATEST(1, v_contract_fights)
    ) RETURNING id INTO v_offer_id;

    IF v_offer_id IS NULL THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'Fight offer could not be created.');
    END IF;

    RETURN jsonb_build_object(
      'status', 'ok',
      'message', 'Fight offer sent to gym. They have 2 weeks to respond.',
      'offer_id', v_offer_id,
      'auto_accepted', false
    );
  END IF;

  IF v_fb.gym_id IS NOT NULL THEN
    SELECT c.fights_remaining INTO v_contract_fights
    FROM public.contracts c
    WHERE c.fighter_id = v_fb.id
      AND c.promotion_id = v_event.promo_id
      AND c.status = 'active'
    ORDER BY c.signed_week DESC, c.id DESC
    LIMIT 1;

    IF NOT FOUND OR v_contract_fights IS NULL THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'Player fighter must have an active promotion contract before fight offers.');
    END IF;

    INSERT INTO public.fight_offers (
      gym_id, fighter_id, opponent_fighter_id, promotion_id, event_id,
      purse, scheduled_week, status, offered_at_week, response_deadline_week, offer_kind, contract_fights
    ) VALUES (
      v_fb.gym_id, v_fb.id, v_fa.id, v_event.promo_id, p_event_id,
      p_purse, v_event.scheduled_week, 'pending', v_tick, v_tick + 2,
      v_offer_kind, GREATEST(1, v_contract_fights)
    ) RETURNING id INTO v_offer_id;

    IF v_offer_id IS NULL THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'Fight offer could not be created.');
    END IF;

    RETURN jsonb_build_object(
      'status', 'ok',
      'message', 'Fight offer sent to gym. They have 2 weeks to respond.',
      'offer_id', v_offer_id,
      'auto_accepted', false
    );
  END IF;

  RETURN jsonb_build_object('status', 'error', 'message', 'Unable to book fight.');
END;
$$;

-- ---------------------------------------------------------------------------
-- accept_offer: defer fight creation for linked PvP offers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.accept_offer(p_offer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_gym RECORD;
  v_sibling RECORD;
  v_event_id uuid;
  v_event_name text;
  v_contract RECORD;
  v_contract_fights int;
  v_has_contract boolean := false;
  v_championship_id uuid;
  v_is_title_fight boolean := false;
  v_tier_up boolean := false;
  v_current_tier int;
  v_offer_tier int;
  v_tick int;
  v_confirm jsonb;
BEGIN
  v_tick := public.get_current_week();

  SELECT * INTO v_offer FROM public.fight_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Offer not found.');
  END IF;

  SELECT * INTO v_gym FROM public.gyms WHERE id = v_offer.gym_id AND owner_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Offer does not belong to your gym.');
  END IF;

  IF v_offer.status <> 'pending' THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Offer is no longer pending.');
  END IF;

  IF v_offer.response_deadline_week < v_tick THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'This offer has expired.');
  END IF;

  SELECT * INTO v_contract
  FROM public.contracts
  WHERE fighter_id = v_offer.fighter_id AND status = 'active'
  ORDER BY signed_week DESC, id DESC
  LIMIT 1;
  v_has_contract := FOUND;

  IF v_has_contract AND v_contract.promotion_id <> v_offer.promotion_id THEN
    SELECT tier INTO v_current_tier FROM public.promotions WHERE id = v_contract.promotion_id;
    SELECT tier INTO v_offer_tier FROM public.promotions WHERE id = v_offer.promotion_id;
    IF v_offer_tier IS NULL OR v_offer_tier <= v_current_tier THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'This fighter is exclusively contracted to another promotion.');
    END IF;
    UPDATE public.contracts SET status = 'expired' WHERE id = v_contract.id;
    v_has_contract := false;
    v_tier_up := true;
  END IF;

  IF v_offer.offer_kind IN ('fight', 'title_shot') AND NOT v_has_contract THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'This fight offer requires an active promotion contract.');
  END IF;

  IF v_offer.offer_kind = 'contract' AND v_offer.opponent_fighter_id IS NULL THEN
    IF NOT v_has_contract THEN
      v_contract_fights := v_offer.contract_fights;
      INSERT INTO public.contracts (
        fighter_id, promotion_id, signed_week, expires_week,
        purse_per_fight, status, contracted_fights, fights_remaining
      ) VALUES (
        v_offer.fighter_id, v_offer.promotion_id, v_tick,
        2147483647, v_offer.purse, 'active', v_contract_fights, v_contract_fights
      );
      UPDATE public.fighters SET promotion_id = v_offer.promotion_id WHERE id = v_offer.fighter_id;
    END IF;

    UPDATE public.fight_offers SET status = 'accepted' WHERE id = v_offer.id;
    UPDATE public.fight_offers SET status = 'declined'
      WHERE fighter_id = v_offer.fighter_id AND status = 'pending' AND id <> v_offer.id;
    UPDATE public.gyms SET cash = cash + v_offer.purse, reputation = reputation + 1 WHERE id = v_gym.id;

    RETURN jsonb_build_object(
      'status', 'ok',
      'message', 'Contract accepted. Exclusive promotion contract: ' || v_offer.contract_fights || ' fight(s).',
      'purse', v_offer.purse
    );
  END IF;

  IF v_offer.opponent_fighter_id IS NOT NULL THEN
    IF v_offer.offer_kind = 'title_shot' THEN
      SELECT c.id INTO v_championship_id
      FROM public.championships c
      JOIN public.fighters f ON f.id = v_offer.fighter_id
      WHERE c.promotion_id = v_offer.promotion_id
        AND c.weight_class = f.weight_class
      LIMIT 1;
      v_is_title_fight := v_championship_id IS NOT NULL;
    ELSE
      SELECT c.id INTO v_championship_id
      FROM public.championships c
      JOIN public.fighters f ON f.id = v_offer.fighter_id
      WHERE c.promotion_id = v_offer.promotion_id
        AND c.weight_class = f.weight_class
        AND c.current_champion_fighter_id IS NOT NULL
        AND (
          c.current_champion_fighter_id = v_offer.fighter_id
          OR c.current_champion_fighter_id = v_offer.opponent_fighter_id
        )
      LIMIT 1;
      v_is_title_fight := v_championship_id IS NOT NULL;
    END IF;

    IF public.fighter_holds_promotion_title(v_offer.opponent_fighter_id) AND NOT v_is_title_fight THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'The champion can only be booked for a title fight.');
    END IF;

    IF public.fighter_holds_promotion_title(v_offer.fighter_id) AND NOT v_is_title_fight THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'Your champion can only be booked for a title fight.');
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.fighters opponent
      WHERE opponent.id = v_offer.opponent_fighter_id
        AND opponent.promotion_id IS NOT NULL
        AND opponent.promotion_id IS DISTINCT FROM v_offer.promotion_id
    ) THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'Opponent is not available for this promotion.');
    END IF;

    IF public.fighter_has_open_booking(v_offer.fighter_id, v_offer.id, v_offer.booking_group_id)
       OR public.fighter_has_open_booking(v_offer.opponent_fighter_id, v_offer.id, v_offer.booking_group_id) THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'One of these fighters is already booked for an upcoming fight.');
    END IF;
  END IF;

  IF NOT v_has_contract AND v_offer.offer_kind IN ('contract', 'renewal') THEN
    v_contract_fights := v_offer.contract_fights;
    INSERT INTO public.contracts (
      fighter_id, promotion_id, signed_week, expires_week,
      purse_per_fight, status, contracted_fights, fights_remaining
    ) VALUES (
      v_offer.fighter_id, v_offer.promotion_id, v_tick,
      2147483647, v_offer.purse, 'active', v_contract_fights, v_contract_fights
    );
    UPDATE public.fighters SET promotion_id = v_offer.promotion_id WHERE id = v_offer.fighter_id;
  ELSIF NOT v_has_contract AND v_offer.offer_kind IN ('fight', 'title_shot') THEN
    NULL;
  ELSIF v_has_contract THEN
    v_contract_fights := v_contract.fights_remaining;
  END IF;

  IF v_offer.booking_group_id IS NOT NULL AND v_offer.opponent_fighter_id IS NOT NULL THEN
    SELECT * INTO v_sibling
    FROM public.fight_offers
    WHERE booking_group_id = v_offer.booking_group_id
      AND id <> v_offer.id
    FOR UPDATE;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'Linked booking offer not found.');
    END IF;

    v_event_id := v_offer.event_id;
    SELECT name INTO v_event_name FROM public.events WHERE id = v_event_id;

    UPDATE public.fight_offers SET status = 'accepted' WHERE id = v_offer.id;

    UPDATE public.fight_offers SET status = 'declined'
    WHERE fighter_id = v_offer.fighter_id
      AND status = 'pending'
      AND id <> v_offer.id
      AND booking_group_id IS DISTINCT FROM v_offer.booking_group_id;

    UPDATE public.gyms SET cash = cash + v_offer.purse, reputation = reputation + 1 WHERE id = v_gym.id;

    IF v_sibling.status = 'accepted' THEN
      v_confirm := public.confirm_pvp_booking_group(v_offer.booking_group_id);
      IF (v_confirm->>'status') = 'ok' THEN
        v_confirm := v_confirm || jsonb_build_object('purse', v_offer.purse);
      END IF;
      RETURN v_confirm;
    END IF;

    RETURN jsonb_build_object(
      'status', 'ok',
      'message', 'Offer accepted. Waiting for the opponent gym to accept before the fight is booked'
        || CASE WHEN v_event_name IS NOT NULL THEN ' on ' || v_event_name ELSE '' END || '.',
      'purse', v_offer.purse,
      'event_id', v_event_id,
      'awaiting_opponent', true
    );
  END IF;

  IF v_offer.event_id IS NOT NULL THEN
    v_event_id := v_offer.event_id;
    SELECT name INTO v_event_name FROM public.events WHERE id = v_event_id;
  ELSE
    SELECT e.id, e.name INTO v_event_id, v_event_name
    FROM public.events e
    WHERE e.promotion_id = v_offer.promotion_id
      AND e.scheduled_week = v_offer.scheduled_week
      AND e.status = 'scheduled'
    ORDER BY e.id LIMIT 1;

    IF v_event_id IS NULL THEN
      v_event_name := public.next_promotion_event_name(v_offer.promotion_id);
      INSERT INTO public.events (promotion_id, name, scheduled_week, status)
      VALUES (v_offer.promotion_id, v_event_name, v_offer.scheduled_week, 'scheduled')
      RETURNING id INTO v_event_id;
    END IF;
  END IF;

  IF v_offer.opponent_fighter_id IS NOT NULL THEN
    INSERT INTO public.fights (event_id, fighter_a_id, fighter_b_id, weight_class, is_title_fight, championship_id, status)
    SELECT v_event_id, v_offer.fighter_id, v_offer.opponent_fighter_id,
           f.weight_class, v_is_title_fight, v_championship_id, 'pending'
    FROM public.fighters f WHERE f.id = v_offer.fighter_id;
  END IF;

  UPDATE public.fight_offers SET status = 'accepted', event_id = v_event_id WHERE id = v_offer.id;
  UPDATE public.fight_offers SET status = 'declined'
    WHERE fighter_id = v_offer.fighter_id AND status = 'pending' AND id <> v_offer.id;
  UPDATE public.gyms SET cash = cash + v_offer.purse, reputation = reputation + 1 WHERE id = v_gym.id;

  RETURN jsonb_build_object(
    'status', 'ok',
    'message',
      CASE
        WHEN v_offer.opponent_fighter_id IS NULL THEN 'Offer accepted.'
        WHEN v_is_title_fight AND public.fighter_holds_promotion_title(v_offer.opponent_fighter_id) THEN
          'Title shot booked on ' || v_event_name || '.'
        WHEN v_is_title_fight THEN 'Title fight booked on ' || v_event_name || '.'
        WHEN v_offer.offer_kind = 'fight' THEN 'Fight booked on ' || v_event_name || '.'
        WHEN v_tier_up THEN 'Tier-up contract accepted and first fight booked on ' || v_event_name || '.'
        WHEN v_offer.offer_kind = 'contract' THEN
          'Contract accepted and first fight booked on ' || v_event_name || '.'
        ELSE 'Fight booked on ' || v_event_name || '.'
      END,
    'purse', v_offer.purse,
    'event_id', v_event_id
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- decline_offer: cancel linked PvP booking groups
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.decline_offer(p_offer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_gym RECORD;
BEGIN
  SELECT * INTO v_offer FROM public.fight_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','error','message','Offer not found.');
  END IF;

  SELECT * INTO v_gym FROM public.gyms WHERE id = v_offer.gym_id AND owner_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','error','message','Offer does not belong to your gym.');
  END IF;

  IF v_offer.status <> 'pending' THEN
    RETURN jsonb_build_object('status','error','message','Offer is no longer pending.');
  END IF;

  IF v_offer.booking_group_id IS NOT NULL THEN
    PERFORM public.cancel_booking_group(v_offer.booking_group_id);
  ELSE
    UPDATE public.fight_offers SET status = 'declined' WHERE id = v_offer.id;
  END IF;

  IF v_offer.offer_kind = 'renewal' THEN
    UPDATE public.fighters
    SET promotion_id = NULL
    WHERE id = v_offer.fighter_id;
  END IF;

  RETURN jsonb_build_object(
    'status','ok',
    'message',
      CASE
        WHEN v_offer.booking_group_id IS NOT NULL THEN
          'Fight offer declined. The linked opponent offer was cancelled as well.'
        WHEN v_offer.offer_kind = 'renewal' THEN 'Contract renewal declined. Fighter is now a free agent.'
        ELSE 'Offer declined.'
      END
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Offer expiry: cancel entire PvP booking groups
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.finalize_week_contracts(p_tick int)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE public.contracts SET status = 'expired'
  WHERE status = 'active'
    AND expires_week <= p_tick
    AND expires_week < 2147483647
    AND NOT EXISTS (
      SELECT 1 FROM public.championships ch
      WHERE ch.current_champion_fighter_id = contracts.fighter_id
        AND ch.promotion_id = contracts.promotion_id
    );

  UPDATE public.fighters SET promotion_id = NULL
  WHERE gym_id IS NULL
    AND id IN (
      SELECT c.fighter_id FROM public.contracts c
      WHERE c.status = 'expired'
        AND NOT public.fighter_holds_promotion_title(c.fighter_id, c.promotion_id)
        AND NOT public.fighter_is_promotion_ranked(c.fighter_id, c.promotion_id)
    );

  UPDATE public.fighters f SET promotion_id = NULL
  FROM public.fight_offers fo
  WHERE fo.fighter_id = f.id
    AND fo.offer_kind = 'renewal'
    AND fo.status = 'pending'
    AND fo.response_deadline_week < p_tick;

  WITH expired_groups AS (
    SELECT DISTINCT booking_group_id
    FROM public.fight_offers
    WHERE booking_group_id IS NOT NULL
      AND status = 'pending'
      AND response_deadline_week < p_tick
  )
  UPDATE public.fight_offers fo
  SET status = 'declined'
  FROM expired_groups eg
  WHERE fo.booking_group_id = eg.booking_group_id
    AND fo.status IN ('pending', 'accepted');

  UPDATE public.fight_offers SET status = 'declined'
  WHERE status = 'pending'
    AND response_deadline_week < p_tick;

  RETURN 0;
END;
$$;

-- ---------------------------------------------------------------------------
-- run_event: block unresolved PvP bookings
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.run_event(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_tick int;
  v_event RECORD;
  v_fights_simulated int;
  v_pending_offers int;
  v_unconfirmed_pvp int;
  v_pending_fights int;
BEGIN
  v_tick := public.get_current_week();

  SELECT e.* INTO v_event FROM public.events e WHERE e.id = p_event_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Event not found.');
  END IF;

  IF NOT public.promotion_owner_check(v_event.promotion_id) THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'You do not own this promotion.');
  END IF;

  IF v_event.status <> 'scheduled' THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Event has already been run or cancelled.');
  END IF;

  IF v_tick < v_event.scheduled_week THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Event date has not been reached yet.');
  END IF;

  SELECT count(*) INTO v_pending_offers
  FROM public.fight_offers fo
  WHERE fo.event_id = p_event_id AND fo.status = 'pending';

  IF v_pending_offers > 0 THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Pending fight offers must be resolved before running the event.');
  END IF;

  SELECT count(*) INTO v_unconfirmed_pvp
  FROM public.fight_offers fo
  WHERE fo.event_id = p_event_id
    AND fo.booking_group_id IS NOT NULL
    AND fo.status = 'accepted'
    AND NOT EXISTS (
      SELECT 1
      FROM public.fights f
      WHERE f.event_id = fo.event_id
        AND f.status = 'pending'
        AND fo.fighter_id IN (f.fighter_a_id, f.fighter_b_id)
        AND fo.opponent_fighter_id IN (f.fighter_a_id, f.fighter_b_id)
    );

  IF v_unconfirmed_pvp > 0 THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Player vs player bookings must be confirmed by both gyms before running the event.'
    );
  END IF;

  SELECT count(*) INTO v_pending_fights
  FROM public.fights f WHERE f.event_id = p_event_id AND f.status = 'pending';

  IF v_pending_fights = 0 THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'No confirmed fights on the card.');
  END IF;

  v_fights_simulated := public.simulate_event_fights(p_event_id, v_tick);

  UPDATE public.events
  SET status = 'completed', completed_at_week = v_tick
  WHERE id = p_event_id;

  PERFORM public.refresh_promotion_rankings(v_event.promotion_id);

  RETURN jsonb_build_object(
    'status', 'ok',
    'message', 'Event completed. ' || v_fights_simulated || ' fight(s) simulated.',
    'fights_simulated', v_fights_simulated
  );
END;
$$;
