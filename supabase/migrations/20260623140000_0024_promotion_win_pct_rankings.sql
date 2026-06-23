/*
# Promotion win-% rankings, top-6 title challengers, ranked contract loyalty

- Rankings sorted by in-promotion fight win percentage.
- Title defenses pick a weighted-random challenger from ranks 1–6.
- Top-15 ranked fighters auto-renew contracts (tier-up offers excepted).
*/

CREATE OR REPLACE FUNCTION public.promotion_fighter_record(
  p_fighter_id uuid,
  p_promotion_id uuid
)
RETURNS TABLE (wins int, losses int, draws int, total int, win_pct numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER SET search_path = public
AS $$
  SELECT
    COUNT(*) FILTER (WHERE fi.winner_id = p_fighter_id)::int AS wins,
    COUNT(*) FILTER (WHERE fi.winner_id IS NOT NULL AND fi.winner_id <> p_fighter_id)::int AS losses,
    COUNT(*) FILTER (WHERE fi.winner_id IS NULL)::int AS draws,
    COUNT(*)::int AS total,
    CASE
      WHEN COUNT(*) > 0 THEN
        COUNT(*) FILTER (WHERE fi.winner_id = p_fighter_id)::numeric / COUNT(*)::numeric
      ELSE 0
    END AS win_pct
  FROM public.fights fi
  JOIN public.events e ON e.id = fi.event_id AND e.promotion_id = p_promotion_id
  WHERE fi.status = 'completed'
    AND p_fighter_id IN (fi.fighter_a_id, fi.fighter_b_id);
$$;

CREATE OR REPLACE FUNCTION public.fighter_is_promotion_ranked(
  p_fighter_id uuid,
  p_promotion_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.rankings r
    JOIN public.fighters f ON f.id = p_fighter_id
    WHERE r.fighter_id = p_fighter_id
      AND r.promotion_id = p_promotion_id
      AND r.weight_class = f.weight_class
      AND r.rank_position <= 15
  );
$$;

CREATE OR REPLACE FUNCTION public.renew_ranked_fighter_contract(
  p_fighter_id uuid,
  p_promotion_id uuid,
  p_tick int
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_contract_id uuid;
  v_purse bigint;
BEGIN
  IF public.fighter_holds_promotion_title(p_fighter_id, p_promotion_id) THEN
    RETURN;
  END IF;

  IF NOT public.fighter_is_promotion_ranked(p_fighter_id, p_promotion_id) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.contracts c
    WHERE c.fighter_id = p_fighter_id
      AND c.promotion_id = p_promotion_id
      AND c.status = 'active'
      AND c.fights_remaining > 0
  ) THEN
    UPDATE public.fighters
    SET promotion_id = p_promotion_id
    WHERE id = p_fighter_id
      AND promotion_id IS DISTINCT FROM p_promotion_id;
    RETURN;
  END IF;

  SELECT c.id INTO v_contract_id
  FROM public.contracts c
  WHERE c.fighter_id = p_fighter_id
    AND c.promotion_id = p_promotion_id
  ORDER BY c.signed_week DESC, c.id DESC
  LIMIT 1;

  v_purse := GREATEST(
    1000,
    (SELECT tier FROM public.promotions WHERE id = p_promotion_id) * 5000
  );

  IF v_contract_id IS NULL THEN
    INSERT INTO public.contracts (
      fighter_id, promotion_id, signed_week, expires_week,
      purse_per_fight, status, contracted_fights, fights_remaining
    ) VALUES (
      p_fighter_id, p_promotion_id, p_tick, 2147483647,
      v_purse, 'active', 4, 4
    );
  ELSE
    UPDATE public.contracts
    SET status = 'active',
        fights_remaining = 4,
        contracted_fights = contracted_fights + 4,
        signed_week = p_tick,
        purse_per_fight = COALESCE(purse_per_fight, v_purse)
    WHERE id = v_contract_id;
  END IF;

  UPDATE public.fighters
  SET promotion_id = p_promotion_id
  WHERE id = p_fighter_id
    AND promotion_id IS DISTINCT FROM p_promotion_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.pick_weighted_title_challenger(
  p_promotion_id uuid,
  p_weight_class text,
  p_exclude_fighter_id uuid,
  p_require_unmanaged boolean DEFAULT false
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER SET search_path = public
AS $$
  SELECT r.fighter_id
  FROM public.rankings r
  JOIN public.fighters f ON f.id = r.fighter_id
  WHERE r.promotion_id = p_promotion_id
    AND r.weight_class = p_weight_class
    AND r.rank_position BETWEEN 1 AND 6
    AND r.fighter_id IS DISTINCT FROM p_exclude_fighter_id
    AND f.retired = false
    AND f.promotion_id = p_promotion_id
    AND NOT public.fighter_holds_promotion_title(f.id, p_promotion_id)
    AND (NOT p_require_unmanaged OR f.gym_id IS NULL)
    AND NOT EXISTS (
      SELECT 1
      FROM public.fights pf
      JOIN public.events pe ON pe.id = pf.event_id
      WHERE pf.status = 'pending'
        AND pe.status = 'scheduled'
        AND f.id IN (pf.fighter_a_id, pf.fighter_b_id)
    )
  ORDER BY random() * (7 - r.rank_position) DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.consume_promotion_contract_fight()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_promotion_id uuid;
  v_tick int;
  v_fighter_id uuid;
BEGIN
  IF NEW.status <> 'completed' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'completed' THEN
    RETURN NEW;
  END IF;

  SELECT promotion_id INTO v_promotion_id
  FROM public.events WHERE id = NEW.event_id;

  SELECT tick_count INTO v_tick FROM public.world_state WHERE id = 1;

  UPDATE public.contracts
  SET completed_fights = completed_fights + 1,
      fights_remaining = GREATEST(0, fights_remaining - 1)
  WHERE status = 'active'
    AND promotion_id = v_promotion_id
    AND fighter_id IN (NEW.fighter_a_id, NEW.fighter_b_id);

  FOR v_fighter_id IN
    SELECT unnest(ARRAY[NEW.fighter_a_id, NEW.fighter_b_id])
  LOOP
    IF public.fighter_holds_promotion_title(v_fighter_id, v_promotion_id)
       AND EXISTS (
         SELECT 1 FROM public.contracts c
         WHERE c.fighter_id = v_fighter_id
           AND c.promotion_id = v_promotion_id
           AND c.fights_remaining = 0
       ) THEN
      PERFORM public.renew_champion_contract(v_fighter_id, v_promotion_id, v_tick);
    ELSIF public.fighter_is_promotion_ranked(v_fighter_id, v_promotion_id)
       AND EXISTS (
         SELECT 1 FROM public.contracts c
         WHERE c.fighter_id = v_fighter_id
           AND c.promotion_id = v_promotion_id
           AND c.fights_remaining = 0
       ) THEN
      PERFORM public.renew_ranked_fighter_contract(v_fighter_id, v_promotion_id, v_tick);
    ELSE
      UPDATE public.contracts
      SET status = 'expired'
      WHERE status = 'active'
        AND promotion_id = v_promotion_id
        AND fighter_id = v_fighter_id
        AND fights_remaining = 0;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_offer_promotion_exclusivity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_contract_promotion uuid;
  v_contract_tier int;
  v_contract_remaining int;
  v_offer_tier int;
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
        AND NOT public.fighter_holds_promotion_title(id, NEW.promotion_id)
    ) THEN
      SELECT id INTO v_replacement_opponent
      FROM public.fighters
      WHERE promotion_id = NEW.promotion_id
        AND gym_id IS NULL
        AND retired = false
        AND weight_class = v_weight_class
        AND id <> NEW.fighter_id
        AND ABS(current_skill - v_skill) <= 15
        AND NOT public.fighter_holds_promotion_title(id, NEW.promotion_id)
      ORDER BY random()
      LIMIT 1;

      IF v_replacement_opponent IS NULL THEN
        RETURN NULL;
      END IF;

      NEW.opponent_fighter_id := v_replacement_opponent;
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.promotion_id <> v_contract_promotion THEN
    SELECT tier INTO v_offer_tier FROM public.promotions WHERE id = NEW.promotion_id;
    IF v_offer_tier IS NULL OR v_offer_tier <= v_contract_tier THEN
      RETURN NULL;
    END IF;

    NEW.offer_kind := 'contract';
    NEW.contract_fights := COALESCE(NULLIF(NEW.contract_fights, 0), 4);
    NEW.purse := v_offer_tier * 5000 + GREATEST(0, (v_skill - 50) * 200);

    IF NOT EXISTS (
      SELECT 1
      FROM public.fighters
      WHERE id = NEW.opponent_fighter_id
        AND promotion_id = NEW.promotion_id
        AND retired = false
        AND weight_class = v_weight_class
        AND NOT public.fighter_holds_promotion_title(id, NEW.promotion_id)
    ) THEN
      SELECT id INTO v_replacement_opponent
      FROM public.fighters
      WHERE promotion_id = NEW.promotion_id
        AND gym_id IS NULL
        AND retired = false
        AND weight_class = v_weight_class
        AND id <> NEW.fighter_id
        AND ABS(current_skill - v_skill) <= 15
        AND NOT public.fighter_holds_promotion_title(id, NEW.promotion_id)
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
      AND NOT public.fighter_holds_promotion_title(id, v_contract_promotion)
  ) THEN
    SELECT id INTO v_replacement_opponent
    FROM public.fighters
    WHERE promotion_id = v_contract_promotion
      AND gym_id IS NULL
      AND retired = false
      AND weight_class = v_weight_class
      AND id <> NEW.fighter_id
      AND ABS(current_skill - v_skill) <= 15
      AND NOT public.fighter_holds_promotion_title(id, v_contract_promotion)
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
  v_championship_id uuid;
  v_is_title_fight boolean := false;
  v_tier_up boolean := false;
  v_current_tier int;
  v_offer_tier int;
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
    SELECT tier INTO v_current_tier FROM public.promotions WHERE id = v_contract.promotion_id;
    SELECT tier INTO v_offer_tier FROM public.promotions WHERE id = v_offer.promotion_id;
    IF v_offer_tier IS NULL OR v_offer_tier <= v_current_tier THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'This fighter is exclusively contracted to another promotion.'
      );
    END IF;
    UPDATE public.contracts SET status = 'expired' WHERE id = v_contract.id;
    v_has_contract := false;
    v_tier_up := true;
  END IF;

  IF v_offer.offer_kind = 'fight' AND NOT v_has_contract THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'This fight offer requires an active promotion contract.'
    );
  END IF;

  SELECT c.id INTO v_championship_id
  FROM public.championships c
  WHERE c.current_champion_fighter_id = v_offer.fighter_id
    AND c.promotion_id = v_offer.promotion_id
  LIMIT 1;

  v_is_title_fight := v_championship_id IS NOT NULL;

  IF public.fighter_holds_promotion_title(v_offer.opponent_fighter_id, v_offer.promotion_id)
     AND NOT v_is_title_fight THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'The champion can only be booked for a title fight.'
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
    UPDATE public.fighters
    SET promotion_id = v_offer.promotion_id
    WHERE id = v_offer.fighter_id;
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
    v_event_name := public.next_promotion_event_name(v_offer.promotion_id);
    INSERT INTO public.events (promotion_id, name, scheduled_week, status)
    VALUES (v_offer.promotion_id, v_event_name, v_offer.scheduled_week, 'scheduled')
    RETURNING id INTO v_event_id;
  END IF;

  INSERT INTO public.fights
    (event_id, fighter_a_id, fighter_b_id, weight_class, is_title_fight, championship_id, status)
  SELECT v_event_id, v_offer.fighter_id, v_offer.opponent_fighter_id,
         f.weight_class, v_is_title_fight, v_championship_id, 'pending'
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
        WHEN v_is_title_fight THEN
          'Title fight booked on ' || v_event_name || '.'
        WHEN v_tier_up THEN
          'Tier-up contract accepted and first fight booked on ' || v_event_name ||
          '. Exclusive promotion contract: ' || v_contract_fights || ' fight' ||
          CASE WHEN v_contract_fights = 1 THEN '' ELSE 's' END || '.'
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

