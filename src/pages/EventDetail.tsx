import { useEffect, useState } from 'react';
import { CalendarDays, ChevronLeft, Trophy } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader, Spinner, Badge, Belt } from '../components/ui';
import { fetchEventDetail } from '../lib/queries';
import { formatTick } from '../lib/format';
import { PROMOTION_TIER_NAMES, PROMOTION_TIER_COLORS } from '../lib/constants';
import { navigate } from '../App';

interface FightRow {
  id: string;
  weight_class: string;
  method: string | null;
  round: number | null;
  is_title_fight: boolean;
  status: string;
  commentary: string[] | null;
  fighter_a?: { id: string; name: string; country: string; wins: number; losses: number };
  fighter_b?: { id: string; name: string; country: string; wins: number; losses: number };
  winner?: { id: string; name: string };
}

export function EventDetail({ params }: PageProps) {
  const [event, setEvent] = useState<any>(null);
  const [fights, setFights] = useState<FightRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedFight, setExpandedFight] = useState<string | null>(null);

  useEffect(() => {
    fetchEventDetail(params.id)
      .then(({ event, fights }) => {
        setEvent(event);
        setFights(fights as FightRow[]);
      })
      .catch((e) => console.error('Failed to load event:', e.message))
      .finally(() => setLoading(false));
  }, [params.id]);

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

  return (
    <div className="animate-slideUp">
      <button
        onClick={() => navigate('events')}
        className="flex items-center gap-1 text-sm text-ink-400 hover:text-ink-200 mb-4"
      >
        <ChevronLeft className="w-4 h-4" /> Back to Events
      </button>

      <PageHeader
        title={event.name}
        subtitle={`${formatTick(event.scheduled_week)} · ${event.status === 'completed' ? 'Completed' : 'Scheduled'}`}
        icon={CalendarDays}
        action={
          promo && (
            <Badge className={PROMOTION_TIER_COLORS[promo.tier]}>
              {PROMOTION_TIER_NAMES[promo.tier]}
            </Badge>
          )
        }
      />

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

      {fights.length === 0 ? (
        <Card><EmptyState icon={CalendarDays} title="No fights booked yet" body={event.status === 'scheduled' ? 'The fight card will be populated as the event approaches.' : 'No fights on record for this event.'} /></Card>
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
