import { useEffect, useState } from 'react';
import {
  Dumbbell, Trophy, Users, Crown, FileText, Newspaper, Wallet, TrendingUp,
  Swords, ChevronRight, Sparkles, Calendar, Target,
} from 'lucide-react';
import { useGym } from '../lib/gym';
import { useWorld } from '../lib/world';
import type { PageProps } from '../App';
import { Card, CardHeader, EmptyState, PageHeader, StatPanel, Badge } from '../components/ui';
import { FighterRow, FighterListItem } from '../components/FighterCard';
import { ResponsiveDataView } from '../components/ResponsiveDataView';
import {
  fetchGymFighters, fetchGymOffers, fetchRecentNews, fetchGymRecentFights,
  fetchGymFightsNeedingPlans,
} from '../lib/queries';
import { formatMoney, formatDate, formatRecord, formatTick } from '../lib/format';
import type { Fighter, FightOffer, NewsItem } from '../lib/types';
import { navigate } from '../App';

export function Dashboard(_: PageProps) {
  const { gym, version } = useGym();
  const { world } = useWorld();
  const [fighters, setFighters] = useState<Fighter[]>([]);
  const [offers, setOffers] = useState<FightOffer[]>([]);
  const [news, setNews] = useState<NewsItem[]>([]);
  const [recentFights, setRecentFights] = useState<any[]>([]);
  const [plansNeeded, setPlansNeeded] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!gym) return;
    const gymId = gym.id;
    let cancelled = false;
    setLoading(true);

    async function loadDashboard() {
      const [fightersResult, offersResult, newsResult, fightsResult, plansResult] = await Promise.allSettled([
        fetchGymFighters(gymId),
        fetchGymOffers(gymId),
        fetchRecentNews(5),
        fetchGymRecentFights(gymId, 5),
        fetchGymFightsNeedingPlans(gymId),
      ]);

      if (cancelled) return;

      if (fightersResult.status === 'fulfilled') setFighters(fightersResult.value);
      else console.error('Dashboard fighters error:', fightersResult.reason);

      if (offersResult.status === 'fulfilled') {
        setOffers(offersResult.value.filter((offer) => offer.status === 'pending'));
      } else {
        console.error('Dashboard offers error:', offersResult.reason);
      }

      if (newsResult.status === 'fulfilled') setNews(newsResult.value);
      else console.error('Dashboard news error:', newsResult.reason);

      if (fightsResult.status === 'fulfilled') setRecentFights(fightsResult.value);
      else console.error('Dashboard recent fights error:', fightsResult.reason);

      if (plansResult.status === 'fulfilled') setPlansNeeded(plansResult.value);
      else console.error('Dashboard plans needed error:', plansResult.reason);

      setLoading(false);
    }

    loadDashboard();
    return () => {
      cancelled = true;
    };
  }, [gym, version, world?.tick_count, world?.last_tick_at]);

  if (!gym) return null;

  return (
    <div className="animate-slideUp">
      <PageHeader
        title={`${gym.name}`}
        subtitle={world ? formatDate(world) : 'Loading world...'}
        icon={Dumbbell}
        action={
          <Badge className="bg-gold-700/30 text-gold-300 border-gold-600/40">
            Tier {gym.tier}
          </Badge>
        }
      />

      {plansNeeded.length > 0 && (
        <Card className="mb-6 border-gold-700/40">
          <CardHeader title="Game Plan Needed" icon={Target} />
          <div className="divide-y divide-ink-800">
            {plansNeeded.map(({ fight, myFighter, forRound }) => (
              <button
                key={fight.id}
                onClick={() => navigate(`fight/${fight.id}`)}
                className="p-4 w-full text-left hover:bg-ink-800/30 flex items-center justify-between gap-3"
              >
                <div>
                  <div className="text-sm font-medium text-gold-200">
                    {myFighter.name} — Round {forRound}
                  </div>
                  <div className="text-xs text-ink-400 mt-0.5">
                    {(fight.event as { name?: string } | null)?.name || 'Live event'} · Submit corner instructions
                  </div>
                </div>
                <ChevronRight className="w-4 h-4 text-gold-400 flex-shrink-0" />
              </button>
            ))}
          </div>
        </Card>
      )}

      {/* Stats grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-3 mb-6">
        <StatPanel
          label="Cash"
          value={formatMoney(gym.cash)}
          icon={Wallet}
          color="text-gold-300"
        />
        <StatPanel
          label="Reputation"
          value={gym.reputation}
          icon={TrendingUp}
          color="text-forest-300"
        />
        <StatPanel
          label="Gym Ranking"
          value={gym.ranking ? `#${gym.ranking}` : '—'}
          icon={Trophy}
          color="text-gold-300"
        />
        <StatPanel
          label="Fighters"
          value={`${fighters.length}/${gym.capacity}`}
          icon={Users}
          color="text-blue-300"
        />
        <StatPanel
          label="Champions"
          value={gym.champions_produced}
          icon={Crown}
          color="text-gold-300"
        />
        <StatPanel
          label="Record"
          value={formatRecord(gym.wins, gym.losses, gym.draws)}
          icon={Swords}
          color="text-ink-100"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Column 1: Fighters + recent results */}
        <div className="lg:col-span-2 space-y-6">
          {/* My Fighters */}
          <Card>
            <CardHeader
              title="My Fighters"
              icon={Users}
              action={
                <button onClick={() => navigate('my-fighters')} className="text-xs text-gold-400 hover:text-gold-300 flex items-center gap-1">
                  View all <ChevronRight className="w-3 h-3" />
                </button>
              }
            />
            {loading ? (
              <div className="p-8 text-center text-ink-500 text-sm">Loading fighters...</div>
            ) : fighters.length === 0 ? (
              <EmptyState
                icon={Users}
                title="No fighters yet"
                body="Visit the Scout page to sign your first fighter."
                action={
                  <button onClick={() => navigate('scout')} className="btn-primary text-sm">
                    Go to Scout
                  </button>
                }
              />
            ) : (
              <ResponsiveDataView
                mobileRows={fighters.slice(0, 5).map((f) => (
                  <FighterListItem
                    key={f.id}
                    fighter={f}
                    onClick={() => navigate(`fighter/${f.id}`)}
                  />
                ))}
              >
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-xs text-ink-500 uppercase tracking-wide border-b border-ink-800">
                      <th className="px-3 py-2 text-left font-semibold">Fighter</th>
                      <th className="px-3 py-2 text-left font-semibold">Class</th>
                      <th className="px-3 py-2 text-left font-semibold">Age</th>
                      <th className="px-3 py-2 text-left font-semibold">Record</th>
                      <th className="px-3 py-2 text-left font-semibold">Skill</th>
                    </tr>
                  </thead>
                  <tbody>
                    {fighters.slice(0, 5).map((f) => (
                      <FighterRow
                        key={f.id}
                        fighter={f}
                        onClick={() => navigate(`fighter/${f.id}`)}
                      />
                    ))}
                  </tbody>
                </table>
              </ResponsiveDataView>
            )}
          </Card>

          {/* Recent Results */}
          <Card>
            <CardHeader
              title="Recent Results"
              icon={Swords}
              action={
                <button onClick={() => navigate('events')} className="text-xs text-gold-400 hover:text-gold-300 flex items-center gap-1">
                  View all <ChevronRight className="w-3 h-3" />
                </button>
              }
            />
            {recentFights.length === 0 ? (
              <EmptyState icon={Swords} title="No fights yet" body="Your gym hasn't had any fights. Accept a fight offer to get started." />
            ) : (
              <div className="divide-y divide-ink-800">
                {recentFights.map((fight) => {
                  const isMyA = fight.fighter_a?.gym_id === gym.id;
                  const myFighter = isMyA ? fight.fighter_a : fight.fighter_b;
                  const opponent = isMyA ? fight.fighter_b : fight.fighter_a;
                  const won = fight.winner_id === myFighter?.id;
                  return (
                    <div
                      key={fight.id}
                      className="flex items-center justify-between p-3 hover:bg-ink-800/30 cursor-pointer"
                      onClick={() => fight.event_id && navigate(`fight/${fight.id}`)}
                    >
                      <div className="flex items-center gap-3 min-w-0">
                        <span className={`badge ${won ? 'bg-forest-700/40 text-forest-200' : 'bg-blood-700/40 text-blood-200'}`}>
                          {won ? 'W' : 'L'}
                        </span>
                        <div className="min-w-0">
                          <div className="text-sm text-ink-100 truncate">
                            <button
                              className="font-medium hover:text-gold-300"
                              onClick={(event) => {
                                event.stopPropagation();
                                if (myFighter?.id) navigate(`fighter/${myFighter.id}`);
                              }}
                            >
                              {myFighter?.name || 'Your fighter'}
                            </button>
                            <span className="text-ink-400 mx-1.5">vs</span>
                            <button
                              className="text-ink-300 hover:text-gold-300"
                              onClick={(event) => {
                                event.stopPropagation();
                                if (opponent?.id) navigate(`fighter/${opponent.id}`);
                              }}
                            >
                              {opponent?.name || 'Opponent'}
                            </button>
                          </div>
                          <div className="text-xs text-ink-500">
                            {fight.method} · R{fight.round}{fight.is_title_fight ? ' · Title fight' : ''}
                          </div>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </Card>
        </div>

        {/* Column 2: Offers + News */}
        <div className="space-y-6">
          <Card>
            <CardHeader
              title="Pending Fight Offers"
              icon={FileText}
              action={
                <button onClick={() => navigate('fight-offers')} className="text-xs text-gold-400 hover:text-gold-300 flex items-center gap-1">
                  View all <ChevronRight className="w-3 h-3" />
                </button>
              }
            />
            {offers.length === 0 ? (
              <EmptyState icon={FileText} title="No pending offers" body="Offers will arrive as the world progresses." />
            ) : (
              <div className="divide-y divide-ink-800">
                {offers.slice(0, 3).map((offer) => (
                  <button
                    key={offer.id}
                    onClick={() => navigate('fight-offers')}
                    className="p-3 w-full text-left hover:bg-ink-800/30"
                  >
                    <div className="text-sm font-medium text-ink-100">
                      {formatMoney(offer.purse)}
                    </div>
                    <div className="text-xs text-ink-400">
                      {formatTick(offer.scheduled_week)}
                    </div>
                  </button>
                ))}
                <div className="p-3 bg-ink-900/40">
                  <button
                    onClick={() => navigate('fight-offers')}
                    className="text-xs text-gold-400 hover:text-gold-300 w-full text-center"
                  >
                    Review {offers.length} offer{offers.length !== 1 ? 's' : ''} →
                  </button>
                </div>
              </div>
            )}
          </Card>

          <Card>
            <CardHeader
              title="World News"
              icon={Newspaper}
              action={
                <button onClick={() => navigate('world-news')} className="text-xs text-gold-400 hover:text-gold-300 flex items-center gap-1">
                  View all <ChevronRight className="w-3 h-3" />
                </button>
              }
            />
            {news.length === 0 ? (
              <EmptyState icon={Newspaper} title="No news yet" body="The world news feed will populate here." />
            ) : (
              <div className="divide-y divide-ink-800">
                {news.map((item) => (
                  <button
                    key={item.id}
                    onClick={() => navigate('world-news')}
                    className="p-3 w-full text-left hover:bg-ink-800/30"
                  >
                    <div className="flex items-center gap-2 mb-1">
                      <NewsTypeIcon type={item.type} />
                      <div className="text-sm font-medium text-ink-100">{item.title}</div>
                    </div>
                    <div className="text-xs text-ink-500 line-clamp-2">{item.body}</div>
                  </button>
                ))}
              </div>
            )}
          </Card>

          {/* Quick actions */}
          {fighters.length === 0 && (
            <Card className="border-gold-700/40">
              <div className="p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Sparkles className="w-4 h-4 text-gold-400" />
                  <div className="font-display font-semibold text-ink-100">Get Started</div>
                </div>
                <p className="text-xs text-ink-400 mb-3">
                  Sign your first fighter from the pool of unsigned prospects.
                </p>
                <button onClick={() => navigate('scout')} className="btn-primary w-full text-sm">
                  Scout Fighters
                </button>
              </div>
            </Card>
          )}
        </div>
      </div>

      {world && (
        <div className="mt-6 flex items-center justify-center text-xs text-ink-500 gap-2">
          <Calendar className="w-3 h-3" />
          Next world tick in {world.last_tick_at ? 'about 1 hour' : 'soon'} · World advances 1 week per hour
        </div>
      )}
    </div>
  );
}

function NewsTypeIcon({ type }: { type: string }) {
  const Icon = type === 'champion_crowned' ? Crown
    : type === 'title_defense' ? Trophy
    : type === 'retirement' ? Users
    : type === 'signing' ? Sparkles
    : type === 'event_result' ? Swords
    : Newspaper;
  return <Icon className={`w-3.5 h-3.5 ${
    type === 'champion_crowned' ? 'text-gold-400' :
    type === 'title_defense' ? 'text-gold-300' :
    type === 'retirement' ? 'text-ink-400' :
    type === 'signing' ? 'text-forest-300' :
    type === 'event_result' ? 'text-blood-300' :
    'text-ink-400'
  }`} />;
}
