import { useEffect, useState } from 'react';
import { Newspaper, Crown, Swords, Users, Sparkles, Trophy } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader, Spinner, Badge } from '../components/ui';
import { fetchRecentNews } from '../lib/queries';
import { formatTick } from '../lib/format';
import { navigate } from '../App';

const TYPE_META: Record<string, { icon: React.ComponentType<{ className?: string }>; color: string; label: string }> = {
  champion_crowned: { icon: Crown, color: 'text-gold-400', label: 'New Champion' },
  title_defense: { icon: Trophy, color: 'text-gold-300', label: 'Title Defense' },
  title_vacated: { icon: Crown, color: 'text-ink-400', label: 'Title Vacated' },
  retirement: { icon: Users, color: 'text-ink-400', label: 'Retirement' },
  signing: { icon: Sparkles, color: 'text-forest-300', label: 'Signing' },
  event_result: { icon: Swords, color: 'text-blood-300', label: 'Event Result' },
  upset: { icon: Swords, color: 'text-blood-300', label: 'Upset' },
  gym_tier: { icon: Trophy, color: 'text-gold-300', label: 'Gym Tier' },
};

const FILTERABLE_TYPES = Object.keys(TYPE_META);

export function WorldNews(_: PageProps) {
  const [news, setNews] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [limit, setLimit] = useState(30);

  useEffect(() => {
    setLoading(true);
    fetchRecentNews(limit)
      .then(setNews)
      .catch((e) => console.error('Failed to load news:', e.message))
      .finally(() => setLoading(false));
  }, [limit]);

  const filtered = typeFilter === 'all' ? news : news.filter((n) => n.type === typeFilter);

  return (
    <div className="animate-slideUp">
      <PageHeader
        title="World News"
        subtitle="The latest from the MMA world"
        icon={Newspaper}
      />

      <div className="flex flex-wrap gap-2 mb-4">
        <button
          onClick={() => setTypeFilter('all')}
          className={`btn text-xs ${typeFilter === 'all' ? 'btn-primary' : 'btn-secondary'}`}
        >
          All
        </button>
        {FILTERABLE_TYPES.map((t) => (
          <button
            key={t}
            onClick={() => setTypeFilter(t)}
            className={`btn text-xs ${typeFilter === t ? 'btn-primary' : 'btn-secondary'}`}
          >
            {TYPE_META[t].label}
          </button>
        ))}
      </div>

      {loading ? (
        <Card><div className="p-8 text-center text-ink-500 text-sm flex items-center justify-center gap-2"><Spinner /> Loading news...</div></Card>
      ) : filtered.length === 0 ? (
        <Card><EmptyState icon={Newspaper} title="No news" body="Check back after the next world tick to see the latest events." /></Card>
      ) : (
        <div className="space-y-2">
          {filtered.map((item) => {
            const meta = TYPE_META[item.type] || TYPE_META.event_result;
            const Icon = meta.icon;
            return (
              <Card key={item.id} className="p-3">
                <div className="flex items-start gap-3">
                  <div className="w-9 h-9 rounded-lg bg-ink-800 flex items-center justify-center flex-shrink-0">
                    <Icon className={`w-4 h-4 ${meta.color}`} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-start justify-between gap-2">
                      <h4 className="font-medium text-ink-100 text-sm leading-snug">{item.title}</h4>
                      <Badge className="text-ink-400 bg-ink-800 border-ink-700 flex-shrink-0">
                        {formatTick(item.week)}
                      </Badge>
                    </div>
                    <p className="text-xs text-ink-400 mt-1 leading-snug">{item.body}</p>
                    <div className="flex items-center gap-3 mt-2 text-xs">
                      <Badge className="bg-ink-800 text-ink-300 border-ink-700">{meta.label}</Badge>
                      {item.fighter_id && (
                        <button onClick={() => navigate(`fighter/${item.fighter_id}`)} className="text-gold-400 hover:text-gold-300">
                          View Fighter
                        </button>
                      )}
                      {item.promotion_id && (
                        <button onClick={() => navigate(`promotion/${item.promotion_id}`)} className="text-ink-400 hover:text-gold-300">
                          View Promotion
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}

      {filtered.length >= limit && (
        <div className="text-center mt-4">
          <button onClick={() => setLimit((l) => l + 30)} className="btn-secondary text-sm">
            Load more
          </button>
        </div>
      )}
    </div>
  );
}
