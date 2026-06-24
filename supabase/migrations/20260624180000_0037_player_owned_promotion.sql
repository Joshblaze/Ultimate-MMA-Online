/*
# Player-owned promotion redesign

- Single promotion, 100 rookie fighters (stats capped under 40)
- Admin assigns promotion owner; owner manually schedules events and fights
- 4-week event lead time, 2-week offer response window
- No AI roster signing, event scheduling, matchmaking, or offer generation
- Owner manually runs events when ready
*/

-- ---------------------------------------------------------------------------
-- Schema: offer response deadline; nullable opponent for contract-only offers
-- ---------------------------------------------------------------------------

ALTER TABLE public.fight_offers
  ADD COLUMN IF NOT EXISTS response_deadline_week int;

UPDATE public.fight_offers
SET response_deadline_week = offered_at_week + 2
WHERE response_deadline_week IS NULL;

ALTER TABLE public.fight_offers
  ALTER COLUMN response_deadline_week SET NOT NULL;

ALTER TABLE public.fight_offers
  ALTER COLUMN opponent_fighter_id DROP NOT NULL;

-- ---------------------------------------------------------------------------
-- World seed: 100 fighters, stats under 40
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_fighters(p_count int DEFAULT 100)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_count int := 0;
  v_wc text[];
  v_countries text[];
  v_first text[];
  v_last text[];
  v_week int;
  v_i int;
  v_age int;
  v_potential int;
  v_skill int;
  v_country text;
  v_wc_row text;
  v_boxing int; v_kick int; v_wrestle int; v_bjj int;
  v_cardio int; v_chin int; v_iq int; v_ath int;
  v_status text;
  v_name text;
  v_first_name text;
  v_last_name text;
  v_used_names text[] := '{}';
