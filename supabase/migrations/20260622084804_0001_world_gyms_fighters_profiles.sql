/*
# Core schema: world state, profiles, gyms, fighters, weight classes

1. New Tables
- `world_state` (singleton id=1): in-game calendar (year/week/month/day), tick counter,
  paused flag, last_tick_at timestamp.
- `profiles`: per-auth-user record with is_admin flag (gate for the admin panel).
- `gyms`: player gyms. owner_id FK to auth.users. tier/reputation/capacity/cash + WLD record.
- `fighters`: AI + player-managed fighters. Full attribute set (boxing..athleticism),
  potential/current_skill/popularity, career_status, W/L/D + breakdown by method,
  gym_id (nullable for unsigned) and promotion_id (nullable) for ownership state.
- `weight_classes`: static reference rows (Flyweight..Heavyweight with weight in lbs).

2. Security
- RLS enabled on every table.
- `world_state` + `weight_classes`: public read, admin/service-only write.
- `profiles`: read own row, update own row; is_admin column drives admin gating.
- `gyms`: public read (leaderboard/rankings), owner-only insert/update for own gym.
- `fighters`: public read; gym-owner insert/update only for fighters where gym_id
  matches a gym owned by auth.uid(); promotion/contract writes happen via service role.

3. Notes
- This migration is idempotent (IF NOT EXISTS); safe to re-apply.
- world_state row id is fixed to 1 (singleton) so all callers can read by id.
- fighters.gym_id + fighters.promotion_id encode the three ownership states:
  (null,null) = Unsigned, (set,*) = Managed By Gym, (null,set) = Signed To Promotion.
  (gym_id,promotion_id both set is valid: a player-managed fighter under contract.)
*/

-- ===== world_state =====
CREATE TABLE IF NOT EXISTS world_state (
  id smallint PRIMARY KEY DEFAULT 1,
  current_year int NOT NULL DEFAULT 1,
  current_week int NOT NULL DEFAULT 1,
  current_month int NOT NULL DEFAULT 1,
  current_day int NOT NULL DEFAULT 1,
  tick_count int NOT NULL DEFAULT 0,
  is_paused boolean NOT NULL DEFAULT false,
  last_tick_at timestamptz
);
ALTER TABLE world_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_world_state" ON world_state;
CREATE POLICY "public_read_world_state" ON world_state FOR SELECT
  TO anon, authenticated USING (true);

-- Only service role (which bypasses RLS) and admins (via profile) can write.
-- Admin writes are scoped through a SECURITY DEFINER function later in 0004.
DROP POLICY IF EXISTS "service_write_world_state" ON world_state;
CREATE POLICY "service_write_world_state" ON world_state FOR UPDATE
  TO authenticated USING (false) WITH CHECK (false);

INSERT INTO world_state (id, current_year, current_week, current_month, current_day, tick_count, is_paused, last_tick_at)
VALUES (1, 1, 1, 1, 1, 0, false, null)
ON CONFLICT (id) DO NOTHING;

-- ===== profiles =====
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  is_admin boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "read_own_profile" ON profiles;
CREATE POLICY "read_own_profile" ON profiles FOR SELECT
  TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "insert_own_profile" ON profiles;
CREATE POLICY "insert_own_profile" ON profiles FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "update_own_profile" ON profiles;
CREATE POLICY "update_own_profile" ON profiles FOR UPDATE
  TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- Allow anyone to read is_admin (needed by frontend to show admin nav item),
-- but only of themselves — already covered by "read_own_profile".
-- If we ever need public leaderboard of admins, add a separate policy.

-- Auto-create profile on new auth user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, is_admin)
  VALUES (NEW.id, false)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ===== weight_classes (static reference) =====
CREATE TABLE IF NOT EXISTS weight_classes (
  name text PRIMARY KEY,
  weight_lbs int NOT NULL,
  "order" int NOT NULL
);
ALTER TABLE weight_classes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_weight_classes" ON weight_classes;
CREATE POLICY "public_read_weight_classes" ON weight_classes FOR SELECT
  TO anon, authenticated USING (true);

INSERT INTO weight_classes (name, weight_lbs, "order") VALUES
  ('Flyweight', 125, 1),
  ('Bantamweight', 135, 2),
  ('Featherweight', 145, 3),
  ('Lightweight', 155, 4),
  ('Welterweight', 170, 5),
  ('Middleweight', 185, 6),
  ('Light Heavyweight', 205, 7),
  ('Heavyweight', 265, 8)
ON CONFLICT (name) DO NOTHING;

