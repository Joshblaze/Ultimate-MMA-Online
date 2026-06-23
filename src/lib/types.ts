// Auto-generated type stubs for the schema. Keep in sync with migrations.
// These are hand-written because we don't run `supabase gen types`.

export type WeightClass =
  | 'Flyweight'
  | 'Bantamweight'
  | 'Featherweight'
  | 'Lightweight'
  | 'Welterweight'
  | 'Middleweight'
  | 'Light Heavyweight'
  | 'Heavyweight';

export type CareerStatus = 'prospect' | 'contender' | 'champion' | 'veteran' | 'retired';

export type FightMethod = 'KO' | 'TKO' | 'Submission' | 'Decision';

export type FightStatus = 'pending' | 'completed';

export type EventStatus = 'scheduled' | 'completed';

export type OfferStatus = 'pending' | 'accepted' | 'declined' | 'completed';
export type OfferKind = 'contract' | 'fight' | 'renewal';

export type PromotionTier = 1 | 2 | 3 | 4 | 5;

export type OwnerKind = 'ai' | 'player';

export type NewsType =
  | 'champion_crowned'
  | 'upset'
  | 'retirement'
  | 'signing'
  | 'gym_tier'
  | 'event_result'
  | 'title_defense'
  | 'title_vacated';

export interface WorldState {
  id: number;
  current_year: number;
  current_week: number; // 1-4 (week within month)
  current_month: number; // 1-12
  current_day: number; // unused; kept at 1
  tick_count: number;
  is_paused: boolean;
  last_tick_at: string | null;
}

export interface Profile {
  id: string;
  is_admin: boolean;
  created_at: string;
}

export interface Gym {
  id: string;
  owner_id: string;
  name: string;
  tier: number;
  reputation: number;
  ranking: number | null;
  capacity: number;
  cash: number;
  wins: number;
  losses: number;
  draws: number;
  champions_produced: number;
  created_at: string;
}

export interface Fighter {
  id: string;
  name: string;
  age: number;
  country: string;
  weight_class: WeightClass;
  boxing: number;
  kickboxing: number;
  wrestling: number;
  bjj: number;
  cardio: number;
  chin: number;
  fight_iq: number;
  athleticism: number;
  potential: number;
  current_skill: number;
  popularity: number;
  career_status: CareerStatus;
  wins: number;
  losses: number;
  draws: number;
  ko_wins: number;
  sub_wins: number;
  dec_wins: number;
  gym_id: string | null;
  promotion_id: string | null;
  retired: boolean;
  born_week: number | null; // absolute tick count; display via formatTick
  created_at: string;
}

export interface Promotion {
  id: string;
  name: string;
  tier: PromotionTier;
  country: string;
  reputation: number;
  fan_base: number;
  owner_kind: OwnerKind;
  owned_by_gym_id: string | null;
  created_at: string;
}

export interface Championship {
  id: string;
  promotion_id: string;
  weight_class: WeightClass;
  current_champion_fighter_id: string | null;
  created_at: string;
}

export interface TitleHistory {
  id: string;
  championship_id: string;
  fighter_id: string;
  won_at_week: number; // absolute tick count; display via formatTick
  lost_at_week: number | null; // absolute tick count; display via formatTick
  defenses: number;
}

export interface Ranking {
  id: string;
  promotion_id: string;
  weight_class: WeightClass;
  fighter_id: string;
  rank_position: number;
  updated_at_week: number; // absolute tick count; display via formatTick
}

export interface GameEvent {
  id: string;
  promotion_id: string;
  name: string;
  scheduled_week: number; // absolute tick count; display via formatTick
  status: EventStatus;
  main_event_fighter_a: string | null;
  main_event_fighter_b: string | null;
  completed_at_week: number | null; // absolute tick count; display via formatTick
}

export interface Fight {
  id: string;
  event_id: string;
  fighter_a_id: string;
  fighter_b_id: string;
  winner_id: string | null;
  method: FightMethod | null;
  round: number | null;
  commentary: string[];
  weight_class: WeightClass;
  is_title_fight: boolean;
  championship_id: string | null;
  status: FightStatus;
  completed_at_week: number | null; // absolute tick count; display via formatTick
}

