import { useEffect, useState } from 'react';
import { CalendarDays } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader, Badge, Spinner } from '../components/ui';
import { fetchEvents } from '../lib/queries';
import { formatTick } from '../lib/format';
import { PROMOTION_TIER_NAMES, PROMOTION_TIER_COLORS } from '../lib/constants';
import { navigate } from '../App';

type Filter = 'scheduled' | 'completed' | 'all';

interface EventRow {
  id: string;
  name: string;
  scheduled_week: number;
  status: string;
  completed_at_week: number | null;
  promotion?: { id: string; name: string; tier: number; country: string };
  fights?: any[];
}

export function Events(_: PageProps) {
  const [events, setEvents] = useState<EventRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<Filter>('scheduled');

  useEffect(() => {
    setLoading(true);
    fetchEvents({ limit: 50 })
      .then((data) => setEvents(data as EventRow[]))
      .catch((e) => console.error('Failed to load events:', e.message))
      .finally(() => setLoading(false));
  }, []);

  const filtered = (events || []).filter((e) => {
    if (filter === 'all') return true;
    if (filter === 'scheduled') return e.status === 'scheduled' || e.status === 'live';
    return e.status === filter;
  });

  const sorted = [...filtered].sort((a, b) => {
    if (filter === 'completed') return (b.completed_at_week || 0) - (a.completed_at_week || 0);
    return b.scheduled_week - a.scheduled_week;
  });

  return (
    <div className="animate-slideUp">
      <PageHeader
        title="Events"
        subtitle={`${events.filter((e) => e.status === 'scheduled' || e.status === 'live').length} upcoming · ${events.filter((e) => e.status === 'completed').length} completed`}
        icon={CalendarDays}
      />

      <div className="flex gap-2 mb-4">
        {(['scheduled', 'completed', 'all'] as Filter[]).map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`btn text-sm ${filter === f ? 'btn-primary' : 'btn-secondary'}`}
          >
            {f === 'all' ? 'All' : f.charAt(0).toUpperCase() + f.slice(1)}
            <span className="text-xs opacity-70 ml-1">
              ({events.filter((e) => f === 'all' || e.status === f || (f === 'scheduled' && e.status === 'live')).length})
            </span>
          </button>
        ))}
      </div>

      {loading ? (
        <Card><div className="p-8 text-center text-ink-500 text-sm flex items-center justify-center gap-2"><Spinner /> Loading events...</div></Card>
      ) : sorted.length === 0 ? (
        <Card><EmptyState icon={CalendarDays} title="No events" body={filter === 'scheduled' ? 'No upcoming events scheduled. New events will appear as the world progresses.' : `No ${filter} events.`} /></Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          {sorted.map((e) => {
            const promo = e.promotion;
            const fightCount = e.fights?.length || 0;
            return (
              <Card key={e.id} hover className="p-4" onClick={() => navigate(`events/${e.id}`)}>
                <div className="flex items-start justify-between mb-2">
                  <div className="min-w-0 flex-1">
                    <div className="font-display font-semibold text-ink-100 truncate">{e.name}</div>
                    {promo && (
                      <button
                        onClick={(ev) => { ev.stopPropagation(); navigate(`promotion/${promo.id}`); }}
                        className="text-xs text-ink-400 hover:text-gold-300"
                      >
                        {promo.name}
                      </button>
                    )}
                  </div>
                  <Badge className={
                    e.status === 'completed' ? 'text-ink-400 bg-ink-800 border-ink-700' :
                    e.status === 'live' ? 'text-blood-200 bg-blood-700/30 border-blood-600/40' :
                    'text-forest-300 bg-forest-700/30 border-forest-600/40'
                  }>
                    {e.status === 'live' ? 'Live' : e.status}
                  </Badge>
                </div>
                {promo && (
                  <Badge className={PROMOTION_TIER_COLORS[promo.tier]}>
                    {PROMOTION_TIER_NAMES[promo.tier]}
                  </Badge>
                )}
                <div className="flex items-center justify-between mt-3 pt-3 border-t border-ink-800 text-xs">
                  <span className="text-ink-500">
                    {e.status === 'scheduled' ? 'Scheduled' : e.status === 'live' ? 'Live now' : 'Held'}{' '}
                    {formatTick(e.status === 'completed' && e.completed_at_week != null ? e.completed_at_week : e.scheduled_week)}
                  </span>
                  {fightCount > 0 && <span className="text-ink-400">{fightCount} fight{fightCount !== 1 ? 's' : ''}</span>}
                </div>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
