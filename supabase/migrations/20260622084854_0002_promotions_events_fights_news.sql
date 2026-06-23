/*
# Promotions, championships, rankings, events, fights, contracts, offers, news

1. New Tables
- `promotions`: AI-controlled (and future player-owned) MMA promotions. Tier 1-5,
  country, reputation, fan_base. `owner_kind` ('ai'|'player') + nullable
  `owned_by_gym_id` designed so a future "buy a promotion" feature can flip a
  row from ai to player without schema changes.
- `championships`: one per promotion per weight_class. `current_champion_fighter_id`
  nullable = vacant title.
- `title_history`: every reign. won_at_week, lost_at_week (null = current), defenses.
- `rankings`: top-15 per promotion per weight_class. rank_position 1-15. updated_at_week ties
  the snapshot to a tick.
- `events`: promotion events with scheduled_week (absolute tick), status, main event fighters.
- `fights`: individual fight records. fighter_a/b, winner, method, round, commentary JSON.
  is_title_fight + championship_id (nullable). status pending/completed.
- `contracts`: fighter<->promotion active/expired contracts with purse_per_fight + week range.
- `fight_offers`: offers to player gyms for their managed fighters. opponent, promotion,
  event, purse, scheduled_week, status pending/accepted/declined.
- `news_items`: global world news feed. type-tagged (champion_crowned, upset, etc.).

2. Security
- RLS enabled on every table.
- All these tables are PUBLIC READ (the world is shared/observable to everyone,
  including unauth'd visitors browsing rankings/news/champions). This is intentional
  — it mirrors how real sports rankings/news are public.
- Writes for sim-owned tables (promotions, championships, rankings, events, fights,
  contracts, news_items) happen ONLY via the service role in the world-tick edge
  function (which bypasses RLS) — no authenticated write policies needed.
- `fight_offers`: special-cased — gym owner can READ + UPDATE (accept/decline) offers
  targeting their gym; creation happens via service role only.

3. Notes
- Foreign keys cascade from gyms/fighters/promotions where appropriate to keep the
  graph consistent on world reset.
- All week fields are absolute tick_count values (NOT in-game year/week) so ranges
  and ordering survive year rollovers.
*/

CREATE TABLE IF NOT EXISTS promotions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  tier int NOT NULL DEFAULT 1 CHECK (tier BETWEEN 1 AND 5),
  country text NOT NULL DEFAULT 'USA',
  reputation int NOT NULL DEFAULT 0,
  fan_base int NOT NULL DEFAULT 1000,
  owner_kind text NOT NULL DEFAULT 'ai' CHECK (owner_kind IN ('ai','player')),
  owned_by_gym_id uuid REFERENCES gyms(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_promotions_tier ON promotions(tier);
CREATE INDEX IF NOT EXISTS idx_promotions_owner_kind ON promotions(owner_kind);
ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_promotions" ON promotions;
CREATE POLICY "public_read_promotions" ON promotions FOR SELECT
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS championships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promotion_id uuid NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  weight_class text NOT NULL REFERENCES weight_classes(name),
  current_champion_fighter_id uuid REFERENCES fighters(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (promotion_id, weight_class)
);
CREATE INDEX IF NOT EXISTS idx_championships_promo ON championships(promotion_id);
CREATE INDEX IF NOT EXISTS idx_championships_champion ON championships(current_champion_fighter_id);
ALTER TABLE championships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_championships" ON championships;
CREATE POLICY "public_read_championships" ON championships FOR SELECT
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS title_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  championship_id uuid NOT NULL REFERENCES championships(id) ON DELETE CASCADE,
  fighter_id uuid NOT NULL REFERENCES fighters(id) ON DELETE CASCADE,
  won_at_week int NOT NULL,
  lost_at_week int,
  defenses int NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_title_history_champ ON title_history(championship_id);
CREATE INDEX IF NOT EXISTS idx_title_history_fighter ON title_history(fighter_id);
ALTER TABLE title_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_title_history" ON title_history;
CREATE POLICY "public_read_title_history" ON title_history FOR SELECT
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS rankings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promotion_id uuid NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  weight_class text NOT NULL REFERENCES weight_classes(name),
  fighter_id uuid NOT NULL REFERENCES fighters(id) ON DELETE CASCADE,
  rank_position int NOT NULL CHECK (rank_position BETWEEN 1 AND 15),
  updated_at_week int NOT NULL DEFAULT 0,
  UNIQUE (promotion_id, weight_class, rank_position)
);
CREATE INDEX IF NOT EXISTS idx_rankings_promo_wc ON rankings(promotion_id, weight_class, rank_position);
CREATE INDEX IF NOT EXISTS idx_rankings_fighter ON rankings(fighter_id);
ALTER TABLE rankings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_rankings" ON rankings;
CREATE POLICY "public_read_rankings" ON rankings FOR SELECT
  TO anon, authenticated USING (true);

