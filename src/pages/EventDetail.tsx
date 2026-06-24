import { useEffect, useState } from 'react';
import { CalendarDays, ChevronLeft, Trophy, Plus, Play, AlertCircle, CheckCircle2 } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader, Spinner, Badge, Belt, Alert } from '../components/ui';
import {
  fetchEventDetail,
  fetchOwnedPromotion,
  fetchBookableFighters,
  fetchEventUnresolvedBookings,
  callAddEventFight,
  callRunEvent,
} from '../lib/queries';
import { formatTick } from '../lib/format';
import { PROMOTION_TIER_NAMES, PROMOTION_TIER_COLORS, EVENT_LEAD_WEEKS } from '../lib/constants';
import { navigate } from '../App';
import { useGym } from '../lib/gym';
import { useWorld } from '../lib/world';
import type { Fighter, Promotion } from '../lib/types';

interface FightRow {
  id: string;
  weight_class: string;
  method: string | null;
  round: number | null;
  is_title_fight: boolean;
  status: string;
  commentary: string[] | null;
  fighter_a?: { id: string; name: string; country: string; wins: number; losses: number; gym_id?: string | null };
  fighter_b?: { id: string; name: string; country: string; wins: number; losses: number; gym_id?: string | null };
  winner?: { id: string; name: string };
}

