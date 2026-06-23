/*
# Helper RPCs (is_admin, get_current_week, generate_fighters, generate_promotions,
# seed_championships_and_rankings, reset_world, pause/resume/wipe)

These were originally part of migration 0004 but it failed before applying them.
All SECURITY DEFINER so the world-tick edge function (service role) and admin actions
can mutate RLS-locked tables from a single SQL call.
*/

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE((SELECT is_admin FROM public.profiles WHERE id = auth.uid()), false);
$$;

CREATE OR REPLACE FUNCTION public.get_current_week()
RETURNS int
LANGUAGE sql
SECURITY DEFINER SET search_path = public
AS $$
  SELECT tick_count FROM public.world_state WHERE id = 1;
$$;

-- generate_fighters(p_count): bulk-insert randomized AI fighters across all 8 weight classes
CREATE OR REPLACE FUNCTION public.generate_fighters(p_count int DEFAULT 1200)
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
BEGIN
  v_week := public.get_current_week();
  v_wc := ARRAY['Flyweight','Bantamweight','Featherweight','Lightweight','Welterweight','Middleweight','Light Heavyweight','Heavyweight'];
  v_countries := ARRAY['USA','Brazil','Mexico','Canada','Ireland','England','Russia','Dagestan','Poland','Nigeria','Australia','Japan','South Korea','Sweden','France','Cuba','Argentina','Germany','Georgia','Ukraine','Kazakhstan','Suriname','Netherlands','Jamaica','Philippines','Kyrgyzstan'];
  v_first := ARRAY['Marcus','Diego','Connor','Khabib','Israel','Alex','Tyron','Daniel','Brock','Junior','Anthony','Max','Justin','Dustin','Charles','Islam','Khamzat','Robert','Sean','Leon','Belal','Gilbert','Michael','Jorge','Rafael','Pedro','Mateusz','Jan','Tom','Ciryl','Alexander','Shavkat','Arman','Renato','Sergei','Volkov','Petr','Aljamain','Merab','Sodiq','Ikram','Mateus','Caio','Trevin','Gabriel','Jailton','Yusuff','Aori','Marcos','Michal','Lerone','David','Bryce','Tony','Kevin','Grant','Rafael','Melsik','Mateusz','Ikram','Rafael','Misha'];
  v_last := ARRAY['Silva','Saint Pierre','McGregor','Nurmagomedov','Adesanya','Volkanovski','Pereira','Jones','Cormier','Lesnar','dos Santos','Pettis','Holloway','Gaethje','Poirier','Oliveira','Makhachev','Chimaev','Whittaker','Strickland','Edwards','Muhammad','Burns','Chandler','Masvidal','Fiziev','Munhoz','Gamrot','Blachowicz','Aspinall','Gane','Volkov','Ngannou','Yan','Sterling','Dvalishvili','Sandhagen','Font','Aldo','Cruz','Emmett','Kattar','Topuria','Holloway','Woodley','Thompson','Edgar','Fabiano','Roberts','Murphy','Vanderford','Eblen','Mix','Kasanganay','Magomedov','Amirkhani','Barcelos','Trizano','Garcia','Hughes','Dariush','Moises','Brito','Puelles'];

  FOR v_i IN 1..p_count LOOP
    v_age := 16 + floor(random() * 18)::int;
    v_potential := 40 + floor(random() * 60)::int;
    v_skill := GREATEST(20, LEAST(99, v_potential - floor(random() * LEAST(40, v_potential - 20))::int));
    v_country := v_countries[1 + floor(random() * array_length(v_countries,1))::int];
    v_wc_row := v_wc[1 + floor(random() * 8)::int];
    v_first_name := v_first[1 + floor(random() * array_length(v_first,1))::int];
    v_last_name := v_last[1 + floor(random() * array_length(v_last,1))::int];
    v_name := v_first_name || ' ' || v_last_name;

    v_boxing := GREATEST(10, LEAST(100, v_skill + floor((random() - 0.5) * 20)::int));
    v_kick := GREATEST(10, LEAST(100, v_skill + floor((random() - 0.5) * 20)::int));
    v_wrestle := GREATEST(10, LEAST(100, v_skill + floor((random() - 0.5) * 20)::int));
    v_bjj := GREATEST(10, LEAST(100, v_skill + floor((random() - 0.5) * 20)::int));
    v_cardio := GREATEST(10, LEAST(100, v_skill + floor((random() - 0.5) * 15)::int));
    v_chin := GREATEST(10, LEAST(100, v_skill + floor((random() - 0.5) * 20)::int));
    v_iq := GREATEST(10, LEAST(100, v_skill + floor((random() - 0.5) * 15)::int));
    v_ath := GREATEST(10, LEAST(100, v_skill + floor((random() - 0.5) * 18)::int));

    IF v_skill >= 88 THEN v_status := 'champion';
    ELSIF v_skill >= 75 THEN v_status := 'contender';
    ELSIF v_age >= 35 THEN v_status := 'veteran';
    ELSE v_status := 'prospect';
    END IF;

    INSERT INTO public.fighters (name, age, country, weight_class,
      boxing, kickboxing, wrestling, bjj, cardio, chin, fight_iq, athleticism,
      potential, current_skill, popularity, career_status,
      wins, losses, draws, ko_wins, sub_wins, dec_wins,
      gym_id, promotion_id, retired, born_week)
    VALUES (v_name, v_age, v_country, v_wc_row,
      v_boxing, v_kick, v_wrestle, v_bjj, v_cardio, v_chin, v_iq, v_ath,
      v_potential, v_skill, LEAST(100, GREATEST(0, (v_skill - 50) * 2)),
      v_status,
      floor(random() * 25)::int, floor(random() * 15)::int, floor(random() * 3)::int,
      floor(random() * 12)::int, floor(random() * 8)::int, floor(random() * 10)::int,
      NULL, NULL, false, v_week);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- generate_promotions(): 8 preset AI promotions across 5 tiers