BEGIN
  IF p_count > 3700 THEN
    RAISE EXCEPTION 'Cannot generate % unique fighters; name pool exhausted', p_count;
  END IF;

  v_week := public.get_current_week();
  v_wc := ARRAY['Flyweight','Bantamweight','Featherweight','Lightweight','Welterweight','Middleweight','Light Heavyweight','Heavyweight'];
  v_countries := ARRAY['USA','Brazil','Mexico','Canada','Ireland','England','Russia','Dagestan','Poland','Nigeria','Australia','Japan','South Korea','Sweden','France','Cuba','Argentina','Germany','Georgia','Ukraine','Kazakhstan','Suriname','Netherlands','Jamaica','Philippines','Kyrgyzstan'];
  v_first := ARRAY['Marcus','Diego','Connor','Khabib','Israel','Alex','Tyron','Daniel','Brock','Junior','Anthony','Max','Justin','Dustin','Charles','Islam','Khamzat','Robert','Sean','Leon','Belal','Gilbert','Michael','Jorge','Rafael','Pedro','Mateusz','Jan','Tom','Ciryl','Alexander','Shavkat','Arman','Renato','Sergei','Volkov','Petr','Aljamain','Merab','Sodiq','Ikram','Mateus','Caio','Trevin','Gabriel','Jailton','Yusuff','Aori','Marcos','Michal','Lerone','David','Bryce','Tony','Kevin','Grant','Melsik','Misha'];
  v_last := ARRAY['Silva','Saint Pierre','McGregor','Nurmagomedov','Adesanya','Volkanovski','Pereira','Jones','Cormier','Lesnar','dos Santos','Pettis','Holloway','Gaethje','Poirier','Oliveira','Makhachev','Chimaev','Whittaker','Strickland','Edwards','Muhammad','Burns','Chandler','Masvidal','Fiziev','Munhoz','Gamrot','Blachowicz','Aspinall','Gane','Volkov','Ngannou','Yan','Sterling','Dvalishvili','Sandhagen','Font','Aldo','Cruz','Emmett','Kattar','Topuria','Holloway','Woodley','Thompson','Edgar','Fabiano','Roberts','Murphy','Vanderford','Eblen','Mix','Kasanganay','Magomedov','Amirkhani','Barcelos','Trizano','Garcia','Hughes','Dariush','Moises','Brito','Puelles'];

  FOR v_i IN 1..p_count LOOP
    v_age := 16 + floor(random() * 18)::int;
    v_potential := 20 + floor(random() * 20)::int;
    v_skill := GREATEST(10, LEAST(39, v_potential - floor(random() * LEAST(15, v_potential - 10))::int));
    v_country := v_countries[1 + floor(random() * array_length(v_countries,1))::int];
    v_wc_row := v_wc[1 + floor(random() * 8)::int];

    LOOP
      v_first_name := v_first[1 + floor(random() * array_length(v_first,1))::int];
      v_last_name := v_last[1 + floor(random() * array_length(v_last,1))::int];
      v_name := v_first_name || ' ' || v_last_name;
      EXIT WHEN NOT (v_name = ANY(v_used_names));
    END LOOP;
    v_used_names := array_append(v_used_names, v_name);

    v_boxing := GREATEST(10, LEAST(39, v_skill + floor((random() - 0.5) * 12)::int));
    v_kick := GREATEST(10, LEAST(39, v_skill + floor((random() - 0.5) * 12)::int));
    v_wrestle := GREATEST(10, LEAST(39, v_skill + floor((random() - 0.5) * 12)::int));
    v_bjj := GREATEST(10, LEAST(39, v_skill + floor((random() - 0.5) * 12)::int));
    v_cardio := GREATEST(10, LEAST(39, v_skill + floor((random() - 0.5) * 10)::int));
    v_chin := GREATEST(10, LEAST(39, v_skill + floor((random() - 0.5) * 12)::int));
    v_iq := GREATEST(10, LEAST(39, v_skill + floor((random() - 0.5) * 10)::int));
    v_ath := GREATEST(10, LEAST(39, v_skill + floor((random() - 0.5) * 11)::int));

    v_status := 'prospect';

    INSERT INTO public.fighters (name, age, country, weight_class,
      boxing, kickboxing, wrestling, bjj, cardio, chin, fight_iq, athleticism,
      potential, current_skill, popularity, career_status,
      wins, losses, draws, ko_wins, sub_wins, dec_wins,
      gym_id, promotion_id, retired, born_week)
    VALUES (v_name, v_age, v_country, v_wc_row,
      v_boxing, v_kick, v_wrestle, v_bjj, v_cardio, v_chin, v_iq, v_ath,
      v_potential, v_skill, LEAST(39, GREATEST(0, (v_skill - 50) * 2)),
      v_status,
      0, 0, 0, 0, 0, 0,
      NULL, NULL, false, v_week);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- Single game-wide promotion
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_promotions()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.promotions (name, tier, country, reputation, fan_base, owner_kind, owned_by_gym_id)
  VALUES ('Ultimate MMA Championship', 5, 'USA', 75, 125000, 'ai', NULL);
  RETURN 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_world()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fighters int;
  v_promos int;
BEGIN
  DELETE FROM public.media_posts;
  DELETE FROM public.news_items;
  DELETE FROM public.fight_offers;
  DELETE FROM public.contracts;
  DELETE FROM public.fights;
  DELETE FROM public.events;
  DELETE FROM public.rankings;
  DELETE FROM public.title_history;
  DELETE FROM public.championships;
  DELETE FROM public.injuries;
  DELETE FROM public.rivalries;
  DELETE FROM public.fighter_personalities;
  DELETE FROM public.fighters;
  DELETE FROM public.sponsorships;
  DELETE FROM public.tv_deals;
  DELETE FROM public.gym_staff;
  DELETE FROM public.coaches;
  DELETE FROM public.facilities;
  DELETE FROM public.promotions;
  DELETE FROM public.gyms;

  UPDATE public.world_state
  SET current_year = 1, current_week = 1, current_month = 1, current_day = 1,
      tick_count = 0, is_paused = false, last_tick_at = now()
  WHERE id = 1;

  v_promos := public.generate_promotions();
  v_fighters := public.generate_fighters(100);
  PERFORM public.seed_championships_and_rankings();

  INSERT INTO public.news_items (week, type, title, body)
  VALUES (0, 'event_result', 'A New Era Begins',
    'A new MMA world has been born. One promotion stands above all, 100 fighters have entered the sport with clean records, and all championships are vacant. The race to crown the first champions begins now.');

  RETURN jsonb_build_object('promotions', v_promos, 'fighters', v_fighters, 'status', 'world_reset');
