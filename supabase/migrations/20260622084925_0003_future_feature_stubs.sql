/*
# Future-feature stub tables (structure only, no player-writable flows yet)

This migration prepares the database for later features WITHOUT building them.
Each table is created, RLS-enabled, and made public-read but admin/service-write-only,
so a future update can simply add policies + UI to flip systems on.

1. Gym facilities / staff / coaches
- `facilities`: gym-owned buildings (e.g. strength cage, recovery wing). Stub fields only.
- `coaches`: gym-employed coaches. Specialty + rating.
- `gym_staff`: gym support staff (nutritionist, cutman, etc.).

2. Promotion-related (future monetization)
- `sponsorships`: sponsors attached to fighters / promotions / gyms.
- `tv_deals`: broadcast deals per promotion (and later player-owned promotion).

3. Fighter dynamics
- `injuries`: fighter injuries with recovery duration.
- `rivalries`: pair-wise fighter rivalries.
- `fighter_personalities`: personality traits affecting fight behavior.
- `media_posts`: press / media artifacts.

All tables:
- RLS enabled.
- Public read (world is observable).
- No authenticated write policies — only service role (bypasses RLS) writes
  during simulation. When the actual feature ships it will add owner-scoped
  write policies.
*/

CREATE TABLE IF NOT EXISTS facilities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  type text NOT NULL,
  level int NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE facilities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_facilities" ON facilities;
CREATE POLICY "public_read_facilities" ON facilities FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS coaches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid REFERENCES gyms(id) ON DELETE SET NULL,
  name text NOT NULL,
  specialty text,
  rating int NOT NULL DEFAULT 50
);
ALTER TABLE coaches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_coaches" ON coaches;
CREATE POLICY "public_read_coaches" ON coaches FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS gym_staff (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  name text NOT NULL,
  role text NOT NULL,
  rating int NOT NULL DEFAULT 50
);
ALTER TABLE gym_staff ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_gym_staff" ON gym_staff;
CREATE POLICY "public_read_gym_staff" ON gym_staff FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS sponsorships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sponsor_name text NOT NULL,
  target_type text NOT NULL CHECK (target_type IN ('fighter','promotion','gym')),
  fighter_id uuid REFERENCES fighters(id) ON DELETE CASCADE,
  promotion_id uuid REFERENCES promotions(id) ON DELETE CASCADE,
  gym_id uuid REFERENCES gyms(id) ON DELETE CASCADE,
  value_per_week bigint NOT NULL DEFAULT 0,
  signed_week int,
  expires_week int
);
ALTER TABLE sponsorships ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_sponsorships" ON sponsorships;
CREATE POLICY "public_read_sponsorships" ON sponsorships FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS tv_deals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promotion_id uuid NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  network text NOT NULL,
  value_per_event bigint NOT NULL DEFAULT 0,
  signed_week int,
  expires_week int
);
ALTER TABLE tv_deals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_tv_deals" ON tv_deals;
CREATE POLICY "public_read_tv_deals" ON tv_deals FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS injuries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fighter_id uuid NOT NULL REFERENCES fighters(id) ON DELETE CASCADE,
  type text NOT NULL,
  severity int NOT NULL DEFAULT 1,
  sustained_week int NOT NULL,
  recovery_week int
);
ALTER TABLE injuries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_injuries" ON injuries;
CREATE POLICY "public_read_injuries" ON injuries FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS rivalries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fighter_a_id uuid NOT NULL REFERENCES fighters(id) ON DELETE CASCADE,
  fighter_b_id uuid NOT NULL REFERENCES fighters(id) ON DELETE CASCADE,
  intensity int NOT NULL DEFAULT 50,
  history jsonb NOT NULL DEFAULT '[]'::jsonb
);
ALTER TABLE rivalries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_rivalries" ON rivalries;
CREATE POLICY "public_read_rivalries" ON rivalries FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS fighter_personalities (
  fighter_id uuid PRIMARY KEY REFERENCES fighters(id) ON DELETE CASCADE,
  trait text NOT NULL,
  value int NOT NULL DEFAULT 50
);
ALTER TABLE fighter_personalities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_personalities" ON fighter_personalities;
CREATE POLICY "public_read_personalities" ON fighter_personalities FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS media_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  week int NOT NULL,
  type text NOT NULL,
  headline text NOT NULL,
  body text NOT NULL DEFAULT '',
  fighter_id uuid REFERENCES fighters(id) ON DELETE SET NULL,
  promotion_id uuid REFERENCES promotions(id) ON DELETE SET NULL,
  gym_id uuid REFERENCES gyms(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE media_posts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_media_posts" ON media_posts;
CREATE POLICY "public_read_media_posts" ON media_posts FOR SELECT TO anon, authenticated USING (true);