CREATE OR REPLACE FUNCTION public.seed_championships_and_rankings()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_promo RECORD;
  v_wc RECORD;
  v_fighter RECORD;
  v_rank int;
  v_week int;
BEGIN
  v_week := public.get_current_week();
  FOR v_promo IN SELECT id FROM public.promotions LOOP
    FOR v_wc IN SELECT name FROM public.weight_classes ORDER BY "order" LOOP
      INSERT INTO public.championships (promotion_id, weight_class, current_champion_fighter_id)
      VALUES (v_promo.id, v_wc.name, NULL)
      ON CONFLICT (promotion_id, weight_class) DO NOTHING;

      v_rank := 1;
      FOR v_fighter IN
        SELECT f.id
        FROM public.fighters f
        LEFT JOIN LATERAL public.promotion_fighter_record(f.id, v_promo.id) rec ON true
        WHERE f.weight_class = v_wc.name
          AND f.retired = false
          AND (f.promotion_id = v_promo.id OR (f.gym_id IS NULL AND f.promotion_id IS NULL))
        ORDER BY rec.win_pct DESC, rec.wins DESC, f.current_skill DESC, f.popularity DESC
        LIMIT 15
      LOOP
        INSERT INTO public.rankings (promotion_id, weight_class, fighter_id, rank_position, updated_at_week)
        VALUES (v_promo.id, v_wc.name, v_fighter.id, v_rank, v_week)
        ON CONFLICT (promotion_id, weight_class, rank_position)
        DO UPDATE SET fighter_id = EXCLUDED.fighter_id, updated_at_week = EXCLUDED.updated_at_week;
        v_rank := v_rank + 1;
      END LOOP;
    END LOOP;
  END LOOP;
  RETURN 1;