export interface Contract {
  id: string;
  fighter_id: string;
  promotion_id: string;
  signed_week: number; // absolute tick count; display via formatTick
  expires_week: number; // legacy compatibility; active contracts use fight counts
  purse_per_fight: number;
  contracted_fights: number;
  fights_remaining: number;
  completed_fights: number;
  status: 'active' | 'expired';
}

export interface FightOffer {
  id: string;
  gym_id: string;
  fighter_id: string;
  opponent_fighter_id: string;
  promotion_id: string;
  event_id: string | null;
  purse: number;
  offer_kind: OfferKind;
  contract_fights: number;
  scheduled_week: number; // absolute tick count; display via formatTick
  status: OfferStatus;
  offered_at_week: number; // absolute tick count; display via formatTick
}

export interface NewsItem {
  id: string;
  week: number; // absolute tick count; display via formatTick
  type: NewsType;
  title: string;
  body: string;
  fighter_id: string | null;
  promotion_id: string | null;
  gym_id: string | null;
  created_at: string;
}

export interface Database {
  public: {
    Tables: {
      world_state: {
        Row: WorldState;
        Insert: Partial<WorldState> & { id?: number };
        Update: Partial<WorldState>;
      };
      profiles: {
        Row: Profile;
        Insert: Partial<Profile> & { id: string };
        Update: Partial<Profile>;
      };
      gyms: {
        Row: Gym;
        Insert: Partial<Gym> & { name: string; owner_id: string };
        Update: Partial<Gym>;
      };
      fighters: {
        Row: Fighter;
        Insert: Partial<Fighter> & { name: string };
        Update: Partial<Fighter>;
      };
      promotions: {
        Row: Promotion;
        Insert: Partial<Promotion> & { name: string };
        Update: Partial<Promotion>;
      };
      championships: {
        Row: Championship;
        Insert: Partial<Championship>;
        Update: Partial<Championship>;
      };
      title_history: {
        Row: TitleHistory;
        Insert: Partial<TitleHistory>;
        Update: Partial<TitleHistory>;
      };
      rankings: {
        Row: Ranking;
        Insert: Partial<Ranking>;
        Update: Partial<Ranking>;
      };
      events: {
        Row: GameEvent;
        Insert: Partial<GameEvent> & { name: string; promotion_id: string };
        Update: Partial<GameEvent>;
      };
      fights: {
        Row: Fight;
        Insert: Partial<Fight>;
        Update: Partial<Fight>;
      };
      contracts: {
        Row: Contract;
        Insert: Partial<Contract>;
        Update: Partial<Contract>;
      };
      fight_offers: {
        Row: FightOffer;
        Insert: Partial<FightOffer>;
        Update: Partial<FightOffer>;
      };
      news_items: {
        Row: NewsItem;
        Insert: Partial<NewsItem>;
        Update: Partial<NewsItem>;
      };
    };
    Functions: {
      reset_world: { Args: Record<string, never>; Returns: unknown };
      advance_week: { Args: Record<string, never>; Returns: unknown };
      generate_fighters: { Args: { p_count?: number }; Returns: number };
      generate_promotions: { Args: Record<string, never>; Returns: number };
      sign_fighter: { Args: { p_fighter_id: string }; Returns: unknown };
      accept_offer: { Args: { p_offer_id: string }; Returns: unknown };
      decline_offer: { Args: { p_offer_id: string }; Returns: unknown };
      is_admin: { Args: Record<string, never>; Returns: boolean };
      get_current_week: { Args: Record<string, never>; Returns: number };
      pause_world: { Args: Record<string, never>; Returns: void };
      resume_world: { Args: Record<string, never>; Returns: void };
      wipe_all_gyms: { Args: Record<string, never>; Returns: void };
      wipe_all_fighters: { Args: Record<string, never>; Returns: void };
    };
  };
}
