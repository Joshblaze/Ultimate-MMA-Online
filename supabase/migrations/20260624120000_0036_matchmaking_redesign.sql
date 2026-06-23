/*
# Matchmaking redesign

- Rank-aware, activity-weighted opponent picking with anti-rematch filters
- Five-loss promotion cut (all fighters; champions exempt)
- Stronger ranking penalty for extended loss streaks
*/

ALTER TABLE public.news_items
  DROP CONSTRAINT IF EXISTS news_items_type_check;

ALTER TABLE public.news_items
  ADD CONSTRAINT news_items_type_check
  CHECK (type IN (
    'champion_crowned', 'upset', 'retirement', 'signing', 'release',
    'gym_tier', 'event_result', 'title_defense', 'title_vacated', 'promotion_cut'
  ));

-- Weeks since last completed promotion fight (never fought = full tick count).
CREATE OR REPLACE FUNCTION public.promotion_fighter_weeks_idle(
  p_fighter_id uuid,
  p_promotion_id uuid,
  p_tick int
)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(
    p_tick - MAX(fi.completed_at_week),
    p_tick
  )::int
  FROM public.fights fi
  JOIN public.events e ON e.id = fi.event_id AND e.promotion_id = p_promotion_id
  WHERE fi.status = 'completed'
    AND p_fighter_id IN (fi.fighter_a_id, fi.fighter_b_id);
$$;

