import { useEffect, useState, useCallback } from 'react';
import { Search, Users, AlertCircle } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader, Spinner } from '../components/ui';
import { FighterRow } from '../components/FighterCard';
import { fetchScoutFighters, callSignFighter } from '../lib/queries';
import { formatMoney } from '../lib/format';
import type { Fighter } from '../lib/types';
import { useGym as useGymCtx } from '../lib/gym';
import { WEIGHT_CLASSES } from '../lib/constants';
import { navigate } from '../App';

const PAGE_SIZE = 50;

export function Scout(_: PageProps) {
  const { gym, refresh: refetchGym, bumpVersion } = useGymCtx();
  const [fighters, setFighters] = useState<Fighter[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [search, setSearch] = useState('');
  const [wcFilter, setWcFilter] = useState('All');
  const [signing, setSigning] = useState<string | null>(null);
  const [signResult, setSignResult] = useState<{ fighterId: string; status: string; message?: string } | null>(null);
  const [page, setPage] = useState(0);

  const load = useCallback(async (reset: boolean) => {
    if (reset) setLoading(true);
    else setLoadingMore(true);
    try {
      const { fighters: newFighters, total: newTotal } = await fetchScoutFighters({
        weightClass: wcFilter,
        limit: PAGE_SIZE,
        offset: reset ? 0 : (page * PAGE_SIZE),
      });
      setFighters(reset ? newFighters : (prev) => [...prev, ...newFighters]);
      setTotal(newTotal);
    } catch (e) {
      console.error('Failed to load scout fighters:', (e as Error).message);
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [wcFilter, page]);

  useEffect(() => {
    setPage(0);
    load(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wcFilter]);

  if (!gym) return null;

  async function handleSign(f: Fighter) {
    setSigning(f.id);
    setSignResult(null);
    try {
      const r = await callSignFighter(f.id);
      setSignResult({ fighterId: f.id, status: r.status, message: r.message });
      if (r.status === 'ok') {
        // Remove from scout list, refresh gym cash, and bump version so
        // any mounted My Fighters / Dashboard widgets refetch.
        setFighters((prev) => prev.filter((x) => x.id !== f.id));
        await refetchGym();
        bumpVersion();
      }
    } catch (e) {
      setSignResult({ fighterId: f.id, status: 'error', message: (e as Error).message });
    } finally {
      setSigning(null);
    }
  }

  const filtered = fighters.filter((f) =>
    !search || f.name.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="animate-slideUp">
      <PageHeader
        title="Scout"
        subtitle="Browse unmanaged fighters and sign them to your gym. Stats are hidden until you scout a fighter."
        icon={Search}
        action={
          <div className="text-right">
            <div className="text-xs text-ink-500 uppercase tracking-wide">Available Cash</div>
            <div className="font-display font-bold text-gold-300">{formatMoney(gym.cash)}</div>
          </div>
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
          <EmptyState icon={Users} title="No fighters available" body="All active fighters currently have gym management. Check back after the next world tick." />
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
                  <th className="px-3 py-2 text-right font-semibold">Sign Cost</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-ink-800">
                {filtered.map((f) => (
                    <FighterRow
                      key={f.id}
                      fighter={f}
                      hideStats
                      onClick={() => navigate(`fighter/${f.id}`)}
                      right={
                        <div className="flex items-center gap-2 justify-end">
                          <span className={`badge border ${
                            f.promotion_id
                              ? 'text-blue-300 bg-blue-900/30 border-blue-700/40'
                              : 'text-ink-400 bg-ink-800 border-ink-700'
                          }`}>
                            {f.promotion_id ? 'Promotion contracted' : 'Free agent'}
                          </span>
                          <span className="text-sm font-mono text-ink-500 italic">
                            Hidden — scout to reveal
                          </span>
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              handleSign(f);
                            }}
                            disabled={signing === f.id}
                            className="btn-primary text-xs px-3 py-1.5"
                          >
                            {signing === f.id ? <Spinner className="w-3 h-3" /> : 'Sign'}
                          </button>
                        </div>
                      }
                    />
                  ))}
              </tbody>
            </table>
            <div className="border-t border-ink-800 p-3 flex items-center justify-between">
              <div className="text-xs text-ink-400">
                Showing {filtered.length} of {total.toLocaleString()} unmanaged fighters
              </div>
              {filtered.length < total && (
                <button
                  onClick={() => { setPage((p) => p + 1); load(false); }}
                  disabled={loadingMore}
                  className="btn-secondary text-xs"
                >
                  {loadingMore ? <Spinner /> : 'Load more'}
                </button>
              )}
            </div>
          </div>
        )}
      </Card>

      {signResult && signResult.status !== 'ok' && (
        <div className="mt-3 flex items-start gap-2 text-sm text-blood-300 bg-blood-950/50 border border-blood-800/50 rounded-lg p-3">
          <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>{signResult.message}</span>
        </div>
      )}
    </div>
  );
}
