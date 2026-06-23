/*
# Book and resolve accepted fight offers

Previously accept_offer() only changed the offer status. It did not attach the
offer to an event or create a fight, so accepted fighters could receive more
offers and their scheduled bout never appeared or ran.
*/

-- Do not generate another offer for either fighter while a booked bout exists.
CREATE OR REPLACE FUNCTION public.reject_offer_for_booked_fighter()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.fights f
    JOIN public.events e ON e.id = f.event_id
    WHERE f.status = 'pending'
      AND e.status = 'scheduled'
      AND (
        NEW.fighter_id IN (f.fighter_a_id, f.fighter_b_id)
        OR NEW.opponent_fighter_id IN (f.fighter_a_id, f.fighter_b_id)
      )
  ) THEN
    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reject_offer_for_booked_fighter ON public.fight_offers;
CREATE TRIGGER reject_offer_for_booked_fighter
BEFORE INSERT ON public.fight_offers
FOR EACH ROW
EXECUTE FUNCTION public.reject_offer_for_booked_fighter();

-- Resolve fights that were booked in advance immediately before their event is
-- marked completed by advance_week().
CREATE OR REPLACE FUNCTION public.resolve_booked_event_fights()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fight RECORD;
  v_a_skill int;
  v_b_skill int;
  v_winner_id uuid;
  v_loser_id uuid;
  v_method text;
  v_round int;
  v_rand float;
  v_commentary jsonb;
  v_winner_name text;
  v_loser_name text;
  v_winner_gym uuid;
  v_loser_gym uuid;
