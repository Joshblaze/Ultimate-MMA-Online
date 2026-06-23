import { useEffect, useState } from 'react';
import { Search, Users } from 'lucide-react';
import { useGym } from '../lib/gym';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader } from '../components/ui';
import { FighterRow } from '../components/FighterCard';
import { fetchGymFighters } from '../lib/queries';
import { formatRecord } from '../lib/format';
import type { Fighter } from '../lib/types';
import { navigate } from '../App';
import { WEIGHT_CLASSES } from '../lib/constants';

export function MyFighters(_: PageProps) {
  const { gym, version } = useGym();
  const [fighters, setFighters] = useState<Fighter[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [wcFilter, setWcFilter] = useState<string>('All');
  useEffect(() => {
    if (!gym) return;
    fetchGymFighters(gym.id)
      .then(setFighters)
      .catch((e) => console.error('Failed to load fighters:', e.message))
      .finally(() => setLoading(false));
  }, [gym, version]);

  const filtered = fighters.filter((f) => {
    if (wcFilter !== 'All' && f.weight_class !== wcFilter) return false;
    if (search && !f.name.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  if (!gym) return null;

  return (
    <div className="animate-slideUp">
      <PageHeader
        title="My Fighters"
        subtitle={`${fighters.length} / ${gym.capacity} · ${formatRecord(gym.wins, gym.losses, gym.draws)} team record`}
        icon={Users}
        action={
          <button onClick={() => navigate('scout')} className="btn-primary text-sm">
            <Search className="w-4 h-4" /> Scout
          </button>
        }
      />

      <div className="mb-4 flex flex-wrap gap-2 items-center">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-500" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by name..."
            className="input pl-10"
          />
        </div>
        <select
          value={wcFilter}
          onChange={(e) => setWcFilter(e.target.value)}
          className="input w-auto"
        >
          <option value="All">All Weight Classes</option>
          {WEIGHT_CLASSES.map((wc) => (
            <option key={wc.name} value={wc.name}>{wc.name}</option>
          ))}
        </select>
      </div>

      <Card>
        {loading ? (
          <div className="p-8 text-center text-ink-500 text-sm">Loading fighters...</div>
        ) : filtered.length === 0 ? (
          <EmptyState
            icon={Users}
            title={fighters.length === 0 ? 'No fighters in your gym' : 'No matches'}
            body={fighters.length === 0
              ? 'Head to the Scout page to sign your first fighter and start building your team.'
              : 'Try a different search or filter.'}
            action={fighters.length === 0 ? (
              <button onClick={() => navigate('scout')} className="btn-primary text-sm">
                Go to Scout
              </button>
            ) : undefined}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-xs text-ink-500 uppercase tracking-wide border-b border-ink-800">
                  <th className="px-3 py-2 text-left font-semibold">Fighter</th>
                  <th className="px-3 py-2 text-left font-semibold">Weight Class</th>
                  <th className="px-3 py-2 text-left font-semibold">Age</th>
                  <th className="px-3 py-2 text-left font-semibold">Record</th>
                  <th className="px-3 py-2 text-left font-semibold">Skill</th>
                  <th className="px-3 py-2 text-right font-semibold">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-ink-800">
                {filtered.map((f) => (
                  <FighterRow
                    key={f.id}
                    fighter={f}
                    onClick={() => navigate(`fighter/${f.id}`)}
                    right={
                      <span className={`badge border ${
                        f.career_status === 'champion' ? 'text-gold-300 bg-gold-700/30 border-gold-600/40' :
                        f.career_status === 'contender' ? 'text-blue-300 bg-blue-700/30 border-blue-600/40' :
                        f.career_status === 'veteran' ? 'text-ink-300 bg-ink-700 border-ink-600' :
                        'text-forest-300 bg-forest-700/30 border-forest-600/40'
                      }`}>
                        {f.career_status}
                      </span>
                    }
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}