-- Add promotion_id FK to fighters now that promotions table exists
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fighters_promotion_id_fkey'
      AND table_name = 'fighters'
  ) THEN
    ALTER TABLE fighters
      ADD CONSTRAINT fighters_promotion_id_fkey
      FOREIGN KEY (promotion_id) REFERENCES promotions(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promotion_id uuid NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  name text NOT NULL,
  scheduled_week int NOT NULL,
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','completed')),
  main_event_fighter_a uuid REFERENCES fighters(id) ON DELETE SET NULL,
  main_event_fighter_b uuid REFERENCES fighters(id) ON DELETE SET NULL,
  completed_at_week int
);
CREATE INDEX IF NOT EXISTS idx_events_promo ON events(promotion_id);
CREATE INDEX IF NOT EXISTS idx_events_week ON events(scheduled_week);
CREATE INDEX IF NOT EXISTS idx_events_status ON events(status);
ALTER TABLE events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_events" ON events;
CREATE POLICY "public_read_events" ON events FOR SELECT
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS fights (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  fighter_a_id uuid NOT NULL REFERENCES fighters(id) ON DELETE CASCADE,
  fighter_b_id uuid NOT NULL REFERENCES fighters(id) ON DELETE CASCADE,
  winner_id uuid REFERENCES fighters(id) ON DELETE SET NULL,
  method text CHECK (method IN ('KO','TKO','Submission','Decision')),
  round int CHECK (round BETWEEN 1 AND 5),
  commentary jsonb NOT NULL DEFAULT '[]'::jsonb,
  weight_class text NOT NULL REFERENCES weight_classes(name),
  is_title_fight boolean NOT NULL DEFAULT false,
  championship_id uuid REFERENCES championships(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','completed')),
  completed_at_week int
);
CREATE INDEX IF NOT EXISTS idx_fights_event ON fights(event_id);
CREATE INDEX IF NOT EXISTS idx_fights_fighter_a ON fights(fighter_a_id);
CREATE INDEX IF NOT EXISTS idx_fights_fighter_b ON fights(fighter_b_id);
CREATE INDEX IF NOT EXISTS idx_fights_winner ON fights(winner_id);
CREATE INDEX IF NOT EXISTS idx_fights_status ON fights(status);
ALTER TABLE fights ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_fights" ON fights;
CREATE POLICY "public_read_fights" ON fights FOR SELECT
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fighter_id uuid NOT NULL REFERENCES fighters(id) ON DELETE CASCADE,
  promotion_id uuid NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  signed_week int NOT NULL,
  expires_week int NOT NULL,
  purse_per_fight bigint NOT NULL DEFAULT 5000,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','expired'))
);
CREATE INDEX IF NOT EXISTS idx_contracts_fighter ON contracts(fighter_id);
CREATE INDEX IF NOT EXISTS idx_contracts_promotion ON contracts(promotion_id);
CREATE INDEX IF NOT EXISTS idx_contracts_status ON contracts(status);
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_contracts" ON contracts;
CREATE POLICY "public_read_contracts" ON contracts FOR SELECT
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS fight_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  fighter_id uuid NOT NULL REFERENCES fighters(id) ON DELETE CASCADE,
  opponent_fighter_id uuid NOT NULL REFERENCES fighters(id) ON DELETE CASCADE,
  promotion_id uuid NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  event_id uuid REFERENCES events(id) ON DELETE SET NULL,
  purse bigint NOT NULL DEFAULT 5000,
  scheduled_week int NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined')),
  offered_at_week int NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_offers_gym ON fight_offers(gym_id);
CREATE INDEX IF NOT EXISTS idx_offers_status ON fight_offers(status);
CREATE INDEX IF NOT EXISTS idx_offers_fighter ON fight_offers(fighter_id);
ALTER TABLE fight_offers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "read_offers_own_gym" ON fight_offers;
CREATE POLICY "read_offers_own_gym" ON fight_offers FOR SELECT
  TO authenticated USING (
    EXISTS (SELECT 1 FROM gyms WHERE gyms.id = fight_offers.gym_id AND gyms.owner_id = auth.uid())
  );

DROP POLICY IF EXISTS "update_offers_own_gym" ON fight_offers;
CREATE POLICY "update_offers_own_gym" ON fight_offers FOR UPDATE
  TO authenticated USING (
    EXISTS (SELECT 1 FROM gyms WHERE gyms.id = fight_offers.gym_id AND gyms.owner_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM gyms WHERE gyms.id = fight_offers.gym_id AND gyms.owner_id = auth.uid())
  );

CREATE TABLE IF NOT EXISTS news_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  week int NOT NULL,
  type text NOT NULL CHECK (type IN (
    'champion_crowned','upset','retirement','signing',
    'gym_tier','event_result','title_defense','title_vacated'
  )),
  title text NOT NULL,
  body text NOT NULL DEFAULT '',
  fighter_id uuid REFERENCES fighters(id) ON DELETE SET NULL,
  promotion_id uuid REFERENCES promotions(id) ON DELETE SET NULL,
  gym_id uuid REFERENCES gyms(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_news_week ON news_items(week DESC);
CREATE INDEX IF NOT EXISTS idx_news_type ON news_items(type);
CREATE INDEX IF NOT EXISTS idx_news_created ON news_items(created_at DESC);
ALTER TABLE news_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_news" ON news_items;
CREATE POLICY "public_read_news" ON news_items FOR SELECT
  TO anon, authenticated USING (true);
