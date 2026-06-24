import { useEffect, useState } from 'react';
import { Search, Users, UserMinus, AlertCircle } from 'lucide-react';
import { useGym } from '../lib/gym';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader, Spinner } from '../components/ui';
import { FighterRow, FighterListItem } from '../components/FighterCard';
import { ResponsiveDataView } from '../components/ResponsiveDataView';
import { callReleaseFighter, fetchGymFighters } from '../lib/queries';
import { formatRecord } from '../lib/format';
import type { Fighter } from '../lib/types';
import { navigate } from '../App';
import { WEIGHT_CLASSES } from '../lib/constants';

export function MyFighters(_: PageProps) {
  const { gym, version, bumpVersion } = useGym();
  const [fighters, setFighters] = useState<Fighter[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [wcFilter, setWcFilter] = useState<string>('All');
  const [releasing, setReleasing] = useState<string | null>(null);
  const [confirmingId, setConfirmingId] = useState<string | null>(null);
  const [releaseError, setReleaseError] = useState<string | null>(null);

  useEffect(() => {
    if (!gym) return;
    fetchGymFighters(gym.id)
      .then(setFighters)
      .catch((e) => console.error('Failed to load fighters:', e.message))
      .finally(() => setLoading(false));
  }, [gym, version]);

  async function handleRelease(f: Fighter) {
    setReleasing(f.id);
    setReleaseError(null);
    try {
      const r = await callReleaseFighter(f.id);
      if (r.status === 'ok') {
        setFighters((prev) => prev.filter((x) => x.id !== f.id));
        setConfirmingId(null);
        bumpVersion();
      } else {
        setReleaseError(r.message || 'Failed to release fighter.');
      }
    } catch (e) {
      setReleaseError((e as Error).message);
    } finally {
      setReleasing(null);
    }
  }

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

      <div className="mb-4 flex flex-col sm:flex-row gap-2 sm:items-center">
        <div className="relative flex-1 min-w-0">
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
          className="input w-full sm:w-auto"
        >
          <option value="All">All Weight Classes</option>
          {WEIGHT_CLASSES.map((wc) => (
            <option key={wc.name} value={wc.name}>{wc.name}</option>
          ))}
        </select>
      </div>

      {releaseError && (
        <div className="mb-4 flex items-start gap-2 text-sm text-blood-300 bg-blood-950/50 border border-blood-800/50 rounded-lg p-3">
          <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>{releaseError}</span>
        </div>
      )}

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
          <ResponsiveDataView
            mobileRows={filtered.map((f) => (
              <FighterListItem
                key={f.id}
                fighter={f}
                onClick={() => navigate(`fighter/${f.id}`)}
                footer={
                  <>
                    <span className={`badge border ${
                      f.career_status === 'champion' ? 'text-gold-300 bg-gold-700/30 border-gold-600/40' :
                      f.career_status === 'contender' ? 'text-blue-300 bg-blue-700/30 border-blue-600/40' :
                      f.career_status === 'veteran' ? 'text-ink-300 bg-ink-700 border-ink-600' :
                      'text-forest-300 bg-forest-700/30 border-forest-600/40'
                    }`}>
                      {f.career_status}
                    </span>
                    {confirmingId === f.id ? (
                      <>
                        <button
                          onClick={() => handleRelease(f)}
                          disabled={releasing === f.id}
                          className="btn-danger text-xs px-2 py-1"
                        >
                          {releasing === f.id ? <Spinner className="w-3 h-3" /> : 'Confirm'}
                        </button>
                        <button
                          onClick={() => setConfirmingId(null)}
                          disabled={releasing === f.id}
                          className="btn-secondary text-xs px-2 py-1"
                        >
                          Cancel
                        </button>
                      </>
                    ) : (
                      <button
                        onClick={() => {
                          setConfirmingId(f.id);
                          setReleaseError(null);
                        }}
                        className="btn-danger text-xs px-2 py-1"
                        title="Release from your gym"
                      >
                        <UserMinus className="w-3 h-3" />
                      </button>
                    )}
                  </>
                }
              />
            ))}
          >
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
                      <div className="flex items-center gap-2 justify-end">
                        <span className={`badge border ${
                          f.career_status === 'champion' ? 'text-gold-300 bg-gold-700/30 border-gold-600/40' :
                          f.career_status === 'contender' ? 'text-blue-300 bg-blue-700/30 border-blue-600/40' :
                          f.career_status === 'veteran' ? 'text-ink-300 bg-ink-700 border-ink-600' :
                          'text-forest-300 bg-forest-700/30 border-forest-600/40'
                        }`}>
                          {f.career_status}
                        </span>
                        {confirmingId === f.id ? (
                          <div className="flex items-center gap-1">
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                handleRelease(f);
                              }}
                              disabled={releasing === f.id}
                              className="btn-danger text-xs px-2 py-1"
                            >
                              {releasing === f.id ? <Spinner className="w-3 h-3" /> : 'Confirm'}
                            </button>
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                setConfirmingId(null);
                              }}
                              disabled={releasing === f.id}
                              className="btn-secondary text-xs px-2 py-1"
                            >
                              Cancel
                            </button>
                          </div>
                        ) : (
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              setConfirmingId(f.id);
                              setReleaseError(null);
                            }}
                            className="btn-danger text-xs px-2 py-1"
                            title="Release from your gym"
                          >
                            <UserMinus className="w-3 h-3" />
                          </button>
                        )}
                      </div>
                    }
                  />
                ))}
              </tbody>
            </table>
          </ResponsiveDataView>
        )}
      </Card>
    </div>
  );
}
