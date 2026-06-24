/*
# Fix player fight offers from add_event_fight

Fight offers were inserted with contract_fights = 0, violating
fight_offers_contract_fights_check (1-12) and silently failing to create offers.
*/

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

  IF v_player_count > 1 THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Only one player-managed fighter can be booked per bout.');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.fights f
    JOIN public.events e ON e.id = f.event_id
    WHERE f.status = 'pending' AND e.status = 'scheduled'
      AND (p_fighter_a_id IN (f.fighter_a_id, f.fighter_b_id)
        OR p_fighter_b_id IN (f.fighter_a_id, f.fighter_b_id))
  ) THEN
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
    INSERT INTO public.fights (event_id, fighter_a_id, fighter_b_id, weight_class, is_title_fight, championship_id, status)
    VALUES (p_event_id, p_fighter_a_id, p_fighter_b_id, v_fa.weight_class, p_is_title_fight, v_championship_id, 'pending')
    RETURNING id INTO v_fight_id;

    RETURN jsonb_build_object(
      'status', 'ok',
      'message', 'Fight booked on the card.',
      'fight_id', v_fight_id,
      'auto_accepted', true
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
