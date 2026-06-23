/*
# Player action RPCs: sign_fighter, accept_offer, decline_offer

These are SECURITY DEFINER functions called by authenticated clients to perform
player-owned world mutations that touch multiple tables at once. Each one
verifies the calling user owns the gym it claims to act on (via auth.uid()).

1. sign_fighter(p_fighter_id) — signs an unsigned fighter to the caller's gym
   - Verifies caller has a gym
   - Verifies fighter is currently unsigned (gym_id is null, retired is false, AND not
     currently under a promotion contract that would block signing — only fighters
     with promotion_id null are signable)
   - Verifies gym has capacity (active fighters < capacity)
   - Verifies gym has enough cash (fee scales with fighter current_skill)
   - Deducts cash, assigns gym_id
   Returns jsonb status.

2. accept_offer(p_offer_id) — accepts a fight offer
   - Verifies offer belongs to caller's gym and is pending
   - Marks offer accepted and pays advance purse to gym
   Returns jsonb status.

3. decline_offer(p_offer_id) — declines a fight offer
   - Verifies offer belongs to caller's gym and is pending
   - Marks offer declined
   Returns jsonb status.
*/

CREATE OR REPLACE FUNCTION public.sign_fighter(p_fighter_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_gym RECORD;
  v_fighter RECORD;
  v_cost bigint;
  v_active_count int;
BEGIN
  SELECT * INTO v_gym FROM public.gyms WHERE owner_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','error','message','You do not own a gym.');
  END IF;

  SELECT * INTO v_fighter FROM public.fighters WHERE id = p_fighter_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','error','message','Fighter not found.');
  END IF;

  IF v_fighter.retired THEN
    RETURN jsonb_build_object('status','error','message','Cannot sign a retired fighter.');
  END IF;

  IF v_fighter.gym_id IS NOT NULL THEN
    RETURN jsonb_build_object('status','error','message','Fighter is already managed by a gym.');
  END IF;

  IF v_fighter.promotion_id IS NOT NULL THEN
    RETURN jsonb_build_object('status','error','message','Fighter is under a promotion contract and cannot be signed directly.');
  END IF;

  SELECT count(*) INTO v_active_count
  FROM public.fighters WHERE gym_id = v_gym.id AND retired = false;
  IF v_active_count >= v_gym.capacity THEN
    RETURN jsonb_build_object('status','error','message','Gym is at capacity. Upgrade capacity first.');
  END IF;

  -- Cost: scales with fighter skill tier (cheaper for low-skill prospects)
  v_cost := GREATEST(2000, (v_fighter.current_skill - 40) * 1500);

  IF v_gym.cash < v_cost THEN
    RETURN jsonb_build_object('status','error','message','Insufficient cash to sign this fighter.','cost', v_cost);
  END IF;

  UPDATE public.gyms SET cash = cash - v_cost WHERE id = v_gym.id;
  UPDATE public.fighters SET gym_id = v_gym.id WHERE id = v_fighter.id;

  INSERT INTO public.news_items (week, type, title, body, fighter_id, gym_id)
  VALUES (public.get_current_week(), 'signing',
    v_gym.name || ' signs ' || v_fighter.name,
    v_gym.name || ' has signed ' || v_fighter.name || ' (' || v_fighter.country || ', ' || v_fighter.weight_class || ') to their management roster.',
    v_fighter.id, v_gym.id);

  RETURN jsonb_build_object('status','ok','message','Signed ' || v_fighter.name,'cost', v_cost);
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
BEGIN
  SELECT * INTO v_offer FROM public.fight_offers WHERE id = p_offer_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','error','message','Offer not found.');
  END IF;

  SELECT * INTO v_gym FROM public.gyms WHERE id = v_offer.gym_id AND owner_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','error','message','Offer does not belong to your gym.');
  END IF;

  IF v_offer.status <> 'pending' THEN
    RETURN jsonb_build_object('status','error','message','Offer is no longer pending.');
  END IF;

  UPDATE public.fight_offers SET status = 'accepted' WHERE id = v_offer.id;

  -- Pay advance purse to gym on acceptance (simulate booking fee)
  UPDATE public.gyms SET cash = cash + v_offer.purse WHERE id = v_gym.id;

  -- Award reputation for accepting fights (encourages engagement)
  UPDATE public.gyms SET reputation = reputation + 1 WHERE id = v_gym.id;

  RETURN jsonb_build_object('status','ok','message','Offer accepted. You will earn the purse when the fight completes.','purse', v_offer.purse);
END;
$$;

CREATE OR REPLACE FUNCTION public.decline_offer(p_offer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_gym RECORD;
BEGIN
  SELECT * INTO v_offer FROM public.fight_offers WHERE id = p_offer_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','error','message','Offer not found.');
  END IF;

  SELECT * INTO v_gym FROM public.gyms WHERE id = v_offer.gym_id AND owner_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','error','message','Offer does not belong to your gym.');
  END IF;

  IF v_offer.status <> 'pending' THEN
    RETURN jsonb_build_object('status','error','message','Offer is no longer pending.');
  END IF;

  UPDATE public.fight_offers SET status = 'declined' WHERE id = v_offer.id;

  RETURN jsonb_build_object('status','ok','message','Offer declined.');
END;
$$;