CREATE OR REPLACE FUNCTION public.generate_promotions()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_count int := 0;
  v_data text[][];
  v_i int;
BEGIN
  v_data := ARRAY[
    ['Kingdom Combat','1','USA'],
    ['Iron Cage Federation','1','Brazil'],
    ['Borough Brawl','2','USA'],
    ['Pacific Rim MMA','2','Japan'],
    ['Frontier Fighting','3','England'],
    ['Continental MMA League','3','USA'],
    ['Apex Worldwide','4','USA'],
    ['Global Apex Championship','5','USA']
  ];
  FOR v_i IN 1..array_length(v_data,1) LOOP
    INSERT INTO public.promotions (name, tier, country, reputation, fan_base, owner_kind)
    VALUES (v_data[v_i][1], v_data[v_i][2]::int, v_data[v_i][3],
      v_data[v_i][2]::int * 15, (v_data[v_i][2]::int ^ 3) * 1000, 'ai');
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- seed_championships_and_rankings(): one championship per promo per weight class (all vacant),
-- seed top-15 per promo per weight class from current_skill DESC
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
        SELECT id FROM public.fighters
        WHERE weight_class = v_wc.name AND retired = false AND gym_id IS NULL
        ORDER BY current_skill DESC, popularity DESC LIMIT 15
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

-- reset_world(): wipes all world data (except user accounts) and regenerates
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
  v_fighters := public.generate_fighters(1200);
  PERFORM public.seed_championships_and_rankings();

  INSERT INTO public.news_items (week, type, title, body)
  VALUES (0, 'event_result', 'A New Era Begins',
    'A new MMA world has been born. 8 promotions across 5 tiers have launched, 1200 fighters have entered the sport, and all championships are vacant. The race to crown the first champions begins now.');

  RETURN jsonb_build_object('promotions', v_promos, 'fighters', v_fighters, 'status', 'world_reset');
END;
$$;

-- Admin actions
CREATE OR REPLACE FUNCTION public.pause_world()
RETURNS void
LANGUAGE sql
SECURITY DEFINER SET search_path = public
AS $$ UPDATE public.world_state SET is_paused = true WHERE id = 1; $$;

CREATE OR REPLACE FUNCTION public.resume_world()
RETURNS void
LANGUAGE sql
SECURITY DEFINER SET search_path = public
AS $$ UPDATE public.world_state SET is_paused = false WHERE id = 1; $$;

CREATE OR REPLACE FUNCTION public.wipe_all_gyms()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE public.fighters SET gym_id = NULL WHERE gym_id IS NOT NULL;
  DELETE FROM public.gyms;
END;
$$;

CREATE OR REPLACE FUNCTION public.wipe_all_fighters()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  DELETE FROM public.fight_offers;
  DELETE FROM public.contracts;
  DELETE FROM public.fights;
  DELETE FROM public.rankings;
  DELETE FROM public.title_history;
  UPDATE public.championships SET current_champion_fighter_id = NULL;
  DELETE FROM public.fighters;
END;
$$;
