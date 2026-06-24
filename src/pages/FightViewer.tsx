import { useCallback, useEffect, useRef, useState } from 'react';
import { ChevronLeft, Swords, Trophy } from 'lucide-react';
import type { PageProps } from '../App';
import { navigate } from '../App';
import { GamePlanPanel, defaultGamePlan } from '../components/GamePlanPanel';
import { Badge, Belt, Card, CardHeader, EmptyState, PageHeader, Spinner, Alert } from '../components/ui';
import { useGym } from '../lib/gym';
import {
  callSubmitFightGamePlan,
  fetchFightDetail,
  parseFightState,
} from '../lib/queries';
import type { FightEvent, FightGamePlan, FightGamePlanInput, FightStatus } from '../lib/types';

const POLL_MS = 5000;

function fightStatusLabel(status: FightStatus, currentRound: number): string {
  switch (status) {
    case 'pending': return 'Scheduled';
    case 'awaiting_plans': return currentRound === 0 ? 'Awaiting game plans' : `Awaiting plans — after R${currentRound}`;
    case 'in_progress': return 'Round in progress';
    case 'between_rounds': return `Between rounds — R${currentRound} complete`;
    case 'completed': return 'Final';
    default: return status;
  }
}

function eventTypeColor(type: string): string {
  if (type === 'finish' || type === 'knockdown') return 'text-blood-300';
  if (type === 'takedown' || type === 'submission_attempt') return 'text-blue-300';
  if (type === 'round_end' || type === 'intro') return 'text-gold-300';
  return 'text-ink-200';
}