END;
$$;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.promotion_owner_check(p_promotion_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.promotions p
    JOIN public.gyms g ON g.id = p.owned_by_gym_id
    WHERE p.id = p_promotion_id
      AND p.owner_kind = 'player'
      AND g.owner_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.get_owned_promotion(p_gym_id uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
STABLE
AS $$
DECLARE
  v_gym_id uuid;
BEGIN
  IF p_gym_id IS NOT NULL THEN
    v_gym_id := p_gym_id;
  ELSE
    SELECT id INTO v_gym_id FROM public.gyms WHERE owner_id = auth.uid() LIMIT 1;
  END IF;

  IF v_gym_id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN (
    SELECT id FROM public.promotions
    WHERE owned_by_gym_id = v_gym_id AND owner_kind = 'player'
    LIMIT 1
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_promotion_owner(p_promotion_id uuid, p_gym_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_gym RECORD;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Admin privileges required.');
  END IF;

  SELECT id, name INTO v_gym FROM public.gyms WHERE id = p_gym_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Gym not found.');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.promotions
    WHERE owned_by_gym_id = p_gym_id AND owner_kind = 'player' AND id <> p_promotion_id
  ) THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Gym already owns a promotion.');
  END IF;

  UPDATE public.promotions
  SET owner_kind = 'player', owned_by_gym_id = p_gym_id
  WHERE id = p_promotion_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Promotion not found.');
  END IF;

  UPDATE public.promotions
  SET owner_kind = 'ai', owned_by_gym_id = NULL
  WHERE owner_kind = 'player'
    AND owned_by_gym_id IS NOT NULL
    AND id <> p_promotion_id;

  RETURN jsonb_build_object(
    'status', 'ok',
    'message', 'Promotion assigned to ' || v_gym.name || '.',
    'promotion_id', p_promotion_id,
    'gym_id', p_gym_id
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Event fight simulation (shared by run_event and trigger)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.simulate_event_fights(p_event_id uuid, p_completed_at_week int)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_event RECORD;
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
  v_old_champ_id uuid;
  v_simulated int := 0;
BEGIN
  SELECT e.*, p.name AS promotion_name
  INTO v_event
  FROM public.events e
  JOIN public.promotions p ON p.id = e.promotion_id
  WHERE e.id = p_event_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  FOR v_fight IN
    SELECT f.*
    FROM public.fights f
    WHERE f.event_id = p_event_id AND f.status = 'pending'
    FOR UPDATE
  LOOP
    SELECT current_skill INTO v_a_skill FROM public.fighters WHERE id = v_fight.fighter_a_id;
    SELECT current_skill INTO v_b_skill FROM public.fighters WHERE id = v_fight.fighter_b_id;

    IF v_a_skill + floor(random() * 25)::int >= v_b_skill + floor(random() * 25)::int THEN
      v_winner_id := v_fight.fighter_a_id;
      v_loser_id := v_fight.fighter_b_id;
    ELSE
      v_winner_id := v_fight.fighter_b_id;
      v_loser_id := v_fight.fighter_a_id;
    END IF;

    v_rand := random();
    IF v_fight.is_title_fight THEN
      IF v_rand < 0.30 THEN v_method := 'KO';
      ELSIF v_rand < 0.55 THEN v_method := 'TKO';
      ELSIF v_rand < 0.75 THEN v_method := 'Submission';
      ELSE v_method := 'Decision';
      END IF;
      v_round := CASE WHEN v_method = 'Decision' THEN 5 ELSE 1 + floor(random() * 5)::int END;
    ELSE
      IF v_rand < 0.28 THEN v_method := 'KO';
      ELSIF v_rand < 0.50 THEN v_method := 'TKO';
      ELSIF v_rand < 0.72 THEN v_method := 'Submission';
      ELSE v_method := 'Decision';
      END IF;
      v_round := CASE WHEN v_method = 'Decision' THEN 3 ELSE 1 + floor(random() * 3)::int END;
    END IF;

    SELECT name, gym_id INTO v_winner_name, v_winner_gym FROM public.fighters WHERE id = v_winner_id;
    SELECT name, gym_id INTO v_loser_name, v_loser_gym FROM public.fighters WHERE id = v_loser_id;

    v_commentary := jsonb_build_array(
      CASE WHEN v_fight.is_title_fight THEN
        'Championship bout: ' || v_winner_name || ' vs ' || v_loser_name || '.'
      ELSE
        v_winner_name || ' and ' || v_loser_name || ' touch gloves.'
      END,
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
        completed_at_week = p_completed_at_week
    WHERE id = v_fight.id;

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
          v_winner_name || ' successfully defended the championship at ' || v_event.name ||
            ' via ' || v_method || ' in round ' || v_round || '.',
          v_winner_id, v_event.promotion_id);
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
            v_winner_name || ' captures the vacant title at ' || v_event.name || '.'
          ELSE
            v_winner_name || ' defeats ' ||
              (SELECT name FROM public.fighters WHERE id = v_old_champ_id) ||
              ' for the championship at ' || v_event.name || '.'
          END,
          v_winner_id, v_event.promotion_id);
      END IF;
    ELSE
      INSERT INTO public.news_items (week, type, title, body, fighter_id, promotion_id)
      VALUES (p_completed_at_week, 'event_result',
        v_winner_name || ' defeats ' || v_loser_name,
        v_winner_name || ' defeated ' || v_loser_name || ' by ' ||
          v_method || ' in round ' || v_round || ' at ' || v_event.name || '.',
        v_winner_id, v_event.promotion_id);
    END IF;

    v_simulated := v_simulated + 1;
  END LOOP;

  RETURN v_simulated;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_booked_event_fights()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF OLD.status <> 'scheduled' OR NEW.status <> 'completed' THEN
    RETURN NEW;
  END IF;

  PERFORM public.simulate_event_fights(OLD.id, NEW.completed_at_week);
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Promotion owner RPCs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_promotion_event(p_name text, p_scheduled_week int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_tick int;
  v_promo_id uuid;
  v_event_id uuid;
BEGIN
  v_tick := public.get_current_week();
  v_promo_id := public.get_owned_promotion();

  IF v_promo_id IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'You do not own a promotion.');
  END IF;

  IF p_scheduled_week < v_tick + 4 THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Events must be scheduled at least 4 weeks (1 month) in advance.');
  END IF;

  IF trim(p_name) = '' THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Event name is required.');
  END IF;

  INSERT INTO public.events (promotion_id, name, scheduled_week, status)
  VALUES (v_promo_id, trim(p_name), p_scheduled_week, 'scheduled')
  RETURNING id INTO v_event_id;

  RETURN jsonb_build_object(
    'status', 'ok',
    'message', 'Event scheduled.',
    'event_id', v_event_id,
    'scheduled_week', p_scheduled_week
  );
END;
$$;

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

CREATE OR REPLACE FUNCTION public.send_contract_offer(
  p_fighter_id uuid,
  p_fights_remaining int DEFAULT 4,
  p_purse_per_fight bigint DEFAULT 5000
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_tick int;
  v_promo RECORD;
  v_fighter RECORD;
  v_offer_id uuid;
BEGIN
  v_tick := public.get_current_week();

  SELECT p.* INTO v_promo
  FROM public.promotions p
  WHERE p.id = public.get_owned_promotion();

  IF v_promo.id IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'You do not own a promotion.');
  END IF;

  SELECT * INTO v_fighter FROM public.fighters WHERE id = p_fighter_id AND retired = false;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fighter not found.');
  END IF;

  IF v_fighter.current_skill > v_promo.reputation THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Fighter skill exceeds promotion reputation. Cannot offer a contract.'
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.contracts c
    WHERE c.fighter_id = p_fighter_id AND c.promotion_id = v_promo.id AND c.status = 'active'
  ) THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fighter already has an active contract with your promotion.');
  END IF;

  IF v_fighter.gym_id IS NULL THEN
    INSERT INTO public.contracts (
      fighter_id, promotion_id, signed_week, expires_week,
      purse_per_fight, status, contracted_fights, fights_remaining
    ) VALUES (
      p_fighter_id, v_promo.id, v_tick, 2147483647,
      p_purse_per_fight, 'active', p_fights_remaining, p_fights_remaining
    );
    UPDATE public.fighters SET promotion_id = v_promo.id WHERE id = p_fighter_id;

    RETURN jsonb_build_object(
      'status', 'ok',
      'message', v_fighter.name || ' accepted the contract automatically.',
      'auto_accepted', true
    );
  END IF;

  INSERT INTO public.fight_offers (
    gym_id, fighter_id, opponent_fighter_id, promotion_id, event_id,
    purse, scheduled_week, status, offered_at_week, response_deadline_week,
    offer_kind, contract_fights
  ) VALUES (
    v_fighter.gym_id, p_fighter_id, NULL, v_promo.id, NULL,
    p_purse_per_fight, v_tick + 4, 'pending', v_tick, v_tick + 2,
    'contract', p_fights_remaining
  ) RETURNING id INTO v_offer_id;

  RETURN jsonb_build_object(
    'status', 'ok',
    'message', 'Contract offer sent to gym. They have 2 weeks to respond.',
    'offer_id', v_offer_id,
    'auto_accepted', false
  );
END;
$$;

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

  SELECT count(*) INTO v_pending_fights
  FROM public.fights f WHERE f.event_id = p_event_id AND f.status = 'pending';

  IF v_pending_fights = 0 THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'No confirmed fights on the card.');
  END IF;

  v_fights_simulated := public.simulate_event_fights(p_event_id, v_tick);

  UPDATE public.events
  SET status = 'completed', completed_at_week = v_tick
  WHERE id = p_event_id;

  PERFORM public.refresh_promotion_rankings(v_tick);

  RETURN jsonb_build_object(
    'status', 'ok',
    'message', 'Event completed. ' || v_fights_simulated || ' fight(s) simulated.',
    'fights_simulated', v_fights_simulated
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Updated accept_offer: deadline, pre-set event, contract-only, free-agent opponents
-- ---------------------------------------------------------------------------

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
  v_tick int;
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

    IF EXISTS (
      SELECT 1 FROM public.fights f
      JOIN public.events e ON e.id = f.event_id
      WHERE f.status = 'pending' AND e.status = 'scheduled'
        AND (
          v_offer.fighter_id IN (f.fighter_a_id, f.fighter_b_id)
          OR v_offer.opponent_fighter_id IN (f.fighter_a_id, f.fighter_b_id)
        )
    ) THEN
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
-- Slim finalize_week_contracts: no AI auto-renewals; response_deadline expiry
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

  UPDATE public.fight_offers SET status = 'declined'
  WHERE status = 'pending' AND response_deadline_week < p_tick;

  RETURN 0;
END;
$$;

-- ---------------------------------------------------------------------------
-- Slim advance_week: calendar + aging only; no AI promotion automation
-- ---------------------------------------------------------------------------

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
  v_gym RECORD;
  v_rank int;
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

  PERFORM public.finalize_week_contracts(v_new_tick);

  v_rank := 1;
  FOR v_gym IN SELECT id FROM public.gyms ORDER BY reputation DESC, wins DESC LOOP
    UPDATE public.gyms SET ranking = v_rank WHERE id = v_gym.id;
    v_rank := v_rank + 1;
  END LOOP;

  PERFORM public.snapshot_gym_fighter_ranks();

  RETURN jsonb_build_object(
    'status','ok','tick', v_new_tick,
    'date', jsonb_build_object('year', v_new_year, 'month', v_new_month, 'week', v_new_week, 'day', v_new_day),
    'retired', v_retired_count,
    'events_processed', 0, 'fights_simulated', 0,
    'offers_generated', 0, 'signed', 0, 'purses_paid', 0
  );
END;
$$;

-- Allow contract-only offers and free-agent fight opponents
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
  v_opponent_is_champion boolean := false;
BEGIN
  IF NEW.opponent_fighter_id IS NULL AND NEW.offer_kind = 'contract' THEN
    RETURN NEW;
  END IF;

  IF NEW.offer_kind IN ('fight', 'title_shot') AND NEW.event_id IS NOT NULL THEN
    IF NEW.opponent_fighter_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.fighters opp
      WHERE opp.id = NEW.opponent_fighter_id
        AND opp.promotion_id IS NOT NULL
        AND opp.promotion_id IS DISTINCT FROM NEW.promotion_id
    ) THEN
      RETURN NULL;
    END IF;
    RETURN NEW;
  END IF;

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

  SELECT EXISTS (
    SELECT 1
    FROM public.championships ch
    WHERE ch.current_champion_fighter_id = NEW.opponent_fighter_id
      AND ch.weight_class = v_weight_class
      AND ch.promotion_id = COALESCE(v_contract_promotion, NEW.promotion_id)
  ) INTO v_opponent_is_champion;

  IF v_opponent_is_champion OR NEW.offer_kind = 'title_shot' THEN
    NEW.offer_kind := 'title_shot';
    IF v_contract_promotion IS NOT NULL THEN
      NEW.promotion_id := v_contract_promotion;
      NEW.contract_fights := COALESCE(NULLIF(NEW.contract_fights, 0), v_contract_remaining);
      IF NEW.purse IS NULL OR NEW.purse = 0 THEN
        NEW.purse := v_contract_tier * 5000 + GREATEST(0, (v_skill - 50) * 200) + 5000;
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  IF v_contract_promotion IS NULL THEN
    IF NEW.offer_kind <> 'renewal' THEN
      NEW.offer_kind := 'contract';
    END IF;

    IF NEW.opponent_fighter_id IS NULL THEN
      RETURN NEW;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.fighters
      WHERE id = NEW.opponent_fighter_id
        AND promotion_id = NEW.promotion_id
        AND retired = false
        AND weight_class = v_weight_class
        AND NOT public.fighter_holds_promotion_title(id)
    ) THEN
      SELECT id INTO v_replacement_opponent
      FROM public.fighters
      WHERE promotion_id = NEW.promotion_id
        AND gym_id IS NULL
        AND retired = false
        AND weight_class = v_weight_class
        AND id <> NEW.fighter_id
        AND ABS(current_skill - v_skill) <= 15
        AND NOT public.fighter_holds_promotion_title(id)
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

    IF NEW.opponent_fighter_id IS NULL THEN
      RETURN NEW;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.fighters
      WHERE id = NEW.opponent_fighter_id
        AND promotion_id = NEW.promotion_id
        AND retired = false
        AND weight_class = v_weight_class
        AND NOT public.fighter_holds_promotion_title(id)
    ) THEN
      SELECT id INTO v_replacement_opponent
      FROM public.fighters
      WHERE promotion_id = NEW.promotion_id
        AND gym_id IS NULL
        AND retired = false
        AND weight_class = v_weight_class
        AND id <> NEW.fighter_id
        AND ABS(current_skill - v_skill) <= 15
        AND NOT public.fighter_holds_promotion_title(id)
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

  IF NEW.opponent_fighter_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.fighters opp
    WHERE opp.id = NEW.opponent_fighter_id
      AND opp.promotion_id IS NULL
  ) THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.fighters
    WHERE id = NEW.opponent_fighter_id
      AND promotion_id = v_contract_promotion
      AND retired = false
      AND weight_class = v_weight_class
      AND NOT public.fighter_holds_promotion_title(id)
  ) THEN
    SELECT id INTO v_replacement_opponent
    FROM public.fighters
    WHERE promotion_id = v_contract_promotion
      AND gym_id IS NULL
      AND retired = false
      AND weight_class = v_weight_class
      AND id <> NEW.fighter_id
      AND ABS(current_skill - v_skill) <= 15
      AND NOT public.fighter_holds_promotion_title(id)
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