END;
$$;

DROP FUNCTION IF EXISTS public.advance_week();

CREATE OR REPLACE FUNCTION public.advance_week()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_world RECORD;
  v_new_week int;
  v_new_year int;
  v_new_month int;
  v_new_day int;
  v_new_tick int;
  v_retired_count int := 0;
  v_events_processed int := 0;
  v_fights_simulated int := 0;
  v_offers_generated int := 0;
  v_promo RECORD;
  v_wc RECORD;
  v_fighter RECORD;
  v_rank int;
  v_events_to_process RECORD;
  v_purse_base bigint;
  v_total_purses_paid bigint := 0;
  v_gym RECORD;
  v_offer_count int;
  v_opp uuid;
  v_signed_count int := 0;
  v_champion RECORD;
  v_winner_id uuid;
  v_method text;
  v_round int;
  v_old_champ_id uuid;
  v_fighter_a uuid;
  v_fighter_b uuid;
  v_fighter_a_skill int;
  v_fighter_b_skill int;
  v_rand float;
  v_a_strength int;
  v_b_strength int;
  v_commentary jsonb;
  v_count int;
  v_promo_offer_id uuid;
  v_promo_offer_tier int;
  v_contender_1 uuid;
  v_contender_2 uuid;
  v_event_has_title_fight boolean;
  v_new_offer_id uuid;
  v_championship_id uuid;
  v_current_tier int;
  v_ranked RECORD;
  v_contract_promo uuid;
