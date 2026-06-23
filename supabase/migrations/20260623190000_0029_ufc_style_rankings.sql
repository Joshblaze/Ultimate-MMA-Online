/*
# UFC-style promotion rankings

- Composite ranking score: bayesian win rate, promo win volume, win/loss streak,
  previous rank inertia, and small-sample penalty (1-0 cannot jump to the top).
- Active champions excluded from the top-15 list (belt tracked separately).
*/

CREATE OR REPLACE FUNCTION public.promotion_fighter_streak(
  p_fighter_id uuid,
  p_promotion_id uuid
)
RETURNS TABLE (win_streak int, loss_streak int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fight RECORD;
  v_mode text := NULL;
  v_win_streak int := 0;
  v_loss_streak int := 0;
BEGIN
  FOR v_fight IN
    SELECT
      CASE
        WHEN fi.winner_id = p_fighter_id THEN 'W'
        WHEN fi.winner_id IS NULL THEN 'D'
        ELSE 'L'
      END AS outcome
    FROM public.fights fi
    JOIN public.events e ON e.id = fi.event_id AND e.promotion_id = p_promotion_id
    WHERE fi.status = 'completed'
      AND p_fighter_id IN (fi.fighter_a_id, fi.fighter_b_id)
    ORDER BY fi.completed_at_week DESC NULLS LAST, fi.id DESC
  LOOP
    IF v_mode IS NULL THEN
      IF v_fight.outcome = 'W' THEN
        v_mode := 'W';
        v_win_streak := 1;
      ELSIF v_fight.outcome = 'L' THEN
        v_mode := 'L';
        v_loss_streak := 1;
      ELSE
        EXIT;
      END IF;
    ELSIF v_mode = 'W' AND v_fight.outcome = 'W' THEN
      v_win_streak := v_win_streak + 1;
    ELSIF v_mode = 'L' AND v_fight.outcome = 'L' THEN
      v_loss_streak := v_loss_streak + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;

  RETURN QUERY SELECT v_win_streak, v_loss_streak;
END;
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
    - LEAST(streak.loss_streak, 3) * 15.0
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

CREATE OR REPLACE FUNCTION public.refresh_promotion_rankings(p_tick int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_promo RECORD;
  v_wc RECORD;
  v_fighter RECORD;
  v_rank int;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _rank_snapshot (
    promotion_id uuid,
    weight_class text,
    fighter_id uuid,
    rank_position int
  ) ON COMMIT DROP;

  TRUNCATE _rank_snapshot;
  INSERT INTO _rank_snapshot (promotion_id, weight_class, fighter_id, rank_position)
  SELECT promotion_id, weight_class, fighter_id, rank_position
  FROM public.rankings;

  FOR v_promo IN SELECT id FROM public.promotions LOOP
    FOR v_wc IN SELECT name FROM public.weight_classes ORDER BY "order" LOOP
      DELETE FROM public.rankings
      WHERE promotion_id = v_promo.id
        AND weight_class = v_wc.name;

      v_rank := 1;
      FOR v_fighter IN
        SELECT f.id
        FROM public.fighters f
        LEFT JOIN _rank_snapshot prev
          ON prev.fighter_id = f.id
          AND prev.promotion_id = v_promo.id
          AND prev.weight_class = v_wc.name
        WHERE f.weight_class = v_wc.name
          AND f.retired = false
          AND public.fighter_is_promotion_signed(f.id, v_promo.id)
          AND NOT public.fighter_holds_promotion_title(f.id, v_promo.id)
        ORDER BY
          public.promotion_fighter_ranking_score(f.id, v_promo.id, prev.rank_position) DESC,
          f.current_skill DESC,
          f.popularity DESC,
          f.id
        LIMIT 15
      LOOP
        INSERT INTO public.rankings (promotion_id, weight_class, fighter_id, rank_position, updated_at_week)
        VALUES (v_promo.id, v_wc.name, v_fighter.id, v_rank, p_tick);
        v_rank := v_rank + 1;
      END LOOP;
    END LOOP;
  END LOOP;
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

      DELETE FROM public.rankings
      WHERE promotion_id = v_promo.id
        AND weight_class = v_wc.name;

      v_rank := 1;
      FOR v_fighter IN
        SELECT f.id
        FROM public.fighters f
        WHERE f.weight_class = v_wc.name
          AND f.retired = false
          AND public.fighter_is_promotion_signed(f.id, v_promo.id)
          AND NOT public.fighter_holds_promotion_title(f.id, v_promo.id)
        ORDER BY
          public.promotion_fighter_ranking_score(f.id, v_promo.id, NULL) DESC,
          f.current_skill DESC,
          f.popularity DESC,
          f.id
        LIMIT 15
      LOOP
        INSERT INTO public.rankings (promotion_id, weight_class, fighter_id, rank_position, updated_at_week)
        VALUES (v_promo.id, v_wc.name, v_fighter.id, v_rank, v_week);
        v_rank := v_rank + 1;
      END LOOP;
    END LOOP;
  END LOOP;
  RETURN 1;
END;
$$;

DROP FUNCTION IF EXISTS public.promotion_ranking_stats(uuid);

CREATE OR REPLACE FUNCTION public.promotion_ranking_stats(p_promotion_id uuid)
RETURNS TABLE (
  fighter_id uuid,
  promo_wins int,
  promo_losses int,
  promo_draws int,
  promo_total int,
  promo_win_pct numeric,
  promo_win_streak int,
  promo_loss_streak int,
  ranking_score numeric
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
    rec.win_pct AS promo_win_pct,
    streak.win_streak AS promo_win_streak,
    streak.loss_streak AS promo_loss_streak,
    public.promotion_fighter_ranking_score(
      f.id,
      p_promotion_id,
      r.rank_position
    ) AS ranking_score
  FROM public.fighters f
  CROSS JOIN LATERAL public.promotion_fighter_record(f.id, p_promotion_id) rec
  CROSS JOIN LATERAL public.promotion_fighter_streak(f.id, p_promotion_id) streak
  LEFT JOIN public.rankings r
    ON r.fighter_id = f.id
    AND r.promotion_id = p_promotion_id
    AND r.weight_class = f.weight_class
  WHERE public.fighter_is_promotion_signed(f.id, p_promotion_id);
$$;

DO $$
DECLARE
  v_tick int;
BEGIN
  SELECT tick_count INTO v_tick FROM public.world_state WHERE id = 1;
  PERFORM public.refresh_promotion_rankings(COALESCE(v_tick, 0));
END;
$$;
