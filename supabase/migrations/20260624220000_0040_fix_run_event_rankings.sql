/*
# Fix run_event rankings refresh call

run_event passed promotion_id to refresh_promotion_rankings, which expects the
current week tick (int). PostgreSQL reported the function as missing because no
uuid overload exists.
*/

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
  v_unconfirmed_pvp int;
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
      'message', 'Player vs player bookings must be confirmed by both gyms before running the event.'
    );
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
