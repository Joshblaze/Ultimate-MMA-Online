/*
# Fix championship belts staying vacant

Migration 0016 skipped title fights whenever any fight existed for a weight class
on the card. Regular bouts ran first, blocking title bouts and preventing
current_champion_fighter_id from being set.
*/

UPDATE public.championships c
SET current_champion_fighter_id = sub.winner_id
FROM (
  SELECT DISTINCT ON (f.championship_id)
    f.championship_id,
    f.winner_id
  FROM public.fights f
  WHERE f.is_title_fight = true
    AND f.status = 'completed'
    AND f.championship_id IS NOT NULL
    AND f.winner_id IS NOT NULL
  ORDER BY f.championship_id, f.completed_at_week DESC NULLS LAST, f.id DESC
) sub
WHERE c.id = sub.championship_id;

INSERT INTO public.title_history (championship_id, fighter_id, won_at_week, defenses)
SELECT c.id, c.current_champion_fighter_id, COALESCE(f.completed_at_week, 0), 0
FROM public.championships c
JOIN LATERAL (
  SELECT completed_at_week
  FROM public.fights
  WHERE championship_id = c.id
    AND is_title_fight = true
    AND status = 'completed'
    AND winner_id = c.current_champion_fighter_id
  ORDER BY completed_at_week DESC NULLS LAST, id DESC
  LIMIT 1
) f ON true
WHERE c.current_champion_fighter_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.title_history th
    WHERE th.championship_id = c.id
      AND th.fighter_id = c.current_champion_fighter_id
      AND th.lost_at_week IS NULL
  );