export function FightViewer({ params }: PageProps) {
  const { gym } = useGym();
  const [fight, setFight] = useState<any>(null);
  const [events, setEvents] = useState<FightEvent[]>([]);
  const [plans, setPlans] = useState<FightGamePlan[]>([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<{ kind: 'success' | 'error'; text: string } | null>(null);
  const feedRef = useRef<HTMLDivElement>(null);

  const load = useCallback(async () => {
    try {
      const data = await fetchFightDetail(params.id);
      setFight(data.fight);
      setEvents(data.events);
      setPlans(data.plans);
    } catch (e) {
      console.error('Failed to load fight:', (e as Error).message);
    } finally {
      setLoading(false);
    }
  }, [params.id]);

  useEffect(() => {
    setLoading(true);
    load();
  }, [load]);

  useEffect(() => {
    if (!fight || fight.status === 'completed') return;
    const interval = setInterval(load, POLL_MS);
    return () => clearInterval(interval);
  }, [fight?.status, load]);

  useEffect(() => {
    if (feedRef.current) {
      feedRef.current.scrollTop = feedRef.current.scrollHeight;
    }
  }, [events.length]);

  const myFighter =
    gym && fight?.fighter_a?.gym_id === gym.id
      ? fight.fighter_a
      : gym && fight?.fighter_b?.gym_id === gym.id
        ? fight.fighter_b
        : null;

  const forRound = (fight?.current_round ?? 0) + 1;
  const needsPlan =
    myFighter &&
    (fight?.status === 'awaiting_plans' || fight?.status === 'between_rounds') &&
    !plans.some((p) => p.fighter_id === myFighter.id && p.for_round === forRound);

  const mySubmittedPlan = myFighter
    ? plans.find((p) => p.fighter_id === myFighter.id && p.for_round === forRound)
    : undefined;

  const fightState = parseFightState(fight?.fight_state);
  const status = fight?.status as FightStatus | undefined;

  async function handleSubmitPlan(plan: FightGamePlanInput) {
    if (!myFighter) return;
    setSubmitting(true);
    setMessage(null);
    try {
      const r = await callSubmitFightGamePlan(params.id, myFighter.id, plan);
      if (r.status !== 'ok') throw new Error(r.message || 'Failed to submit plan.');
      setMessage({ kind: 'success', text: r.message || 'Game plan submitted.' });
      await load();
    } catch (err) {
      setMessage({ kind: 'error', text: (err as Error).message });
    } finally {
      setSubmitting(false);
    }
  }

  if (loading && !fight) {
    return (
      <div>
        <PageHeader title="Fight" icon={Swords} />
        <Card><div className="p-8 text-center text-ink-500 text-sm flex items-center justify-center gap-2"><Spinner /> Loading...</div></Card>
      </div>
    );
  }

  if (!fight) {
    return (
      <div>
        <PageHeader title="Fight" icon={Swords} />
        <Card><EmptyState icon={Swords} title="Fight not found" /></Card>
      </div>
    );
  }

  const winnerA = fight.winner_id === fight.fighter_a?.id;
  const winnerB = fight.winner_id === fight.fighter_b?.id;
  const eventsByRound = events.reduce<Record<number, FightEvent[]>>((acc, ev) => {
    const r = ev.round;
    if (!acc[r]) acc[r] = [];
    acc[r].push(ev);
    return acc;
  }, {});
  const roundKeys = Object.keys(eventsByRound).map(Number).sort((a, b) => a - b);

  return (
    <div className="animate-slideUp">
      <button
        onClick={() => navigate(fight.event_id ? `events/${fight.event_id}` : 'events')}
        className="flex items-center gap-1 text-sm text-ink-400 hover:text-ink-200 mb-4"
      >
        <ChevronLeft className="w-4 h-4" /> Back to event
      </button>

      <PageHeader
        title={`${fight.fighter_a?.name || 'TBD'} vs ${fight.fighter_b?.name || 'TBD'}`}
        subtitle={fight.event?.name || fight.weight_class}
        icon={Swords}
        action={
          <div className="flex items-center gap-2 flex-wrap">
            {fight.is_title_fight && <Belt size="sm" glowing />}
            {status && (
              <Badge className="bg-forest-700/30 text-forest-200 border-forest-600/40">
                {fightStatusLabel(status, fight.current_round ?? 0)}
              </Badge>
            )}
          </div>
        }
      />

      {message && (
        <div className="mb-4">
          <Alert variant={message.kind === 'success' ? 'success' : 'error'}>{message.text}</Alert>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
          {/* Matchup header */}
          <Card>
            <div className="p-4 grid grid-cols-[1fr_auto_1fr] gap-3 items-center">
              <div className={`text-right ${winnerA ? 'text-gold-300' : 'text-ink-100'}`}>
                <div className="font-display font-semibold">{fight.fighter_a?.name}</div>
                <div className="text-xs text-ink-500">{fight.fighter_a?.wins}-{fight.fighter_a?.losses}</div>
                {winnerA && <Trophy className="w-4 h-4 text-gold-400 inline mt-1" />}
              </div>
              <div className="text-center text-xs text-ink-500 uppercase">vs</div>
              <div className={`${winnerB ? 'text-gold-300' : 'text-ink-100'}`}>
                <div className="font-display font-semibold">{fight.fighter_b?.name}</div>
                <div className="text-xs text-ink-500">{fight.fighter_b?.wins}-{fight.fighter_b?.losses}</div>
                {winnerB && <Trophy className="w-4 h-4 text-gold-400 inline mt-1" />}
              </div>
            </div>
            {status === 'completed' && fight.method && (
              <div className="border-t border-ink-800 px-4 py-3 text-sm text-center text-gold-300">
                {fight.winner?.name} wins by {fight.method} in round {fight.round}
              </div>
            )}
          </Card>

          {/* Play-by-play */}
          <Card className="overflow-hidden">
            <CardHeader title="Play-by-play" icon={Swords} />
            <div ref={feedRef} className="max-h-[32rem] overflow-y-auto p-4 space-y-4">
              {events.length === 0 ? (
                <EmptyState icon={Swords} title="Waiting to begin" body="The fight will start once both corners submit their game plans." />
              ) : (
                roundKeys.map((round) => (
                  <div key={round}>
                    {round > 0 && (
                      <div className="text-xs text-ink-500 uppercase tracking-wide font-semibold mb-2 sticky top-0 bg-ink-950/90 py-1">
                        Round {round}
                      </div>
                    )}
                    <div className="space-y-2">
                      {eventsByRound[round].map((ev) => (
                        <div key={ev.id} className="flex gap-2 text-sm">
                          <span className="text-ink-600 font-mono text-xs w-6 flex-shrink-0">{ev.sequence}</span>
                          <span className={eventTypeColor(ev.event_type)}>{ev.detail}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                ))
              )}
            </div>
          </Card>
        </div>

        <div className="space-y-6">
          {/* Score / state */}
          <Card>
            <CardHeader title="Fight state" subtitle={fight.max_rounds ? `Up to ${fight.max_rounds} rounds` : undefined} />
            <div className="p-4 space-y-4">
              <CornerState
                name={fight.fighter_a?.name || 'Red corner'}
                state={fightState.a}
                align="left"
              />
              <CornerState
                name={fight.fighter_b?.name || 'Blue corner'}
                state={fightState.b}
                align="right"
              />
            </div>
          </Card>

          {needsPlan && myFighter && (
            <GamePlanPanel
              key={`${myFighter.id}-${forRound}`}
              fighterName={myFighter.name}
              forRound={forRound}
              initialPlan={mySubmittedPlan ? {
                preset: mySubmittedPlan.preset,
                pressure: mySubmittedPlan.pressure,
                distance: mySubmittedPlan.distance,
                takedown_freq: mySubmittedPlan.takedown_freq,
                risk: mySubmittedPlan.risk,
              } : defaultGamePlan()}
              submitting={submitting}
              onSubmit={handleSubmitPlan}
            />
          )}

          {myFighter && !needsPlan && (status === 'awaiting_plans' || status === 'between_rounds') && (
            <Card>
              <div className="p-4 text-sm text-forest-300">
                Your game plan for round {forRound} is locked in. Waiting for the other corner
                {status === 'between_rounds' ? ' before the next round begins.' : ' before the fight begins.'}
              </div>
            </Card>
          )}

          {!myFighter && (status === 'awaiting_plans' || status === 'between_rounds') && (
            <Card>
              <div className="p-4 text-sm text-ink-400">
                Managers are setting game plans between rounds. You can follow the action live here.
              </div>
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}

function CornerState({
  name,
  state,
  align,
}: {
  name: string;
  state: { stamina: number; damage: number; rounds_won: number };
  align: 'left' | 'right';
}) {
  return (
    <div className={align === 'right' ? 'text-right' : ''}>
      <div className="text-sm font-medium text-ink-100 mb-2">{name}</div>
      <div className="text-xs text-ink-500 mb-1">Rounds won: {state.rounds_won}</div>
      <StatBar label="Stamina" value={state.stamina} max={100} color="bg-forest-500" align={align} />
      <StatBar label="Damage taken" value={state.damage} max={120} color="bg-blood-500" align={align} />
    </div>
  );
}

function StatBar({
  label,
  value,
  max,
  color,
  align,
}: {
  label: string;
  value: number;
  max: number;
  color: string;
  align: 'left' | 'right';
}) {
  const pct = Math.min(100, Math.round((value / max) * 100));
  return (
    <div className="mb-2">
      <div className={`flex justify-between text-xs text-ink-500 mb-0.5 ${align === 'right' ? 'flex-row-reverse gap-2' : ''}`}>
        <span>{label}</span>
        <span>{Math.round(value)}</span>
      </div>
      <div className="h-1.5 bg-ink-800 rounded-full overflow-hidden">
        <div className={`h-full ${color} rounded-full transition-all`} style={{ width: `${pct}%`, marginLeft: align === 'right' ? 'auto' : undefined }} />
      </div>
    </div>
  );
}