BEGIN
  SELECT * INTO v_world FROM public.world_state WHERE id = 1 FOR UPDATE;
  IF v_world.is_paused THEN
    RETURN jsonb_build_object('status','paused');
  END IF;

  v_new_tick := v_world.tick_count + 1;
  v_new_year  := floor(v_new_tick / 48) + 1;
  v_new_month := floor((v_new_tick % 48) / 4) + 1;
  v_new_week  := (v_new_tick % 4) + 1;
  v_new_day   := 1;

  UPDATE public.world_state
  SET current_week = v_new_week, current_month = v_new_month,
      current_year = v_new_year, current_day = v_new_day,
      tick_count = v_new_tick, last_tick_at = now()
  WHERE id = 1;

  UPDATE public.fighters SET age = age + 1
  WHERE (v_new_tick % 48) = 0 AND retired = false;

  UPDATE public.fighters
  SET
    boxing = GREATEST(1, LEAST(100, boxing + CASE WHEN boxing < potential THEN floor(random() * 2)::int ELSE 0 END)),
    kickboxing = GREATEST(1, LEAST(100, kickboxing + CASE WHEN kickboxing < potential THEN floor(random() * 2)::int ELSE 0 END)),
    wrestling = GREATEST(1, LEAST(100, wrestling + CASE WHEN wrestling < potential THEN floor(random() * 2)::int ELSE 0 END)),
    bjj = GREATEST(1, LEAST(100, bjj + CASE WHEN bjj < potential THEN floor(random() * 2)::int ELSE 0 END)),
    cardio = GREATEST(1, LEAST(100, cardio + CASE WHEN cardio < potential THEN floor(random() * 2)::int ELSE 0 END)),
    fight_iq = GREATEST(1, LEAST(100, fight_iq + CASE WHEN fight_iq < potential THEN floor(random() * 2)::int ELSE 0 END)),
    athleticism = GREATEST(1, LEAST(100, athleticism + CASE WHEN athleticism < potential THEN floor(random() * 2)::int ELSE 0 END)),
    current_skill = GREATEST(1, LEAST(100, current_skill + CASE WHEN current_skill < potential THEN floor(random() * 2)::int ELSE 0 END)),
    popularity = GREATEST(0, LEAST(100, popularity + CASE WHEN popularity < current_skill THEN floor(random() * 3)::int ELSE 0 END))
  WHERE retired = false;

  UPDATE public.fighters
  SET retired = true, career_status = 'retired'
  WHERE retired = false AND (age >= 45 OR (age >= 40 AND current_skill < 55));
  GET DIAGNOSTICS v_retired_count = ROW_COUNT;

  FOR v_promo IN SELECT id, tier FROM public.promotions WHERE owner_kind = 'ai' LOOP
    SELECT count(*) INTO v_count FROM public.fighters
    WHERE promotion_id = v_promo.id AND retired = false;
    IF v_count < (v_promo.tier * 25 + 15) THEN
      FOR v_fighter IN
        SELECT id FROM public.fighters
        WHERE gym_id IS NULL AND promotion_id IS NULL AND retired = false
          AND NOT public.fighter_holds_promotion_title(id)
        ORDER BY current_skill DESC
        LIMIT LEAST(10, (v_promo.tier * 25 + 15) - v_count)
      LOOP
        UPDATE public.fighters SET promotion_id = v_promo.id WHERE id = v_fighter.id;
        INSERT INTO public.contracts (fighter_id, promotion_id, signed_week, expires_week, purse_per_fight, status)
        VALUES (v_fighter.id, v_promo.id, v_new_tick,
          v_new_tick + 24 + floor(random() * 36)::int,
          GREATEST(1000, v_promo.tier * 5000 + floor(random() * 5000)::int),
          'active');
        v_signed_count := v_signed_count + 1;
      END LOOP;
    END IF;
  END LOOP;

  FOR v_promo IN SELECT id, tier, fan_base, name FROM public.promotions WHERE owner_kind = 'ai' LOOP
    SELECT count(*) INTO v_count FROM public.events
    WHERE promotion_id = v_promo.id AND status = 'scheduled' AND scheduled_week > v_new_tick;
    IF v_count < 1 THEN
      INSERT INTO public.events (promotion_id, name, scheduled_week, status)
      VALUES (v_promo.id, public.next_promotion_event_name(v_promo.id),
        v_new_tick + 4 + floor(random() * 2)::int, 'scheduled');
    END IF;
  END LOOP;

  -- PLACEHOLDER_EVENTS_LOOP
  FOR v_events_to_process IN
    SELECT e.id, e.promotion_id, e.name FROM public.events e
    WHERE e.status = 'scheduled' AND e.scheduled_week <= v_new_tick
  LOOP
    v_events_processed := v_events_processed + 1;
    v_purse_base := (SELECT tier FROM public.promotions WHERE id = v_events_to_process.promotion_id) * 5000;

    v_event_has_title_fight := EXISTS (
      SELECT 1 FROM public.fights f
      WHERE f.event_id = v_events_to_process.id AND f.is_title_fight = true
    );

    FOR v_champion IN
      SELECT c.id AS champ_id, c.weight_class, c.current_champion_fighter_id AS champ_fighter, c.promotion_id
      FROM public.championships c WHERE c.promotion_id = v_events_to_process.promotion_id
    LOOP
      IF v_event_has_title_fight THEN EXIT; END IF;

      v_opp := NULL;
      v_winner_id := NULL;
      v_fighter_a := NULL;
      v_fighter_b := NULL;
      v_old_champ_id := v_champion.champ_fighter;

      IF EXISTS (
        SELECT 1 FROM public.fights f
        WHERE f.event_id = v_events_to_process.id
          AND f.weight_class = v_champion.weight_class
          AND (f.is_title_fight = true OR f.status = 'pending')
      ) THEN CONTINUE; END IF;

      IF v_champion.champ_fighter IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.fighters
        WHERE id = v_champion.champ_fighter AND gym_id IS NOT NULL
      ) AND NOT EXISTS (
        SELECT 1 FROM public.fights f
        WHERE f.event_id = v_events_to_process.id
          AND f.status = 'pending'
          AND v_champion.champ_fighter IN (f.fighter_a_id, f.fighter_b_id)
      ) THEN CONTINUE; END IF;

      IF v_champion.champ_fighter IS NULL THEN
        IF random() < 0.6 THEN
          v_contender_1 := NULL; v_contender_2 := NULL;
          SELECT r.fighter_id INTO v_contender_1
          FROM public.rankings r
          JOIN public.fighters f ON f.id = r.fighter_id
          WHERE r.promotion_id = v_champion.promotion_id AND r.weight_class = v_champion.weight_class
            AND f.gym_id IS NULL AND f.promotion_id = v_champion.promotion_id
            AND NOT public.fighter_holds_promotion_title(f.id, v_champion.promotion_id)
          ORDER BY r.rank_position ASC LIMIT 1 OFFSET 0;
          SELECT r.fighter_id INTO v_contender_2
          FROM public.rankings r
          JOIN public.fighters f ON f.id = r.fighter_id
          WHERE r.promotion_id = v_champion.promotion_id AND r.weight_class = v_champion.weight_class
            AND f.gym_id IS NULL AND f.promotion_id = v_champion.promotion_id
            AND r.fighter_id IS DISTINCT FROM v_contender_1
            AND NOT public.fighter_holds_promotion_title(f.id, v_champion.promotion_id)
          ORDER BY r.rank_position ASC LIMIT 1 OFFSET 0;

          IF v_contender_1 IS NULL OR v_contender_2 IS NULL THEN
            SELECT id INTO v_contender_1 FROM public.fighters
            WHERE promotion_id = v_champion.promotion_id AND weight_class = v_champion.weight_class
              AND retired = false AND gym_id IS NULL
              AND NOT public.fighter_holds_promotion_title(id, v_champion.promotion_id)
            ORDER BY current_skill DESC, popularity DESC LIMIT 1 OFFSET 0;
            SELECT id INTO v_contender_2 FROM public.fighters
            WHERE promotion_id = v_champion.promotion_id AND weight_class = v_champion.weight_class
              AND retired = false AND gym_id IS NULL AND id IS DISTINCT FROM v_contender_1
              AND NOT public.fighter_holds_promotion_title(id, v_champion.promotion_id)
            ORDER BY current_skill DESC, popularity DESC LIMIT 1 OFFSET 0;
          END IF;

          IF v_contender_1 IS NOT NULL AND v_contender_2 IS NOT NULL THEN
            v_fighter_a := v_contender_1;
            v_fighter_b := v_contender_2;
            v_fighter_a_skill := (SELECT current_skill FROM public.fighters WHERE id = v_fighter_a);
            v_fighter_b_skill := (SELECT current_skill FROM public.fighters WHERE id = v_fighter_b);
            v_a_strength := v_fighter_a_skill + floor(random() * 25)::int;
            v_b_strength := v_fighter_b_skill + floor(random() * 25)::int;
            IF v_a_strength >= v_b_strength THEN v_winner_id := v_fighter_a; ELSE v_winner_id := v_fighter_b; END IF;
          END IF;
        END IF;
      ELSE
        IF random() < 0.4 THEN
          v_opp := public.pick_weighted_title_challenger(
            v_champion.promotion_id,
            v_champion.weight_class,
            v_champion.champ_fighter,
            true
          );

          IF v_opp IS NULL THEN
            SELECT id INTO v_opp FROM public.fighters
            WHERE promotion_id = v_champion.promotion_id AND weight_class = v_champion.weight_class
              AND retired = false AND gym_id IS NULL AND id <> v_champion.champ_fighter
              AND NOT public.fighter_holds_promotion_title(id, v_champion.promotion_id)
            ORDER BY current_skill DESC, popularity DESC LIMIT 1;
          END IF;

          IF v_opp IS NOT NULL THEN
            v_fighter_a := v_champion.champ_fighter;
            v_fighter_b := v_opp;
            v_fighter_a_skill := (SELECT current_skill FROM public.fighters WHERE id = v_fighter_a);
            v_fighter_b_skill := (SELECT current_skill FROM public.fighters WHERE id = v_fighter_b);
            v_a_strength := v_fighter_a_skill + floor(random() * 25)::int;
            v_b_strength := v_fighter_b_skill + floor(random() * 25)::int;
            IF v_a_strength >= v_b_strength THEN v_winner_id := v_fighter_a; ELSE v_winner_id := v_fighter_b; END IF;
          END IF;
        END IF;
      END IF;

      IF v_winner_id IS NOT NULL AND v_fighter_a IS NOT NULL AND v_fighter_b IS NOT NULL THEN
        v_rand := random();
        IF v_rand < 0.30 THEN v_method := 'KO';
        ELSIF v_rand < 0.55 THEN v_method := 'TKO';
        ELSIF v_rand < 0.75 THEN v_method := 'Submission';
        ELSE v_method := 'Decision';
        END IF;
        v_round := CASE WHEN v_method = 'Decision' THEN 5 ELSE 1 + floor(random() * 5)::int END;

        v_commentary := jsonb_build_array(
          CASE WHEN v_old_champ_id IS NULL THEN
            'Vacant title fight: ' || (SELECT name FROM public.fighters WHERE id = v_fighter_a) ||
            ' battles ' || (SELECT name FROM public.fighters WHERE id = v_fighter_b) || ' for the championship.'
          ELSE
            'Championship main event: ' || (SELECT name FROM public.fighters WHERE id = v_old_champ_id) ||
            ' defends against ' || (SELECT name FROM public.fighters WHERE id = v_opp) || '.'
          END,
          'Round ' || v_round || ' action.',
          CASE v_method
            WHEN 'Submission' THEN 'Submission locked in. New drama at the top.'
            WHEN 'Decision' THEN 'The judges render their scorecards.'
            ELSE 'A decisive finish ends the contest.' END,
          v_method || ' victory for ' || (SELECT name FROM public.fighters WHERE id = v_winner_id) || '.'
        );

        INSERT INTO public.fights (event_id, fighter_a_id, fighter_b_id, winner_id, method, round,
          commentary, weight_class, is_title_fight, championship_id, status, completed_at_week)
        VALUES (v_events_to_process.id, v_fighter_a, v_fighter_b, v_winner_id, v_method, v_round,
          v_commentary, v_champion.weight_class, true, v_champion.champ_id, 'completed', v_new_tick);

        UPDATE public.fighters SET wins = wins + 1 WHERE id = v_winner_id;
        UPDATE public.fighters SET losses = losses + 1
          WHERE id IN (v_fighter_a, v_fighter_b) AND id <> v_winner_id;

        IF v_old_champ_id IS NOT NULL AND v_winner_id = v_old_champ_id THEN
          UPDATE public.title_history SET defenses = defenses + 1
          WHERE championship_id = v_champion.champ_id AND fighter_id = v_winner_id AND lost_at_week IS NULL;

          INSERT INTO public.news_items (week, type, title, body, fighter_id, promotion_id)
          VALUES (v_new_tick, 'title_defense',
            (SELECT name FROM public.fighters WHERE id = v_winner_id) || ' retains the title',
            (SELECT name FROM public.fighters WHERE id = v_winner_id) || ' successfully defended the championship at ' || v_events_to_process.name || ' via ' || v_method || ' in round ' || v_round || '.',
            v_winner_id, v_champion.promotion_id);
        ELSE
          IF v_old_champ_id IS NOT NULL THEN
            UPDATE public.title_history SET lost_at_week = v_new_tick
            WHERE championship_id = v_champion.champ_id AND fighter_id = v_old_champ_id AND lost_at_week IS NULL;
            UPDATE public.fighters SET career_status = 'contender' WHERE id = v_old_champ_id;
          END IF;

          UPDATE public.championships SET current_champion_fighter_id = v_winner_id WHERE id = v_champion.champ_id;
          INSERT INTO public.title_history (championship_id, fighter_id, won_at_week, defenses)
          VALUES (v_champion.champ_id, v_winner_id, v_new_tick, 0);
          UPDATE public.fighters SET career_status = 'champion' WHERE id = v_winner_id;

          UPDATE public.gyms SET champions_produced = champions_produced + 1, reputation = reputation + 25
          WHERE id = (SELECT gym_id FROM public.fighters WHERE id = v_winner_id) AND id IS NOT NULL;

          INSERT INTO public.news_items (week, type, title, body, fighter_id, promotion_id)
          VALUES (v_new_tick, 'champion_crowned',
            (SELECT name FROM public.fighters WHERE id = v_winner_id) || ' is the NEW champion!',
            CASE WHEN v_old_champ_id IS NULL THEN
              (SELECT name FROM public.fighters WHERE id = v_winner_id) || ' captures the vacant ' || v_champion.weight_class || ' title at ' || v_events_to_process.name || '.'
            ELSE
              'A new era begins as ' || (SELECT name FROM public.fighters WHERE id = v_winner_id) ||
              ' defeats ' || (SELECT name FROM public.fighters WHERE id = v_old_champ_id) ||
              ' for the ' || v_champion.weight_class || ' title at ' || v_events_to_process.name || '.'
            END,
            v_winner_id, v_champion.promotion_id);
        END IF;
        v_fights_simulated := v_fights_simulated + 1;
        v_event_has_title_fight := true;
        EXIT;
      END IF;
    END LOOP;

    -- PLACEHOLDER_UNDERCARD_LOOP
    FOR v_wc IN SELECT name FROM public.weight_classes ORDER BY "order" LOOP
      SELECT count(*) INTO v_count FROM public.fights WHERE event_id = v_events_to_process.id AND weight_class = v_wc.name;
      IF v_count > 0 THEN CONTINUE; END IF;

      v_fighter_a := NULL; v_fighter_b := NULL;
      SELECT id INTO v_fighter_a FROM public.fighters
      WHERE promotion_id = v_events_to_process.promotion_id AND weight_class = v_wc.name
        AND retired = false AND gym_id IS NULL
        AND NOT public.fighter_holds_promotion_title(id, v_events_to_process.promotion_id)
      ORDER BY random() LIMIT 1;

      IF v_fighter_a IS NOT NULL THEN
        SELECT id INTO v_fighter_b FROM public.fighters
        WHERE promotion_id = v_events_to_process.promotion_id AND weight_class = v_wc.name
          AND retired = false AND id <> v_fighter_a AND gym_id IS NULL
          AND NOT public.fighter_holds_promotion_title(id, v_events_to_process.promotion_id)
        ORDER BY random() LIMIT 1;
      END IF;

      IF v_fighter_a IS NOT NULL AND v_fighter_b IS NOT NULL THEN
        v_fighter_a_skill := (SELECT current_skill FROM public.fighters WHERE id = v_fighter_a);
        v_fighter_b_skill := (SELECT current_skill FROM public.fighters WHERE id = v_fighter_b);
        v_a_strength := v_fighter_a_skill + floor(random() * 25)::int;
        v_b_strength := v_fighter_b_skill + floor(random() * 25)::int;
        IF v_a_strength >= v_b_strength THEN v_winner_id := v_fighter_a; ELSE v_winner_id := v_fighter_b; END IF;

        v_rand := random();
        IF v_rand < 0.28 THEN v_method := 'KO';
        ELSIF v_rand < 0.50 THEN v_method := 'TKO';
        ELSIF v_rand < 0.72 THEN v_method := 'Submission';
        ELSE v_method := 'Decision';
        END IF;
        v_round := CASE WHEN v_method = 'Decision' THEN 3 ELSE 1 + floor(random() * 3)::int END;

        v_commentary := jsonb_build_array(
          'Round ' || v_round || ': the fight begins.',
          (SELECT name FROM public.fighters WHERE id = v_fighter_a) || ' and ' ||
            (SELECT name FROM public.fighters WHERE id = v_fighter_b) || ' touch gloves.',
          CASE WHEN v_method = 'Submission' THEN 'Grappling exchange leads to a submission attempt.'
               WHEN v_method IN ('KO','TKO') THEN 'A heavy strike lands flush.'
               ELSE 'The fight goes the distance.' END,
          v_method || ' victory for ' || (SELECT name FROM public.fighters WHERE id = v_winner_id) || '.'
        );

        INSERT INTO public.fights (event_id, fighter_a_id, fighter_b_id, winner_id, method, round,
          commentary, weight_class, is_title_fight, championship_id, status, completed_at_week)
        SELECT v_events_to_process.id, v_fighter_a, v_fighter_b, v_winner_id, v_method, v_round,
          v_commentary, v_wc.name, false, NULL, 'completed', v_new_tick
        WHERE NOT EXISTS (SELECT 1 FROM public.fights WHERE event_id = v_events_to_process.id AND weight_class = v_wc.name);

        UPDATE public.fighters SET wins = wins + 1,
          ko_wins = ko_wins + (CASE WHEN v_method IN ('KO','TKO') AND v_winner_id = v_fighter_a THEN 1 ELSE 0 END),
          sub_wins = sub_wins + (CASE WHEN v_method = 'Submission' AND v_winner_id = v_fighter_a THEN 1 ELSE 0 END),
          dec_wins = dec_wins + (CASE WHEN v_method = 'Decision' AND v_winner_id = v_fighter_a THEN 1 ELSE 0 END)
        WHERE id = v_fighter_a;

        UPDATE public.fighters SET wins = wins + 1,
          ko_wins = ko_wins + (CASE WHEN v_method IN ('KO','TKO') AND v_winner_id = v_fighter_b THEN 1 ELSE 0 END),
          sub_wins = sub_wins + (CASE WHEN v_method = 'Submission' AND v_winner_id = v_fighter_b THEN 1 ELSE 0 END),
          dec_wins = dec_wins + (CASE WHEN v_method = 'Decision' AND v_winner_id = v_fighter_b THEN 1 ELSE 0 END)
        WHERE id = v_fighter_b;

        UPDATE public.fighters SET losses = losses + 1 WHERE id = v_fighter_a AND id <> v_winner_id;
        UPDATE public.fighters SET losses = losses + 1 WHERE id = v_fighter_b AND id <> v_winner_id;

        v_fights_simulated := v_fights_simulated + 1;

        UPDATE public.gyms SET cash = cash + v_purse_base
        WHERE id IN (
          SELECT gym_id FROM public.fighters
          WHERE id IN (v_fighter_a, v_fighter_b) AND gym_id IS NOT NULL
        );
        v_total_purses_paid := v_total_purses_paid + v_purse_base * 2;
      END IF;
    END LOOP;

    UPDATE public.events SET status = 'completed', completed_at_week = v_new_tick WHERE id = v_events_to_process.id;

    INSERT INTO public.news_items (week, type, title, body, promotion_id)
    VALUES (v_new_tick, 'event_result', v_events_to_process.name || ' results are in',
      v_events_to_process.name || ' has concluded. View full results on the Events page.',
      v_events_to_process.promotion_id);
  END LOOP;

  -- PLACEHOLDER_RANKINGS_LOOP
  FOR v_promo IN SELECT id FROM public.promotions LOOP
    FOR v_wc IN SELECT name FROM public.weight_classes ORDER BY "order" LOOP
      v_rank := 1;
      FOR v_fighter IN
        SELECT f.id
        FROM public.fighters f
        LEFT JOIN LATERAL public.promotion_fighter_record(f.id, v_promo.id) rec ON true
        WHERE f.weight_class = v_wc.name
          AND f.retired = false
          AND f.promotion_id = v_promo.id
        ORDER BY rec.win_pct DESC, rec.wins DESC, f.current_skill DESC, f.popularity DESC
        LIMIT 15
      LOOP
        INSERT INTO public.rankings (promotion_id, weight_class, fighter_id, rank_position, updated_at_week)
        VALUES (v_promo.id, v_wc.name, v_fighter.id, v_rank, v_new_tick)
        ON CONFLICT (promotion_id, weight_class, rank_position)
        DO UPDATE SET fighter_id = EXCLUDED.fighter_id, updated_at_week = EXCLUDED.updated_at_week;
        v_rank := v_rank + 1;
      END LOOP;
    END LOOP;
  END LOOP;

  -- PLACEHOLDER_OFFERS_LOOP
  FOR v_gym IN SELECT id, reputation, tier FROM public.gyms LOOP
    FOR v_fighter IN
      SELECT id, weight_class, current_skill FROM public.fighters
      WHERE gym_id = v_gym.id AND retired = false
    LOOP
      IF EXISTS (
        SELECT 1
        FROM public.fights f
        JOIN public.events e ON e.id = f.event_id
        WHERE f.status = 'pending' AND e.status = 'scheduled'
          AND v_fighter.id IN (f.fighter_a_id, f.fighter_b_id)
      ) THEN CONTINUE; END IF;

      SELECT c.id, c.promotion_id INTO v_championship_id, v_promo_offer_id
      FROM public.championships c
      WHERE c.current_champion_fighter_id = v_fighter.id
      LIMIT 1;

      IF v_championship_id IS NOT NULL THEN
        IF random() < LEAST(0.5, (v_fighter.current_skill + v_gym.reputation) / 250.0) THEN
          SELECT count(*) INTO v_offer_count FROM public.fight_offers
          WHERE gym_id = v_gym.id AND status = 'pending' AND fighter_id = v_fighter.id;
          IF v_offer_count < 3 THEN
            SELECT tier INTO v_promo_offer_tier FROM public.promotions WHERE id = v_promo_offer_id;
            v_opp := public.pick_weighted_title_challenger(
              v_promo_offer_id,
              v_fighter.weight_class,
              v_fighter.id,
              true
            );

            IF v_opp IS NULL THEN
              SELECT id INTO v_opp
              FROM public.fighters opp
              WHERE opp.promotion_id = v_promo_offer_id
                AND opp.gym_id IS NULL
                AND opp.weight_class = v_fighter.weight_class
                AND opp.retired = false
                AND opp.id <> v_fighter.id
                AND NOT public.fighter_holds_promotion_title(opp.id, v_promo_offer_id)
                AND NOT EXISTS (
                  SELECT 1
                  FROM public.fights pf
                  JOIN public.events pe ON pe.id = pf.event_id
                  WHERE pf.status = 'pending'
                    AND pe.status = 'scheduled'
                    AND opp.id IN (pf.fighter_a_id, pf.fighter_b_id)
                )
              ORDER BY opp.current_skill DESC, opp.popularity DESC
              LIMIT 1;
            END IF;

            IF v_opp IS NOT NULL THEN
              v_purse_base := v_promo_offer_tier * 5000 + GREATEST(0, (v_fighter.current_skill - 50) * 200);
              INSERT INTO public.fight_offers (gym_id, fighter_id, opponent_fighter_id, promotion_id, event_id,
                purse, scheduled_week, status, offered_at_week)
              VALUES (v_gym.id, v_fighter.id, v_opp, v_promo_offer_id, NULL,
                v_purse_base, v_new_tick + 4 + floor(random() * 2)::int, 'pending', v_new_tick)
              RETURNING id INTO v_new_offer_id;
              IF v_new_offer_id IS NOT NULL THEN v_offers_generated := v_offers_generated + 1; END IF;
            END IF;
          END IF;
        END IF;
        CONTINUE;
      END IF;

      IF random() < LEAST(0.4, (v_fighter.current_skill + v_gym.reputation) / 300.0) THEN
        SELECT count(*) INTO v_offer_count FROM public.fight_offers
        WHERE gym_id = v_gym.id AND status = 'pending' AND fighter_id = v_fighter.id;
        IF v_offer_count < 3 THEN
          v_promo_offer_id := NULL;
          v_promo_offer_tier := NULL;
          v_opp := NULL;
          v_current_tier := NULL;
          v_contract_promo := NULL;

          SELECT c.promotion_id, p.tier
          INTO v_contract_promo, v_promo_offer_tier
          FROM public.contracts c
          JOIN public.promotions p ON p.id = c.promotion_id
          WHERE c.fighter_id = v_fighter.id
            AND c.status = 'active'
          ORDER BY c.signed_week DESC, c.id DESC
          LIMIT 1;

          v_promo_offer_id := v_contract_promo;

          IF v_promo_offer_id IS NULL THEN
            SELECT id, tier INTO v_promo_offer_id, v_promo_offer_tier
            FROM public.promotions
            WHERE owner_kind = 'ai'
              AND tier >= GREATEST(1, v_gym.tier)
              AND tier <= v_gym.tier + 1
              AND EXISTS (
                SELECT 1 FROM public.fighters f
                WHERE f.promotion_id = promotions.id
                  AND f.gym_id IS NULL
                  AND f.retired = false
                  AND f.weight_class = v_fighter.weight_class
                  AND ABS(f.current_skill - v_fighter.current_skill) <= 15
                  AND NOT public.fighter_holds_promotion_title(f.id, promotions.id)
                  AND NOT EXISTS (
                    SELECT 1
                    FROM public.fights pf
                    JOIN public.events pe ON pe.id = pf.event_id
                    WHERE pf.status = 'pending'
                      AND pe.status = 'scheduled'
                      AND f.id IN (pf.fighter_a_id, pf.fighter_b_id)
                  )
              )
            ORDER BY random()
            LIMIT 1;
          END IF;

          IF v_promo_offer_id IS NOT NULL THEN
            SELECT id INTO v_opp
            FROM public.fighters opp
            WHERE opp.promotion_id = v_promo_offer_id
              AND opp.gym_id IS NULL
              AND opp.weight_class = v_fighter.weight_class
              AND opp.retired = false
              AND opp.id <> v_fighter.id
              AND ABS(opp.current_skill - v_fighter.current_skill) <= 15
              AND NOT public.fighter_holds_promotion_title(opp.id, v_promo_offer_id)
              AND NOT EXISTS (
                SELECT 1
                FROM public.fights pf
                JOIN public.events pe ON pe.id = pf.event_id
                WHERE pf.status = 'pending'
                  AND pe.status = 'scheduled'
                  AND opp.id IN (pf.fighter_a_id, pf.fighter_b_id)
              )
            ORDER BY random()
            LIMIT 1;

            IF v_opp IS NOT NULL THEN
              v_purse_base := v_promo_offer_tier * 5000 + GREATEST(0, (v_fighter.current_skill - 50) * 200);
              INSERT INTO public.fight_offers (gym_id, fighter_id, opponent_fighter_id, promotion_id, event_id,
                purse, scheduled_week, status, offered_at_week)
              VALUES (v_gym.id, v_fighter.id, v_opp, v_promo_offer_id, NULL,
                v_purse_base, v_new_tick + 4 + floor(random() * 2)::int, 'pending', v_new_tick)
              RETURNING id INTO v_new_offer_id;
              IF v_new_offer_id IS NOT NULL THEN v_offers_generated := v_offers_generated + 1; END IF;
            END IF;
          END IF;

          IF v_contract_promo IS NOT NULL AND public.fighter_is_promotion_ranked(v_fighter.id, v_contract_promo) THEN
            SELECT tier INTO v_current_tier FROM public.promotions WHERE id = v_contract_promo;
            IF v_current_tier IS NOT NULL AND random() < 0.12 THEN
              SELECT count(*) INTO v_offer_count FROM public.fight_offers
              WHERE gym_id = v_gym.id AND status = 'pending' AND fighter_id = v_fighter.id;
              IF v_offer_count < 3 THEN
                SELECT id, tier INTO v_promo_offer_id, v_promo_offer_tier
                FROM public.promotions
                WHERE owner_kind = 'ai'
                  AND tier = v_current_tier + 1
                  AND tier <= v_gym.tier + 1
                  AND EXISTS (
                    SELECT 1 FROM public.fighters f
                    WHERE f.promotion_id = promotions.id
                      AND f.gym_id IS NULL
                      AND f.retired = false
                      AND f.weight_class = v_fighter.weight_class
                      AND ABS(f.current_skill - v_fighter.current_skill) <= 15
                      AND NOT public.fighter_holds_promotion_title(f.id, promotions.id)
                      AND NOT EXISTS (
                        SELECT 1
                        FROM public.fights pf
                        JOIN public.events pe ON pe.id = pf.event_id
                        WHERE pf.status = 'pending'
                          AND pe.status = 'scheduled'
                          AND f.id IN (pf.fighter_a_id, pf.fighter_b_id)
                      )
                  )
                ORDER BY random()
                LIMIT 1;

                IF v_promo_offer_id IS NOT NULL THEN
                  SELECT id INTO v_opp
                  FROM public.fighters opp
                  WHERE opp.promotion_id = v_promo_offer_id
                    AND opp.gym_id IS NULL
                    AND opp.weight_class = v_fighter.weight_class
                    AND opp.retired = false
                    AND opp.id <> v_fighter.id
                    AND ABS(opp.current_skill - v_fighter.current_skill) <= 15
                    AND NOT public.fighter_holds_promotion_title(opp.id, v_promo_offer_id)
                    AND NOT EXISTS (
                      SELECT 1
                      FROM public.fights pf
                      JOIN public.events pe ON pe.id = pf.event_id
                      WHERE pf.status = 'pending'
                        AND pe.status = 'scheduled'
                        AND opp.id IN (pf.fighter_a_id, pf.fighter_b_id)
                    )
                  ORDER BY random()
                  LIMIT 1;

                  IF v_opp IS NOT NULL THEN
                    v_purse_base := v_promo_offer_tier * 5000 + GREATEST(0, (v_fighter.current_skill - 50) * 200);
                    INSERT INTO public.fight_offers (gym_id, fighter_id, opponent_fighter_id, promotion_id, event_id,
                      purse, scheduled_week, status, offered_at_week, offer_kind, contract_fights)
                    VALUES (v_gym.id, v_fighter.id, v_opp, v_promo_offer_id, NULL,
                      v_purse_base, v_new_tick + 4 + floor(random() * 2)::int, 'pending', v_new_tick, 'contract', 4)
                    RETURNING id INTO v_new_offer_id;
                    IF v_new_offer_id IS NOT NULL THEN v_offers_generated := v_offers_generated + 1; END IF;
                  END IF;
                END IF;
              END IF;
            END IF;
          END IF;
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  v_rank := 1;
  FOR v_gym IN SELECT id FROM public.gyms ORDER BY reputation DESC, wins DESC LOOP
    UPDATE public.gyms SET ranking = v_rank WHERE id = v_gym.id;
    v_rank := v_rank + 1;
  END LOOP;

  FOR v_champion IN
    SELECT c.current_champion_fighter_id AS fighter_id, c.promotion_id
    FROM public.championships c
    WHERE c.current_champion_fighter_id IS NOT NULL
  LOOP
    PERFORM public.renew_champion_contract(
      v_champion.fighter_id,
      v_champion.promotion_id,
      v_new_tick
    );
  END LOOP;

  FOR v_ranked IN
    SELECT r.fighter_id, r.promotion_id
    FROM public.rankings r
    WHERE r.rank_position <= 15
  LOOP
    IF NOT public.fighter_holds_promotion_title(v_ranked.fighter_id, v_ranked.promotion_id) THEN
      PERFORM public.renew_ranked_fighter_contract(
        v_ranked.fighter_id,
        v_ranked.promotion_id,
        v_new_tick
      );
    END IF;
  END LOOP;

  UPDATE public.contracts SET status = 'expired'
  WHERE status = 'active'
    AND expires_week <= v_new_tick
    AND NOT EXISTS (
      SELECT 1 FROM public.championships ch
      WHERE ch.current_champion_fighter_id = contracts.fighter_id
        AND ch.promotion_id = contracts.promotion_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.rankings r
      WHERE r.fighter_id = contracts.fighter_id
        AND r.promotion_id = contracts.promotion_id
        AND r.rank_position <= 15
    );

  UPDATE public.fighters SET promotion_id = NULL
  WHERE gym_id IS NULL
    AND id IN (
      SELECT c.fighter_id FROM public.contracts c
      WHERE c.status = 'expired'
        AND NOT public.fighter_holds_promotion_title(c.fighter_id, c.promotion_id)
        AND NOT public.fighter_is_promotion_ranked(c.fighter_id, c.promotion_id)
    );

  UPDATE public.fight_offers SET status = 'declined'
  WHERE status = 'pending' AND scheduled_week < v_new_tick;

  RETURN jsonb_build_object(
    'status','ok','tick', v_new_tick,
    'date', jsonb_build_object('year', v_new_year, 'month', v_new_month, 'week', v_new_week, 'day', v_new_day),
    'retired', v_retired_count, 'signed', v_signed_count,
    'events_processed', v_events_processed, 'fights_simulated', v_fights_simulated,
    'offers_generated', v_offers_generated, 'purses_paid', v_total_purses_paid);