-- True when B appears among A's last N completed promotion opponents.
CREATE OR REPLACE FUNCTION public.fighters_recently_matched(
  p_fighter_a uuid,
  p_fighter_b uuid,
  p_promotion_id uuid,
  p_lookback_fights int DEFAULT 2
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE
    WHEN p_lookback_fights <= 0 THEN false
    ELSE EXISTS (
      SELECT 1
      FROM (
        SELECT
          CASE
            WHEN fi.fighter_a_id = p_fighter_a THEN fi.fighter_b_id
            ELSE fi.fighter_a_id
          END AS opponent_id
        FROM public.fights fi
        JOIN public.events e ON e.id = fi.event_id AND e.promotion_id = p_promotion_id
        WHERE fi.status = 'completed'
          AND p_fighter_a IN (fi.fighter_a_id, fi.fighter_b_id)
        ORDER BY fi.completed_at_week DESC NULLS LAST, fi.id DESC
        LIMIT p_lookback_fights
      ) recent
      WHERE recent.opponent_id = p_fighter_b
    )
  END;
$$;

-- Central opponent picker with rematch avoidance and rank/idle weighting.
CREATE OR REPLACE FUNCTION public.pick_matchmaking_opponent(
  p_fighter_id uuid,
  p_promotion_id uuid,
  p_weight_class text,
  p_exclude_ids uuid[],
  p_tick int,
  p_require_unmanaged boolean DEFAULT false,
  p_skill_band int DEFAULT NULL,
  p_rematch_lookback int DEFAULT 2
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_candidate uuid;
  v_lookback int;
  v_use_rank_penalty boolean;
  v_fighter_skill int;
BEGIN
  SELECT current_skill INTO v_fighter_skill
  FROM public.fighters WHERE id = p_fighter_id;

  -- Tier 1: full rematch filter + rank penalty
  -- Tier 2: full rematch filter, no rank penalty
  -- Tier 3: last-1 rematch filter, no rank penalty
  -- Tier 4: random among eligible
  FOR v_lookback, v_use_rank_penalty IN
    SELECT * FROM (VALUES
      (p_rematch_lookback, true),
      (p_rematch_lookback, false),
      (CASE WHEN p_rematch_lookback > 1 THEN 1 ELSE 0 END, false),
      (0, false)
    ) AS tiers(lookback, use_rank)
  LOOP
    IF v_lookback = 0 THEN
      SELECT f.id INTO v_candidate
      FROM public.fighters f
      WHERE f.promotion_id = p_promotion_id
        AND f.weight_class = p_weight_class
        AND f.retired = false
        AND f.id <> p_fighter_id
        AND (NOT p_require_unmanaged OR f.gym_id IS NULL)
        AND NOT public.fighter_holds_promotion_title(f.id)
        AND (
          p_exclude_ids IS NULL
          OR cardinality(p_exclude_ids) = 0
          OR NOT (f.id = ANY (p_exclude_ids))
        )
        AND (
          p_skill_band IS NULL
          OR ABS(f.current_skill - v_fighter_skill) <= p_skill_band
        )
        AND NOT EXISTS (
          SELECT 1
          FROM public.fights pf
          JOIN public.events pe ON pe.id = pf.event_id
          WHERE pf.status = 'pending'
            AND pe.status = 'scheduled'
            AND f.id IN (pf.fighter_a_id, pf.fighter_b_id)
        )
      ORDER BY random()
      LIMIT 1;
      RETURN v_candidate;
    END IF;

    SELECT scored.id INTO v_candidate
    FROM (
      SELECT
        f.id,
        public.promotion_fighter_weeks_idle(f.id, p_promotion_id, p_tick) * 2.0
        - CASE
            WHEN v_use_rank_penalty THEN
              ABS(
                COALESCE(ra.rank_position, 16)
                - COALESCE(rb.rank_position, 16)
              ) * 1.5
            ELSE 0.0
          END
        + random() * 4.0 AS score
      FROM public.fighters f
      LEFT JOIN public.rankings ra
        ON ra.fighter_id = p_fighter_id
        AND ra.promotion_id = p_promotion_id
        AND ra.weight_class = p_weight_class
      LEFT JOIN public.rankings rb
        ON rb.fighter_id = f.id
        AND rb.promotion_id = p_promotion_id
        AND rb.weight_class = p_weight_class
      WHERE f.promotion_id = p_promotion_id
        AND f.weight_class = p_weight_class
        AND f.retired = false
        AND f.id <> p_fighter_id
        AND (NOT p_require_unmanaged OR f.gym_id IS NULL)
        AND NOT public.fighter_holds_promotion_title(f.id)
        AND (
          p_exclude_ids IS NULL
          OR cardinality(p_exclude_ids) = 0
          OR NOT (f.id = ANY (p_exclude_ids))
        )
        AND (
          p_skill_band IS NULL
          OR ABS(f.current_skill - v_fighter_skill) <= p_skill_band
        )
        AND NOT public.fighters_recently_matched(
          p_fighter_id, f.id, p_promotion_id, v_lookback
        )
        AND NOT EXISTS (
          SELECT 1
          FROM public.fights pf
          JOIN public.events pe ON pe.id = pf.event_id
          WHERE pf.status = 'pending'
            AND pe.status = 'scheduled'
            AND f.id IN (pf.fighter_a_id, pf.fighter_b_id)
        )
    ) scored
    ORDER BY scored.score DESC
    LIMIT 1;

    IF v_candidate IS NOT NULL THEN
      RETURN v_candidate;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;

-- Release a fighter from a promotion after poor performance.
CREATE OR REPLACE FUNCTION public.cut_fighter_from_promotion(
  p_fighter_id uuid,
  p_promotion_id uuid,
  p_tick int,
  p_reason text DEFAULT 'five_loss_streak'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fighter RECORD;
  v_promo_name text;
BEGIN
  IF public.fighter_holds_promotion_title(p_fighter_id, p_promotion_id) THEN
    RETURN false;
  END IF;

  SELECT f.id, f.name INTO v_fighter
  FROM public.fighters f
  WHERE f.id = p_fighter_id
    AND f.promotion_id = p_promotion_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  UPDATE public.contracts
  SET status = 'expired'
  WHERE fighter_id = p_fighter_id
    AND promotion_id = p_promotion_id
    AND status = 'active';

  UPDATE public.fighters
  SET promotion_id = NULL
  WHERE id = p_fighter_id;

  UPDATE public.fight_offers
  SET status = 'declined'
  WHERE status = 'pending'
    AND promotion_id = p_promotion_id
    AND (fighter_id = p_fighter_id OR opponent_fighter_id = p_fighter_id);

  SELECT name INTO v_promo_name FROM public.promotions WHERE id = p_promotion_id;

  INSERT INTO public.news_items (week, type, title, body, fighter_id, promotion_id)
  VALUES (
    p_tick,
    'promotion_cut',
    v_fighter.name || ' released by ' || COALESCE(v_promo_name, 'promotion'),
    v_fighter.name || ' has been released after five consecutive losses in '
      || COALESCE(v_promo_name, 'the promotion') || '.',
    p_fighter_id,
    p_promotion_id
  );

  RETURN true;
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
    AND NOT public.fighter_holds_promotion_title(f.id)
    AND (NOT p_require_unmanaged OR f.gym_id IS NULL)
    AND NOT EXISTS (
      SELECT 1
      FROM public.fights pf
      JOIN public.events pe ON pe.id = pf.event_id
      WHERE pf.status = 'pending'
        AND pe.status = 'scheduled'
        AND f.id IN (pf.fighter_a_id, pf.fighter_b_id)
    )
    AND r.fighter_id <> COALESCE((
      SELECT CASE
        WHEN fi.fighter_a_id = p_exclude_fighter_id THEN fi.fighter_b_id
        ELSE fi.fighter_a_id
      END
      FROM public.fights fi
      JOIN public.events e ON e.id = fi.event_id AND e.promotion_id = p_promotion_id
      WHERE fi.status = 'completed'
        AND fi.is_title_fight = true
        AND fi.weight_class = p_weight_class
        AND p_exclude_fighter_id IN (fi.fighter_a_id, fi.fighter_b_id)
      ORDER BY fi.completed_at_week DESC NULLS LAST, fi.id DESC
      LIMIT 1
    ), '00000000-0000-0000-0000-000000000000'::uuid)
  ORDER BY
    CASE
      WHEN f.gym_id IS NOT NULL AND r.rank_position <= 5 THEN 0
      WHEN f.gym_id IS NOT NULL THEN 1
      ELSE 2
    END,
    r.rank_position ASC,
    random() * (7 - r.rank_position) DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.promotion_fighter_ranking_score(
  p_fighter_id uuid,
  p_promotion_id uuid,
  p_prev_rank int DEFAULT NULL
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER SET search_path = public
AS $$
  WITH rec AS (
    SELECT * FROM public.promotion_fighter_record(p_fighter_id, p_promotion_id)
  ),
  streak AS (
    SELECT * FROM public.promotion_fighter_streak(p_fighter_id, p_promotion_id)
  ),
  fighter AS (
    SELECT current_skill, popularity
    FROM public.fighters
    WHERE id = p_fighter_id
  )
  SELECT
    ((rec.wins + 2.0) / NULLIF(rec.total + 4.0, 0)) * 40.0
    + LEAST(rec.wins, 12) * 8.0
    + LEAST(streak.win_streak, 5) * 12.0
    - LEAST(streak.loss_streak, 5) * 15.0
    + CASE
        WHEN p_prev_rank BETWEEN 1 AND 15 THEN (16 - p_prev_rank) * 3.0
        ELSE 0.0
      END
    - CASE
        WHEN rec.total = 0 THEN 40.0
        WHEN rec.total = 1 THEN 28.0
        WHEN rec.total = 2 THEN 12.0
        ELSE 0.0
      END
    + fighter.current_skill * 0.15
    + fighter.popularity * 0.05
  FROM rec, streak, fighter;
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
  IF EXISTS (
    SELECT 1 FROM public.fighters f
    WHERE f.id = p_fighter_id AND f.gym_id IS NOT NULL
  ) THEN
    RETURN;
  END IF;

  IF public.fighter_holds_promotion_title(p_fighter_id, p_promotion_id) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.promotion_fighter_streak(p_fighter_id, p_promotion_id) s
    WHERE s.loss_streak >= 5
  ) THEN
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

CREATE OR REPLACE FUNCTION public.consume_promotion_contract_fight()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_promotion_id uuid;
  v_tick int;
  v_fighter_id uuid;
  v_is_gym_fighter boolean;
  v_loss_streak int;
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
    IF NEW.winner_id IS NOT NULL AND NEW.winner_id IS DISTINCT FROM v_fighter_id THEN
      SELECT s.loss_streak INTO v_loss_streak
      FROM public.promotion_fighter_streak(v_fighter_id, v_promotion_id) s;

      IF COALESCE(v_loss_streak, 0) >= 5 THEN
        PERFORM public.cut_fighter_from_promotion(
          v_fighter_id, v_promotion_id, v_tick, 'five_loss_streak'
        );
        CONTINUE;
      END IF;
    END IF;

    SELECT (f.gym_id IS NOT NULL) INTO v_is_gym_fighter
    FROM public.fighters f WHERE f.id = v_fighter_id;

    IF public.fighter_holds_promotion_title(v_fighter_id, v_promotion_id)
       AND EXISTS (
         SELECT 1 FROM public.contracts c
         WHERE c.fighter_id = v_fighter_id
           AND c.promotion_id = v_promotion_id
           AND c.fights_remaining = 0
       ) THEN
      PERFORM public.renew_champion_contract(v_fighter_id, v_promotion_id, v_tick);
    ELSIF v_is_gym_fighter
       AND NOT public.fighter_holds_promotion_title(v_fighter_id, v_promotion_id)
       AND EXISTS (
         SELECT 1 FROM public.contracts c
         WHERE c.fighter_id = v_fighter_id
           AND c.promotion_id = v_promotion_id
           AND c.fights_remaining = 0
       ) THEN
      UPDATE public.contracts
      SET status = 'expired'
      WHERE status = 'active'
        AND promotion_id = v_promotion_id
        AND fighter_id = v_fighter_id
        AND fights_remaining = 0;
      PERFORM public.offer_gym_fighter_contract_renewal(v_fighter_id, v_promotion_id, v_tick);
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

CREATE OR REPLACE FUNCTION public.offer_gym_fighter_contract_renewal(
  p_fighter_id uuid,
  p_promotion_id uuid,
  p_tick int
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fighter RECORD;
  v_opp uuid;
  v_purse bigint;
  v_tier int;
  v_scheduled int;
BEGIN
  SELECT f.id, f.gym_id, f.weight_class, f.current_skill
  INTO v_fighter
  FROM public.fighters f
  WHERE f.id = p_fighter_id
    AND f.gym_id IS NOT NULL
    AND f.retired = false;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF public.fighter_holds_promotion_title(p_fighter_id, p_promotion_id) THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.fight_offers fo
    WHERE fo.fighter_id = p_fighter_id
      AND fo.promotion_id = p_promotion_id
      AND fo.offer_kind = 'renewal'
      AND fo.status = 'pending'
  ) THEN
    RETURN false;
  END IF;

  SELECT tier INTO v_tier FROM public.promotions WHERE id = p_promotion_id;
  IF v_tier IS NULL THEN
    RETURN false;
  END IF;

  v_opp := public.pick_matchmaking_opponent(
    p_fighter_id,
    p_promotion_id,
    v_fighter.weight_class,
    ARRAY[]::uuid[],
    p_tick,
    true,
    15,
    2
  );

  IF v_opp IS NULL THEN
    RETURN false;
  END IF;

  v_purse := v_tier * 5000 + GREATEST(0, (v_fighter.current_skill - 50) * 200);
  v_scheduled := p_tick + 4 + floor(random() * 2)::int;

  INSERT INTO public.fight_offers (
    gym_id, fighter_id, opponent_fighter_id, promotion_id,
    purse, scheduled_week, status, offered_at_week,
    offer_kind, contract_fights
  ) VALUES (
    v_fighter.gym_id, p_fighter_id, v_opp, p_promotion_id,
    v_purse, v_scheduled, 'pending', p_tick,
    'renewal', 4
  );

  RETURN true;
END;
$$;


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
  v_bout_slot int;
  v_fighter_offer_tier int;
  v_card_excluded uuid[];
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
    FOR v_wc IN SELECT name FROM public.weight_classes ORDER BY "order" LOOP
      SELECT count(*) INTO v_count FROM public.fighters
      WHERE promotion_id = v_promo.id AND weight_class = v_wc.name AND retired = false;
      IF v_count < 15 THEN
        FOR v_fighter IN
          SELECT id FROM public.fighters
          WHERE gym_id IS NULL AND promotion_id IS NULL AND retired = false
            AND weight_class = v_wc.name
            AND NOT public.fighter_holds_promotion_title(id)
          ORDER BY current_skill DESC
          LIMIT LEAST(10, 15 - v_count)
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
  END LOOP;

  FOR v_promo IN SELECT id, tier, fan_base, name FROM public.promotions WHERE owner_kind = 'ai' LOOP
    WHILE (
      SELECT count(*) FROM public.events
      WHERE promotion_id = v_promo.id AND status = 'scheduled' AND scheduled_week > v_new_tick
    ) < 2 LOOP
      SELECT count(*) INTO v_count FROM public.events
      WHERE promotion_id = v_promo.id AND status = 'scheduled' AND scheduled_week > v_new_tick;
      INSERT INTO public.events (promotion_id, name, scheduled_week, status)
      VALUES (v_promo.id, public.next_promotion_event_name(v_promo.id),
        v_new_tick + 2 * (v_count + 1) + floor(random() * 2)::int, 'scheduled');
    END LOOP;
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
      FROM public.championships c
      JOIN public.weight_classes wc ON wc.name = c.weight_class
      WHERE c.promotion_id = v_events_to_process.promotion_id
      ORDER BY c.last_title_fight_at_week ASC NULLS FIRST, wc."order" ASC
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
          v_contender_1 := NULL; v_contender_2 := NULL;
          SELECT r.fighter_id INTO v_contender_1
          FROM public.rankings r
          JOIN public.fighters f ON f.id = r.fighter_id
          WHERE r.promotion_id = v_champion.promotion_id AND r.weight_class = v_champion.weight_class
            AND f.gym_id IS NULL AND f.promotion_id = v_champion.promotion_id
            AND NOT public.fighter_holds_promotion_title(f.id)
          ORDER BY r.rank_position ASC LIMIT 1 OFFSET 0;
          SELECT r.fighter_id INTO v_contender_2
          FROM public.rankings r
          JOIN public.fighters f ON f.id = r.fighter_id
          WHERE r.promotion_id = v_champion.promotion_id AND r.weight_class = v_champion.weight_class
            AND f.gym_id IS NULL AND f.promotion_id = v_champion.promotion_id
            AND r.fighter_id IS DISTINCT FROM v_contender_1
            AND NOT public.fighter_holds_promotion_title(f.id)
          ORDER BY r.rank_position ASC LIMIT 1 OFFSET 0;

          IF v_contender_1 IS NULL OR v_contender_2 IS NULL THEN
            SELECT id INTO v_contender_1 FROM public.fighters
            WHERE promotion_id = v_champion.promotion_id AND weight_class = v_champion.weight_class
              AND retired = false AND gym_id IS NULL
              AND NOT public.fighter_holds_promotion_title(id)
            ORDER BY current_skill DESC, popularity DESC LIMIT 1 OFFSET 0;
            SELECT id INTO v_contender_2 FROM public.fighters
            WHERE promotion_id = v_champion.promotion_id AND weight_class = v_champion.weight_class
              AND retired = false AND gym_id IS NULL AND id IS DISTINCT FROM v_contender_1
              AND NOT public.fighter_holds_promotion_title(id)
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
      ELSE
          v_opp := public.pick_weighted_title_challenger(
            v_champion.promotion_id,
            v_champion.weight_class,
            v_champion.champ_fighter,
            true
          );

          IF v_opp IS NULL THEN
            SELECT f.id INTO v_opp
            FROM public.rankings r
            JOIN public.fighters f ON f.id = r.fighter_id
            WHERE r.promotion_id = v_champion.promotion_id
              AND r.weight_class = v_champion.weight_class
              AND r.rank_position BETWEEN 1 AND 6
              AND f.retired = false
              AND f.gym_id IS NULL
              AND f.id <> v_champion.champ_fighter
              AND f.promotion_id = v_champion.promotion_id
              AND NOT public.fighter_holds_promotion_title(f.id)
            ORDER BY r.rank_position ASC
            LIMIT 1;
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

        UPDATE public.championships
        SET last_title_fight_at_week = v_new_tick
        WHERE id = v_champion.champ_id;

        v_fights_simulated := v_fights_simulated + 1;
        v_event_has_title_fight := true;
        EXIT;
      END IF;
    END LOOP;

    -- PLACEHOLDER_UNDERCARD_LOOP
    FOR v_wc IN SELECT name FROM public.weight_classes ORDER BY "order" LOOP
      FOR v_bout_slot IN 1..2 LOOP
        SELECT count(*) INTO v_count FROM public.fights
        WHERE event_id = v_events_to_process.id AND weight_class = v_wc.name;
        IF v_count >= 2 THEN
          EXIT;
        END IF;

        v_fighter_a := NULL; v_fighter_b := NULL;
        SELECT COALESCE(array_agg(DISTINCT fid), ARRAY[]::uuid[]) INTO v_card_excluded
        FROM (
          SELECT fighter_a_id AS fid FROM public.fights WHERE event_id = v_events_to_process.id
          UNION
          SELECT fighter_b_id FROM public.fights WHERE event_id = v_events_to_process.id
        ) card_ids;

        SELECT f.id INTO v_fighter_a
        FROM public.fighters f
        WHERE f.promotion_id = v_events_to_process.promotion_id AND f.weight_class = v_wc.name
          AND f.retired = false AND f.gym_id IS NULL
          AND NOT public.fighter_holds_promotion_title(f.id)
          AND NOT (f.id = ANY (v_card_excluded))
        ORDER BY public.promotion_fighter_weeks_idle(f.id, v_events_to_process.promotion_id, v_new_tick) DESC,
                 random()
        LIMIT 1;

        IF v_fighter_a IS NOT NULL THEN
          v_fighter_b := public.pick_matchmaking_opponent(
            v_fighter_a,
            v_events_to_process.promotion_id,
            v_wc.name,
            v_card_excluded,
            v_new_tick,
            true,
            NULL,
            2
          );
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
        VALUES (v_events_to_process.id, v_fighter_a, v_fighter_b, v_winner_id, v_method, v_round,
          v_commentary, v_wc.name, false, NULL, 'completed', v_new_tick);

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
    END LOOP;

    UPDATE public.events SET status = 'completed', completed_at_week = v_new_tick WHERE id = v_events_to_process.id;

    INSERT INTO public.news_items (week, type, title, body, promotion_id)
    VALUES (v_new_tick, 'event_result', v_events_to_process.name || ' results are in',
      v_events_to_process.name || ' has concluded. View full results on the Events page.',
      v_events_to_process.promotion_id);
  END LOOP;

  PERFORM public.refresh_promotion_rankings(v_new_tick);
  PERFORM public.mark_title_shot_due_for_new_top_five(v_new_tick);

  -- Re-mark top-5 gym fighters stuck without a pending title shot for weekly retry.
  UPDATE public.fighters f
  SET title_shot_due_week = v_new_tick
  FROM public.rankings r
  JOIN public.championships ch ON ch.promotion_id = r.promotion_id
    AND ch.weight_class = r.weight_class
  JOIN public.fighters champ ON champ.id = ch.current_champion_fighter_id
  WHERE f.id = r.fighter_id
    AND f.gym_id IS NOT NULL
    AND f.retired = false
    AND f.weight_class = r.weight_class
    AND r.rank_position <= 5
    AND f.title_shot_due_week IS NULL
    AND ch.current_champion_fighter_id <> f.id
    AND champ.gym_id IS NULL
    AND EXISTS (
      SELECT 1 FROM public.contracts c
      WHERE c.fighter_id = f.id
        AND c.promotion_id = r.promotion_id
        AND c.status = 'active'
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.fight_offers fo
      WHERE fo.gym_id = f.gym_id
        AND fo.fighter_id = f.id
        AND fo.status = 'pending'
        AND fo.offer_kind = 'title_shot'
        AND fo.opponent_fighter_id = ch.current_champion_fighter_id
    );

  -- PLACEHOLDER_OFFERS_LOOP
  FOR v_gym IN SELECT id, reputation, tier FROM public.gyms LOOP
    FOR v_fighter IN
      SELECT id, weight_class, current_skill, popularity, title_shot_due_week
      FROM public.fighters
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
              false
            );

            IF v_opp IS NULL THEN
              SELECT f.id INTO v_opp
              FROM public.rankings r
              JOIN public.fighters f ON f.id = r.fighter_id
              WHERE r.promotion_id = v_promo_offer_id
                AND r.weight_class = v_fighter.weight_class
                AND r.rank_position BETWEEN 1 AND 6
                AND f.retired = false
                AND f.id <> v_fighter.id
                AND f.promotion_id = v_promo_offer_id
                AND NOT public.fighter_holds_promotion_title(f.id)
                AND NOT EXISTS (
                  SELECT 1
                  FROM public.fights pf
                  JOIN public.events pe ON pe.id = pf.event_id
                  WHERE pf.status = 'pending'
                    AND pe.status = 'scheduled'
                    AND f.id IN (pf.fighter_a_id, pf.fighter_b_id)
                )
              ORDER BY
                CASE
                  WHEN f.gym_id IS NOT NULL AND r.rank_position <= 5 THEN 0
                  WHEN f.gym_id IS NOT NULL THEN 1
                  ELSE 2
                END,
                r.rank_position ASC
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

      -- Title shot for top-5 gym fighters vs AI champion (break-in + weekly retry)
      v_championship_id := NULL;
      v_promo_offer_id := NULL;
      v_opp := NULL;
      v_promo_offer_tier := NULL;

      SELECT ch.id, ch.promotion_id, ch.current_champion_fighter_id, p.tier
      INTO v_championship_id, v_promo_offer_id, v_opp, v_promo_offer_tier
      FROM public.championships ch
      JOIN public.promotions p ON p.id = ch.promotion_id
      JOIN public.fighters champ ON champ.id = ch.current_champion_fighter_id
      JOIN public.rankings r ON r.promotion_id = ch.promotion_id
        AND r.weight_class = ch.weight_class
        AND r.fighter_id = v_fighter.id
        AND r.rank_position <= 5
      WHERE ch.weight_class = v_fighter.weight_class
        AND ch.current_champion_fighter_id <> v_fighter.id
        AND champ.gym_id IS NULL
        AND EXISTS (
          SELECT 1 FROM public.contracts c
          WHERE c.fighter_id = v_fighter.id
            AND c.promotion_id = ch.promotion_id
            AND c.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1
          FROM public.fights f
          JOIN public.events e ON e.id = f.event_id
          WHERE f.status = 'pending'
            AND e.status = 'scheduled'
            AND ch.current_champion_fighter_id IN (f.fighter_a_id, f.fighter_b_id)
        )
        AND (
          v_fighter.title_shot_due_week = v_new_tick
          OR NOT EXISTS (
            SELECT 1 FROM public.fight_offers fo
            WHERE fo.gym_id = v_gym.id
              AND fo.fighter_id = v_fighter.id
              AND fo.status = 'pending'
              AND fo.offer_kind = 'title_shot'
              AND fo.opponent_fighter_id = ch.current_champion_fighter_id
          )
        )
      ORDER BY r.rank_position ASC
      LIMIT 1;

      IF v_championship_id IS NOT NULL THEN
        SELECT count(*) INTO v_offer_count FROM public.fight_offers
        WHERE gym_id = v_gym.id AND status = 'pending' AND fighter_id = v_fighter.id;
        IF v_offer_count < 3 THEN
          v_purse_base := v_promo_offer_tier * 5000
            + GREATEST(0, (v_fighter.current_skill - 50) * 200)
            + 10000;
          INSERT INTO public.fight_offers (
            gym_id, fighter_id, opponent_fighter_id, promotion_id, event_id,
            purse, scheduled_week, status, offered_at_week, offer_kind, contract_fights
          )
          VALUES (
            v_gym.id, v_fighter.id, v_opp, v_promo_offer_id, NULL,
            v_purse_base, v_new_tick + 2 + floor(random() * 2)::int, 'pending', v_new_tick, 'title_shot',
            COALESCE((
              SELECT c.fights_remaining
              FROM public.contracts c
              WHERE c.fighter_id = v_fighter.id
                AND c.promotion_id = v_promo_offer_id
                AND c.status = 'active'
              LIMIT 1
            ), 1)
          )
          RETURNING id INTO v_new_offer_id;
          IF v_new_offer_id IS NOT NULL THEN
            v_offers_generated := v_offers_generated + 1;
            UPDATE public.fighters
            SET title_shot_due_week = NULL
            WHERE id = v_fighter.id;
            CONTINUE;
          END IF;
        END IF;
      END IF;

      IF random() < LEAST(0.5, (v_fighter.current_skill + v_gym.reputation + v_fighter.popularity * 0.25) / 300.0) THEN
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
            v_fighter_offer_tier := public.fighter_contract_offer_tier(v_fighter.popularity);
            SELECT id, tier INTO v_promo_offer_id, v_promo_offer_tier
            FROM public.promotions
            WHERE owner_kind = 'ai'
              AND tier >= v_fighter_offer_tier
              AND tier <= LEAST(5, v_fighter_offer_tier + 1)
              AND EXISTS (
                SELECT 1 FROM public.fighters f
                WHERE f.promotion_id = promotions.id
                  AND f.gym_id IS NULL
                  AND f.retired = false
                  AND f.weight_class = v_fighter.weight_class
                  AND ABS(f.current_skill - v_fighter.current_skill) <= 15
                  AND NOT public.fighter_holds_promotion_title(f.id)
                  AND NOT EXISTS (
                    SELECT 1
                    FROM public.fights pf
                    JOIN public.events pe ON pe.id = pf.event_id
                    WHERE pf.status = 'pending'
                      AND pe.status = 'scheduled'
                      AND f.id IN (pf.fighter_a_id, pf.fighter_b_id)
                  )
              )
            ORDER BY tier DESC, random()
            LIMIT 1;
          END IF;

          IF v_promo_offer_id IS NOT NULL THEN
            v_opp := public.pick_matchmaking_opponent(
              v_fighter.id,
              v_promo_offer_id,
              v_fighter.weight_class,
              ARRAY[]::uuid[],
              v_new_tick,
              true,
              15,
              2
            );

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
                  AND tier <= LEAST(5, public.fighter_contract_offer_tier(v_fighter.popularity) + 1)
                  AND EXISTS (
                    SELECT 1 FROM public.fighters f
                    WHERE f.promotion_id = promotions.id
                      AND f.gym_id IS NULL
                      AND f.retired = false
                      AND f.weight_class = v_fighter.weight_class
                      AND ABS(f.current_skill - v_fighter.current_skill) <= 15
                      AND NOT public.fighter_holds_promotion_title(f.id)
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
                  v_opp := public.pick_matchmaking_opponent(
                    v_fighter.id,
                    v_promo_offer_id,
                    v_fighter.weight_class,
                    ARRAY[]::uuid[],
                    v_new_tick,
                    true,
                    15,
                    2
                  );

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

  v_offers_generated := v_offers_generated + public.finalize_week_contracts(v_new_tick);

  PERFORM public.snapshot_gym_fighter_ranks();

  RETURN jsonb_build_object(
    'status','ok','tick', v_new_tick,
    'date', jsonb_build_object('year', v_new_year, 'month', v_new_month, 'week', v_new_week, 'day', v_new_day),
    'retired', v_retired_count, 'signed', v_signed_count,
    'events_processed', v_events_processed, 'fights_simulated', v_fights_simulated,
    'offers_generated', v_offers_generated, 'purses_paid', v_total_purses_paid);
END;
$$;

