/*
# release_fighter — player releases a managed fighter from their gym

Removes gym management (gym_id -> NULL) without touching promotion contracts.
Declines pending fight offers for that fighter. Blocks release when a scheduled
bout is still pending.
*/

ALTER TABLE public.news_items
  DROP CONSTRAINT IF EXISTS news_items_type_check;

ALTER TABLE public.news_items
  ADD CONSTRAINT news_items_type_check
  CHECK (type IN (
    'champion_crowned', 'upset', 'retirement', 'signing', 'release',
    'gym_tier', 'event_result', 'title_defense', 'title_vacated'
  ));

CREATE OR REPLACE FUNCTION public.release_fighter(p_fighter_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_gym RECORD;
  v_fighter RECORD;
BEGIN
  SELECT * INTO v_gym FROM public.gyms WHERE owner_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'You do not own a gym.');
  END IF;

  SELECT * INTO v_fighter
  FROM public.fighters WHERE id = p_fighter_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Fighter not found.');
  END IF;

  IF v_fighter.gym_id IS NULL OR v_fighter.gym_id <> v_gym.id THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'This fighter is not managed by your gym.');
  END IF;

  IF v_fighter.retired THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Cannot release a retired fighter.');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.fights f
    JOIN public.events e ON e.id = f.event_id
    WHERE f.status = 'pending'
      AND e.status = 'scheduled'
      AND (f.fighter_a_id = v_fighter.id OR f.fighter_b_id = v_fighter.id)
  ) THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Cannot release a fighter with a booked fight. Wait until the bout is completed.'
    );
  END IF;

  UPDATE public.fight_offers
  SET status = 'declined'
  WHERE gym_id = v_gym.id
    AND fighter_id = v_fighter.id
    AND status = 'pending';

  UPDATE public.fighters
  SET gym_id = NULL
  WHERE id = v_fighter.id;

  INSERT INTO public.news_items (week, type, title, body, fighter_id, gym_id)
  VALUES (
    public.get_current_week(), 'release',
    v_gym.name || ' releases ' || v_fighter.name,
    v_gym.name || ' has released ' || v_fighter.name ||
      ' from management.' ||
      CASE WHEN v_fighter.promotion_id IS NOT NULL
        THEN ' Their promotion contract remains in force.'
        ELSE ' They are now a free agent.'
      END,
    v_fighter.id, v_gym.id
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'message', 'Released ' || v_fighter.name || ' from your gym.' ||
      CASE WHEN v_fighter.promotion_id IS NOT NULL
        THEN ' Their promotion contract remains active.'
        ELSE ' They are now available to scout.'
      END
  );
END;
$$;
