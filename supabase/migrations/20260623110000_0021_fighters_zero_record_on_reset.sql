/*
# Zero-fight records on world reset

- generate_fighters: new fighters start 0-0-0 with no KO/sub/dec wins
*/

CREATE OR REPLACE FUNCTION public.generate_fighters(p_count int DEFAULT 500)
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
    v_potential := 40 + floor(random() * 60)::int;
    v_skill := GREATEST(20, LEAST(99, v_potential - floor(random() * LEAST(40, v_potential - 20))::int));
    v_country := v_countries[1 + floor(random() * array_length(v_countries,1))::int];
    v_wc_row := v_wc[1 + floor(random() * 8)::int];

    LOOP
      v_first_name := v_first[1 + floor(random() * array_length(v_first,1))::int];
      v_last_name := v_last[1 + floor(random() * array_length(v_last,1))::int];
      v_name := v_first_name || ' ' || v_last_name;
      EXIT WHEN NOT (v_name = ANY(v_used_names));
    END LOOP;
    v_used_names := array_append(v_used_names, v_name);

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
      0, 0, 0, 0, 0, 0,
      NULL, NULL, false, v_week);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
