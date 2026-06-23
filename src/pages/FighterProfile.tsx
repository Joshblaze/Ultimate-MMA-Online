import { useEffect, useState } from 'react';
import { User, MapPin, Cake, Trophy, Swords, Activity, CalendarDays, UserMinus, AlertCircle } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, CardHeader, EmptyState, PageHeader, Avatar, Belt, Badge, Spinner } from '../components/ui';
import { FighterStatBar } from '../components/ui';
import { HiddenFighterStats } from '../components/HiddenFighterStats';
import { fetchFighter, callReleaseFighter } from '../lib/queries';
import { formatRecord, formatTick } from '../lib/format';
import { CAREER_STATUS_COLOR } from '../lib/constants';
import { areFighterStatsVisible } from '../lib/fighters';
import type { Fighter } from '../lib/types';
import { useGym } from '../lib/gym';
import { useAuth } from '../lib/auth';
import { navigate } from '../App';
import { PromotionRankBadge } from '../components/PromotionRankBadge';

export function FighterProfile({ params }: PageProps) {
  const { gym, bumpVersion } = useGym();
  const { profile } = useAuth();
  const [data, setData] = useState<{
    fighter: Fighter | null;
    fights: any[];
    upcomingFights: any[];
    contracts: any[];
    ranking?: {
      rank_position: number;
      promotion?: { id: string; name: string; tier: number } | null;
    } | null;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [releasing, setReleasing] = useState(false);
  const [confirmRelease, setConfirmRelease] = useState(false);
  const [releaseError, setReleaseError] = useState<string | null>(null);

  useEffect(() => {
    fetchFighter(params.id, { withHistory: true })
      .then((d) => {
        if (!d || !d.fighter) setNotFound(true);
        else setData(d as any);
      })
      .catch((e) => {
        console.error('Failed to load fighter:', e.message);
        setNotFound(true);
      })
      .finally(() => setLoading(false));
  }, [params.id]);

  if (loading) {
    return (
      <PageHeader title="Fighter Profile" icon={User} subtitle="Loading..." />
    );
  }

  if (notFound || !data?.fighter) {
    return (
      <div>
        <PageHeader title="Fighter Profile" icon={User} />
        <Card>
          <EmptyState icon={User} title="Fighter not found" body="This fighter may have retired or been removed from the database." />
        </Card>
      </div>
    );
  }

  const f = data.fighter as Fighter;
  const fights = (data.fights || []) as any[];
  const upcomingFights = (data.upcomingFights || []) as any[];
  const contracts = (data.contracts || []) as any[];
  const activeContract = contracts.find((contract: any) => contract.status === 'active');
  const statsVisible = areFighterStatsVisible(f, gym?.id, profile?.is_admin ?? false);
  const isChampion = statsVisible && f.career_status === 'champion';
  const isOwnFighter = !!gym && f.gym_id === gym.id;
  const ranking = data.ranking;
  const showRankBadge = statsVisible && ranking && ranking.rank_position <= 15 && ranking.promotion?.name;

  async function handleRelease() {
    setReleasing(true);
    setReleaseError(null);
    try {
      const r = await callReleaseFighter(f.id);
      if (r.status === 'ok') {
        bumpVersion();
        navigate('my-fighters');
      } else {
        setReleaseError(r.message || 'Failed to release fighter.');
      }
    } catch (e) {
      setReleaseError((e as Error).message);
    } finally {
      setReleasing(false);
      setConfirmRelease(false);
    }
  }

  return (
    <div className="animate-slideUp">
      <PageHeader
        title={f.name}
        subtitle={`${f.weight_class} · ${f.country} · Age ${f.age}`}
        icon={User}
        action={
          <div className="flex flex-wrap items-center justify-end gap-2">
            {showRankBadge && (
              <PromotionRankBadge
                rankPosition={ranking!.rank_position}
                promotionName={ranking!.promotion!.name}
              />
            )}
            {statsVisible && (
              <Badge className={CAREER_STATUS_COLOR[f.career_status]}>
                {f.career_status}
              </Badge>
            )}
            {isOwnFighter && (
              confirmRelease ? (
                <div className="flex items-center gap-2">
                  <button
                    onClick={handleRelease}
                    disabled={releasing}
                    className="btn-danger text-xs"
                  >
                    {releasing ? <Spinner className="w-3 h-3" /> : 'Confirm release'}
                  </button>
                  <button
                    onClick={() => setConfirmRelease(false)}
                    disabled={releasing}
                    className="btn-secondary text-xs"
                  >
                    Cancel
                  </button>
                </div>
              ) : (
                <button
                  onClick={() => {
                    setConfirmRelease(true);
                    setReleaseError(null);
                  }}
                  className="btn-danger text-xs"
                >
                  <UserMinus className="w-3.5 h-3.5" /> Release
                </button>
              )
            )}
          </div>
        }
      />

      {releaseError && (
        <div className="mb-4 flex items-start gap-2 text-sm text-blood-300 bg-blood-950/50 border border-blood-800/50 rounded-lg p-3">
          <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>{releaseError}</span>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left column: profile + attributes */}
        <div className="space-y-6">
          <Card>
            <div className="p-5">
              <div className="flex items-center gap-4">
                <div className="relative">
                  <Avatar name={f.name} size="lg" />
                  {isChampion && (
                    <div className="absolute -bottom-2 -right-2">
                      <Belt size="md" glowing />
                    </div>
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <h2 className="font-display text-xl font-bold text-ink-100 flex items-center gap-2">
                    {f.name}
                    {isChampion && <Trophy className="w-5 h-5 text-gold-400" />}
                  </h2>
                  <div className="flex items-center gap-2 text-sm text-ink-400 mt-1">
                    <MapPin className="w-3.5 h-3.5" /> {f.country}
                    <Cake className="w-3.5 h-3.5 ml-1" /> Age {f.age}
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-2 mt-5">
                <Stat label="Record" value={formatRecord(f.wins, f.losses, f.draws)} />
                <Stat label="Weight Class" value={f.weight_class} />
                {statsVisible ? (
                  <>
                    <Stat label="KO Wins" value={String(f.ko_wins)} />
                    <Stat label="Submission Wins" value={String(f.sub_wins)} />
                    <Stat label="Decision Wins" value={String(f.dec_wins)} />
                    <Stat label="Current Skill" value={String(f.current_skill)} />
                    <Stat label="Potential" value={String(f.potential)} />
                    <Stat label="Popularity" value={String(f.popularity)} />
                  </>
                ) : (
                  <div className="col-span-2">
                    <HiddenFighterStats />
                  </div>
                )}
              </div>
            </div>
          </Card>

          {/* Attributes */}
          {statsVisible && (
            <Card>
              <CardHeader title="Attributes" icon={Activity} />
              <div className="p-4 space-y-3">
                <FighterStatBar label="Boxing" value={f.boxing} />
                <FighterStatBar label="Kickboxing" value={f.kickboxing} />
                <FighterStatBar label="Wrestling" value={f.wrestling} />
                <FighterStatBar label="BJJ" value={f.bjj} />
                <FighterStatBar label="Cardio" value={f.cardio} />
                <FighterStatBar label="Chin" value={f.chin} />
                <FighterStatBar label="Fight IQ" value={f.fight_iq} />
                <FighterStatBar label="Athleticism" value={f.athleticism} />
              </div>
            </Card>
          )}
        </div>

        {/* Right column: contract + fight history */}
        <div className="lg:col-span-2 space-y-6">
          {/* Upcoming fights */}
          <Card>
            <CardHeader
              title="Upcoming Fights"
              icon={CalendarDays}
              subtitle={`${upcomingFights.length} booked fight${upcomingFights.length === 1 ? '' : 's'}`}
            />
            {upcomingFights.length === 0 ? (
              <EmptyState
                icon={CalendarDays}
                title="No upcoming fights"
                body="This fighter does not currently have an accepted fight booked."
              />
            ) : (
              <div className="divide-y divide-ink-800">
                {upcomingFights.map((fight: any) => {
                  const isA = fight.fighter_a_id === f.id;
                  const opponent = isA ? fight.fighter_b : fight.fighter_a;

                  return (
                    <div key={fight.id} className="p-4 flex items-center justify-between gap-4">
                      <div className="flex items-center gap-3 min-w-0">
                        <span className="badge text-gold-300 bg-gold-700/20 border-gold-600/30">
                          Booked
                        </span>
                        <div className="min-w-0">
                          <div className="text-sm text-ink-100">
                            <span className="text-ink-500">vs </span>
                            <button
                              className="text-ink-100 hover:text-gold-300 font-medium"
                              onClick={() => opponent && navigate(`fighter/${opponent.id}`)}
                            >
                              {opponent?.name || 'Opponent TBD'}
                            </button>
                          </div>
                          <div className="text-xs text-ink-500 mt-0.5">
                            {fight.weight_class}
                            {fight.is_title_fight && <span className="text-gold-400 ml-1"> · Title Fight</span>}
                          </div>
                        </div>
                      </div>
                      <div className="text-right flex-shrink-0">
                        <div className="text-sm text-ink-200 font-mono">
                          {fight.event ? formatTick(fight.event.scheduled_week) : 'Date TBD'}
                        </div>
                        {fight.event && (
                          <button
                            className="text-xs text-gold-400 hover:text-gold-300 mt-1"
                            onClick={() => navigate(`events/${fight.event.id}`)}
                          >
                            {fight.event.name}
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </Card>

          {/* Active contract */}
          <Card>
            <CardHeader
              title="Promotion Contract"
              icon={Swords}
              subtitle={activeContract
                ? `Exclusively signed for ${activeContract.fights_remaining} more fight${activeContract.fights_remaining === 1 ? '' : 's'}`
                : 'Not currently signed to a promotion'}
            />
            <div className="p-4">
              {contracts.length === 0 ? (
                <div className="text-sm text-ink-500">No contracts on record.</div>
              ) : (
                <div className="space-y-2">
                  {contracts.slice(0, 3).map((c: any, i: number) => (
                    <div key={c.id || i} className="flex items-center justify-between p-2 rounded-lg bg-ink-900 border border-ink-800">
                      <div>
                        <div className="text-sm text-ink-100 font-medium">
                          {c.promotion?.name || 'Promotion'}
                          {c.promotion && <span className="text-ink-500 ml-2">Tier {c.promotion.tier}</span>}
                        </div>
                        <div className="text-xs text-ink-500">
                          {c.completed_fights} completed · {c.fights_remaining} remaining
                          <span className="ml-1">
                            of {c.contracted_fights} contracted fights
                          </span>
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-sm text-gold-300 font-mono">${c.purse_per_fight.toLocaleString()}</div>
                        <span className={`badge border ${
                          c.status === 'active' ? 'text-forest-300 bg-forest-700/30 border-forest-600/40' : 'text-ink-400 bg-ink-800 border-ink-700'
                        }`}>{c.status}</span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
              {f.gym_id && (
                <div className="mt-2 text-xs text-ink-400">
                  Managed by a player gym. Management is separate from the promotion contract above.
                </div>
              )}
            </div>
          </Card>

          {/* Fight history */}
          <Card>
            <CardHeader title="Fight History" icon={Swords} subtitle={`${fights.length} fight${fights.length === 1 ? '' : 's'}`} />
            {fights.length === 0 ? (
              <EmptyState icon={Swords} title="No fights yet" body="This fighter hasn't competed yet." />
            ) : (
              <div className="divide-y divide-ink-800">
                {fights.map((fight: any) => {
                  const isA = fight.fighter_a_id === f.id;
                  const opp = isA ? fight.fighter_b : fight.fighter_a;
                  const won = fight.winner_id === f.id;
                  return (
                    <div key={fight.id} className="p-3 flex items-center justify-between">
                      <div className="flex items-center gap-3 min-w-0">
                        <span className={`badge ${won ? 'bg-forest-700/40 text-forest-200' : 'bg-blood-700/40 text-blood-200'}`}>
                          {won ? 'W' : 'L'}
                        </span>
                        <div className="min-w-0">
                          <div className="text-sm text-ink-100">
                            <span className="text-ink-500">vs </span>
                            <button
                              className="text-ink-200 hover:text-gold-300"
                              onClick={() => opp && navigate(`fighter/${opp.id}`)}
                            >
                              {opp?.name || 'Unknown'}
                            </button>
                          </div>
                          <div className="text-xs text-ink-500">
                            {fight.method} · R{fight.round}
                            {fight.is_title_fight && <span className="text-gold-400 ml-1">· Title</span>}
                          </div>
                        </div>
                      </div>
                      {fight.event ? (
                        <button
                          className="text-xs text-ink-500 hover:text-gold-300 flex-shrink-0"
                          onClick={() => navigate(`events/${fight.event.id}`)}
                        >
                          {fight.event.name}
                        </button>
                      ) : null}
                    </div>
                  );
                })}
              </div>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-ink-900 border border-ink-800 p-2.5">
      <div className="text-[10px] text-ink-500 uppercase tracking-wider">{label}</div>
      <div className="text-sm text-ink-100 mt-0.5 font-display font-semibold">{value}</div>
    </div>
  );
}