END;
$$;

CREATE OR REPLACE FUNCTION public.promotion_ranking_stats(p_promotion_id uuid)
RETURNS TABLE (
  fighter_id uuid,
  promo_wins int,
  promo_losses int,
  promo_draws int,
  promo_total int,
  promo_win_pct numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER SET search_path = public
AS $$
  SELECT
    f.id AS fighter_id,
    rec.wins AS promo_wins,
    rec.losses AS promo_losses,
    rec.draws AS promo_draws,
    rec.total AS promo_total,
    rec.win_pct AS promo_win_pct
  FROM public.fighters f
  CROSS JOIN LATERAL public.promotion_fighter_record(f.id, p_promotion_id) rec
  WHERE f.promotion_id = p_promotion_id;
$$;

-- Repair ranked fighters who lost promotion ties when a contract expired.
DO $$
DECLARE
  v_tick int;
  v_ranked RECORD;
BEGIN
  SELECT tick_count INTO v_tick FROM public.world_state WHERE id = 1;

  FOR v_ranked IN
    SELECT r.fighter_id, r.promotion_id
    FROM public.rankings r
    WHERE r.rank_position <= 15
  LOOP
    IF NOT public.fighter_holds_promotion_title(v_ranked.fighter_id, v_ranked.promotion_id) THEN
      PERFORM public.renew_ranked_fighter_contract(
        v_ranked.fighter_id,
        v_ranked.promotion_id,
        COALESCE(v_tick, 0)
      );
    END IF;
  END LOOP;
END;
$$;
