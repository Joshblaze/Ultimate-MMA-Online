/*
# Rankings only for actively signed promotion fighters

- A fighter must be signed to a promotion (matching promotion_id + active contract,
  or holding that promotion's title) to appear in its rankings.
- Rebuild rankings each tick and clear vacant slots so unsigned fighters drop off.
*/

CREATE OR REPLACE FUNCTION public.fighter_is_promotion_signed(
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
    FROM public.fighters f
    WHERE f.id = p_fighter_id
      AND f.promotion_id = p_promotion_id
      AND f.retired = false
      AND (
        public.fighter_holds_promotion_title(p_fighter_id, p_promotion_id)
        OR EXISTS (
          SELECT 1
          FROM public.contracts c
          WHERE c.fighter_id = p_fighter_id
            AND c.promotion_id = p_promotion_id
            AND c.status = 'active'
            AND c.fights_remaining > 0
        )
      )
  );
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
  FOR v_promo IN SELECT id FROM public.promotions LOOP
    FOR v_wc IN SELECT name FROM public.weight_classes ORDER BY "order" LOOP
      DELETE FROM public.rankings
      WHERE promotion_id = v_promo.id
        AND weight_class = v_wc.name;

      v_rank := 1;
      FOR v_fighter IN
        SELECT f.id
        FROM public.fighters f
        LEFT JOIN LATERAL public.promotion_fighter_record(f.id, v_promo.id) rec ON true
        WHERE f.weight_class = v_wc.name
          AND f.retired = false
          AND public.fighter_is_promotion_signed(f.id, v_promo.id)
        ORDER BY rec.win_pct DESC, f.id
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
        LEFT JOIN LATERAL public.promotion_fighter_record(f.id, v_promo.id) rec ON true
        WHERE f.weight_class = v_wc.name
          AND f.retired = false
          AND public.fighter_is_promotion_signed(f.id, v_promo.id)
        ORDER BY rec.win_pct DESC, f.id
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
  WHERE public.fighter_is_promotion_signed(f.id, p_promotion_id);
$$;

-- Rebuild rankings now so unsigned / stale entries are removed immediately.
DO $$
DECLARE
  v_tick int;
BEGIN
  SELECT tick_count INTO v_tick FROM public.world_state WHERE id = 1;
  PERFORM public.refresh_promotion_rankings(COALESCE(v_tick, 0));
END;
$$;
