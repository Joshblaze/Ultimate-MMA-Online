/*
# Round-by-round fight simulation with play-by-play events and manager game plans

Replaces instant batch resolution with async round-by-round fights. Managers submit
game plans (preset + tactical sliders) between rounds; AI corners auto-plan.
*/

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_status_check;
ALTER TABLE public.events
  ADD CONSTRAINT events_status_check CHECK (status IN ('scheduled', 'live', 'completed'));

ALTER TABLE public.fights DROP CONSTRAINT IF EXISTS fights_status_check;

ALTER TABLE public.fights
  ADD COLUMN IF NOT EXISTS current_round int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS max_rounds int,
  ADD COLUMN IF NOT EXISTS fight_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS card_order int;

ALTER TABLE public.fights
  ADD CONSTRAINT fights_status_check CHECK (
    status IN ('pending', 'awaiting_plans', 'in_progress', 'between_rounds', 'completed')
  );

CREATE TABLE IF NOT EXISTS public.fight_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fight_id uuid NOT NULL REFERENCES public.fights(id) ON DELETE CASCADE,
  sequence int NOT NULL,
  round int NOT NULL,
  event_type text NOT NULL CHECK (
    event_type IN ('intro', 'strike', 'takedown', 'submission_attempt', 'knockdown', 'round_end', 'finish')
  ),
  actor_fighter_id uuid REFERENCES public.fighters(id) ON DELETE SET NULL,
  target_fighter_id uuid REFERENCES public.fighters(id) ON DELETE SET NULL,
  detail text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (fight_id, sequence)
);
CREATE INDEX IF NOT EXISTS idx_fight_events_fight ON public.fight_events(fight_id, sequence);
ALTER TABLE public.fight_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_fight_events" ON public.fight_events;
CREATE POLICY "public_read_fight_events" ON public.fight_events FOR SELECT
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.fight_game_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fight_id uuid NOT NULL REFERENCES public.fights(id) ON DELETE CASCADE,
  fighter_id uuid NOT NULL REFERENCES public.fighters(id) ON DELETE CASCADE,
  gym_id uuid REFERENCES public.gyms(id) ON DELETE SET NULL,
  for_round int NOT NULL CHECK (for_round BETWEEN 1 AND 5),
  preset text NOT NULL CHECK (preset IN ('striker', 'grappler', 'counter', 'volume')),
  pressure int NOT NULL DEFAULT 50 CHECK (pressure BETWEEN 0 AND 100),
  distance int NOT NULL DEFAULT 50 CHECK (distance BETWEEN 0 AND 100),
  takedown_freq int NOT NULL DEFAULT 50 CHECK (takedown_freq BETWEEN 0 AND 100),
  risk int NOT NULL DEFAULT 50 CHECK (risk BETWEEN 0 AND 100),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (fight_id, fighter_id, for_round)
);
CREATE INDEX IF NOT EXISTS idx_fight_game_plans_fight ON public.fight_game_plans(fight_id, for_round);
ALTER TABLE public.fight_game_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_fight_game_plans" ON public.fight_game_plans;
CREATE POLICY "public_read_fight_game_plans" ON public.fight_game_plans FOR SELECT
  TO anon, authenticated USING (true);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fighter_needs_player_plan(p_fighter_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.fighters f
    WHERE f.id = p_fighter_id
      AND f.gym_id IS NOT NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.fight_plan_exists(
  p_fight_id uuid,
  p_fighter_id uuid,
  p_for_round int
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.fight_game_plans
    WHERE fight_id = p_fight_id
      AND fighter_id = p_fighter_id
      AND for_round = p_for_round
  );
$$;

CREATE OR REPLACE FUNCTION public.init_fight_state()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'a', jsonb_build_object('stamina', 100, 'damage', 0, 'rounds_won', 0, 'round_damage', 0),
    'b', jsonb_build_object('stamina', 100, 'damage', 0, 'rounds_won', 0, 'round_damage', 0)
  );
$$;

