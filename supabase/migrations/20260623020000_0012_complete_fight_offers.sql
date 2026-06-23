/*
# Move resolved bookings into completed fight offers

Accepted means the fight is booked and upcoming. Once the linked fight is
resolved, its offer moves to completed so the UI can show it separately.
*/

ALTER TABLE public.fight_offers
  DROP CONSTRAINT IF EXISTS fight_offers_status_check;

ALTER TABLE public.fight_offers
  ADD CONSTRAINT fight_offers_status_check
  CHECK (status IN ('pending', 'accepted', 'declined', 'completed'));

CREATE OR REPLACE FUNCTION public.complete_linked_fight_offer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
    UPDATE public.fight_offers
    SET status = 'completed'
    WHERE event_id = NEW.event_id
      AND status = 'accepted'
      AND fighter_id = NEW.fighter_a_id
      AND opponent_fighter_id = NEW.fighter_b_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS complete_linked_fight_offer ON public.fights;
CREATE TRIGGER complete_linked_fight_offer
AFTER UPDATE OF status ON public.fights
FOR EACH ROW
EXECUTE FUNCTION public.complete_linked_fight_offer();

-- Repair offers for fights that completed before this migration was applied.
UPDATE public.fight_offers fo
SET status = 'completed'
FROM public.fights f
WHERE fo.status = 'accepted'
  AND fo.event_id = f.event_id
  AND fo.fighter_id = f.fighter_a_id
  AND fo.opponent_fighter_id = f.fighter_b_id
  AND f.status = 'completed';