UPDATE public.fighters f
SET career_status = 'champion'
FROM public.championships c
WHERE c.current_champion_fighter_id = f.id
  AND f.career_status IS DISTINCT FROM 'champion';

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

  FOR v_events_to_process IN
    SELECT e.id, e.promotion_id, e.name FROM public.events e
    WHERE e.status = 'scheduled' AND e.scheduled_week <= v_new_tick
  LOOP
    v_events_processed := v_events_processed + 1;
    v_purse_base := (SELECT tier FROM public.promotions WHERE id = v_events_to_process.promotion_id) * 5000;

    -- Title fights before regular bouts so belts can be contested on the same card.
    FOR v_champion IN
      SELECT c.id AS champ_id, c.weight_class, c.current_champion_fighter_id AS champ_fighter, c.promotion_id
      FROM public.championships c WHERE c.promotion_id = v_events_to_process.promotion_id
    LOOP
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
      ) THEN
        CONTINUE;
      END IF;

      IF v_champion.champ_fighter IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.fighters
        WHERE id = v_champion.champ_fighter AND gym_id IS NOT NULL
      ) AND NOT EXISTS (
        SELECT 1 FROM public.fights f
        WHERE f.event_id = v_events_to_process.id
          AND f.status = 'pending'
          AND v_champion.champ_fighter IN (f.fighter_a_id, f.fighter_b_id)
      ) THEN
        CONTINUE;
      END IF;

      IF v_champion.champ_fighter IS NULL THEN
        IF random() < 0.6 THEN
          v_contender_1 := NULL; v_contender_2 := NULL;
          SELECT r.fighter_id INTO v_contender_1
          FROM public.rankings r
          JOIN public.fighters f ON f.id = r.fighter_id
          WHERE r.promotion_id = v_champion.promotion_id AND r.weight_class = v_champion.weight_class
            AND f.gym_id IS NULL AND f.promotion_id = v_champion.promotion_id
          ORDER BY r.rank_position ASC LIMIT 1 OFFSET 0;
          SELECT r.fighter_id INTO v_contender_2
          FROM public.rankings r
          JOIN public.fighters f ON f.id = r.fighter_id
          WHERE r.promotion_id = v_champion.promotion_id AND r.weight_class = v_champion.weight_class
            AND f.gym_id IS NULL AND f.promotion_id = v_champion.promotion_id
            AND r.fighter_id IS DISTINCT FROM v_contender_1
          ORDER BY r.rank_position ASC LIMIT 1 OFFSET 0;

          IF v_contender_1 IS NULL OR v_contender_2 IS NULL THEN
            SELECT id INTO v_contender_1 FROM public.fighters
            WHERE promotion_id = v_champion.promotion_id AND weight_class = v_champion.weight_class
              AND retired = false AND gym_id IS NULL
            ORDER BY current_skill DESC, popularity DESC LIMIT 1 OFFSET 0;
            SELECT id INTO v_contender_2 FROM public.fighters
            WHERE promotion_id = v_champion.promotion_id AND weight_class = v_champion.weight_class
              AND retired = false AND gym_id IS NULL AND id IS DISTINCT FROM v_contender_1
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
          SELECT r.fighter_id INTO v_opp
          FROM public.rankings r
          JOIN public.fighters f ON f.id = r.fighter_id
          WHERE r.promotion_id = v_champion.promotion_id AND r.weight_class = v_champion.weight_class
            AND r.fighter_id <> v_champion.champ_fighter AND f.gym_id IS NULL
            AND f.promotion_id = v_champion.promotion_id
          ORDER BY r.rank_position ASC LIMIT 1;

          IF v_opp IS NULL THEN
            SELECT id INTO v_opp FROM public.fighters
            WHERE promotion_id = v_champion.promotion_id AND weight_class = v_champion.weight_class
              AND retired = false AND gym_id IS NULL AND id <> v_champion.champ_fighter
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
      END IF;
    END LOOP;

    FOR v_wc IN SELECT name FROM public.weight_classes ORDER BY "order" LOOP
      SELECT count(*) INTO v_count FROM public.fights WHERE event_id = v_events_to_process.id AND weight_class = v_wc.name;
      IF v_count > 0 THEN CONTINUE; END IF;

      v_fighter_a := NULL; v_fighter_b := NULL;
      SELECT id INTO v_fighter_a FROM public.fighters
      WHERE promotion_id = v_events_to_process.promotion_id AND weight_class = v_wc.name
        AND retired = false AND gym_id IS NULL
      ORDER BY random() LIMIT 1;

      IF v_fighter_a IS NOT NULL THEN
        SELECT id INTO v_fighter_b FROM public.fighters
        WHERE promotion_id = v_events_to_process.promotion_id AND weight_class = v_wc.name
          AND retired = false AND id <> v_fighter_a AND gym_id IS NULL
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

  FOR v_promo IN SELECT id FROM public.promotions LOOP
    FOR v_wc IN SELECT name FROM public.weight_classes ORDER BY "order" LOOP
      v_rank := 1;
      FOR v_fighter IN
        SELECT id FROM public.fighters
        WHERE weight_class = v_wc.name AND retired = false
          AND (promotion_id = v_promo.id OR gym_id IS NOT NULL)
        ORDER BY current_skill DESC, popularity DESC, wins DESC LIMIT 15
      LOOP
        INSERT INTO public.rankings (promotion_id, weight_class, fighter_id, rank_position, updated_at_week)
        VALUES (v_promo.id, v_wc.name, v_fighter.id, v_rank, v_new_tick)
        ON CONFLICT (promotion_id, weight_class, rank_position)
        DO UPDATE SET fighter_id = EXCLUDED.fighter_id, updated_at_week = EXCLUDED.updated_at_week;
        v_rank := v_rank + 1;
      END LOOP;
    END LOOP;
  END LOOP;

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
      ) THEN
        CONTINUE;
      END IF;

      IF random() < LEAST(0.4, (v_fighter.current_skill + v_gym.reputation) / 300.0) THEN
        SELECT count(*) INTO v_offer_count FROM public.fight_offers
        WHERE gym_id = v_gym.id AND status = 'pending' AND fighter_id = v_fighter.id;
        IF v_offer_count < 3 THEN
          v_opp := NULL;
          SELECT id INTO v_opp FROM public.fighters
          WHERE promotion_id IS NOT NULL AND gym_id IS NULL
            AND weight_class = v_fighter.weight_class AND retired = false
            AND ABS(current_skill - v_fighter.current_skill) <= 15
          ORDER BY random() LIMIT 1;

          IF v_opp IS NOT NULL THEN
            v_promo_offer_id := NULL; v_promo_offer_tier := NULL;
            SELECT id, tier INTO v_promo_offer_id, v_promo_offer_tier FROM public.promotions
            WHERE owner_kind = 'ai' AND tier >= GREATEST(1, v_gym.tier) AND tier <= v_gym.tier + 1
            ORDER BY random() LIMIT 1;

            IF v_promo_offer_id IS NOT NULL THEN
              v_purse_base := v_promo_offer_tier * 5000 + GREATEST(0, (v_fighter.current_skill - 50) * 200);
              INSERT INTO public.fight_offers (gym_id, fighter_id, opponent_fighter_id, promotion_id, event_id,
                purse, scheduled_week, status, offered_at_week)
              VALUES (v_gym.id, v_fighter.id, v_opp, v_promo_offer_id, NULL,
                v_purse_base, v_new_tick + 4 + floor(random() * 2)::int, 'pending', v_new_tick);
              v_offers_generated := v_offers_generated + 1;
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

  UPDATE public.contracts SET status = 'expired' WHERE status = 'active' AND expires_week <= v_new_tick;
  UPDATE public.fighters SET promotion_id = NULL
  WHERE id IN (SELECT fighter_id FROM public.contracts WHERE status = 'expired') AND gym_id IS NULL;
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