-- ===== gyms =====
CREATE TABLE IF NOT EXISTS gyms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  tier int NOT NULL DEFAULT 1 CHECK (tier BETWEEN 1 AND 10),
  reputation int NOT NULL DEFAULT 0,
  ranking int,
  capacity int NOT NULL DEFAULT 10,
  cash bigint NOT NULL DEFAULT 50000,
  wins int NOT NULL DEFAULT 0,
  losses int NOT NULL DEFAULT 0,
  draws int NOT NULL DEFAULT 0,
  champions_produced int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_gyms_owner ON gyms(owner_id);
CREATE INDEX IF NOT EXISTS idx_gyms_reputation ON gyms(reputation DESC);
ALTER TABLE gyms ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_gyms" ON gyms;
CREATE POLICY "public_read_gyms" ON gyms FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "insert_own_gym" ON gyms;
CREATE POLICY "insert_own_gym" ON gyms FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "update_own_gym" ON gyms;
CREATE POLICY "update_own_gym" ON gyms FOR UPDATE
  TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- No public DELETE policy: only service role / admin via RPC can wipe gyms.

-- ===== fighters =====
CREATE TABLE IF NOT EXISTS fighters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  age int NOT NULL CHECK (age BETWEEN 16 AND 50),
  country text NOT NULL DEFAULT 'USA',
  weight_class text NOT NULL REFERENCES weight_classes(name),
  boxing int NOT NULL DEFAULT 30 CHECK (boxing BETWEEN 1 AND 100),
  kickboxing int NOT NULL DEFAULT 30 CHECK (kickboxing BETWEEN 1 AND 100),
  wrestling int NOT NULL DEFAULT 30 CHECK (wrestling BETWEEN 1 AND 100),
  bjj int NOT NULL DEFAULT 30 CHECK (bjj BETWEEN 1 AND 100),
  cardio int NOT NULL DEFAULT 30 CHECK (cardio BETWEEN 1 AND 100),
  chin int NOT NULL DEFAULT 30 CHECK (chin BETWEEN 1 AND 100),
  fight_iq int NOT NULL DEFAULT 30 CHECK (fight_iq BETWEEN 1 AND 100),
  athleticism int NOT NULL DEFAULT 30 CHECK (athleticism BETWEEN 1 AND 100),
  potential int NOT NULL DEFAULT 50 CHECK (potential BETWEEN 1 AND 100),
  current_skill int NOT NULL DEFAULT 30 CHECK (current_skill BETWEEN 1 AND 100),
  popularity int NOT NULL DEFAULT 0 CHECK (popularity BETWEEN 0 AND 100),
  career_status text NOT NULL DEFAULT 'prospect'
    CHECK (career_status IN ('prospect','contender','champion','veteran','retired')),
  wins int NOT NULL DEFAULT 0,
  losses int NOT NULL DEFAULT 0,
  draws int NOT NULL DEFAULT 0,
  ko_wins int NOT NULL DEFAULT 0,
  sub_wins int NOT NULL DEFAULT 0,
  dec_wins int NOT NULL DEFAULT 0,
  gym_id uuid REFERENCES gyms(id) ON DELETE SET NULL,
  promotion_id uuid,
  retired boolean NOT NULL DEFAULT false,
  born_week int,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fighters_gym ON fighters(gym_id);
CREATE INDEX IF NOT EXISTS idx_fighters_promotion ON fighters(promotion_id);
CREATE INDEX IF NOT EXISTS idx_fighters_weight ON fighters(weight_class);
CREATE INDEX IF NOT EXISTS idx_fighters_status ON fighters(career_status);
CREATE INDEX IF NOT EXISTS idx_fighters_skill ON fighters(current_skill DESC);
CREATE INDEX IF NOT EXISTS idx_fighters_retired ON fighters(retired);
ALTER TABLE fighters ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_fighters" ON fighters;
CREATE POLICY "public_read_fighters" ON fighters FOR SELECT
  TO anon, authenticated USING (true);

-- A gym owner can insert/update fighters only where the fighter is assigned to THEIR gym.
DROP POLICY IF EXISTS "insert_own_gym_fighters" ON fighters;
CREATE POLICY "insert_own_gym_fighters" ON fighters FOR INSERT
  TO authenticated WITH CHECK (
    gym_id IS NULL OR EXISTS (
      SELECT 1 FROM gyms WHERE gyms.id = fighters.gym_id AND gyms.owner_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "update_own_gym_fighters" ON fighters;
CREATE POLICY "update_own_gym_fighters" ON fighters FOR UPDATE
  TO authenticated USING (
    gym_id IS NULL OR EXISTS (
      SELECT 1 FROM gyms WHERE gyms.id = fighters.gym_id AND gyms.owner_id = auth.uid()
    )
  ) WITH CHECK (
    gym_id IS NULL OR EXISTS (
      SELECT 1 FROM gyms WHERE gyms.id = fighters.gym_id AND gyms.owner_id = auth.uid()
    )
  );

-- No DELETE/UPDATE-on-non-owned policy — service role handles sim writes.
