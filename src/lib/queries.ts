import { supabase } from './supabase';
import type {
  Fighter, Gym, Promotion, Championship, TitleHistory, Ranking,
  GameEvent, Fight, Contract, FightOffer, NewsItem, WorldState,
  WeightClass,
} from './types';

export async function fetchWorldState(): Promise<WorldState | null> {
  const { data, error } = await supabase
    .from('world_state')
    .select('*')
    .eq('id', 1)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function fetchFighter(id: string, options?: { withHistory?: boolean }) {
  const { data: fighter, error } = await supabase
    .from('fighters')
    .select('*')
    .eq('id', id)
    .maybeSingle();
  if (error) throw error;
  if (!fighter) return null;

  if (!options?.withHistory) return { fighter, fights: [], upcomingFights: [], contracts: [] };

  const fightSelect = '*, event:events(id, name, promotion_id, scheduled_week, completed_at_week), fighter_a:fighters!fights_fighter_a_id_fkey(id, name, country, wins, losses), fighter_b:fighters!fights_fighter_b_id_fkey(id, name, country, wins, losses)';

  const fightsQ = supabase
    .from('fights')
    .select(fightSelect)
    .or(`fighter_a_id.eq.${id},fighter_b_id.eq.${id}`)
    .eq('status', 'completed')
    .order('completed_at_week', { ascending: false, nullsFirst: false })
    .limit(20);

  const upcomingFightsQ = supabase
    .from('fights')
    .select(fightSelect)
    .or(`fighter_a_id.eq.${id},fighter_b_id.eq.${id}`)
    .eq('status', 'pending')
    .order('scheduled_week', { ascending: true, referencedTable: 'event' });

  const contractsQ = supabase
    .from('contracts')
    .select('*, promotion:promotions(name, tier)')
    .eq('fighter_id', id)
    .order('signed_week', { ascending: false })
    .limit(5);

  const [fightsRes, upcomingFightsRes, contractsRes] = await Promise.all([
    fightsQ,
    upcomingFightsQ,
    contractsQ,
  ]);
  if (fightsRes.error) throw fightsRes.error;
  if (upcomingFightsRes.error) throw upcomingFightsRes.error;
  if (contractsRes.error) throw contractsRes.error;

  return {
    fighter,
    fights: fightsRes.data || [],
    upcomingFights: upcomingFightsRes.data || [],
    contracts: contractsRes.data || [],
  };
}

export async function fetchGymFighters(gymId: string): Promise<Fighter[]> {
  const { data, error } = await supabase
    .from('fighters')
    .select('*')
    .eq('gym_id', gymId)
    .order('current_skill', { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function fetchGymOffers(gymId: string): Promise<(FightOffer & {
  fighter: Pick<Fighter, 'id' | 'name' | 'weight_class'>;
  opponent_fighter: Pick<Fighter, 'id' | 'name' | 'weight_class' | 'current_skill' | 'gym_id'>;
  promotion: Pick<Promotion, 'id' | 'name' | 'tier'>;
  event: (Pick<GameEvent, 'id' | 'name' | 'status'> & {
    fights: Pick<Fight, 'id' | 'fighter_a_id' | 'fighter_b_id' | 'winner_id' | 'method' | 'round' | 'status' | 'completed_at_week'>[];
  }) | null;
})[]> {
  const { data, error } = await supabase
    .from('fight_offers')
    .select('*, fighter:fighters(id, name, weight_class, current_skill, gym_id), opponent_fighter:fighters!fight_offers_opponent_fighter_id_fkey(id, name, weight_class, current_skill, gym_id), promotion:promotions(id, name, tier), event:events(id, name, status, fights(id, fighter_a_id, fighter_b_id, winner_id, method, round, status, completed_at_week))')
    .eq('gym_id', gymId)
    .order('offered_at_week', { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function fetchRecentNews(limit = 10): Promise<NewsItem[]> {
  const { data, error } = await supabase
    .from('news_items')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data || [];
}

export async function fetchGymRecentFights(gymId: string, limit = 5) {
  const fighterIds = (await fetchGymFighters(gymId)).map((fighter) => fighter.id);
  if (fighterIds.length === 0) return [];

  const idList = fighterIds.join(',');
  const { data, error } = await supabase
    .from('fights')
    .select('*, event:events(name, promotion_id), fighter_a:fighters!fights_fighter_a_id_fkey(id, name, gym_id), fighter_b:fighters!fights_fighter_b_id_fkey(id, name, gym_id), winner:fighters!fights_winner_id_fkey(id, name)')
    .or(`fighter_a_id.in.(${idList}),fighter_b_id.in.(${idList})`)
    .eq('status', 'completed')
    .order('completed_at_week', { ascending: false, nullsFirst: false })
    .limit(limit);
  if (error) throw error;
  return data || [];
}

export async function fetchPromotions(): Promise<Promotion[]> {
  const { data, error } = await supabase
    .from('promotions')
    .select('*')
    .order('tier', { ascending: false })
    .order('name', { ascending: true });
  if (error) throw error;
  return data || [];
}

export async function fetchPromotion(id: string) {
  const promoQ = supabase.from('promotions').select('*').eq('id', id).maybeSingle();
  const champsQ = supabase
    .from('championships')
    .select('*, current_champion:fighters(id, name, wins, losses, country), weight_class_obj:weight_classes(name, weight_lbs, order)')
    .eq('promotion_id', id);
  const eventsQ = supabase
    .from('events')
    .select('*')
    .eq('promotion_id', id)
    .order('scheduled_week', { ascending: false })
    .limit(10);
  const rankingsQ = supabase
    .from('rankings')
    .select('*, fighter:fighters(id, name, wins, losses, current_skill, country, gym_id)')
    .eq('promotion_id', id)
    .order('weight_class')
    .order('rank_position');

  const [promoR, champsR, eventsR, rankingsR] = await Promise.all([promoQ, champsQ, eventsQ, rankingsQ]);
  if (promoR.error) throw promoR.error;
  if (champsR.error) throw champsR.error;
  if (eventsR.error) throw eventsR.error;
  if (rankingsR.error) throw rankingsR.error;

  return {
    promotion: promoR.data,
    championships: champsR.data || [],
    events: eventsR.data || [],
    rankings: rankingsR.data || [],
  };
}

export async function fetchAllChampionships() {
  const { data, error } = await supabase
    .from('championships')
    .select('*, promotion:promotions(id, name, tier, country), current_champion:fighters(id, name, wins, losses, country, weight_class), weight_class_obj:weight_classes(name, weight_lbs, order)')
    .order('weight_class_obj(order)')
    .order('promotion(tier)', { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function fetchTitleHistory(championshipId: string): Promise<(TitleHistory & {
  fighter: Pick<Fighter, 'id' | 'name' | 'wins' | 'losses' | 'country'>;
})[]> {
  const { data, error } = await supabase
    .from('title_history')
    .select('*, fighter:fighters(id, name, wins, losses, country)')
    .eq('championship_id', championshipId)
    .order('won_at_week', { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function fetchEvents(options: { status?: string; limit?: number } = {}) {
  let q = supabase
    .from('events')
    .select('*, promotion:promotions(id, name, tier, country), fights:fights(id, winner_id, method, round, is_title_fight, fighter_a:fighters!fights_fighter_a_id_fkey(id, name), fighter_b:fighters!fights_fighter_b_id_fkey(id, name), winner:fighters!fights_winner_id_fkey(id, name))')
    .order('scheduled_week', { ascending: false });
  if (options.status) q = q.eq('status', options.status);
  if (options.limit) q = q.limit(options.limit);
  const { data, error } = await q;
  if (error) throw error;
  return data || [];
}

export async function fetchEventDetail(id: string) {
  const [eventQ, fightsQ] = await Promise.all([
    supabase.from('events').select('*, promotion:promotions(*)').eq('id', id).maybeSingle(),
    supabase.from('fights')
      .select('*, fighter_a:fighters!fights_fighter_a_id_fkey(id, name, country, wins, losses, gym_id), fighter_b:fighters!fights_fighter_b_id_fkey(id, name, country, wins, losses, gym_id), winner:fighters!fights_winner_id_fkey(id, name)')
      .eq('event_id', id)
      .order('is_title_fight', { ascending: false })
      .order('round', { ascending: false }),
  ]);
  if (eventQ.error) throw eventQ.error;
  if (fightsQ.error) throw fightsQ.error;
  return { event: eventQ.data, fights: fightsQ.data || [] };
}

export async function fetchScoutFighters(opts: { weightClass?: string; limit?: number; offset?: number } = {}): Promise<{ fighters: Fighter[]; total: number }> {
  let q = supabase
    .from('fighters')
    .select('*', { count: 'exact' })
    .is('gym_id', null)
    .eq('retired', false)
    .order('current_skill', { ascending: false });
  if (opts.weightClass && opts.weightClass !== 'All') q = q.eq('weight_class', opts.weightClass as WeightClass);
  if (opts.limit) q = q.limit(opts.limit);
  if (opts.offset) q = q.range(opts.offset, opts.offset + (opts.limit || 50) - 1);
  const { data, error, count } = await q;
  if (error) throw error;
  return { fighters: data || [], total: count || 0 };
}

export async function fetchGymLeaderboard(limit = 50): Promise<Gym[]> {
  const { data, error } = await supabase
    .from('gyms')
    .select('id, name, tier, reputation, ranking, champions_produced, wins, losses, draws, cash, created_at')
    .order('reputation', { ascending: false })
    .order('wins', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data || [];
}

export async function callSignFighter(fighterId: string): Promise<{ status: string; message?: string }> {
  const { data, error } = await supabase.rpc('sign_fighter', { p_fighter_id: fighterId } as any);
  if (error) throw error;
  return data as { status: string; message?: string };
}

export async function callAcceptOffer(offerId: string): Promise<{ status: string; message?: string }> {
  const { data, error } = await supabase.rpc('accept_offer', { p_offer_id: offerId } as any);
  if (error) throw error;
  return data as { status: string; message?: string };
}

export async function callDeclineOffer(offerId: string): Promise<{ status: string; message?: string }> {
  const { data, error } = await supabase.rpc('decline_offer', { p_offer_id: offerId } as any);
  if (error) throw error;
  return data as { status: string; message?: string };
}

const ADMIN_URL = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/admin-control`;

export async function callAdmin(action: string): Promise<unknown> {
  const { data } = await supabase.auth.getSession();
  const token = data?.session?.access_token;
  if (!token) throw new Error('Not authenticated.');

  const response = await fetch(ADMIN_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({ action }),
  });

  if (!response.ok) {
    let msg = `Admin action failed (${response.status})`;
    try {
      const body = await response.json();
      if (body?.error) msg = body.error;
      if (body?.message) msg = body.message;
    } catch {
      // ignore parse failure
    }
    throw new Error(msg);
  }

  const body = await response.json();
  if (body?.status === 'error') throw new Error(body.error || body.message || 'Admin action failed.');
  if (body?.status === 'unauthorized') throw new Error(body.message || 'Unauthorized.');
  return body;
}

export async function fetchRankings(promotionId?: string) {
  let q = supabase
    .from('rankings')
    .select('*, fighter:fighters(id, name, country, wins, losses, draws, current_skill, weight_class, career_status, gym_id), promotion:promotions(id, name, tier)')
    .order('weight_class')
    .order('rank_position');
  if (promotionId) q = q.eq('promotion_id', promotionId);
  const { data, error } = await q;
  if (error) throw error;
  return data || [];
}

export type { Fighter, Gym, Promotion, Championship, TitleHistory, Ranking, GameEvent, Fight, Contract, FightOffer, NewsItem };