CREATE OR REPLACE FUNCTION public.compute_effective_stats(
  p_boxing int,
  p_kickboxing int,
  p_wrestling int,
  p_bjj int,
  p_cardio int,
  p_chin int,
  p_fight_iq int,
  p_athleticism int,
  p_preset text,
  p_pressure int,
  p_distance int,
  p_takedown_freq int,
  p_risk int
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_striking float;
  v_grappling float;
  v_defense float;
  v_finish float;
  v_cardio float;
  v_pressure float := p_pressure / 100.0;
  v_distance float := p_distance / 100.0;
  v_takedown float := p_takedown_freq / 100.0;
  v_risk float := p_risk / 100.0;
BEGIN
  v_striking := (p_boxing + p_kickboxing) / 2.0;
  v_grappling := (p_wrestling + p_bjj) / 2.0;
  v_defense := (p_chin + p_fight_iq) / 2.0;
  v_finish := (p_boxing + p_athleticism) / 2.0;
  v_cardio := p_cardio;

  CASE p_preset
    WHEN 'striker' THEN
      v_striking := v_striking * 1.25;
      v_grappling := v_grappling * 0.85;
    WHEN 'grappler' THEN
      v_grappling := v_grappling * 1.25;
      v_striking := v_striking * 0.90;
    WHEN 'counter' THEN
      v_defense := v_defense * 1.20;
      IF p_risk <= 45 THEN
        v_finish := v_finish * 1.15;
      END IF;
    WHEN 'volume' THEN
      v_striking := v_striking * 1.10;
      v_cardio := v_cardio * 0.92;
    ELSE NULL;
  END CASE;

  v_striking := v_striking * (0.75 + v_distance * 0.5);
  v_grappling := v_grappling * (0.85 + v_pressure * 0.35 + v_takedown * 0.25);
  v_finish := v_finish * (0.70 + v_risk * 0.6);
  v_defense := v_defense * (1.05 - v_risk * 0.25);

  RETURN jsonb_build_object(
    'striking', GREATEST(1, round(v_striking)::int),
    'grappling', GREATEST(1, round(v_grappling)::int),
    'defense', GREATEST(1, round(v_defense)::int),
    'finish', GREATEST(1, round(v_finish)::int),
    'cardio', GREATEST(1, round(v_cardio)::int),
    'takedown_bias', round(v_takedown * 100)::int,
    'risk', round(v_risk * 100)::int
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_ai_game_plan(
  p_fight_id uuid,
  p_fighter_id uuid,
  p_for_round int
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_f RECORD;
  v_preset text;
  v_pressure int;
  v_distance int;
  v_takedown int;
  v_risk int;
BEGIN
  IF public.fight_plan_exists(p_fight_id, p_fighter_id, p_for_round) THEN
    RETURN;
  END IF;

  SELECT * INTO v_f FROM public.fighters WHERE id = p_fighter_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF (v_f.wrestling + v_f.bjj) >= (v_f.boxing + v_f.kickboxing) + 8 THEN
    v_preset := 'grappler';
  ELSIF (v_f.boxing + v_f.kickboxing) >= (v_f.wrestling + v_f.bjj) + 8 THEN
    v_preset := 'striker';
  ELSIF v_f.fight_iq >= 72 THEN
    v_preset := 'counter';
  ELSE
    v_preset := 'volume';
  END IF;

  v_pressure := LEAST(100, GREATEST(20, v_f.wrestling));
  v_distance := LEAST(100, GREATEST(20, (v_f.boxing + v_f.kickboxing) / 2));
  v_takedown := LEAST(100, GREATEST(15, (v_f.wrestling + v_f.bjj) / 2));
  v_risk := CASE
    WHEN v_preset = 'counter' THEN 35
    WHEN v_preset = 'grappler' THEN 55
    WHEN v_preset = 'striker' THEN 60
    ELSE 50
  END;

  INSERT INTO public.fight_game_plans (
    fight_id, fighter_id, gym_id, for_round, preset,
    pressure, distance, takedown_freq, risk
  )
  VALUES (
    p_fight_id, p_fighter_id, v_f.gym_id, p_for_round, v_preset,
    v_pressure, v_distance, v_takedown, v_risk
  )
  ON CONFLICT (fight_id, fighter_id, for_round) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_ai_game_plans(
  p_fight_id uuid,
  p_for_round int
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fight RECORD;
BEGIN
  SELECT * INTO v_fight FROM public.fights WHERE id = p_fight_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF NOT public.fighter_needs_player_plan(v_fight.fighter_a_id) THEN
    PERFORM public.generate_ai_game_plan(p_fight_id, v_fight.fighter_a_id, p_for_round);
  END IF;

  IF NOT public.fighter_needs_player_plan(v_fight.fighter_b_id) THEN
    PERFORM public.generate_ai_game_plan(p_fight_id, v_fight.fighter_b_id, p_for_round);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.both_fight_plans_ready(
  p_fight_id uuid,
  p_for_round int
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_fight RECORD;
BEGIN
  SELECT * INTO v_fight FROM public.fights WHERE id = p_fight_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  RETURN public.fight_plan_exists(p_fight_id, v_fight.fighter_a_id, p_for_round)
     AND public.fight_plan_exists(p_fight_id, v_fight.fighter_b_id, p_for_round);
END;
$$;

CREATE OR REPLACE FUNCTION public.next_fight_event_sequence(p_fight_id uuid)
RETURNS int
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(max(sequence), 0) + 1 FROM public.fight_events WHERE fight_id = p_fight_id;
$$;

CREATE OR REPLACE FUNCTION public.insert_fight_event(
  p_fight_id uuid,
  p_round int,
  p_event_type text,
  p_actor uuid,
  p_target uuid,
  p_detail text,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_seq int;
BEGIN
  v_seq := public.next_fight_event_sequence(p_fight_id);
  INSERT INTO public.fight_events (
    fight_id, sequence, round, event_type, actor_fighter_id, target_fighter_id, detail, metadata
  )
  VALUES (p_fight_id, v_seq, p_round, p_event_type, p_actor, p_target, p_detail, p_metadata);
  RETURN v_seq;
END;
$$;

-- ---------------------------------------------------------------------------
-- Round simulation
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.simulate_fight_round(p_fight_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fight RECORD;
  v_fa RECORD;
  v_fb RECORD;
  v_plan_a RECORD;
  v_plan_b RECORD;
  v_for_round int;
  v_state jsonb;
  v_stats_a jsonb;
  v_stats_b jsonb;
  v_name_a text;
  v_name_b text;
  v_position text := 'standing';
  v_i int;
  v_events int;
  v_roll float;
  v_actor uuid;
  v_target uuid;
  v_actor_key text;
  v_target_key text;
  v_actor_stats jsonb;
  v_target_stats jsonb;
  v_damage numeric;
  v_stamina_a numeric;
  v_stamina_b numeric;
  v_round_damage_a numeric := 0;
  v_round_damage_b numeric := 0;
  v_finish boolean := false;
  v_finish_method text;
  v_finish_actor uuid;
  v_winner_key text;
  v_round_winner text;
  v_commentary_lines text[] := ARRAY[]::text[];
  v_a_striking int;
  v_b_striking int;
  v_chin_a int;
  v_chin_b int;
  v_total_damage_a numeric;
  v_total_damage_b numeric;
BEGIN
  SELECT * INTO v_fight FROM public.fights WHERE id = p_fight_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_for_round := v_fight.current_round + 1;

  SELECT * INTO v_fa FROM public.fighters WHERE id = v_fight.fighter_a_id;
  SELECT * INTO v_fb FROM public.fighters WHERE id = v_fight.fighter_b_id;
  SELECT * INTO v_plan_a FROM public.fight_game_plans
    WHERE fight_id = p_fight_id AND fighter_id = v_fight.fighter_a_id AND for_round = v_for_round;
  SELECT * INTO v_plan_b FROM public.fight_game_plans
    WHERE fight_id = p_fight_id AND fighter_id = v_fight.fighter_b_id AND for_round = v_for_round;

  IF v_plan_a.id IS NULL OR v_plan_b.id IS NULL THEN
    RAISE EXCEPTION 'Missing game plans for round %', v_for_round;
  END IF;

  v_name_a := v_fa.name;
  v_name_b := v_fb.name;
  v_state := COALESCE(NULLIF(v_fight.fight_state, '{}'::jsonb), public.init_fight_state());

  v_state := jsonb_set(v_state, '{a,round_damage}', '0'::jsonb);
  v_state := jsonb_set(v_state, '{b,round_damage}', '0'::jsonb);

  v_stats_a := public.compute_effective_stats(
    v_fa.boxing, v_fa.kickboxing, v_fa.wrestling, v_fa.bjj, v_fa.cardio, v_fa.chin, v_fa.fight_iq, v_fa.athleticism,
    v_plan_a.preset, v_plan_a.pressure, v_plan_a.distance, v_plan_a.takedown_freq, v_plan_a.risk
  );
  v_stats_b := public.compute_effective_stats(
    v_fb.boxing, v_fb.kickboxing, v_fb.wrestling, v_fb.bjj, v_fb.cardio, v_fb.chin, v_fb.fight_iq, v_fb.athleticism,
    v_plan_b.preset, v_plan_b.pressure, v_plan_b.distance, v_plan_b.takedown_freq, v_plan_b.risk
  );

  v_a_striking := (v_stats_a->>'striking')::int;
  v_b_striking := (v_stats_b->>'striking')::int;
  v_chin_a := v_fa.chin;
  v_chin_b := v_fb.chin;

  v_events := 8 + floor(random() * 8)::int;

  FOR v_i IN 1..v_events LOOP
    EXIT WHEN v_finish;

    IF (v_a_striking + floor(random() * 20)::int) >= (v_b_striking + floor(random() * 20)::int) THEN
      v_actor := v_fight.fighter_a_id;
      v_target := v_fight.fighter_b_id;
      v_actor_key := 'a';
      v_target_key := 'b';
      v_actor_stats := v_stats_a;
      v_target_stats := v_stats_b;
    ELSE
      v_actor := v_fight.fighter_b_id;
      v_target := v_fight.fighter_a_id;
      v_actor_key := 'b';
      v_target_key := 'a';
      v_actor_stats := v_stats_b;
      v_target_stats := v_stats_a;
    END IF;

    v_stamina_a := (v_state->'a'->>'stamina')::numeric;
    v_stamina_b := (v_state->'b'->>'stamina')::numeric;

    IF v_actor_key = 'a' AND v_stamina_a < 15 THEN
      v_actor := v_fight.fighter_b_id;
      v_target := v_fight.fighter_a_id;
      v_actor_key := 'b';
      v_target_key := 'a';
      v_actor_stats := v_stats_b;
      v_target_stats := v_stats_a;
    ELSIF v_actor_key = 'b' AND v_stamina_b < 15 THEN
      v_actor := v_fight.fighter_a_id;
      v_target := v_fight.fighter_b_id;
      v_actor_key := 'a';
      v_target_key := 'b';
      v_actor_stats := v_stats_a;
      v_target_stats := v_stats_b;
    END IF;

    v_roll := random();

    IF v_position = 'standing' THEN
      IF v_roll < ((v_actor_stats->>'takedown_bias')::numeric / 400.0) + 0.05 THEN
        IF (v_actor_stats->>'grappling')::int + floor(random() * 15)::int >
           (v_target_stats->>'defense')::int + floor(random() * 10)::int THEN
          v_position := 'ground';
          PERFORM public.insert_fight_event(
            p_fight_id, v_for_round, 'takedown', v_actor, v_target,
            (SELECT name FROM public.fighters WHERE id = v_actor) || ' secures a takedown.',
            jsonb_build_object('position', 'ground')
          );
        ELSE
          PERFORM public.insert_fight_event(
            p_fight_id, v_for_round, 'takedown', v_actor, v_target,
            (SELECT name FROM public.fighters WHERE id = v_actor) || '''s takedown is stuffed.',
            jsonb_build_object('success', false)
          );
        END IF;
      ELSIF v_roll < 0.55 THEN
        v_damage := ((v_actor_stats->>'striking')::numeric * (0.4 + random() * 0.6)) / 12.0;
        v_damage := v_damage * (1.0 + (v_actor_stats->>'risk')::numeric / 200.0);

        IF v_target_key = 'a' THEN
          v_round_damage_a := v_round_damage_a + v_damage;
        ELSE
          v_round_damage_b := v_round_damage_b + v_damage;
        END IF;

        v_state := jsonb_set(
          v_state,
          ARRAY[v_target_key, 'round_damage'],
          to_jsonb((v_state->v_target_key->>'round_damage')::numeric + v_damage)
        );
        v_state := jsonb_set(
          v_state,
          ARRAY[v_target_key, 'damage'],
          to_jsonb((v_state->v_target_key->>'damage')::numeric + v_damage)
        );
        v_state := jsonb_set(
          v_state,
          ARRAY[v_actor_key, 'stamina'],
          to_jsonb(GREATEST(0, (v_state->v_actor_key->>'stamina')::numeric - (2 + random() * 4)))
        );

        IF v_damage >= 8 AND random() < 0.25 THEN
          PERFORM public.insert_fight_event(
            p_fight_id, v_for_round, 'knockdown', v_actor, v_target,
            (SELECT name FROM public.fighters WHERE id = v_actor) || ' drops ' ||
              (SELECT name FROM public.fighters WHERE id = v_target) || '!',
            jsonb_build_object('damage', v_damage)
          );
        ELSE
          PERFORM public.insert_fight_event(
            p_fight_id, v_for_round, 'strike', v_actor, v_target,
            (SELECT name FROM public.fighters WHERE id = v_actor) || ' lands a solid combination.',
            jsonb_build_object('damage', round(v_damage::numeric, 1))
          );
        END IF;

        IF v_target_key = 'a' AND (v_state->'a'->>'damage')::numeric >= v_chin_a * 1.15 THEN
          v_finish := true;
          v_finish_method := CASE WHEN random() < 0.5 THEN 'KO' ELSE 'TKO' END;
          v_finish_actor := v_actor;
        ELSIF v_target_key = 'b' AND (v_state->'b'->>'damage')::numeric >= v_chin_b * 1.15 THEN
          v_finish := true;
          v_finish_method := CASE WHEN random() < 0.5 THEN 'KO' ELSE 'TKO' END;
          v_finish_actor := v_actor;
        END IF;
      ELSE
        PERFORM public.insert_fight_event(
          p_fight_id, v_for_round, 'strike', v_actor, v_target,
          'Feint and footwork exchange in the center of the cage.',
          jsonb_build_object('damage', 0)
        );
      END IF;
    ELSE
      IF v_roll < ((v_actor_stats->>'risk')::numeric / 250.0) + 0.08 THEN
        IF (v_actor_stats->>'grappling')::int + (v_actor_stats->>'finish')::int + floor(random() * 20)::int >
           (v_target_stats->>'defense')::int + floor(random() * 15)::int THEN
          v_finish := true;
          v_finish_method := 'Submission';
          v_finish_actor := v_actor;
          PERFORM public.insert_fight_event(
            p_fight_id, v_for_round, 'finish', v_actor, v_target,
            (SELECT name FROM public.fighters WHERE id = v_actor) || ' locks in a fight-ending submission!',
            jsonb_build_object('method', 'Submission')
          );
        ELSE
          PERFORM public.insert_fight_event(
            p_fight_id, v_for_round, 'submission_attempt', v_actor, v_target,
            (SELECT name FROM public.fighters WHERE id = v_actor) || ' threatens a submission — defended.',
            jsonb_build_object('success', false)
          );
        END IF;
      ELSE
        v_damage := ((v_actor_stats->>'grappling')::numeric * (0.3 + random() * 0.5)) / 15.0;
        IF v_target_key = 'a' THEN
          v_round_damage_a := v_round_damage_a + v_damage;
        ELSE
          v_round_damage_b := v_round_damage_b + v_damage;
        END IF;
        v_state := jsonb_set(
          v_state,
          ARRAY[v_target_key, 'round_damage'],
          to_jsonb((v_state->v_target_key->>'round_damage')::numeric + v_damage)
        );
        v_state := jsonb_set(
          v_state,
          ARRAY[v_target_key, 'damage'],
          to_jsonb((v_state->v_target_key->>'damage')::numeric + v_damage)
        );
        PERFORM public.insert_fight_event(
          p_fight_id, v_for_round, 'strike', v_actor, v_target,
          'Ground-and-pound from ' || (SELECT name FROM public.fighters WHERE id = v_actor) || '.',
          jsonb_build_object('damage', round(v_damage::numeric, 1), 'position', 'ground')
        );
        IF random() < 0.15 THEN
          v_position := 'standing';
        END IF;
      END IF;
    END IF;
  END LOOP;

  IF NOT v_finish THEN
    IF v_round_damage_b > v_round_damage_a + 1 THEN
      v_round_winner := 'a';
    ELSIF v_round_damage_a > v_round_damage_b + 1 THEN
      v_round_winner := 'b';
    ELSIF random() < 0.5 THEN
      v_round_winner := 'a';
    ELSE
      v_round_winner := 'b';
    END IF;

    v_state := jsonb_set(
      v_state,
      ARRAY[v_round_winner, 'rounds_won'],
      to_jsonb((v_state->v_round_winner->>'rounds_won')::int + 1)
    );

    PERFORM public.insert_fight_event(
      p_fight_id, v_for_round, 'round_end', NULL, NULL,
      'End of round ' || v_for_round || '. ' ||
        CASE v_round_winner
          WHEN 'a' THEN v_name_a || ' takes the round on our scorecard.'
          ELSE v_name_b || ' takes the round on our scorecard.'
        END,
      jsonb_build_object(
        'round_winner', v_round_winner,
        'damage_a', round(v_round_damage_a, 1),
        'damage_b', round(v_round_damage_b, 1)
      )
    );
  END IF;

  IF v_finish THEN
    IF v_finish_method <> 'Submission' THEN
      PERFORM public.insert_fight_event(
        p_fight_id, v_for_round, 'finish', v_finish_actor,
        CASE WHEN v_finish_actor = v_fight.fighter_a_id THEN v_fight.fighter_b_id ELSE v_fight.fighter_a_id END,
        (SELECT name FROM public.fighters WHERE id = v_finish_actor) || ' wins by ' || v_finish_method || '!',
        jsonb_build_object('method', v_finish_method)
      );
    END IF;

    UPDATE public.fights
    SET current_round = v_for_round,
        fight_state = v_state,
        winner_id = v_finish_actor,
        method = v_finish_method,
        round = v_for_round,
        status = 'completed',
        commentary = COALESCE(commentary, '[]'::jsonb) || to_jsonb(ARRAY[
          'Round ' || v_for_round || ': ' || (SELECT name FROM public.fighters WHERE id = v_finish_actor) ||
            ' finishes the fight by ' || v_finish_method || '.'
        ])
    WHERE id = p_fight_id;
    RETURN;
  END IF;

  v_total_damage_a := (v_state->'a'->>'damage')::numeric;
  v_total_damage_b := (v_state->'b'->>'damage')::numeric;

  IF v_for_round >= COALESCE(v_fight.max_rounds, 3) THEN
    IF (v_state->'a'->>'rounds_won')::int > (v_state->'b'->>'rounds_won')::int THEN
      v_winner_key := 'a';
    ELSIF (v_state->'b'->>'rounds_won')::int > (v_state->'a'->>'rounds_won')::int THEN
      v_winner_key := 'b';
    ELSIF v_total_damage_b > v_total_damage_a THEN
      v_winner_key := 'a';
    ELSE
      v_winner_key := 'b';
    END IF;

    UPDATE public.fights
    SET current_round = v_for_round,
        fight_state = v_state,
        winner_id = CASE WHEN v_winner_key = 'a' THEN v_fight.fighter_a_id ELSE v_fight.fighter_b_id END,
        method = 'Decision',
        round = v_for_round,
        status = 'completed',
        commentary = COALESCE(commentary, '[]'::jsonb) || to_jsonb(ARRAY[
          'The fight goes the distance.',
          CASE WHEN v_winner_key = 'a' THEN v_name_a ELSE v_name_b END || ' wins by Decision.'
        ])
    WHERE id = p_fight_id;
    RETURN;
  END IF;

  UPDATE public.fights
  SET current_round = v_for_round,
      fight_state = v_state,
      status = 'between_rounds',
      commentary = COALESCE(commentary, '[]'::jsonb) || to_jsonb(ARRAY[
        'Round ' || v_for_round || ' complete.'
      ])
  WHERE id = p_fight_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Post-fight finalization (records, titles, news)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.finalize_fight(p_fight_id uuid, p_completed_at_week int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fight RECORD;
  v_event RECORD;
  v_winner_id uuid;
  v_loser_id uuid;
  v_method text;
  v_round int;
  v_winner_name text;
  v_loser_name text;
  v_winner_gym uuid;
  v_loser_gym uuid;
  v_old_champ_id uuid;
BEGIN
  SELECT f.*, e.name AS event_name, e.promotion_id
  INTO v_fight
  FROM public.fights f
  JOIN public.events e ON e.id = f.event_id
  WHERE f.id = p_fight_id;

  IF NOT FOUND OR v_fight.status <> 'completed' OR v_fight.winner_id IS NULL THEN
    RETURN;
  END IF;

  IF v_fight.completed_at_week IS NOT NULL THEN
    RETURN;
  END IF;

  v_winner_id := v_fight.winner_id;
  v_loser_id := CASE
    WHEN v_winner_id = v_fight.fighter_a_id THEN v_fight.fighter_b_id
    ELSE v_fight.fighter_a_id
  END;
  v_method := v_fight.method;
  v_round := v_fight.round;

  SELECT name, gym_id INTO v_winner_name, v_winner_gym FROM public.fighters WHERE id = v_winner_id;
  SELECT name, gym_id INTO v_loser_name, v_loser_gym FROM public.fighters WHERE id = v_loser_id;

  UPDATE public.fights
  SET completed_at_week = p_completed_at_week
  WHERE id = p_fight_id;

  UPDATE public.fighters
  SET wins = wins + 1,
      ko_wins = ko_wins + CASE WHEN v_method IN ('KO', 'TKO') THEN 1 ELSE 0 END,
      sub_wins = sub_wins + CASE WHEN v_method = 'Submission' THEN 1 ELSE 0 END,
      dec_wins = dec_wins + CASE WHEN v_method = 'Decision' THEN 1 ELSE 0 END
  WHERE id = v_winner_id;

  UPDATE public.fighters SET losses = losses + 1 WHERE id = v_loser_id;

  IF v_winner_gym IS NOT NULL THEN
    UPDATE public.gyms SET wins = wins + 1, reputation = reputation + 2 WHERE id = v_winner_gym;
  END IF;
  IF v_loser_gym IS NOT NULL THEN
    UPDATE public.gyms SET losses = losses + 1 WHERE id = v_loser_gym;
  END IF;

  IF v_fight.is_title_fight AND v_fight.championship_id IS NOT NULL THEN
    SELECT current_champion_fighter_id INTO v_old_champ_id
    FROM public.championships WHERE id = v_fight.championship_id;

    IF v_old_champ_id IS NOT NULL AND v_winner_id = v_old_champ_id THEN
      UPDATE public.title_history SET defenses = defenses + 1
      WHERE championship_id = v_fight.championship_id
        AND fighter_id = v_winner_id AND lost_at_week IS NULL;

      INSERT INTO public.news_items (week, type, title, body, fighter_id, promotion_id)
      VALUES (p_completed_at_week, 'title_defense',
        v_winner_name || ' retains the title',
        v_winner_name || ' successfully defended the championship at ' || v_fight.event_name ||
          ' via ' || v_method || ' in round ' || v_round || '.',
        v_winner_id, v_fight.promotion_id);
    ELSE
      IF v_old_champ_id IS NOT NULL THEN
        UPDATE public.title_history SET lost_at_week = p_completed_at_week
        WHERE championship_id = v_fight.championship_id
          AND fighter_id = v_old_champ_id AND lost_at_week IS NULL;
        UPDATE public.fighters SET career_status = 'contender' WHERE id = v_old_champ_id;
      END IF;

      UPDATE public.championships
      SET current_champion_fighter_id = v_winner_id,
          last_title_fight_at_week = p_completed_at_week
      WHERE id = v_fight.championship_id;

      INSERT INTO public.title_history (championship_id, fighter_id, won_at_week, defenses)
      VALUES (v_fight.championship_id, v_winner_id, p_completed_at_week, 0);

      UPDATE public.fighters SET career_status = 'champion' WHERE id = v_winner_id;

      UPDATE public.gyms
      SET champions_produced = champions_produced + 1, reputation = reputation + 25
      WHERE id = (SELECT gym_id FROM public.fighters WHERE id = v_winner_id)
        AND id IS NOT NULL;

      INSERT INTO public.news_items (week, type, title, body, fighter_id, promotion_id)
      VALUES (p_completed_at_week, 'champion_crowned',
        v_winner_name || ' is the NEW champion!',
        CASE WHEN v_old_champ_id IS NULL THEN
          v_winner_name || ' captures the vacant title at ' || v_fight.event_name || '.'
        ELSE
          v_winner_name || ' defeats ' ||
            (SELECT name FROM public.fighters WHERE id = v_old_champ_id) ||
            ' for the championship at ' || v_fight.event_name || '.'
        END,
        v_winner_id, v_fight.promotion_id);
    END IF;
  ELSE
    INSERT INTO public.news_items (week, type, title, body, fighter_id, promotion_id)
    VALUES (p_completed_at_week, 'event_result',
      v_winner_name || ' defeats ' || v_loser_name,
      v_winner_name || ' defeated ' || v_loser_name || ' by ' ||
        v_method || ' in round ' || v_round || ' at ' || v_fight.event_name || '.',
      v_winner_id, v_fight.promotion_id);
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Fight flow orchestration
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.open_fight_plan_window(p_fight_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_for_round int;
BEGIN
  SELECT current_round + 1 INTO v_for_round FROM public.fights WHERE id = p_fight_id;
  PERFORM public.ensure_ai_game_plans(p_fight_id, v_for_round);
  UPDATE public.fights SET status = 'awaiting_plans' WHERE id = p_fight_id;
  PERFORM public.try_advance_fight(p_fight_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.try_advance_fight(p_fight_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fight RECORD;
  v_for_round int;
  v_tick int;
  v_event_id uuid;
BEGIN
  SELECT * INTO v_fight FROM public.fights WHERE id = p_fight_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_fight.status NOT IN ('awaiting_plans', 'between_rounds') THEN
    RETURN;
  END IF;

  v_for_round := v_fight.current_round + 1;
  PERFORM public.ensure_ai_game_plans(p_fight_id, v_for_round);

  IF NOT public.both_fight_plans_ready(p_fight_id, v_for_round) THEN
    IF v_fight.status = 'between_rounds' THEN
      UPDATE public.fights SET status = 'awaiting_plans' WHERE id = p_fight_id;
    END IF;
    RETURN;
  END IF;

  UPDATE public.fights SET status = 'in_progress' WHERE id = p_fight_id;
  PERFORM public.simulate_fight_round(p_fight_id);

  SELECT * INTO v_fight FROM public.fights WHERE id = p_fight_id;

  IF v_fight.status = 'completed' THEN
    v_tick := public.get_current_week();
    PERFORM public.finalize_fight(p_fight_id, v_tick);
    v_event_id := v_fight.event_id;
    PERFORM public.start_next_event_fight(v_event_id);
    RETURN;
  END IF;

  PERFORM public.open_fight_plan_window(p_fight_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.start_next_event_fight(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fight RECORD;
  v_fa_name text;
  v_fb_name text;
  v_tick int;
  v_pending int;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.fights
    WHERE event_id = p_event_id
      AND status IN ('awaiting_plans', 'in_progress', 'between_rounds')
  ) THEN
    RETURN;
  END IF;

  SELECT f.* INTO v_fight
  FROM public.fights f
  WHERE f.event_id = p_event_id AND f.status = 'pending'
  ORDER BY f.card_order NULLS LAST, f.is_title_fight DESC, f.id
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    v_tick := public.get_current_week();
    UPDATE public.events
    SET status = 'completed', completed_at_week = v_tick
    WHERE id = p_event_id AND status = 'live';

    PERFORM public.refresh_promotion_rankings(v_tick);
    RETURN;
  END IF;

  SELECT name INTO v_fa_name FROM public.fighters WHERE id = v_fight.fighter_a_id;
  SELECT name INTO v_fb_name FROM public.fighters WHERE id = v_fight.fighter_b_id;

  UPDATE public.fights
  SET status = 'awaiting_plans',
      current_round = 0,
      max_rounds = CASE WHEN v_fight.is_title_fight THEN 5 ELSE 3 END,
      fight_state = public.init_fight_state(),
      card_order = COALESCE(v_fight.card_order, 1)
  WHERE id = v_fight.id;

  PERFORM public.insert_fight_event(
    v_fight.id, 0, 'intro', NULL, NULL,
    CASE WHEN v_fight.is_title_fight THEN
      'Championship bout: ' || v_fa_name || ' vs ' || v_fb_name || '.'
    ELSE
      v_fa_name || ' and ' || v_fb_name || ' touch gloves.'
    END,
    jsonb_build_object('kind', 'intro')
  );

  PERFORM public.open_fight_plan_window(v_fight.id);
  PERFORM public.try_advance_fight(v_fight.id);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_fight_game_plan(
  p_fight_id uuid,
  p_fighter_id uuid,
  p_preset text,
  p_pressure int,
  p_distance int,
  p_takedown_freq int,
  p_risk int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fight RECORD;
  v_fighter RECORD;
  v_gym RECORD;
  v_for_round int;
BEGIN
  IF p_preset NOT IN ('striker', 'grappler', 'counter', 'volume') THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Invalid game plan preset.');
  END IF;

  SELECT * INTO v_fight FROM public.fights WHERE id = p_fight_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fight not found.');
  END IF;

  IF v_fight.status NOT IN ('awaiting_plans', 'between_rounds') THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fight is not accepting game plans right now.');
  END IF;

  IF p_fighter_id NOT IN (v_fight.fighter_a_id, v_fight.fighter_b_id) THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fighter is not in this bout.');
  END IF;

  SELECT * INTO v_fighter FROM public.fighters WHERE id = p_fighter_id;
  IF v_fighter.gym_id IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'This corner is managed automatically.');
  END IF;

  SELECT * INTO v_gym FROM public.gyms WHERE id = v_fighter.gym_id AND owner_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'You do not manage this fighter.');
  END IF;

  v_for_round := v_fight.current_round + 1;

  INSERT INTO public.fight_game_plans (
    fight_id, fighter_id, gym_id, for_round, preset,
    pressure, distance, takedown_freq, risk
  )
  VALUES (
    p_fight_id, p_fighter_id, v_fighter.gym_id, v_for_round, p_preset,
    LEAST(100, GREATEST(0, p_pressure)),
    LEAST(100, GREATEST(0, p_distance)),
    LEAST(100, GREATEST(0, p_takedown_freq)),
    LEAST(100, GREATEST(0, p_risk))
  )
  ON CONFLICT (fight_id, fighter_id, for_round) DO UPDATE SET
    preset = EXCLUDED.preset,
    pressure = EXCLUDED.pressure,
    distance = EXCLUDED.distance,
    takedown_freq = EXCLUDED.takedown_freq,
    risk = EXCLUDED.risk,
    submitted_at = now();

  PERFORM public.try_advance_fight(p_fight_id);

  RETURN jsonb_build_object('status', 'ok', 'message', 'Game plan submitted.', 'for_round', v_for_round);
END;
$$;

CREATE OR REPLACE FUNCTION public.start_event(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_tick int;
  v_event RECORD;
  v_pending_offers int;
  v_unconfirmed_pvp int;
  v_pending_fights int;
  v_active_fights int;
BEGIN
  v_tick := public.get_current_week();

  SELECT e.* INTO v_event FROM public.events e WHERE e.id = p_event_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Event not found.');
  END IF;

  IF NOT public.promotion_owner_check(v_event.promotion_id) THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'You do not own this promotion.');
  END IF;

  IF v_event.status NOT IN ('scheduled', 'live') THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Event has already finished.');
  END IF;

  IF v_tick < v_event.scheduled_week THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Event date has not been reached yet.');
  END IF;

  IF v_event.status = 'scheduled' THEN
    SELECT count(*) INTO v_pending_offers
    FROM public.fight_offers fo
    WHERE fo.event_id = p_event_id AND fo.status = 'pending';

    IF v_pending_offers > 0 THEN
      RETURN jsonb_build_object('status', 'error', 'message', 'Pending fight offers must be resolved before starting the event.');
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
        'message', 'Player vs player bookings must be confirmed by both gyms before starting the event.'
      );
    END IF;

    SELECT count(*) INTO v_pending_fights
    FROM public.fights f WHERE f.event_id = p_event_id AND f.status = 'pending';

    IF v_pending_fights = 0 THEN
      SELECT count(*) INTO v_active_fights
      FROM public.fights f
      WHERE f.event_id = p_event_id
        AND f.status IN ('awaiting_plans', 'in_progress', 'between_rounds');

      IF v_active_fights = 0 THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'No confirmed fights on the card.');
      END IF;
    END IF;

    WITH ordered AS (
      SELECT id, row_number() OVER (
        ORDER BY is_title_fight DESC, id
      ) AS rn
      FROM public.fights
      WHERE event_id = p_event_id AND status = 'pending'
    )
    UPDATE public.fights f
    SET card_order = ordered.rn
    FROM ordered
    WHERE f.id = ordered.id;

    UPDATE public.events SET status = 'live' WHERE id = p_event_id;
    PERFORM public.start_next_event_fight(p_event_id);
  ELSE
    PERFORM public.start_next_event_fight(p_event_id);
  END IF;

  RETURN jsonb_build_object(
    'status', 'ok',
    'message', 'Event started. Fights will play out round by round as managers submit game plans.',
    'event_status', 'live'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.run_event(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN public.start_event(p_event_id);
END;
$$;