export function EventDetail({ params }: PageProps) {
  const { gym } = useGym();
  const { world, refresh: refreshWorld } = useWorld();
  const [event, setEvent] = useState<any>(null);
  const [fights, setFights] = useState<FightRow[]>([]);
  const [ownedPromotion, setOwnedPromotion] = useState<Promotion | null>(null);
  const [bookableFighters, setBookableFighters] = useState<Fighter[]>([]);
  const [unresolvedBookings, setUnresolvedBookings] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedFight, setExpandedFight] = useState<string | null>(null);
  const [fighterAId, setFighterAId] = useState('');
  const [fighterBId, setFighterBId] = useState('');
  const [isTitleFight, setIsTitleFight] = useState(false);
  const [purse, setPurse] = useState(5000);
  const [addingFight, setAddingFight] = useState(false);
  const [runningEvent, setRunningEvent] = useState(false);
  const [message, setMessage] = useState<{ kind: 'success' | 'error'; text: string } | null>(null);

  const isOwner = ownedPromotion && event?.promotion_id === ownedPromotion.id;
  const canRun = isOwner && event?.status === 'scheduled' && world && world.tick_count >= event.scheduled_week;

  async function load() {
    setLoading(true);
    try {
      const [{ event: ev, fights: f }, promo, offers] = await Promise.all([
        fetchEventDetail(params.id),
        gym ? fetchOwnedPromotion(gym.id) : Promise.resolve(null),
        fetchEventUnresolvedBookings(params.id),
      ]);
      setEvent(ev);
      setFights(f as FightRow[]);
      setOwnedPromotion(promo);
      setUnresolvedBookings(offers);
      if (promo && ev?.promotion_id === promo.id) {
        const roster = await fetchBookableFighters(promo.id);
        setBookableFighters(roster as Fighter[]);
      }
    } catch (e) {
      console.error('Failed to load event:', (e as Error).message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, [params.id, gym?.id, world?.tick_count]);

  async function handleAddFight(e: React.FormEvent) {
    e.preventDefault();
    if (!fighterAId || !fighterBId) return;
    setAddingFight(true);
    setMessage(null);
    try {
      const r = await callAddEventFight(params.id, fighterAId, fighterBId, isTitleFight, purse);
      if (r.status !== 'ok') throw new Error(r.message || 'Failed to add fight.');
      setMessage({ kind: 'success', text: r.message || 'Fight added.' });
      setFighterAId('');
      setFighterBId('');
      setIsTitleFight(false);
      await load();
    } catch (err) {
      setMessage({ kind: 'error', text: (err as Error).message });
    } finally {
      setAddingFight(false);
    }
  }

  async function handleRunEvent() {
    setRunningEvent(true);
    setMessage(null);
    try {
      const r = await callRunEvent(params.id);
      if (r.status !== 'ok') throw new Error(r.message || 'Failed to run event.');
      setMessage({ kind: 'success', text: r.message || 'Event completed.' });
      await refreshWorld();
      await load();
    } catch (err) {
      setMessage({ kind: 'error', text: (err as Error).message });
    } finally {
      setRunningEvent(false);
    }
  }

  if (loading) {
    return (
      <div>
        <PageHeader title="Event" icon={CalendarDays} />
        <Card><div className="p-8 text-center text-ink-500 text-sm flex items-center justify-center gap-2"><Spinner /> Loading...</div></Card>
      </div>
    );
  }

  if (!event) {
    return (
      <div>
        <PageHeader title="Event" icon={CalendarDays} />
        <Card><EmptyState icon={CalendarDays} title="Event not found" /></Card>
      </div>
    );
  }

  const promo = event.promotion;
  const hasUnresolvedBookings = unresolvedBookings.length > 0;

  function bookingSummary(groupKey: string, offers: typeof unresolvedBookings) {
    const groupOffers = offers.filter((o) => (o.booking_group_id || o.id) === groupKey);
    if (groupOffers.length === 0) return null;

    const sample = groupOffers[0];
    const fighterName = sample.fighter?.name || 'Fighter';
    const opponentName = sample.opponent_fighter?.name || 'Opponent';

    if (sample.booking_group_id && groupOffers.length > 1) {
      const accepted = groupOffers.filter((o) => o.status === 'accepted');
      const pending = groupOffers.filter((o) => o.status === 'pending');
      if (accepted.length === 2) {
        return `${fighterName} vs ${opponentName} — both gyms accepted, confirming bout`;
      }
      if (accepted.length === 1 && pending.length === 1) {
        const waitingGym = pending[0]?.gym?.name || pending[0]?.fighter?.name || 'opponent gym';
        return `${fighterName} vs ${opponentName} — awaiting ${waitingGym}`;
      }
      return `${fighterName} vs ${opponentName} — awaiting both gyms (${pending.length} pending)`;
    }

    return `${fighterName} vs ${opponentName} — offer pending`;
  }

  const bookingGroups = Array.from(
    new Set(unresolvedBookings.map((o) => o.booking_group_id || o.id)),
  );
  const filteredFighters = bookableFighters.filter(
    (f) => !fighterBId || f.id !== fighterBId,
  );
  const filteredFightersB = bookableFighters.filter(
    (f) => !fighterAId || f.id !== fighterAId,
  );

  return (
    <div className="animate-slideUp">
      <button
        onClick={() => navigate(isOwner ? 'manage-promotion' : 'events')}
        className="flex items-center gap-1 text-sm text-ink-400 hover:text-ink-200 mb-4"
      >
        <ChevronLeft className="w-4 h-4" /> Back
      </button>

      <PageHeader
        title={event.name}
        subtitle={`${formatTick(event.scheduled_week)} · ${event.status === 'completed' ? 'Completed' : 'Scheduled'}`}
        icon={CalendarDays}
        action={
          <div className="flex items-center gap-2">
            {promo && (
              <Badge className={PROMOTION_TIER_COLORS[promo.tier]}>
                {PROMOTION_TIER_NAMES[promo.tier]}
              </Badge>
            )}
            {canRun && (
              <button
                onClick={handleRunEvent}
                disabled={runningEvent || hasUnresolvedBookings}
                className="btn-primary text-sm"
                title={hasUnresolvedBookings ? 'Resolve pending offers first' : 'Simulate event'}
              >
                {runningEvent ? <Spinner /> : <><Play className="w-4 h-4" /> Run Event</>}
              </button>
            )}
          </div>
        }
      />

      {message && (
        <div className="mb-4">
          {message.kind === 'success' ? (
            <Alert variant="success"><span className="flex items-center gap-2"><CheckCircle2 className="w-4 h-4" /> {message.text}</span></Alert>
          ) : (
            <Alert variant="error"><span className="flex items-center gap-2"><AlertCircle className="w-4 h-4" /> {message.text}</span></Alert>
          )}
        </div>
      )}

      {promo && (
        <div className="mb-6">
          <button
            onClick={() => navigate(`promotion/${promo.id}`)}
            className="text-sm text-ink-300 hover:text-gold-300"
          >
            Hosted by {promo.name} · {promo.country}
          </button>
        </div>
      )}

      {isOwner && event.status === 'scheduled' && (
        <Card className="mb-6">
          <div className="p-4 border-b border-ink-800">
            <h3 className="font-display font-semibold text-ink-100">Add Fight to Card</h3>
            <p className="text-xs text-ink-400 mt-1">
              Unsigned fighters auto-accept. One player gym gets a single offer; two player gyms each get an offer and both must accept.
              Book at least {EVENT_LEAD_WEEKS} weeks before the event date.
            </p>
          </div>
          <form onSubmit={handleAddFight} className="p-4 space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div>
                <label className="label">Fighter A</label>
                <select className="input" value={fighterAId} onChange={(e) => setFighterAId(e.target.value)} required>
                  <option value="">Select...</option>
                  {filteredFighters.map((f) => (
                    <option key={f.id} value={f.id}>{f.name} · {f.weight_class}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="label">Fighter B</label>
                <select className="input" value={fighterBId} onChange={(e) => setFighterBId(e.target.value)} required>
                  <option value="">Select...</option>
                  {filteredFightersB.map((f) => (
                    <option key={f.id} value={f.id}>{f.name} · {f.weight_class}</option>
                  ))}
                </select>
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-4">
              <label className="flex items-center gap-2 text-sm text-ink-300">
                <input type="checkbox" checked={isTitleFight} onChange={(e) => setIsTitleFight(e.target.checked)} />
                Title fight
              </label>
              <div className="flex items-center gap-2">
                <label className="label mb-0">Purse</label>
                <input
                  type="number"
                  min={1000}
                  step={500}
                  className="input w-32"
                  value={purse}
                  onChange={(e) => setPurse(parseInt(e.target.value, 10) || 5000)}
                />
              </div>
            </div>
            <button type="submit" disabled={addingFight} className="btn-primary">
              {addingFight ? <Spinner /> : <><Plus className="w-4 h-4" /> Add Fight</>}
            </button>
          </form>
        </Card>
      )}

      {hasUnresolvedBookings && (
        <Card className="mb-6 p-4">
          <h3 className="font-display font-semibold text-ink-100 mb-2">Awaiting Gym Response</h3>
          <ul className="space-y-2 text-sm text-ink-300">
            {bookingGroups.map((groupKey) => {
              const summary = bookingSummary(groupKey, unresolvedBookings);
              return summary ? <li key={groupKey}>{summary}</li> : null;
            })}
          </ul>
        </Card>
      )}

      {fights.length === 0 ? (
        <Card><EmptyState icon={CalendarDays} title="No fights booked yet" body={event.status === 'scheduled' ? 'Add fights to build the card.' : 'No fights on record for this event.'} /></Card>
      ) : (
        <div className="space-y-3">
          {fights.map((fight) => {
            const winnerA = fight.winner?.id === fight.fighter_a?.id;
            const winnerB = fight.winner?.id === fight.fighter_b?.id;
            const expanded = expandedFight === fight.id;
            const commentary = Array.isArray(fight.commentary) ? fight.commentary : [];
            return (
              <Card key={fight.id} className="overflow-hidden">
                <div
                  className="p-4 cursor-pointer hover:bg-ink-800/40 transition-colors"
                  onClick={() => setExpandedFight(expanded ? null : fight.id)}
                >
                  <div className="flex items-center justify-between gap-3">
                    <div className="flex items-center gap-3 flex-1">
                      {fight.is_title_fight && <Belt size="sm" glowing />}
                      <div className="flex items-center gap-2 flex-1 justify-end">
                        <button
                          onClick={(e) => { e.stopPropagation(); fight.fighter_a && navigate(`fighter/${fight.fighter_a.id}`); }}
                          className={`text-sm font-medium hover:text-gold-300 ${winnerA ? 'text-gold-300' : 'text-ink-200'}`}
                        >
                          {fight.fighter_a?.name || 'TBD'}
                        </button>
                        {winnerA && <Trophy className="w-3.5 h-3.5 text-gold-400" />}
                      </div>
                      <div className="text-xs text-ink-500 uppercase tracking-wide w-12 text-center">vs</div>
                      <div className="flex items-center gap-2 flex-1">
                        {winnerB && <Trophy className="w-3.5 h-3.5 text-gold-400" />}
                        <button
                          onClick={(e) => { e.stopPropagation(); fight.fighter_b && navigate(`fighter/${fight.fighter_b.id}`); }}
                          className={`text-sm font-medium hover:text-gold-300 ${winnerB ? 'text-gold-300' : 'text-ink-200'}`}
                        >
                          {fight.fighter_b?.name || 'TBD'}
                        </button>
                      </div>
                    </div>
                    <div className="text-right flex-shrink-0">
                      {fight.status === 'completed' ? (
                        <>
                          <div className="text-sm text-gold-300 font-medium">
                            {fight.method} · R{fight.round}
                          </div>
                          <div className="text-xs text-ink-500">{fight.weight_class}</div>
                        </>
                      ) : (
                        <Badge className="text-forest-300 bg-forest-700/30 border-forest-600/40">
                          {fight.weight_class}
                        </Badge>
                      )}
                    </div>
                  </div>
                </div>

                {expanded && commentary.length > 0 && (
                  <div className="border-t border-ink-800 p-4 bg-ink-900/40 animate-slideUp">
                    <div className="text-xs text-ink-500 uppercase tracking-wide font-semibold mb-2">
                      Fight Commentary
                    </div>
                    <div className="space-y-1.5">
                      {commentary.map((line, i) => (
                        <div key={i} className="text-sm text-ink-300 flex gap-2">
                          <span className="text-ink-600">{i + 1}.</span>
                          <span>{line}</span>
                        </div>
                      ))}
                      {fight.winner && (
                        <div className="mt-2 pt-2 border-t border-ink-800 flex items-center gap-2 text-sm">
                          <Trophy className="w-4 h-4 text-gold-400" />
                          <span className="text-gold-300 font-semibold">
                            {fight.winner.name} wins by {fight.method} in round {fight.round}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                )}
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