BEGIN
  IF OLD.status <> 'scheduled' OR NEW.status <> 'completed' THEN
    RETURN NEW;
  END IF;

  FOR v_fight IN
    SELECT f.*
    FROM public.fights f
    WHERE f.event_id = OLD.id AND f.status = 'pending'
    FOR UPDATE
  LOOP
    SELECT current_skill INTO v_a_skill
    FROM public.fighters WHERE id = v_fight.fighter_a_id;

    SELECT current_skill INTO v_b_skill
    FROM public.fighters WHERE id = v_fight.fighter_b_id;

    IF v_a_skill + floor(random() * 25)::int
       >= v_b_skill + floor(random() * 25)::int THEN
      v_winner_id := v_fight.fighter_a_id;
      v_loser_id := v_fight.fighter_b_id;
    ELSE
      v_winner_id := v_fight.fighter_b_id;
      v_loser_id := v_fight.fighter_a_id;
    END IF;

    v_rand := random();
    IF v_rand < 0.28 THEN
      v_method := 'KO';
    ELSIF v_rand < 0.50 THEN
      v_method := 'TKO';
    ELSIF v_rand < 0.72 THEN
      v_method := 'Submission';
    ELSE
      v_method := 'Decision';
    END IF;
    v_round := CASE WHEN v_method = 'Decision'
      THEN 3 ELSE 1 + floor(random() * 3)::int END;

    SELECT name, gym_id INTO v_winner_name, v_winner_gym
    FROM public.fighters WHERE id = v_winner_id;
    SELECT name, gym_id INTO v_loser_name, v_loser_gym
    FROM public.fighters WHERE id = v_loser_id;

    v_commentary := jsonb_build_array(
      v_winner_name || ' and ' || v_loser_name || ' touch gloves.',
      CASE
        WHEN v_method = 'Submission' THEN 'A grappling exchange produces a fight-ending submission.'
        WHEN v_method IN ('KO', 'TKO') THEN 'A clean power shot brings the contest to an end.'
        ELSE 'The bout goes the distance and the judges submit their scorecards.'
      END,
      v_winner_name || ' wins by ' || v_method || ' in round ' || v_round || '.'
    );

    UPDATE public.fights
    SET winner_id = v_winner_id,
        method = v_method,
        round = v_round,
        commentary = v_commentary,
        status = 'completed',
        completed_at_week = NEW.completed_at_week
    WHERE id = v_fight.id;

    UPDATE public.fighters
    SET wins = wins + 1,
        ko_wins = ko_wins + CASE WHEN v_method IN ('KO', 'TKO') THEN 1 ELSE 0 END,
        sub_wins = sub_wins + CASE WHEN v_method = 'Submission' THEN 1 ELSE 0 END,
        dec_wins = dec_wins + CASE WHEN v_method = 'Decision' THEN 1 ELSE 0 END
    WHERE id = v_winner_id;

    UPDATE public.fighters SET losses = losses + 1 WHERE id = v_loser_id;

    IF v_winner_gym IS NOT NULL THEN
      UPDATE public.gyms
      SET wins = wins + 1, reputation = reputation + 2
      WHERE id = v_winner_gym;
    END IF;
    IF v_loser_gym IS NOT NULL THEN
      UPDATE public.gyms SET losses = losses + 1 WHERE id = v_loser_gym;
    END IF;

    INSERT INTO public.news_items
      (week, type, title, body, fighter_id, promotion_id)
    VALUES
      (NEW.completed_at_week, 'event_result',
       v_winner_name || ' defeats ' || v_loser_name,
       v_winner_name || ' defeated ' || v_loser_name || ' by ' ||
         v_method || ' in round ' || v_round || ' at ' || OLD.name || '.',
       v_winner_id, OLD.promotion_id);
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resolve_booked_event_fights ON public.events;
CREATE TRIGGER resolve_booked_event_fights
BEFORE UPDATE OF status ON public.events
FOR EACH ROW
EXECUTE FUNCTION public.resolve_booked_event_fights();

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
BEGIN
  SELECT * INTO v_offer
  FROM public.fight_offers
  WHERE id = p_offer_id
  FOR UPDATE;

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

  IF EXISTS (
    SELECT 1
    FROM public.fights f
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

  SELECT e.id, e.name INTO v_event_id, v_event_name
  FROM public.events e
  WHERE e.promotion_id = v_offer.promotion_id
    AND e.scheduled_week = v_offer.scheduled_week
    AND e.status = 'scheduled'
  ORDER BY e.id
  LIMIT 1;

  IF v_event_id IS NULL THEN
    SELECT p.name || ' #' || v_offer.scheduled_week
    INTO v_event_name
    FROM public.promotions p
    WHERE p.id = v_offer.promotion_id;

    INSERT INTO public.events (promotion_id, name, scheduled_week, status)
    VALUES (v_offer.promotion_id, v_event_name, v_offer.scheduled_week, 'scheduled')
    RETURNING id INTO v_event_id;
  END IF;

  INSERT INTO public.fights
    (event_id, fighter_a_id, fighter_b_id, weight_class, status)
  SELECT v_event_id, v_offer.fighter_id, v_offer.opponent_fighter_id,
         f.weight_class, 'pending'
  FROM public.fighters f
  WHERE f.id = v_offer.fighter_id;

  UPDATE public.fight_offers
  SET status = 'accepted', event_id = v_event_id
  WHERE id = v_offer.id;

  -- Once this fighter is booked, all of their other offers are no longer valid.
  UPDATE public.fight_offers
  SET status = 'declined'
  WHERE fighter_id = v_offer.fighter_id
    AND status = 'pending'
    AND id <> v_offer.id;

  UPDATE public.gyms
  SET cash = cash + v_offer.purse,
      reputation = reputation + 1
  WHERE id = v_gym.id;

  RETURN jsonb_build_object(
    'status', 'ok',
    'message', 'Offer accepted and booked on ' || v_event_name || '.',
    'purse', v_offer.purse,
    'event_id', v_event_id
  );
END;
$$;

-- Repair accepted offers created before this migration. Past-due unbooked offers
-- are moved to the next game week so they still get the fight they accepted.
DO $$
DECLARE
  v_offer RECORD;
  v_event_id uuid;
  v_event_name text;
  v_current_tick int;
  v_scheduled_week int;
BEGIN
  SELECT tick_count INTO v_current_tick FROM public.world_state WHERE id = 1;

  UPDATE public.fight_offers fo
  SET event_id = f.event_id
  FROM public.fights f
  WHERE fo.status = 'accepted'
    AND fo.event_id IS NULL
    AND f.fighter_a_id = fo.fighter_id
    AND f.fighter_b_id = fo.opponent_fighter_id;

  FOR v_offer IN
    SELECT fo.*
    FROM public.fight_offers fo
    WHERE fo.status = 'accepted'
      AND NOT EXISTS (
        SELECT 1 FROM public.fights f
        WHERE f.fighter_a_id = fo.fighter_id
          AND f.fighter_b_id = fo.opponent_fighter_id
      )
    ORDER BY fo.offered_at_week, fo.id
  LOOP
    IF EXISTS (
      SELECT 1
      FROM public.fights booked
      JOIN public.events booked_event ON booked_event.id = booked.event_id
      WHERE booked.status = 'pending'
        AND booked_event.status = 'scheduled'
        AND v_offer.fighter_id IN (booked.fighter_a_id, booked.fighter_b_id)
    ) THEN
      UPDATE public.fight_offers
      SET status = 'declined'
      WHERE id = v_offer.id;
      CONTINUE;
    END IF;

    v_scheduled_week := GREATEST(v_offer.scheduled_week, v_current_tick + 1);
    v_event_id := NULL;

    SELECT e.id, e.name INTO v_event_id, v_event_name
    FROM public.events e
    WHERE e.promotion_id = v_offer.promotion_id
      AND e.scheduled_week = v_scheduled_week
      AND e.status = 'scheduled'
    ORDER BY e.id
    LIMIT 1;

    IF v_event_id IS NULL THEN
      SELECT p.name || ' #' || v_scheduled_week INTO v_event_name
      FROM public.promotions p WHERE p.id = v_offer.promotion_id;

      INSERT INTO public.events (promotion_id, name, scheduled_week, status)
      VALUES (v_offer.promotion_id, v_event_name, v_scheduled_week, 'scheduled')
      RETURNING id INTO v_event_id;
    END IF;

    INSERT INTO public.fights
      (event_id, fighter_a_id, fighter_b_id, weight_class, status)
    SELECT v_event_id, v_offer.fighter_id, v_offer.opponent_fighter_id,
           f.weight_class, 'pending'
    FROM public.fighters f
    WHERE f.id = v_offer.fighter_id;

    IF FOUND THEN
      UPDATE public.fight_offers
      SET event_id = v_event_id, scheduled_week = v_scheduled_week
      WHERE id = v_offer.id;

      UPDATE public.fight_offers
      SET status = 'declined'
      WHERE fighter_id = v_offer.fighter_id
        AND status = 'pending';
    END IF;
  END LOOP;
END;
$$;
